import SwiftUI

/// Draws a sheet of paper into a `GraphicsContext`.
///
/// Free-standing rather than living inside `CanvasBackgroundView` because the
/// paper is drawn twice: full size under the ink, and thumbnail-sized inside
/// every swatch of the paper picker. One painter keeps the swatch honest — what
/// the user taps is literally what lands under their pencil.
enum CanvasPaperPainter {
    /// Paints the sheet and its pattern over the whole of `size`.
    ///
    /// - Parameters:
    ///   - style: Which paper to draw.
    ///   - transform: Canvas pan/zoom; the pattern is positioned in canvas space
    ///     so it tracks the ink.
    ///   - size: Area to cover, in screen points.
    ///   - context: Destination, drawn into in place.
    static func paint(
        style: CanvasBackgroundStyle,
        transform: CanvasTransform,
        size: CGSize,
        in context: inout GraphicsContext
    ) {
        let paper = style.paper
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(paper.sheet))

        switch paper.pattern {
        case .blank:
            break
        case .dots(let color):
            context.fill(dotGridPath(transform: transform, size: size), with: .color(color))
        case .grid(let minor, let major, let majorEvery):
            paintGrid(minor: minor, major: major, majorEvery: majorEvery,
                      transform: transform, size: size, in: &context)
        case .ruled(let rule, let margin):
            paintRules(rule: rule, margin: margin,
                       transform: transform, size: size, in: &context)
        }
    }

    // MARK: - Dots

    /// The whole grid goes down as **one** path and one fill. A fill per dot is
    /// hundreds of draw calls on every frame of a pan — at the minimum spacing,
    /// close to ten thousand — and that cost lands squarely on the gesture the
    /// paper is supposed to follow.
    private static func dotGridPath(transform: CanvasTransform, size: CGSize) -> Path {
        let spacing = CanvasGrid.screenSpacing(atScale: transform.scale)
        let radius = CanvasGrid.dotRadius(atScale: transform.scale)
        let firstX = CanvasGrid.firstDotOffset(translation: transform.translation.x, spacing: spacing)
        let firstY = CanvasGrid.firstDotOffset(translation: transform.translation.y, spacing: spacing)

        return Path { path in
            var x = firstX
            while x < size.width {
                var y = firstY
                while y < size.height {
                    path.addEllipse(in: CGRect(x: x - radius, y: y - radius,
                                               width: radius * 2, height: radius * 2))
                    y += spacing
                }
                x += spacing
            }
        }
    }

    // MARK: - Lines

    /// Squared paper: every line of the lattice, heavy ones stroked over light.
    private static func paintGrid(
        minor: Color,
        major: Color,
        majorEvery: Int,
        transform: CanvasTransform,
        size: CGSize,
        in context: inout GraphicsContext
    ) {
        var minorPath = Path()
        var majorPath = Path()
        let metrics = LineMetrics(transform: transform, majorEvery: majorEvery)

        metrics.appendLines(axis: .vertical, size: size, translation: transform.translation.x,
                            minor: &minorPath, major: &majorPath)
        metrics.appendLines(axis: .horizontal, size: size, translation: transform.translation.y,
                            minor: &minorPath, major: &majorPath)

        context.stroke(minorPath, with: .color(minor), lineWidth: metrics.width)
        context.stroke(majorPath, with: .color(major), lineWidth: metrics.width * 1.6)
    }

    /// Note paper: horizontal rules, plus the margin standing on canvas x = 0.
    private static func paintRules(
        rule: Color,
        margin: Color?,
        transform: CanvasTransform,
        size: CGSize,
        in context: inout GraphicsContext
    ) {
        var rulePath = Path()
        // Note paper has no heavy rules, so `majorEvery: 0` sends every line to
        // the light path and this one stays empty.
        var heavyRules = Path()
        let metrics = LineMetrics(transform: transform, majorEvery: 0)

        metrics.appendLines(axis: .horizontal, size: size, translation: transform.translation.y,
                            minor: &rulePath, major: &heavyRules)
        context.stroke(rulePath, with: .color(rule), lineWidth: metrics.width)

        guard let margin else { return }
        let marginX = transform.translation.x
        guard marginX >= 0, marginX <= size.width else { return }
        let marginLine = Path { path in
            path.move(to: CGPoint(x: marginX, y: 0))
            path.addLine(to: CGPoint(x: marginX, y: size.height))
        }
        context.stroke(marginLine, with: .color(margin), lineWidth: metrics.width * 1.6)
    }

    /// Line spacing, thickness and heavy-line rhythm at one zoom level, so the
    /// two axes of a lattice are laid out by the same numbers.
    private struct LineMetrics {
        let spacing: CGFloat
        let width: CGFloat
        let coarseningFactor: Int
        let majorEvery: Int

        init(transform: CanvasTransform, majorEvery: Int) {
            spacing = CanvasGrid.screenSpacing(atScale: transform.scale)
            width = CanvasGrid.lineWidth(atScale: transform.scale)
            coarseningFactor = CanvasGrid.coarseningFactor(atScale: transform.scale)
            self.majorEvery = majorEvery
        }

        enum Axis { case vertical, horizontal }

        /// Walks the visible lines on one axis into the light or heavy path.
        func appendLines(
            axis: Axis,
            size: CGSize,
            translation: CGFloat,
            minor: inout Path,
            major: inout Path
        ) {
            let extent = axis == .vertical ? size.width : size.height
            let crossExtent = axis == .vertical ? size.height : size.width
            var index = CanvasGrid.firstLineIndex(translation: translation, spacing: spacing)
            var position = translation + CGFloat(index) * spacing

            while position < extent {
                let isMajor = CanvasGrid.isMajorLine(visibleIndex: index,
                                                     coarseningFactor: coarseningFactor,
                                                     majorEvery: majorEvery)
                let start = axis == .vertical ? CGPoint(x: position, y: 0) : CGPoint(x: 0, y: position)
                let end = axis == .vertical
                    ? CGPoint(x: position, y: crossExtent)
                    : CGPoint(x: crossExtent, y: position)
                if isMajor {
                    major.move(to: start)
                    major.addLine(to: end)
                } else {
                    minor.move(to: start)
                    minor.addLine(to: end)
                }
                index += 1
                position += spacing
            }
        }
    }
}
