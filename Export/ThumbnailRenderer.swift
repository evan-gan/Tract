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
        let inkBounds = StrokeRasterizer.inkedBounds(of: strokes.filter(\.style.tool.isDrawingTool))
        guard !inkBounds.isNull, !strokes.isEmpty else { return nil }

        let format = UIGraphicsImageRendererFormat.preferred()
        // Thumbnails are cached to disk and only ever shown small; 1× keeps the
        // file a few kilobytes instead of a few hundred.
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            paperColor.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let contentRect = CGRect(origin: .zero, size: size).insetBy(dx: contentInset, dy: contentInset)
            context.cgContext.concatenate(
                InkFitTransform.centring(inkBounds, in: contentRect, maximumScale: maximumScale)
            )
            StrokeRasterizer.draw(strokes, in: context.cgContext, offset: inkBounds.origin)
        }
    }
}
