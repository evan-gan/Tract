import SwiftUI

/// A thumbnail of one paper style, drawn by the same painter the canvas uses so
/// the swatch cannot drift from the sheet it is advertising.
struct CanvasPaperSwatch: View {
    let style: CanvasBackgroundStyle
    var cornerRadius: CGFloat = 8

    /// Zoomed out so a few cells of the pattern fit in a swatch this size, and
    /// panned right so the ruled papers show their margin rule.
    private static let previewScale: CGFloat = 0.32
    private static let marginFraction: CGFloat = 0.28

    var body: some View {
        Canvas { context, size in
            CanvasPaperPainter.paint(
                style: style,
                transform: previewTransform(for: size),
                size: size,
                in: &context
            )
        }
        .clipShape(.rect(cornerRadius: cornerRadius))
    }

    private func previewTransform(for size: CGSize) -> CanvasTransform {
        var transform = CanvasTransform()
        transform.scale = Self.previewScale
        transform.translation = CGPoint(x: size.width * Self.marginFraction, y: 0)
        return transform
    }
}
