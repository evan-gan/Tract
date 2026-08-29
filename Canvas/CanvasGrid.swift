import CoreGraphics

/// Placement maths for the paper's dot grid. Pure and view-free so the spacing
/// rules can be tested without rendering anything.
///
/// The grid belongs to the paper, not the screen: its dots sit at fixed canvas
/// coordinates, so they pan and zoom with the ink drawn on them.
enum CanvasGrid {
    /// Distance between dots in canvas space.
    static let canvasSpacing: CGFloat = 48
    static let canvasDotRadius: CGFloat = 1

    /// Below this the dots crowd into a texture and the count explodes — at 10%
    /// zoom a literal 48pt grid would be 4.8pt apart, tens of thousands of dots
    /// on an iPad screen. The grid coarsens by doubling instead, which keeps the
    /// remaining dots exactly where they were.
    static let minimumScreenSpacing: CGFloat = 12

    /// A dot is a mark on the paper, not a blob: it grows with the zoom, but only
    /// so far, and never shrinks below what a display can actually show.
    static let minimumDotRadius: CGFloat = 0.4
    static let maximumDotRadius: CGFloat = 2.5

    /// Screen distance between neighbouring dots at a given zoom.
    ///
    /// - Parameter scale: Canvas zoom factor; values at or below zero fall back
    ///   to the unzoomed spacing.
    /// - Returns: The on-screen gap, coarsened by successive doubling until it is
    ///   at least `minimumScreenSpacing`.
    static func screenSpacing(atScale scale: CGFloat) -> CGFloat {
        guard scale > 0 else { return canvasSpacing }
        var spacing = canvasSpacing * scale
        // Doubling keeps every surviving dot on a canvas coordinate the finer
        // grid also used, so coarsening drops dots instead of shifting them.
        while spacing < minimumScreenSpacing {
            spacing *= 2
        }
        return spacing
    }

    static func dotRadius(atScale scale: CGFloat) -> CGFloat {
        let scaled = canvasDotRadius * max(scale, 0)
        return min(max(scaled, minimumDotRadius), maximumDotRadius)
    }

    /// Screen position of the first dot at or after the origin on one axis.
    ///
    /// Dot screen positions are `translation + multiple of spacing`, so the whole
    /// row is fixed by where that pattern first lands inside the viewport.
    ///
    /// - Parameters:
    ///   - translation: The transform's translation on this axis, in screen points.
    ///   - spacing: Screen distance between dots, from `screenSpacing(atScale:)`.
    /// - Returns: An offset in `0 ..< spacing`.
    static func firstDotOffset(translation: CGFloat, spacing: CGFloat) -> CGFloat {
        guard spacing > 0 else { return 0 }
        let phase = translation.truncatingRemainder(dividingBy: spacing)
        return phase < 0 ? phase + spacing : phase
    }
}
