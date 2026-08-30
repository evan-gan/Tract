import CoreGraphics

/// Maps a drawing's canvas-space bounds onto a target rect. Shared by every
/// consumer that has to place ink inside a box it did not choose — a library
/// thumbnail card, a PDF page, a cell in a problem table.
enum InkFitTransform {
    /// A transform that scales ink down to fit `target` and centres it there.
    ///
    /// - Parameters:
    ///   - inkBounds: Canvas-space bounds of the ink being placed.
    ///   - target: Destination rect, in the coordinate space of the context the
    ///     transform will be concatenated onto.
    ///   - maximumScale: Ceiling on enlargement. The default of 1 reproduces ink
    ///     at its natural size; pass a larger value to let a small drawing grow
    ///     to fill the target.
    /// - Returns: A transform expecting stroke coordinates already offset by
    ///   `inkBounds.origin`, i.e. starting at (0, 0).
    static func centring(
        _ inkBounds: CGRect,
        in target: CGRect,
        maximumScale: CGFloat = 1
    ) -> CGAffineTransform {
        // A perfectly horizontal or vertical drawing has zero extent on one axis;
        // fall back to the other so it still lands in the box instead of dividing by zero.
        let widthScale = inkBounds.width > 0 ? target.width / inkBounds.width : .greatestFiniteMagnitude
        let heightScale = inkBounds.height > 0 ? target.height / inkBounds.height : .greatestFiniteMagnitude
        let scale = min(widthScale, heightScale, maximumScale)

        let scaledSize = CGSize(width: inkBounds.width * scale, height: inkBounds.height * scale)
        return CGAffineTransform(
            translationX: target.midX - scaledSize.width / 2,
            y: target.midY - scaledSize.height / 2
        )
        .scaledBy(x: scale, y: scale)
    }
}
