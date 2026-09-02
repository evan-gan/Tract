import SwiftUI

/// `UIViewRepresentable` wrapper around `CanvasUIView`.
/// This file contains wrapping logic only — no drawing, no input handling.
struct CanvasView: UIViewRepresentable {
    let viewModel: CanvasViewModel
    /// Moved by the hover recognizer inside `CanvasUIView`, but drawn by
    /// `PencilHoverDotView` further up the stack.
    let hoverDot: PencilHoverDot

    func makeUIView(context: Context) -> CanvasUIView {
        let view = CanvasUIView(hoverDot: hoverDot)
        view.viewModel = viewModel
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: CanvasUIView, context: Context) {
        // The UIView doesn't need to re-configure on updates;
        // CanvasUIView reads from viewModel directly.
        uiView.viewModel = viewModel
    }
}
