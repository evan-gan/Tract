import SwiftUI

/// The white canvas and its dot grid. The paper stays white in both colour
/// schemes — it is the sheet being drawn on, not chrome, and a canvas that
/// inverted would flip the meaning of every stroke colour already on it.
///
/// The grid tracks the canvas transform, so zooming magnifies the paper itself
/// rather than sliding the drawing across a fixed backdrop.
struct CanvasBackgroundView: View {
    let transform: CanvasTransform

    private static let dotColor: Color = .black.opacity(0.08)

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            drawDotGrid(in: &context, size: size)
        }
        // The paper must track the pencil and the pinch exactly; an animated
        // catch-up here would slide the grid out from under the ink.
        .transaction { $0.animation = nil }
    }

    private func drawDotGrid(in context: inout GraphicsContext, size: CGSize) {
        let spacing = CanvasGrid.screenSpacing(atScale: transform.scale)
        let radius = CanvasGrid.dotRadius(atScale: transform.scale)
        let firstX = CanvasGrid.firstDotOffset(translation: transform.translation.x,
                                               spacing: spacing)
        let firstY = CanvasGrid.firstDotOffset(translation: transform.translation.y,
                                               spacing: spacing)

        var x = firstX
        while x < size.width {
            var y = firstY
            while y < size.height {
                context.fill(dot(atX: x, y: y, radius: radius), with: .color(Self.dotColor))
                y += spacing
            }
            x += spacing
        }
    }

    private func dot(atX x: CGFloat, y: CGFloat, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                               width: radius * 2, height: radius * 2))
    }
}
