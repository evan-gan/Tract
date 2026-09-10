import CoreGraphics

/// The shape that frames a lasso selection: every point lying within `radius` of
/// the selected ink, traced as one or more closed contours.
///
/// This is a dilation of the ink itself rather than a hull, which is what makes
/// the frame follow the drawing's contours instead of boxing it in. It also
/// settles the split rule for free — two pieces of ink further apart than twice
/// the radius grow regions that never meet, so they come back as two separate
/// outlines, and merge into one the moment they do touch.
///
/// The dilation is found by measuring a grid of samples against the ink (a
/// `DistanceField`) and tracing the `radius` iso-line through it with
/// `MarchingSquares`. The cost of that is set by the size of the grid, which is
/// capped, rather than by how much ink is selected.
///
/// The frame drawn around a *problem* is deliberately not this shape — see
/// `ProblemRegion`, which stands the same distance off the ink but refuses to
/// follow it into every gap.
///
/// Pure geometry: the caller decides which space it works in.
enum SelectionRegion {

    /// How many samples the grid spends across one radius. Coarser and a curve
    /// reads as a staircase; finer costs cells quadratically for no visible gain.
    static let samplesPerRadius: CGFloat = 7

    /// Hard ceiling on the sampling grid's longest side. A selection spanning a
    /// whole zoomed-out page must not turn into a million-cell field.
    static let maximumGridSide = 256

    /// Loops shorter than this are sampling noise rather than shapes.
    static let minimumContourVertices = 4

    /// How large an enclosed pocket has to be, as a multiple of the area of the
    /// disc the region was dilated with, to be worth drawing. Anything under it
    /// is a blip: a gap barely wider than the standoff itself, which reads as
    /// litter inside the frame rather than as a hole the user left there.
    private static let enclosedPocketAreaLimit: CGFloat = 1.0

    /// Traces the outline(s) of the region within `radius` of any of `polylines`.
    ///
    /// - Parameters:
    ///   - polylines: The selected ink, one point list per stroke. A single-point
    ///     list is a dot and contributes a circle.
    ///   - radius: How far the outline stands off the ink.
    /// - Returns: Closed contours, each a vertex loop that does not repeat its
    ///   first point. Outer boundaries and the boundaries of enclosed holes both
    ///   appear; an empty array means there was nothing to frame.
    static func contours(around polylines: [[CGPoint]], radius: CGFloat) -> [[CGPoint]] {
        guard radius > 0, let inkBounds = boundingBox(of: polylines) else { return [] }

        // Pad by more than the radius so the contour is always strictly inside
        // the grid, with a margin of definitely-outside samples beyond it.
        let padding = radius * 1.5
        var field = DistanceField(
            covering: inkBounds.insetBy(dx: -padding, dy: -padding),
            idealSpacing: radius / samplesPerRadius,
            maximumSide: maximumGridSide
        )
        for polyline in polylines {
            field.seed(alongPolyline: polyline)
        }
        guard field.hasSeeds else { return [] }
        field.propagateNearestSeed()

        let traced = MarchingSquares.contours(
            of: field,
            at: radius,
            insideIsBelow: true,
            minimumVertices: minimumContourVertices
        )
        return withoutEnclosedBlips(traced, radius: radius)
    }

    // MARK: - Blips

    /// Drops the small pockets a dilation can leave inside a bigger region.
    ///
    /// Crossing strokes routinely leave a gap just wide enough to survive being
    /// dilated, and the speck of an outline that comes back sits inside the frame
    /// looking like a mistake. A pocket is only dropped when something else
    /// encloses it — a small region standing on its own is a separate piece of
    /// ink, which is exactly what the split rule exists to show.
    private static func withoutEnclosedBlips(
        _ contours: [[CGPoint]],
        radius: CGFloat
    ) -> [[CGPoint]] {
        guard contours.count > 1 else { return contours }
        let areaLimit = .pi * radius * radius * enclosedPocketAreaLimit
        let extents = contours.map(boundingBox(of:))

        return contours.indices
            .filter { index in
                guard area(of: contours[index]) < areaLimit else { return true }
                return !isEnclosed(contours[index], byAnyOf: contours,
                                   extents: extents, ignoring: index)
            }
            .map { contours[$0] }
    }

    /// A vertex of the candidate is enough to test with: contours never cross, so
    /// if one point of it is inside another contour, all of it is.
    private static func isEnclosed(
        _ contour: [CGPoint],
        byAnyOf contours: [[CGPoint]],
        extents: [CGRect],
        ignoring ownIndex: Int
    ) -> Bool {
        guard let probe = contour.first else { return false }
        return contours.indices.contains { index in
            index != ownIndex
                // Nothing outside a contour's own extent can be inside it, and
                // the box test is a hundredth of the cost of the ray cast.
                && extents[index].contains(probe)
                && StrokeGeometry.polygon(contours[index], contains: probe)
        }
    }

    /// Unsigned area of a closed polygon, by the shoelace formula.
    static func area(of polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var doubledArea: CGFloat = 0
        var previous = polygon[polygon.count - 1]
        for vertex in polygon {
            doubledArea += previous.x * vertex.y - vertex.x * previous.y
            previous = vertex
        }
        return abs(doubledArea) / 2
    }

    static func boundingBox(of polylines: [[CGPoint]]) -> CGRect? {
        let bounds = polylines.reduce(CGRect.null) { $0.union(boundingBox(of: $1)) }
        return bounds.isNull ? nil : bounds
    }

    static func boundingBox(of polyline: [CGPoint]) -> CGRect {
        polyline.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}
