import CoreGraphics

/// The shape drawn around one problem's work: a box that has been shrunk onto
/// the ink until it touched, curving around whatever it met on the way in.
///
/// This is deliberately **not** the lasso's frame. `SelectionRegion` conforms to
/// the ink — it follows the drawing into every gap between two letters, which is
/// what you want when the question is "which marks did I pick up", and exactly
/// what you do not want when the question is "which patch of the page is
/// problem 3". A bounding region has to read as a region: roughly rectangular
/// where the work is a block of writing, dented only where the drawing genuinely
/// leaves a bite out of it.
///
/// The construction is a rolling ball. Grow the ink by `padding + curveRadius`,
/// then pull the result back in by `curveRadius`: the boundary that comes back
/// is the path a ball of that radius traces rolling around the outside of the
/// padded ink. Anywhere the ink is dense the ball rides at exactly `padding`
/// from it, and anywhere it would have to dip into a gap narrower than itself it
/// bridges across in an arc instead. Turning `curveRadius` up moves the shape
/// towards the plain rectangle; turning it to nothing gives back the lasso's
/// conforming outline.
///
/// Both distances are whatever space the caller works in — the canvas, in this
/// app, so a region magnifies with the drawing it frames the way ink width and
/// the lasso frame do, rather than being a screen-space constant that would
/// crowd the ink when zoomed in and swamp it when zoomed out.
enum ProblemRegion {

    /// How many grid samples are spent across the smaller of the two distances.
    /// The shape is smooth by construction, so it needs far less resolution than
    /// the lasso's ink-hugging outline does.
    private static let samplesPerFeature: CGFloat = 6

    /// Hard ceiling on the sampling grid's longest side. A problem spanning a
    /// zoomed-out page coarsens rather than growing an enormous field.
    private static let maximumGridSide = 128

    /// How far past the ink the grid reaches, as a multiple of the total growth.
    /// It has to clear that growth outright, so the samples at the border are
    /// reliably outside everything and the traced loop closes inside the grid.
    private static let gridMarginFactor: CGFloat = 1.2

    /// Traces the region around one problem's ink.
    ///
    /// - Parameters:
    ///   - polylines: The problem's strokes, one point list per stroke.
    ///   - padding: How far the boundary stands off the ink where it touches it.
    ///   - curveRadius: The radius of the curves that carry the boundary across
    ///     gaps — how much the shape refuses to conform.
    /// - Returns: Closed contours, each a vertex loop that does not repeat its
    ///   first point. More than one means the problem's work sits in patches too
    ///   far apart for the ball to bridge; an empty array means there was nothing
    ///   to frame.
    static func contours(
        around polylines: [[CGPoint]],
        padding: CGFloat,
        curveRadius: CGFloat
    ) -> [[CGPoint]] {
        guard padding > 0, let inkBounds = SelectionRegion.boundingBox(of: polylines) else {
            return []
        }
        // With no ball to roll, the shape *is* the dilation — which is the frame
        // the lasso already knows how to build.
        guard curveRadius > 0 else {
            return SelectionRegion.contours(around: polylines, radius: padding)
        }

        let growth = padding + curveRadius
        let margin = growth * gridMarginFactor
        var inkField = DistanceField(
            covering: inkBounds.insetBy(dx: -margin, dy: -margin),
            idealSpacing: min(padding, curveRadius) / samplesPerFeature,
            maximumSide: maximumGridSide
        )
        for polyline in polylines {
            inkField.seed(alongPolyline: polyline)
        }
        guard inkField.hasSeeds else { return [] }
        inkField.propagateNearestSeed()

        guard let clearanceField = clearanceField(beyond: growth, in: inkField) else {
            // Nowhere on the grid is far enough from the ink for the ball to sit,
            // so nothing was pulled back in and the dilation is the answer.
            return SelectionRegion.contours(around: polylines, radius: padding)
        }
        return MarchingSquares.contours(
            of: clearanceField,
            at: curveRadius,
            // The region is what the ball could *not* reach, so it is the samples
            // at or beyond one radius from every position the ball can sit in.
            insideIsBelow: false,
            minimumVertices: SelectionRegion.minimumContourVertices
        )
    }

    /// Distance to the nearest place the rolling ball's centre can sit.
    ///
    /// A ball of `curveRadius` fits outside the padded ink exactly where the ink
    /// is at least `growth` away — and because `inkField` holds a true distance,
    /// that set is just its `growth` super-level set, with no second measurement
    /// needed. Seeding a field from those samples and sweeping it gives, for
    /// every point on the page, how far it is from the nearest ball centre; the
    /// region is then everything the ball stayed a full radius away from.
    ///
    /// - Returns: The swept field, or `nil` when the ball has nowhere to sit at
    ///   all, which leaves the caller nothing to threshold.
    private static func clearanceField(
        beyond growth: CGFloat,
        in inkField: DistanceField
    ) -> DistanceField? {
        var field = DistanceField(matchingGridOf: inkField)
        for row in 0 ..< inkField.rows {
            for column in 0 ..< inkField.columns where inkField[column, row] >= growth {
                field.seedSample(column: column, row: row)
            }
        }
        guard field.hasSeeds else { return nil }
        field.propagateNearestSeed()
        return field
    }
}
