#if canImport(UIKit)
import UIKit
#else
#error("This file requires UIKit and is designed for iOS/iPadOS only")
#endif

/// UIView subclass responsible for four things only:
///   1. Routing Apple Pencil touches to the view model.
///   2. Handling one-finger pan, two-finger pan, and pinch-to-zoom gestures.
///   3. Tracking where the pencil hovers, so the canvas can preview the nib.
///   4. Letting one finger move a lasso selection, and a tap act on or dismiss it.
///
/// Finger touches are intentionally ignored for drawing — they fall through
/// to the gesture recognizers, which are also configured to finger-only.
final class CanvasUIView: UIView {
    var viewModel: CanvasViewModel?

    // Pinch gesture handles both pan and zoom — a single recognizer for all
    // two-finger canvas navigation, eliminating any interference between
    // a separate pan recognizer and the pinch recognizer.
    private let pinchGesture = UIPinchGestureRecognizer()

    // One finger drags the paper. Palm rejection lives inside the recognizer, so
    // a hand can rest on the canvas while a finger elsewhere pans it.
    private let fingerPanGesture = FingerPanGestureRecognizer(target: nil, action: nil)

    // Reports the pencil's position while it is near the glass but not touching,
    // which is what drives the hover preview dot.
    private let hoverGesture = UIHoverGestureRecognizer()

    // One finger moves an existing selection. It only begins when the touch
    // lands inside the selection (see gestureRecognizerShouldBegin), so a finger
    // anywhere else still belongs to pan and zoom.
    private let selectionPanGesture = UIPanGestureRecognizer()

    // A finger tapping the selection asks what can be done with it; tapping the
    // blank paper drops it. Pencil taps need no equivalent: they already go
    // through the lasso's own begin/end path, which tells a tap from a drag there.
    private let selectionTapGesture = UITapGestureRecognizer()

    // Canvas-space positions of the two fingers captured at gesture start.
    // Held fixed for the duration of the gesture; each frame solves for the
    // transform that maps these canvas points back to the current finger positions.
    private var pinchCanvasAnchor0: CGPoint = .zero
    private var pinchCanvasAnchor1: CGPoint = .zero
    // Explicit validity flag — avoids stale values from a previous gesture
    // being used when .began fires with only 1 touch and our guard exits early.
    private var pinchAnchorsValid = false

    // Canvas-space point sitting under the panning finger, captured when the pan
    // begins. Solving against it each frame keeps that point glued to the finger.
    private var fingerPanCanvasAnchor: CGPoint = .zero
    private var fingerPanAnchorValid = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureGestures()
        configurePencilInteraction()
        isMultipleTouchEnabled = true
    }

    required init?(coder: NSCoder) {
        fatalError("CanvasUIView must be created in code, not Interface Builder")
    }

    // MARK: - Setup

    private func configureGestures() {
        // Restrict to finger touches only so the recognizer doesn't eat pencil input.
        let fingerTouchType = NSNumber(value: UITouch.TouchType.direct.rawValue)
        pinchGesture.allowedTouchTypes = [fingerTouchType]
        pinchGesture.delegate = self
        pinchGesture.addTarget(self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)

        // Touch types are set by the recognizer itself; it must see palms in order
        // to reject them, which is why it is not filtered down to fingertips here.
        fingerPanGesture.delegate = self
        fingerPanGesture.addTarget(self, action: #selector(handleFingerPan(_:)))
        addGestureRecognizer(fingerPanGesture)

        // Pencil only: a trackpad pointer also produces hover events, and a preview
        // dot chasing the cursor would be claiming a nib that isn't there.
        let pencilTouchType = NSNumber(value: UITouch.TouchType.pencil.rawValue)
        hoverGesture.allowedTouchTypes = [pencilTouchType]
        hoverGesture.addTarget(self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hoverGesture)

        // Capped at one touch so that adding a second finger hands the gesture
        // back to the pinch rather than dragging the selection around with it.
        selectionPanGesture.allowedTouchTypes = [fingerTouchType]
        selectionPanGesture.maximumNumberOfTouches = 1
        selectionPanGesture.delegate = self
        selectionPanGesture.addTarget(self, action: #selector(handleSelectionPan(_:)))
        addGestureRecognizer(selectionPanGesture)

        selectionTapGesture.allowedTouchTypes = [fingerTouchType]
        selectionTapGesture.delegate = self
        selectionTapGesture.addTarget(self, action: #selector(handleSelectionTap(_:)))
        addGestureRecognizer(selectionTapGesture)
    }

    private func configurePencilInteraction() {
        // Squeeze gesture for Pencil Pro tool switching.
        let pencilInteraction = UIPencilInteraction()
        pencilInteraction.delegate = self
        addInteraction(pencilInteraction)
    }

    // MARK: - Pencil touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        addStrokePoint(from: touch, phase: .began)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        // Consume coalesced touches to capture all 240 Hz Pencil Pro samples.
        let samples = event?.coalescedTouches(for: touch) ?? [touch]
        for sample in samples {
            addStrokePoint(from: sample, phase: .moved)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, touch.type == .pencil else { return }
        addStrokePoint(from: touch, phase: .ended)
        Task { @MainActor in viewModel?.endStroke() }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touches.first?.type == .pencil else { return }
        Task { @MainActor in viewModel?.cancelStroke() }
    }

    // MARK: - Pencil hover

    /// Publishes the hovering nib's screen position, and clears it the moment the
    /// pencil leaves range so no stale dot is left sitting on the canvas.
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        guard let viewModel else { return }
        let hoverLocation: CGPoint? = switch gesture.state {
        case .began, .changed: gesture.location(in: self)
        default: nil
        }
        // Hover callbacks already arrive on the main thread; going through a Task
        // would let the dot trail a frame or two behind the pencil.
        MainActor.assumeIsolated { viewModel.updatePencilHover(to: hoverLocation) }
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        for touch in touches {
            guard let index = touch.estimationUpdateIndex?.intValue else { continue }
            let point = makeStrokePoint(from: touch)
            Task { @MainActor in viewModel?.updateEstimatedPoint(updateIndex: index, with: point) }
        }
    }

    // MARK: - Point extraction

    private func addStrokePoint(from touch: UITouch, phase: UITouch.Phase) {
        guard let viewModel else { return }
        let point = makeStrokePoint(from: touch)
        Task { @MainActor in
            if phase == .began {
                viewModel.beginStroke(with: point)
            } else {
                viewModel.continueStroke(with: point)
            }
        }
    }

    private func makeStrokePoint(from touch: UITouch) -> StrokePoint {
        let screenPoint = touch.preciseLocation(in: self)
        // Transform from screen space into canvas space.
        let canvasPoint = viewModel?.canvasTransform.toCanvas(screenPoint) ?? screenPoint
        let updateIndex = touch.estimationUpdateIndex?.intValue
        return StrokePoint(
            position: canvasPoint,
            force: touch.force,
            azimuth: touch.azimuthAngle(in: self),
            altitude: touch.altitudeAngle,
            rollAngle: touch.rollAngle,
            estimatedPropertiesMask: touch.estimatedPropertiesExpectingUpdates.rawValue,
            estimationUpdateIndex: updateIndex
        )
    }

    // MARK: - Moving a selection with a finger

    /// Drags the current selection. Positions are converted to canvas space and
    /// handed over whole rather than as the recognizer's own translation, so the
    /// selection stays under the finger even if the canvas is zoomed mid-drag.
    @objc private func handleSelectionPan(_ gesture: UIPanGestureRecognizer) {
        guard let viewModel else { return }
        let screenLocation = gesture.location(in: self)
        MainActor.assumeIsolated {
            let canvasPoint = viewModel.canvasTransform.toCanvas(screenLocation)
            switch gesture.state {
            case .began: viewModel.beginSelectionDrag(at: canvasPoint)
            case .changed: viewModel.updateSelectionDrag(to: canvasPoint)
            case .ended: viewModel.endSelectionDrag()
            default: viewModel.cancelSelectionDrag()
            }
        }
    }

    /// Tapping the selection opens its action menu; tapping off it clears the
    /// selection. The recognizer itself is what keeps a drag out of this: it only
    /// fires for a touch that went down and up again without travelling.
    @objc private func handleSelectionTap(_ gesture: UITapGestureRecognizer) {
        guard let viewModel, gesture.state == .ended else { return }
        let screenLocation = gesture.location(in: self)
        MainActor.assumeIsolated {
            viewModel.handleSelectionTap(at: viewModel.canvasTransform.toCanvas(screenLocation))
        }
    }

    // MARK: - Gesture gating

    /// The selection drag claims a finger only when it starts on the selection.
    /// Refusing to begin here rather than bailing out in the handler is what
    /// leaves every other finger touch free for pan and zoom.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let viewModel else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        switch gestureRecognizer {
        case selectionPanGesture:
            return startsOnSelection(gestureRecognizer.location(in: self), viewModel: viewModel)
        case fingerPanGesture:
            // A finger that landed on the selection is moving the selection, not
            // the paper underneath it.
            return !startsOnSelection(fingerPanGesture.initialLocation, viewModel: viewModel)
        default:
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
    }

    private func startsOnSelection(_ screenLocation: CGPoint, viewModel: CanvasViewModel) -> Bool {
        MainActor.assumeIsolated {
            viewModel.selectionContains(viewModel.canvasTransform.toCanvas(screenLocation))
        }
    }

    // MARK: - One-finger pan

    /// Drags the paper under the finger. Like the pinch, it solves for the
    /// transform that puts the anchored canvas point back under the touch rather
    /// than accumulating the recognizer's frame-to-frame translation, so a pan
    /// interrupted by a zoom cannot drift.
    @objc private func handleFingerPan(_ gesture: FingerPanGestureRecognizer) {
        guard let viewModel else { return }
        // Both recognizers are allowed to run at once so neither can lock the other
        // out, which makes the pinch the tie-breaker: while it is driving the
        // transform, a leftover pan frame would fight it for the same translation.
        guard !isPinchActive else {
            fingerPanAnchorValid = false
            return
        }
        let screenLocation = gesture.location(in: self)
        MainActor.assumeIsolated {
            switch gesture.state {
            case .began:
                fingerPanCanvasAnchor = viewModel.canvasTransform.toCanvas(screenLocation)
                fingerPanAnchorValid = true
            case .changed:
                guard fingerPanAnchorValid else { return }
                let scale = viewModel.canvasTransform.scale
                viewModel.canvasTransform.translation = CGPoint(
                    x: screenLocation.x - fingerPanCanvasAnchor.x * scale,
                    y: screenLocation.y - fingerPanCanvasAnchor.y * scale
                )
            default:
                fingerPanAnchorValid = false
            }
        }
    }

    // MARK: - Pinch gesture (handles pan + zoom)

    private var isPinchActive: Bool {
        pinchGesture.state == .began || pinchGesture.state == .changed
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let viewModel else { return }

        // Invalidate anchors on gesture end so stale values can't bleed
        // into the next gesture. Must happen before the numberOfTouches
        // guard because terminal states often report fewer than 2 touches.
        guard gesture.state == .began || gesture.state == .changed else {
            pinchAnchorsValid = false
            return
        }

        guard gesture.numberOfTouches == 2 else { return }

        let curr0 = gesture.location(ofTouch: 0, in: self)
        let curr1 = gesture.location(ofTouch: 1, in: self)

        // All transform reads AND writes happen synchronously on the main
        // thread via assumeIsolated. Using async Tasks caused a race where
        // anchor capture read a stale transform that hadn't been updated by
        // the previous frame's queued Task yet.
        MainActor.assumeIsolated {
            // Capture anchors if not yet valid. Handles both:
            //   1. Normal: .began with 2 touches.
            //   2. Fallback: .began had 1 touch, so we capture lazily here.
            // First-frame computation is a no-op (produces the same transform).
            if !pinchAnchorsValid {
                pinchCanvasAnchor0 = viewModel.canvasTransform.toCanvas(curr0)
                pinchCanvasAnchor1 = viewModel.canvasTransform.toCanvas(curr1)
                pinchAnchorsValid = true
            }

            guard gesture.state == .changed else { return }

            let a0 = pinchCanvasAnchor0
            let a1 = pinchCanvasAnchor1
            let canvasDist = a0.distance(to: a1)
            guard canvasDist > 0 else { return }

            // Solve for the unique scale+translation that places canvas point
            // a0 at screen position curr0 and a1 at curr1. Absolute, not
            // incremental, so floating-point errors cannot accumulate.
            viewModel.canvasTransform.scale = curr0.distance(to: curr1) / canvasDist
            // Read the scale back rather than reusing the requested one: at the
            // zoom limits it has been clamped, and solving with the unclamped
            // value would slide the canvas out from under a pinch that can no
            // longer zoom.
            let appliedScale = viewModel.canvasTransform.scale
            viewModel.canvasTransform.translation = CGPoint(
                x: curr0.x - a0.x * appliedScale,
                y: curr0.y - a0.y * appliedScale
            )
        }
    }
}

// The gate itself is an override of UIView's own hook, which cannot live in an
// extension — see `gestureRecognizerShouldBegin` above.
extension CanvasUIView: UIGestureRecognizerDelegate {
    /// Keeps palms out of the finger gestures. Without this a resting palm counts
    /// as a second contact, which would let a hand plus a finger read as a pinch
    /// and throw the canvas across the screen.
    ///
    /// The threshold is deliberately generous — see `FingerPanArbiter` — because a
    /// touch refused here is invisible to the gesture for the rest of the sequence,
    /// and losing one finger of a real pinch is far worse than letting a palm
    /// through to the movement test that backs this up.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard touch.type == .direct else { return true }
        return !FingerPanArbiter.isLikelyPalm(majorRadius: touch.majorRadius,
                                              tolerance: touch.majorRadiusTolerance)
    }

    /// The one-finger pan must never lock the pinch out.
    ///
    /// By default the first recognizer to recognize prevents the others sharing its
    /// touches — so a finger that panned even briefly before the second one landed
    /// would kill the pinch for the whole touch sequence, which is exactly the
    /// "pinch works sometimes" failure. Allowing them to run together means the
    /// pinch is always available; the pan then stands down on its own (it ends the
    /// moment a second fingertip arrives, and `handleFingerPan` ignores anything
    /// that arrives while the pinch is live) so the two never fight over the
    /// transform.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let pair = Set([ObjectIdentifier(gestureRecognizer), ObjectIdentifier(other)])
        return pair == Set([ObjectIdentifier(fingerPanGesture), ObjectIdentifier(pinchGesture)])
    }
}

// MARK: - UIPencilInteractionDelegate

extension CanvasUIView: UIPencilInteractionDelegate {
    func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
        Task { @MainActor in viewModel?.togglePencilShortcutTool() }
    }
}
