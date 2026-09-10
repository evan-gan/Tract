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

    private func draw(_ region: ProblemBounds, in context: inout GraphicsContext) {
        let isSelected = region.nodeID == selectedNodeID
        let tint = ProblemTintPalette.color(forProblemIndex: region.problemIndex)
        let path = Path { path in
            for contour in region.contours {
                path.addSmoothedLoop(through: contour.map(transform.toScreen))
            }
        }

        context.fill(
            path,
            with: .color(tint.opacity(isSelected
                ? ProblemBoundsStyle.selectedFillOpacity
                : ProblemBoundsStyle.fillOpacity)),
            // Even-odd so an enclosed hole is left unfilled whichever way
            // marching squares happened to wind it.
            style: FillStyle(eoFill: true)
        )
        context.stroke(
            path,
            with: .color(tint.opacity(isSelected
                ? ProblemBoundsStyle.selectedStrokeOpacity
                : ProblemBoundsStyle.strokeOpacity)),
            lineWidth: isSelected
                ? ProblemBoundsStyle.selectedLineWidth
                : ProblemBoundsStyle.lineWidth
        )
    }
}
