import SwiftUI

/// The zoom pill, wired to the canvas.
///
/// The live scale is read here rather than in the container: a pinch changes it
/// on every frame, and the top chrome around it has no reason to be rebuilt for
/// a number that moved.
struct CanvasZoomIndicator: View {
    let viewModel: CanvasViewModel
    let glassNamespace: Namespace.ID

    var body: some View {
        ZoomIndicatorView(
            scale: viewModel.canvasTransform.scale,
            onReset: viewModel.resetZoom
        )
        .glassEffectID("zoomIndicator", in: glassNamespace)
    }
}
