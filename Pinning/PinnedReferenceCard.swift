import SwiftUI

/// One pinned reference: the ink on a small sheet of the document's paper,
/// dragged around by its body, resized by a pinch or its corner handle, and
/// closed with its × — all in screen space, whatever the canvas is doing.
///
/// Gestures are held as live offsets and only handed back through the
/// callbacks when they end, so a drag costs no model churn per frame and a
/// cancelled gesture snaps back on its own.
struct PinnedReferenceCard: View {
    let reference: PinnedReference
    let strokes: [Stroke]
    /// Canvas-space box the pinned ink occupies, nib width included.
    let inkBounds: CGRect
    /// The screen the card floats over, which it may not be lost off.
    let viewport: CGSize
    /// The document's sheet colour, so white ink on blueprint stays legible.
    let paperColor: Color
    /// Where the ink this pin came from is, when a tap has asked and it is off
    /// screen. The card points an arrow at it.
    let offscreenSourcePoint: CGPoint?
    /// Changes on every source flash, which replays the arrow's fade.
    let sourceFlashTrigger: Int
    /// Set only for a pin just made: the card first appears as bare ink exactly
    /// over the lassoed ink, then flies to its place and grows its sheet.
    let arrival: PinArrival?
    let onArrived: () -> Void
    let onTap: () -> Void
    let onDoubleTap: () -> Void
    let onMove: (CGPoint) -> Void
    let onResize: (_ center: CGPoint, _ longestSide: CGFloat) -> Void
    let onUnpin: () -> Void

    @GestureState private var moveTranslation: CGSize = .zero
    /// Nil whenever no pinch is in flight.
    @GestureState private var pinch: PinchState? = nil
    @GestureState private var handleTranslation: CGSize = .zero

    /// Flips once, on appear, to fly an arriving card into place. A card with
    /// no `arrival` ignores it and is simply where it belongs.
    @State private var hasLanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let cornerRadius: CGFloat = 14
    private static let controlSize: CGFloat = 28
    private static let flight = Animation.spring(duration: 0.5, bounce: 0.18)

    var body: some View {
        let frame = liveFrame
        let flight = flightTransform(frame: frame)
        // The sheet, border, shadow and controls fade in as the ink lands, so
        // what leaves the page reads as the ink itself, not a card.
        let chromeOpacity: Double = isAtSource ? 0 : 1
        PinnedInkView(strokes: strokes, inkBounds: inkBounds)
            .frame(width: frame.size.width, height: frame.size.height)
            .background(paperColor.opacity(chromeOpacity))
            .clipShape(.rect(cornerRadius: Self.cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(.separator, lineWidth: 1)
                    .opacity(chromeOpacity)
            }
            .shadow(color: .black.opacity(0.18 * chromeOpacity), radius: 10, y: 4)
            .overlay { sourceArrow(frame: frame) }
            // Inside the card rather than hanging off its corners: SwiftUI does
            // not hit-test what falls outside a view's bounds.
            .overlay(alignment: .topTrailing) { unpinButton.opacity(chromeOpacity) }
            .overlay(alignment: .bottomTrailing) { resizeHandle.opacity(chromeOpacity) }
            .contentShape(.rect(cornerRadius: Self.cornerRadius))
            // Raises the pin and shows where its ink came from.
            .onTapGesture(perform: onTap)
            // Alongside the single tap rather than in front of it: an exclusive
            // double tap would hold every single tap back while it waited to
            // see whether a second was coming.
            .simultaneousGesture(TapGesture(count: 2).onEnded(onDoubleTap))
            .gesture(moveGesture.simultaneously(with: pinchGesture))
            .scaleEffect(flight.scale)
            .offset(flight.offset)
            .position(frame.center)
            .onAppear(perform: flyInIfArriving)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pinned reference")
            .accessibilityIdentifier("pinnedReference")
    }

    // MARK: - Arrival

    private var isAtSource: Bool { arrival != nil && !hasLanded }

    /// The scale and shift that lay the card's ink exactly over the ink on the
    /// page: the card centres its ink, so its centre goes to the ink's centre,
    /// and it shrinks by how much more it magnifies the ink than the canvas does.
    private func flightTransform(frame: (center: CGPoint, size: CGSize)) -> (scale: CGFloat, offset: CGSize) {
        guard isAtSource, let arrival else { return (1, .zero) }
        let fitScale = PinnedReferenceGeometry.inkFitScale(inkBounds: inkBounds, cardSize: frame.size)
        guard fitScale > 0 else { return (1, .zero) }
        return (
            arrival.canvasScale / fitScale,
            CGSize(
                width: arrival.sourceInkCenter.x - frame.center.x,
                height: arrival.sourceInkCenter.y - frame.center.y
            )
        )
    }

    private func flyInIfArriving() {
        guard arrival != nil, !hasLanded else { return }
        // With Reduce Motion on, the pin just appears where it belongs.
        guard !reduceMotion else {
            hasLanded = true
            onArrived()
            return
        }
        withAnimation(Self.flight) {
            hasLanded = true
        } completion: {
            onArrived()
        }
    }

    // MARK: - Frame

    private var inkSize: CGSize { inkBounds.size }

    /// Where the card is drawn right now: the stored frame with every gesture
    /// still in flight applied on top.
    private var liveFrame: (center: CGPoint, size: CGSize) {
        var resized = (center: reference.center, longestSide: reference.longestSide)
        if let pinch {
            resized = pinchedFrame(pinch)
        }
        if handleTranslation != .zero {
            resized = PinnedReferenceGeometry.resizedFromCorner(
                center: reference.center,
                longestSide: reference.longestSide,
                inkSize: inkSize,
                dragTranslation: handleTranslation,
                viewport: viewport
            )
        }
        let size = PinnedReferenceGeometry.cardSize(inkSize: inkSize, longestSide: resized.longestSide)
        let moved = CGPoint(
            x: resized.center.x + moveTranslation.width,
            y: resized.center.y + moveTranslation.height
        )
        return (PinnedReferenceGeometry.clampedCenter(moved, cardSize: size, viewport: viewport), size)
    }

    private func clampedCenter(_ center: CGPoint, longestSide: CGFloat) -> CGPoint {
        let size = PinnedReferenceGeometry.cardSize(inkSize: inkSize, longestSide: longestSide)
        return PinnedReferenceGeometry.clampedCenter(center, cardSize: size, viewport: viewport)
    }

    // MARK: - Gestures

    /// Global coordinates: the card moves under the finger as it is dragged, so
    /// a translation measured in its own space would chase itself. The move
    /// starts at the same tap circle as a selection drag, so the two feel alike;
    /// the translation is measured from touchdown, so the card jumps to the nib.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: SelectionTouchClassifier.tapRadius, coordinateSpace: .global)
            .updating($moveTranslation) { value, translation, _ in translation = value.translation }
            .onEnded { value in
                let moved = CGPoint(
                    x: reference.center.x + value.translation.width,
                    y: reference.center.y + value.translation.height
                )
                onMove(clampedCenter(moved, longestSide: reference.longestSide))
            }
    }

    /// Scales about the point the pinch started at, like the canvas zoom.
    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, pinch, _ in
                pinch = PinchState(magnification: value.magnification, anchor: value.startAnchor)
            }
            .onEnded { value in
                let resized = pinchedFrame(PinchState(magnification: value.magnification, anchor: value.startAnchor))
                onResize(clampedCenter(resized.center, longestSide: resized.longestSide), resized.longestSide)
            }
    }

    private func pinchedFrame(_ pinch: PinchState) -> (center: CGPoint, longestSide: CGFloat) {
        PinnedReferenceGeometry.resizedAboutAnchor(
            center: reference.center,
            longestSide: reference.longestSide,
            inkSize: inkSize,
            magnification: pinch.magnification,
            anchor: CGPoint(x: pinch.anchor.x, y: pinch.anchor.y),
            viewport: viewport
        )
    }

    private var handleGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($handleTranslation) { value, translation, _ in translation = value.translation }
            .onEnded { value in
                let resized = PinnedReferenceGeometry.resizedFromCorner(
                    center: reference.center,
                    longestSide: reference.longestSide,
                    inkSize: inkSize,
                    dragTranslation: value.translation,
                    viewport: viewport
                )
                onResize(clampedCenter(resized.center, longestSide: resized.longestSide), resized.longestSide)
            }
    }

    // MARK: - Controls

    /// Measured from where the card is drawn right now, so the arrow keeps
    /// pointing the right way if the card is dragged while it fades.
    private func sourceArrow(frame: (center: CGPoint, size: CGSize)) -> some View {
        let placement = offscreenSourcePoint.flatMap { target in
            PinnedReferenceGeometry.sourceArrowPlacement(
                cardCenter: frame.center,
                cardSize: frame.size,
                toward: target,
                inset: PinnedSourceArrowView.size / 2 + 4
            )
        }
        let offset = placement.map {
            CGSize(width: $0.center.x - frame.center.x, height: $0.center.y - frame.center.y)
        } ?? .zero
        return PinnedSourceArrowView(angle: placement?.angle, trigger: sourceFlashTrigger)
            .offset(offset)
    }

    private var unpinButton: some View {
        Button(action: onUnpin) {
            PinnedReferenceControlGlyph(systemImage: "xmark", size: Self.controlSize)
        }
        .buttonStyle(.plain)
        .padding(4)
        .accessibilityLabel("Unpin")
        .accessibilityIdentifier("pinnedReferenceUnpin")
    }

    private var resizeHandle: some View {
        PinnedReferenceControlGlyph(
            systemImage: "arrow.up.left.and.arrow.down.right",
            size: Self.controlSize
        )
        .padding(4)
        .contentShape(.rect)
        // High priority, or the card's own drag takes the touch and moves the
        // card instead of resizing it.
        .highPriorityGesture(handleGesture)
        .accessibilityLabel("Resize pinned reference")
        .accessibilityIdentifier("pinnedReferenceResize")
    }
}

/// A pinch in flight: how far it has scaled, and where on the card it began.
private struct PinchState {
    let magnification: CGFloat
    let anchor: UnitPoint
}

/// A small round control sitting on a pin's corner. Material-backed so it reads
/// over ink of any colour on paper of any colour.
private struct PinnedReferenceControlGlyph: View {
    let systemImage: String
    let size: CGFloat

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.regularMaterial, in: .circle)
    }
}
