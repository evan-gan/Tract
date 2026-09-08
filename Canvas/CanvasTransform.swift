import CoreGraphics

/// Value type representing the current pan and zoom state of the infinite canvas.
/// All stroke positions are stored in canvas space; this transform converts
/// between canvas space and screen space.
struct CanvasTransform: Sendable {
    /// Zoom limits. Clamped here rather than in the pinch handler so no caller —
    /// a restored document, a future zoom control — can put the canvas somewhere
    /// the user cannot pinch their way back out of.
    static let minimumScale: CGFloat = 0.1
    static let maximumScale: CGFloat = 4.0

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

    /// The canvas-space rect a view of this size is currently showing.
    ///
    /// The renderer culls against it: on an infinite canvas most of a long
    /// document is off screen, and ink nobody can see costs nothing to skip.
    func visibleCanvasRect(inViewOfSize viewSize: CGSize) -> CGRect {
        CGRect(origin: .zero, size: viewSize).applying(matrix.inverted())
    }

    /// Convert a canvas-space length — a stroke width, a radius — to screen points.
    ///
    /// Widths are stored in canvas space, so they have to grow and shrink with the
    /// zoom exactly like the geometry they belong to. Left unscaled, zooming in
    /// would thin the ink relative to the drawing instead of magnifying it.
    func toScreen(length canvasLength: CGFloat) -> CGFloat {
        canvasLength * scale
    }

    /// The transform that shows `contentRect` centred in a view of `viewSize`,
    /// as large as the zoom limits and `padding` allow.
    ///
    /// - Parameters:
    ///   - contentRect: Canvas-space box to bring into view.
    ///   - viewSize: Size of the canvas view, in screen points.
    ///   - padding: Screen-space breathing room to leave on every side.
    /// - Returns: The fitted transform, or `nil` when there is nothing to fit —
    ///   an empty box, or a view too small to hold the padding.
    static func fitting(
        _ contentRect: CGRect,
        inViewOfSize viewSize: CGSize,
        padding: CGFloat = 48
    ) -> CanvasTransform? {
        guard !contentRect.isNull, !contentRect.isInfinite else { return nil }

        let availableWidth = viewSize.width - padding * 2
        let availableHeight = viewSize.height - padding * 2
        guard availableWidth > 0, availableHeight > 0 else { return nil }

        // A drawing with no extent on an axis — a single dot, one horizontal
        // line — puts no ceiling on the zoom from that axis, so it sits out of
        // the minimum rather than dividing by zero.
        let widthLimit = contentRect.width > 0 ? availableWidth / contentRect.width : .infinity
        let heightLimit = contentRect.height > 0 ? availableHeight / contentRect.height : .infinity
        let unclampedScale = min(widthLimit, heightLimit)

        var fitted = CanvasTransform()
        // Assigning through `scale` clamps to the zoom limits; `.infinity` — every
        // axis unbounded — lands on the maximum, which is the right answer for a dot.
        fitted.scale = unclampedScale
        fitted.translation = CGPoint(
            x: viewSize.width / 2 - contentRect.midX * fitted.scale,
            y: viewSize.height / 2 - contentRect.midY * fitted.scale
        )
        return fitted
    }

    /// Convert a screen-space length — a fingertip's reach, an eraser tip — to
    /// canvas units, so a tolerance that should stay a fixed size under the hand
    /// can be compared against canvas geometry.
    func toCanvas(length screenLength: CGFloat) -> CGFloat {
        screenLength / scale
    }

}
