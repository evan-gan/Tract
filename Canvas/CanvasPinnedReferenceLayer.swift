import SwiftUI

/// The pinned references, floating in screen space over the canvas.
///
/// Its own layer, like `CanvasSelectionLayer`, so that moving a pin repaints
/// only the pins — and because, unlike everything in that layer, nothing here
/// reads the canvas transform: a pan or a zoom must not touch it at all.
struct CanvasPinnedReferenceLayer: View {
    let viewModel: CanvasViewModel

    var body: some View {
        // Empty space in a GeometryReader takes no touches, so the canvas under
        // it keeps drawing everywhere but on the cards themselves.
        GeometryReader { proxy in
            ZStack {
                ForEach(viewModel.pins.references) { reference in
                    card(for: reference, viewport: proxy.size)
                }
            }
        }
    }

    /// A pin whose ink has all been erased draws nothing, but is kept rather
    /// than removed — an undo brings the ink, and so the pin, straight back.
    @ViewBuilder
    private func card(for reference: PinnedReference, viewport: CGSize) -> some View {
        let ink = viewModel.pinnedInk(for: reference)
        if !ink.isEmpty {
            PinnedReferenceCard(
                reference: reference,
                strokes: ink,
                inkBounds: StrokeRasterizer.inkedBounds(of: ink),
                viewport: viewport,
                paperColor: viewModel.backgroundStyle.paper.sheet,
                offscreenSourcePoint: offscreenSourcePoint(for: reference),
                sourceFlashTrigger: viewModel.pins.sourceHighlightSequence,
                arrival: viewModel.pins.arrival?.pinID == reference.id ? viewModel.pins.arrival : nil,
                onArrived: { viewModel.pins.finishArrival(of: reference.id) },
                onTap: { viewModel.handlePinTap(reference.id) },
                onDoubleTap: { viewModel.panToPinSource(reference.id) },
                onMove: { viewModel.pins.move(reference.id, to: $0) },
                onResize: { viewModel.pins.resize(reference.id, longestSide: $1, center: $0) },
                onUnpin: { viewModel.pins.unpin(reference.id) }
            )
        }
    }

    /// Captured when the pin was tapped rather than tracked live, which is what
    /// keeps this layer from reading the canvas transform.
    private func offscreenSourcePoint(for reference: PinnedReference) -> CGPoint? {
        guard let highlight = viewModel.pins.sourceHighlight, highlight.pinID == reference.id
        else { return nil }
        return highlight.offscreenSourcePoint
    }
}
