import CoreGraphics

/// Value type representing the current pan and zoom state of the infinite canvas.
/// All stroke positions are stored in canvas space; this transform converts
/// between canvas space and screen space.
struct CanvasTransform: Sendable {
    var scale: CGFloat = 1.0
    var translation: CGPoint = .zero

    /// The affine transform that maps canvas space → screen space: `p' = p*scale + translation`.
    /// Built directly rather than via .scaledBy().translatedBy() because CGAffineTransformTranslate
    /// multiplies tx/ty by the existing scale (new_tx = old_tx + dx * a), which would make
    /// the stored translation mean screen-space-offset-divided-by-scale — not what the
    /// pinch formula or toCanvas/toScreen callers expect.
    var matrix: CGAffineTransform {
        CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: translation.x, ty: translation.y)
    }

    /// Convert a screen-space point to canvas space (for pencil input).
    func toCanvas(_ screenPoint: CGPoint) -> CGPoint {
        screenPoint.applying(matrix.inverted())
    }

    /// Convert a canvas-space point to screen space (for rendering).
    func toScreen(_ canvasPoint: CGPoint) -> CGPoint {
        canvasPoint.applying(matrix)
    }

}
