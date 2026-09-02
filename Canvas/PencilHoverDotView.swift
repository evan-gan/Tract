import SwiftUI

/// Hosts the pencil hover dot's layer above the canvas chrome.
///
/// The dot is *tracked* by `CanvasUIView`, which owns the hover recognizer, but
/// drawn one layer higher so the selection's marching ants cannot crawl across
/// the nib preview. It stays below the glass chrome: a dot floating over the
/// dock would be claiming a nib that is nowhere near the paper.
///
/// The hover location arrives in `CanvasUIView`'s coordinates and is used here
/// unchanged, so **both views must fill exactly the same space** — they are
/// stacked full-bleed in `CanvasContainerView` for that reason. Give either one
/// a different frame and the dot sits off the nib by the difference.
struct PencilHoverDotView: UIViewRepresentable {
    let hoverDot: PencilHoverDot

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        // Chrome only: every touch belongs to the canvas underneath.
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(hoverDot.layer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // Nothing to update: the dot is moved by the hover callback itself, which
        // is the whole point of it not being a SwiftUI view.
    }
}
