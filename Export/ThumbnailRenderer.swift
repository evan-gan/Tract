import UIKit

/// Renders the small preview shown on a document card in the library.
///
/// Kept separate from `PNGExporter`: an export is a faithful, full-resolution
/// copy of the ink, while a thumbnail is deliberately scaled to fit a fixed card
/// and drawn on opaque paper so it reads at 200 points wide.
enum ThumbnailRenderer {
    /// Card previews are wider than tall, matching the aspect the library draws.
    static let size = CGSize(width: 400, height: 300)

    /// Never let a small drawing be blown up to fill the card — a three-inch
    /// scribble magnified 20× reads as an abstract blob rather than as itself.
    private static let maximumScale: CGFloat = 1.0

    /// Ink is inset from the card edges so strokes do not run into the crop.
    private static let contentInset: CGFloat = 12

    /// - Returns: PNG data, or nil when there is no ink to preview.
    static func renderPNG(strokes: [Stroke], paperColor: UIColor = .white) -> Data? {
        let inkBounds = StrokeRasterizer.unionBounds(of: strokes.filter(\.style.tool.isDrawingTool))
        guard !inkBounds.isNull, !strokes.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        // Thumbnails are cached to disk and only ever shown small; 1× keeps the
        // file a few kilobytes instead of a few hundred.
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            paperColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let fit = fitTransform(for: inkBounds)
            context.cgContext.concatenate(fit)
            StrokeRasterizer.draw(strokes, in: context.cgContext, offset: inkBounds.origin)
        }
    }

    /// Scales the ink to fit inside the card's inset area and centres it.
    /// The returned transform expects stroke coordinates already offset by
    /// `inkBounds.origin`, i.e. starting at (0, 0).
    private static func fitTransform(for inkBounds: CGRect) -> CGAffineTransform {
        let available = size.insetBy(contentInset)
        // A perfectly horizontal or vertical drawing has zero extent on one axis;
        // fall back to the other so it still lands on the card instead of dividing by zero.
        let widthScale = inkBounds.width > 0 ? available.width / inkBounds.width : .greatestFiniteMagnitude
        let heightScale = inkBounds.height > 0 ? available.height / inkBounds.height : .greatestFiniteMagnitude
        let scale = min(widthScale, heightScale, maximumScale)

        let scaledSize = CGSize(width: inkBounds.width * scale, height: inkBounds.height * scale)
        return CGAffineTransform(translationX: (size.width - scaledSize.width) / 2,
                                 y: (size.height - scaledSize.height) / 2)
            .scaledBy(x: scale, y: scale)
    }
}

private extension CGSize {
    func insetBy(_ inset: CGFloat) -> CGSize {
        CGSize(width: max(width - inset * 2, 1), height: max(height - inset * 2, 1))
    }
}
