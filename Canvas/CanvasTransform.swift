import CoreGraphics

/// Value type representing the current pan and zoom state of the infinite canvas.
/// All stroke positions are stored in canvas space; this transform converts
/// between canvas space and screen space.
struct CanvasTransform: Sendable {
    /// Zoom limits. Clamped here rather than in the pinch handler so no caller —
    /// a restored document, a future zoom control — can put the canvas somewhere
    /// the user cannot pinch their way back out of.
    static let minimumScale: CGFloat = 0.1
    static let maximumScale: CGFloat = 5.0

    /// Assigning out of range silently clamps. Re-assigning inside `didSet` does
    /// not re-trigger it, so this settles in one pass.
    var scale: CGFloat = 1.0 {
        didSet { scale = min(max(scale, Self.minimumScale), Self.maximumScale) }
    }
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

    /// Convert a canvas-space length — a stroke width, a radius — to screen points.
    ///
    /// Widths are stored in canvas space, so they have to grow and shrink with the
    /// zoom exactly like the geometry they belong to. Left unscaled, zooming in
    /// would thin the ink relative to the drawing instead of magnifying it.
    func toScreen(length canvasLength: CGFloat) -> CGFloat {
        canvasLength * scale
    }

}
