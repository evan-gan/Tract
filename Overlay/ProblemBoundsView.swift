import SwiftUI

/// The region drawn around each problem's work — the shape a tap has to land in
/// to switch the picker to that problem.
///
/// One `Canvas` for every region rather than a view each: the shapes are pure
/// geometry that has to be re-projected on each frame of a pan, and a stack of
/// views would put a layout pass in front of every one of them.
struct ProblemBoundsView: View {
    let regions: [ProblemBounds]
    /// The problem the picker is pointed at, drawn stronger than the rest so it
    /// is obvious which region new ink is going into.
    let selectedNodeID: UUID?
    let transform: CanvasTransform
    /// Where the automatic layout has moved each problem to. Added as each
    /// point is projected, which costs nothing — the point is being transformed
    /// anyway — where translating every contour up front would cost a pass over
    /// the whole page on every frame of the animation.
    var placement: ProblemLayoutPlacement = .identity
    /// The problem whose bubble is being replaced by the focus frame, and how
    /// far that replacement has got. The bubble fades out as the dashed box
    /// opens out of it, so the boundary reads as one shape changing rather than
    /// as two shapes swapping places.
    var focusFrameNodeID: UUID?
    var focusFrameProgress: CGFloat = 0
    /// The problem focus has just jumped away from, whose bubble fades back in
    /// as its box closes onto it.
    var closingFrameNodeID: UUID?
    var closingFrameProgress: CGFloat = 0

    var body: some View {
        Canvas { context, _ in
            for region in regions {
                draw(region, in: &context)
            }
        }
        // The regions are hit-tested against the canvas transform by
        // `CanvasViewModel`, not by SwiftUI, so this layer takes no touches of
        // its own — a tap has to reach the drawing surface underneath it.
        .allowsHitTesting(false)
    }

    /// How visible one region is: fully, unless it is the one dissolving into
    /// a focus frame.
    private func fade(for region: ProblemBounds) -> CGFloat {
        switch region.nodeID {
        case focusFrameNodeID: 1 - min(max(focusFrameProgress, 0), 1)
        case closingFrameNodeID: 1 - min(max(closingFrameProgress, 0), 1)
        default: 1
        }
    }

    private func draw(_ region: ProblemBounds, in context: inout GraphicsContext) {
        let fade = fade(for: region)
        guard fade > 0 else { return }

        let isSelected = region.nodeID == selectedNodeID
        let tint = ProblemTintPalette.color(forProblemIndex: region.problemIndex)
        let offset = placement.offset(forNode: region.nodeID)
        let path = Path { path in
            for contour in region.contours {
                path.addSmoothedLoop(through: contour.map { transform.toScreen($0 + offset) })
            }
        }

        let fillOpacity = (isSelected
            ? ProblemBoundsStyle.selectedFillOpacity
            : ProblemBoundsStyle.fillOpacity) * fade
        let strokeOpacity = (isSelected
            ? ProblemBoundsStyle.selectedStrokeOpacity
            : ProblemBoundsStyle.strokeOpacity) * fade

        context.fill(
            path,
            with: .color(tint.opacity(fillOpacity)),
            // Even-odd so an enclosed hole is left unfilled whichever way
            // marching squares happened to wind it.
            style: FillStyle(eoFill: true)
        )
        context.stroke(
            path,
            with: .color(tint.opacity(strokeOpacity)),
            lineWidth: isSelected
                ? ProblemBoundsStyle.selectedLineWidth
                : ProblemBoundsStyle.lineWidth
        )
    }
}
