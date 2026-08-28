import SwiftUI

/// Converts `Stroke` data into a SwiftUI `Canvas` drawing.
/// Kept separate from the UIKit input layer so rendering can be swapped
/// for Metal later without touching any touch-handling code.
struct CanvasRenderer: View {
    let strokes: [Stroke]
    let activeStroke: Stroke?
    let transform: CanvasTransform

    var body: some View {
        Canvas { context, _ in
            for stroke in strokes {
                draw(stroke: stroke, in: &context)
            }
            if let active = activeStroke {
                draw(stroke: active, in: &context)
            }
        }
        // Disable animations on the canvas — strokes must appear instantly.
        .transaction { $0.animation = nil }
    }

    private func draw(stroke: Stroke, in context: inout GraphicsContext) {
        // The eraser and lasso leave no ink; documents saved before they became
        // non-drawing tools can still carry such strokes, so skip them here.
        guard stroke.style.tool.isDrawingTool, stroke.points.count >= 2 else { return }

        let path = buildPath(for: stroke)
        context.stroke(
            path,
            with: .color(stroke.style.swiftUIColor),
            style: SwiftUI.StrokeStyle(
                lineWidth: transform.toScreen(length: stroke.style.lineWidth),
                lineCap: .round,
                lineJoin: .round
            )
        )
    }

    /// Builds a smooth path through all stroke points using midpoint quadratic
    /// Béziers. The control point is the actual data point; the curve passes
    /// through midpoints — a cheap technique that looks smooth without cubic math.
    private func buildPath(for stroke: Stroke) -> Path {
        Path { path in
            let screenPoints = stroke.points.map { transform.toScreen($0.position) }
            path.move(to: screenPoints[0])

            for idx in 1 ..< screenPoints.count {
                let prev = screenPoints[idx - 1]
                let current = screenPoints[idx]
                let mid = prev.midpoint(to: current)
                if idx == 1 {
                    // First segment: straight line to first midpoint.
                    path.addLine(to: mid)
                } else {
                    path.addQuadCurve(to: mid, control: prev)
                }
            }
            path.addLine(to: screenPoints[screenPoints.count - 1])
        }
    }
}
