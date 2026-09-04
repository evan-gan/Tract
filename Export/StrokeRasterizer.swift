import CoreGraphics

/// Draws strokes into a `CGContext`. Shared by every raster consumer — PNG
/// export, PDF export and document thumbnails — so a change to how ink looks
/// lands in all three at once instead of in one and not the others.
enum StrokeRasterizer {
    /// The smallest rect containing every stroke, in canvas space.
    /// `.null` when there is nothing to bound.
    static func unionBounds(of strokes: [Stroke]) -> CGRect {
        strokes.reduce(CGRect.null) { $0.union($1.canvasBounds) }
    }

    /// The smallest rect containing the ink as it is actually *painted*, in
    /// canvas space. `.null` when there is nothing to bound.
    ///
    /// `unionBounds` traces the centreline the samples describe, but a stroke is
    /// drawn `lineWidth` wide about that line and capped round at its ends, so
    /// half a nib always sits outside it. Cropping or fitting to the centreline
    /// shaves that half off — a flat edge down the outermost mark, and the more
    /// the drawing is scaled up to fill its box the more obvious it gets.
    static func inkedBounds(of strokes: [Stroke]) -> CGRect {
        let centrelineBounds = unionBounds(of: strokes)
        guard !centrelineBounds.isNull else { return centrelineBounds }

        // The widest nib in the set: any narrower stroke is covered by it, and
        // per-stroke padding would need per-stroke bounds to be worth anything.
        let widestNib = strokes
            .filter(\.style.tool.isDrawingTool)
            .map(\.style.lineWidth)
            .max() ?? 0
        return centrelineBounds.insetBy(dx: -widestNib / 2, dy: -widestNib / 2)
    }

    static func strokes(_ strokes: [Stroke], intersecting viewport: CGRect?) -> [Stroke] {
        guard let viewport else { return strokes }
        return strokes.filter { $0.canvasBounds.intersects(viewport) }
    }

    /// Only the strokes that will actually put ink on the page. Bounds taken over
    /// anything else — a lasso loop, a single tap with no segment to draw — pad an
    /// export with empty space around marks the viewer will never see.
    static func inkStrokes(_ strokes: [Stroke], intersecting viewport: CGRect? = nil) -> [Stroke] {
        self.strokes(strokes, intersecting: viewport)
            .filter { $0.style.tool.isDrawingTool && $0.points.count >= 2 }
    }

    /// - Parameters:
    ///   - offset: Canvas-space origin that maps to (0, 0) in the context —
    ///     normally the origin of the exported bounds.
    static func draw(_ strokes: [Stroke], in cgContext: CGContext, offset: CGPoint) {
        cgContext.setLineCap(.round)
        cgContext.setLineJoin(.round)

        for stroke in strokes {
            // The eraser and lasso lay down no ink, and a single sample has no
            // segment to draw — CanvasRenderer skips both, so exports must too.
            guard stroke.style.tool.isDrawingTool, stroke.points.count >= 2 else { continue }
            cgContext.setStrokeColor(cgColor(from: stroke.style))
            cgContext.setLineWidth(stroke.style.lineWidth)
            cgContext.addPath(path(for: stroke, offset: offset))
            cgContext.strokePath()
        }
    }

    /// Midpoint quadratic Béziers through the samples — the same smoothing
    /// `CanvasRenderer` uses on screen, so a raster of a drawing matches what
    /// the user was actually looking at.
    static func path(for stroke: Stroke, offset: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let points = stroke.points.map { $0.position - offset }
        path.move(to: points[0])

        for index in 1 ..< points.count {
            let previous = points[index - 1]
            let midpoint = previous.midpoint(to: points[index])
            if index == 1 {
                path.addLine(to: midpoint)
            } else {
                path.addQuadCurve(to: midpoint, control: previous)
            }
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    private static func cgColor(from style: StrokeStyle) -> CGColor {
        CGColor(
            red: CGFloat(style.color.x),
            green: CGFloat(style.color.y),
            blue: CGFloat(style.color.z),
            alpha: CGFloat(style.color.w) * style.opacity
        )
    }
}
