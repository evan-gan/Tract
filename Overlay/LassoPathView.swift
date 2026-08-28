import SwiftUI

/// The loop the user is currently tracing with the lasso. Drawn closed — the
/// straight run between the two ends is exactly the edge the enclosure test
/// uses, so the user sees the region they are about to select.
/// The dashes hold still here; they only march once a selection exists.
struct LassoPathView: View {
    /// The in-progress loop in canvas space.
    let canvasPoints: [CGPoint]
    let transform: CanvasTransform

    var body: some View {
        Canvas { context, _ in
            guard canvasPoints.count >= 2 else { return }
            context.stroke(
                loopPath(),
                with: .color(SelectionStyle.color),
                style: SelectionStyle.outline()
            )
        }
        .allowsHitTesting(false)
        // The loop must track the pencil exactly, with no animated catch-up.
        .transaction { $0.animation = nil }
    }

    private func loopPath() -> Path {
        Path { path in
            let screenPoints = canvasPoints.map(transform.toScreen)
            path.addLines(screenPoints)
            path.closeSubpath()
        }
    }
}
