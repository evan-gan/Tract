import SwiftUI

/// `UIViewRepresentable` wrapper around `CanvasUIView`.
/// This file contains wrapping logic only — no drawing, no input handling.
struct CanvasView: UIViewRepresentable {
    let viewModel: CanvasViewModel

    func makeUIView(context: Context) -> CanvasUIView {
        let view = CanvasUIView()
        view.viewModel = viewModel
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: CanvasUIView, context: Context) {
        // The UIView doesn't need to re-configure on updates;
        // CanvasUIView reads from viewModel directly via Task.
        uiView.viewModel = viewModel
    }
}
