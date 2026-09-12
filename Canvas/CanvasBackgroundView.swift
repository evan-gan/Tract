import SwiftUI

/// The sheet of paper under the ink, in whichever style the document is set to.
/// The paper keeps its own colours in both colour schemes — it is the sheet
/// being drawn on, not chrome, and a canvas that inverted would flip the meaning
/// of every stroke colour already on it.
///
/// The pattern tracks the canvas transform, so zooming magnifies the paper
/// itself rather than sliding the drawing across a fixed backdrop.
struct CanvasBackgroundView: View {
    let style: CanvasBackgroundStyle
    let transform: CanvasTransform

    var body: some View {
        Canvas { context, size in
            CanvasPaperPainter.paint(style: style, transform: transform, size: size, in: &context)
        }
        // The paper must track the pencil and the pinch exactly; an animated
        // catch-up here would slide the pattern out from under the ink.
        .transaction { $0.animation = nil }
    }
}
