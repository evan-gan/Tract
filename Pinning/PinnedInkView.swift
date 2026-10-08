import SwiftUI

/// Paints pinned ink scaled to fill whatever size it is given.
struct PinnedInkView: View {
    /// The ink to paint, in page order — the order it must be painted in.
    let strokes: [Stroke]
    /// Canvas-space box the ink occupies, nib width included.
    let inkBounds: CGRect

    /// Resizing a pin repaints it every frame; the paths themselves do not
    /// change, so they are traced once and kept.
    @State private var pathCache = StrokePathCache()

    var body: some View {
        Canvas { context, size in
            context.concatenate(PinnedReferenceGeometry.inkTransform(inkBounds: inkBounds, cardSize: size))
            // The path cache is main-actor state, and the renderer runs on the
            // main thread either way.
            let paths = MainActor.assumeIsolated { strokes.map { pathCache.path(for: $0) } }
            for (stroke, path) in zip(strokes, paths) {
                context.stroke(
                    path,
                    with: .color(stroke.style.swiftUIColor),
                    style: SwiftUI.StrokeStyle(
                        lineWidth: stroke.style.lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
            }
        }
        .transaction { $0.animation = nil }
    }
}
