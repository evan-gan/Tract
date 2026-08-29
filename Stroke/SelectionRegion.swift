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
/// Pure geometry: the caller decides which space it works in.
enum SelectionRegion {

    /// How many samples the grid spends across one radius. Coarser and a curve
    /// reads as a staircase; finer costs cells quadratically for no visible gain.
    fileprivate static let samplesPerRadius: CGFloat = 7

    /// Hard ceiling on the sampling grid's longest side. A selection spanning a
    /// whole zoomed-out page must not turn into a million-cell field.
    fileprivate static let maximumGridSide = 256

    /// Loops shorter than this are sampling noise rather than shapes.
    private static let minimumContourVertices = 4

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
        var field = DistanceField(covering: inkBounds.insetBy(dx: -padding, dy: -padding),
                                  radius: radius)
        for polyline in polylines {
            field.splat(polyline: decimated(polyline, minimumSpacing: field.spacing / 2))
        }
        return withoutEnclosedBlips(traceContours(of: field, at: radius), radius: radius)
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

        return contours.indices
            .filter { index in
                guard area(of: contours[index]) < areaLimit else { return true }
                return !isEnclosed(contours[index], byAnyOf: contours, ignoring: index)
            }
            .map { contours[$0] }
    }

    /// A vertex of the candidate is enough to test with: contours never cross, so
    /// if one point of it is inside another contour, all of it is.
    private static func isEnclosed(
        _ contour: [CGPoint],
        byAnyOf contours: [[CGPoint]],
        ignoring ownIndex: Int
    ) -> Bool {
        guard let probe = contour.first else { return false }
        return contours.indices.contains { index in
            index != ownIndex && StrokeGeometry.polygon(contours[index], contains: probe)
        }
    }

    /// Unsigned area of a closed polygon, by the shoelace formula.
    private static func area(of polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var doubledArea: CGFloat = 0
        var previous = polygon[polygon.count - 1]
        for vertex in polygon {
            doubledArea += previous.x * vertex.y - vertex.x * previous.y
            previous = vertex
        }
        return abs(doubledArea) / 2
    }

    private static func boundingBox(of polylines: [[CGPoint]]) -> CGRect? {
        let bounds = polylines.joined().reduce(CGRect.null) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
        return bounds.isNull ? nil : bounds
    }

    /// Drops samples closer together than the grid can resolve. Pencil telemetry
    /// arrives at 240 Hz, and splatting every one of those samples costs a great
    /// deal for movement the field could not represent anyway.
    private static func decimated(_ polyline: [CGPoint], minimumSpacing: CGFloat) -> [CGPoint] {
        guard polyline.count > 2 else { return polyline }
        var kept = [polyline[0]]
        for point in polyline.dropFirst()
        where point.distance(to: kept[kept.count - 1]) >= minimumSpacing {
            kept.append(point)
        }
        // The final sample is where the stroke actually ends, so it always stays.
        if let last = polyline.last, last != kept[kept.count - 1] { kept.append(last) }
        return kept
    }

    // MARK: - Marching squares

    /// Walks every cell of the field, collects where the contour cuts each grid
    /// edge, and stitches those crossings into closed loops.
    private static func traceContours(of field: DistanceField, at threshold: CGFloat) -> [[CGPoint]] {
        var crossings: [Int: CGPoint] = [:]
        var neighbours: [Int: [Int]] = [:]

        for row in 0 ..< field.rows - 1 {
            for column in 0 ..< field.columns - 1 {
                for edgePair in cellSegments(in: field, column: column, row: row, threshold: threshold) {
                    neighbours[edgePair.0, default: []].append(edgePair.1)
                    neighbours[edgePair.1, default: []].append(edgePair.0)
                    crossings[edgePair.0] = field.crossing(onEdge: edgePair.0, at: threshold)
                    crossings[edgePair.1] = field.crossing(onEdge: edgePair.1, at: threshold)
                }
            }
        }
        return stitchLoops(neighbours: neighbours, crossings: crossings)
    }

    /// Which pairs of the cell's four edges the contour joins, decided by which
    /// of its corners fall inside the region.
    private static func cellSegments(
        in field: DistanceField,
        column: Int,
        row: Int,
        threshold: CGFloat
    ) -> [(Int, Int)] {
        var insideCode = 0
        if field[column, row] < threshold { insideCode |= 8 }              // top left
        if field[column + 1, row] < threshold { insideCode |= 4 }          // top right
        if field[column + 1, row + 1] < threshold { insideCode |= 2 }      // bottom right
        if field[column, row + 1] < threshold { insideCode |= 1 }          // bottom left

        let top = field.horizontalEdgeKey(column: column, row: row)
        let bottom = field.horizontalEdgeKey(column: column, row: row + 1)
        let left = field.verticalEdgeKey(column: column, row: row)
        let right = field.verticalEdgeKey(column: column + 1, row: row)

        switch insideCode {
        case 1, 14: return [(left, bottom)]
        case 2, 13: return [(bottom, right)]
        case 3, 12: return [(left, right)]
        case 4, 11: return [(top, right)]
        case 6, 9: return [(top, bottom)]
        case 7, 8: return [(left, top)]
        // Saddles: two opposite corners are inside. Cutting the cell into two
        // corners keeps the pieces of ink apart rather than bridging them.
        case 5: return [(top, right), (left, bottom)]
        case 10: return [(left, top), (bottom, right)]
        default: return []
        }
    }

    /// Links crossings into loops. Every grid edge is shared by at most two
    /// cells, so each crossing has at most two neighbours and the walk around a
    /// loop is unambiguous. Keys are visited in sorted order so the same field
    /// always produces the same contours.
    private static func stitchLoops(
        neighbours: [Int: [Int]],
        crossings: [Int: CGPoint]
    ) -> [[CGPoint]] {
        var visited: Set<Int> = []
        var loops: [[CGPoint]] = []

        for startEdge in neighbours.keys.sorted() where !visited.contains(startEdge) {
            var loop: [Int] = []
            var currentEdge = startEdge
            while !visited.contains(currentEdge) {
                visited.insert(currentEdge)
                loop.append(currentEdge)
                guard let nextEdge = neighbours[currentEdge]?
                    .first(where: { !visited.contains($0) }) else { break }
                currentEdge = nextEdge
            }
            guard loop.count >= minimumContourVertices else { continue }
            loops.append(loop.compactMap { crossings[$0] })
        }
        return loops
    }
}

// MARK: - Distance field

/// A regular grid of samples holding the distance from each sample to the
/// nearest piece of ink. The region's boundary is the `radius` iso-line through
/// it, which is what `SelectionRegion` traces.
private struct DistanceField {
    let origin: CGPoint
    let spacing: CGFloat
    /// Counts of sample points, not cells — a grid of N columns has N-1 cells.
    let columns: Int
    let rows: Int
    /// How far from a segment it is still worth measuring. Samples beyond this
    /// keep their initial value, which reads as "comfortably outside".
    private let reach: CGFloat
    private var distances: [CGFloat]

    init(covering bounds: CGRect, radius: CGFloat) {
        let idealSpacing = radius / SelectionRegion.samplesPerRadius
        let longestSide = max(bounds.width, bounds.height)
        // Coarsen rather than grow past the ceiling, so cost stays bounded.
        spacing = max(idealSpacing, longestSide / CGFloat(SelectionRegion.maximumGridSide))
        origin = CGPoint(x: bounds.minX, y: bounds.minY)
        columns = Int((bounds.width / spacing).rounded(.up)) + 1
        rows = Int((bounds.height / spacing).rounded(.up)) + 1
        // Two samples of slack: the interpolation at the boundary reads the
        // neighbours of every inside sample, and those must be real distances.
        reach = radius + spacing * 2
        distances = Array(repeating: .greatestFiniteMagnitude, count: columns * rows)
    }

    subscript(column: Int, row: Int) -> CGFloat {
        distances[row * columns + column]
    }

    func position(column: Int, row: Int) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(column) * spacing, y: origin.y + CGFloat(row) * spacing)
    }

    // MARK: Writing

    mutating func splat(polyline: [CGPoint]) {
        guard let first = polyline.first else { return }
        // A lone sample is a dot: no segment to measure against, so measure to
        // the point itself by treating it as a zero-length segment.
        guard polyline.count >= 2 else { return splat(segmentFrom: first, to: first) }
        for index in 1 ..< polyline.count {
            splat(segmentFrom: polyline[index - 1], to: polyline[index])
        }
    }

    private mutating func splat(segmentFrom start: CGPoint, to end: CGPoint) {
        let firstColumn = clampedColumn(for: min(start.x, end.x) - reach, rounding: .down)
        let lastColumn = clampedColumn(for: max(start.x, end.x) + reach, rounding: .up)
        let firstRow = clampedRow(for: min(start.y, end.y) - reach, rounding: .down)
        let lastRow = clampedRow(for: max(start.y, end.y) + reach, rounding: .up)
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return }

        for row in firstRow ... lastRow {
            for column in firstColumn ... lastColumn {
                let distance = StrokeGeometry.distance(
                    from: position(column: column, row: row),
                    toSegment: start, end
                )
                let index = row * columns + column
                if distance < distances[index] { distances[index] = distance }
            }
        }
    }

    private func clampedColumn(for x: CGFloat, rounding rule: FloatingPointRoundingRule) -> Int {
        min(max(Int(((x - origin.x) / spacing).rounded(rule)), 0), columns - 1)
    }

    private func clampedRow(for y: CGFloat, rounding rule: FloatingPointRoundingRule) -> Int {
        min(max(Int(((y - origin.y) / spacing).rounded(rule)), 0), rows - 1)
    }

    // MARK: Edges

    // A crossing is identified by the grid edge it sits on, so the two cells
    // sharing that edge produce an identical key and the contour stitches back
    // together exactly instead of by floating-point coincidence.

    func horizontalEdgeKey(column: Int, row: Int) -> Int { (row * columns + column) * 2 }
    func verticalEdgeKey(column: Int, row: Int) -> Int { (row * columns + column) * 2 + 1 }

    /// Where along an edge the distance passes through `threshold`, found by
    /// interpolating between the two samples the edge joins.
    func crossing(onEdge key: Int, at threshold: CGFloat) -> CGPoint {
        let isHorizontal = key.isMultiple(of: 2)
        let sampleIndex = key / 2
        let column = sampleIndex % columns
        let row = sampleIndex / columns

        let near = self[column, row]
        let far = isHorizontal ? self[column + 1, row] : self[column, row + 1]
        let fraction = crossingFraction(from: near, to: far, at: threshold)

        let base = position(column: column, row: row)
        return isHorizontal
            ? CGPoint(x: base.x + fraction * spacing, y: base.y)
            : CGPoint(x: base.x, y: base.y + fraction * spacing)
    }

    private func crossingFraction(from near: CGFloat, to far: CGFloat, at threshold: CGFloat) -> CGFloat {
        let span = far - near
        // Equal samples give no gradient to solve against; split the edge.
        guard abs(span) > .ulpOfOne else { return 0.5 }
        return min(max((threshold - near) / span, 0), 1)
    }
}
