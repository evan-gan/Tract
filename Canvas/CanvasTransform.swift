import CoreGraphics

/// Value type representing the current pan and zoom state of the infinite canvas.
/// All stroke positions are stored in canvas space; this transform converts
/// between canvas space and screen space.
struct CanvasTransform: Sendable {
    var scale: CGFloat = 1.0
    var translation: CGPoint = .zero

    /// The affine transform that maps canvas space → screen space.
    /// Order matters: scale first, then translate. This gives `p' = p*scale + translation`,
    /// which is what the zoom formula assumes. Reversed order would scale the translation
    /// offset too, making zoom anchoring incorrect.
    var matrix: CGAffineTransform {
        CGAffineTransform.identity
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: translation.x, y: translation.y)
    }

    /// Convert a screen-space point to canvas space (for pencil input).
    func toCanvas(_ screenPoint: CGPoint) -> CGPoint {
        screenPoint.applying(matrix.inverted())
    }

    /// Convert a canvas-space point to screen space (for rendering).
    func toScreen(_ canvasPoint: CGPoint) -> CGPoint {
        canvasPoint.applying(matrix)
    }

    /// Zoom about a fixed screen point so that point stays under the finger.
    mutating func zoom(by factor: CGFloat, around screenAnchor: CGPoint) {
        // Translate so the anchor is at the origin, scale, translate back.
        translation.x = screenAnchor.x + (translation.x - screenAnchor.x) * factor
        translation.y = screenAnchor.y + (translation.y - screenAnchor.y) * factor
        scale *= factor
    }

}
