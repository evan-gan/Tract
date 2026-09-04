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
/// The dilation is found by measuring a grid of samples against the ink — a
/// distance transform — and tracing the `radius` iso-line through it with
/// marching squares. The cost of that is set by the size of the grid, which is
/// capped, rather than by how much ink is selected.
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
            field.seed(alongPolyline: decimated(polyline, minimumSpacing: field.spacing))
        }
        field.propagateNearestInk()
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
        let bounds = polylines.reduce(CGRect.null) { $0.union(boundingBox(of: $1)) }
        return bounds.isNull ? nil : bounds
    }

    private static func boundingBox(of polyline: [CGPoint]) -> CGRect {
        polyline.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// Drops samples closer together than the grid can resolve. Pencil telemetry
    /// arrives at 240 Hz, and measuring every one of those samples costs a great
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
        var graph = CrossingGraph(edgeKeyCount: field.edgeKeyCount)

        for row in 0 ..< field.rows - 1 {
            for column in 0 ..< field.columns - 1 {
                for edgePair in cellSegments(in: field, column: column, row: row, threshold: threshold) {
                    let start = graph.crossingIndex(ofEdge: edgePair.0, in: field, at: threshold)
                    let end = graph.crossingIndex(ofEdge: edgePair.1, in: field, at: threshold)
                    graph.link(start, end)
                }
            }
        }
        return graph.stitchLoops(minimumVertices: minimumContourVertices)
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

        // Every cell outside the region is this case, so it is worth answering
        // before working out four edge keys nothing will use.
        guard insideCode != 0, insideCode != 15 else { return [] }

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
}

// MARK: - Crossing graph

/// The points where the contour cuts grid edges, and which of them are joined.
///
/// Crossings are addressed by grid edge through a flat lookup table rather than
/// a dictionary. A full-size grid produces tens of thousands of them, and
/// hashing every edge — plus the small array a dictionary of neighbour lists
/// heap-allocates per crossing — cost more than the tracing itself.
private struct CrossingGraph {
    /// Where each grid edge's crossing landed in `points`, or -1 for an edge the
    /// contour does not cut.
    private var indexByEdgeKey: [Int32]
    private var points: [CGPoint] = []
    /// A crossing joins at most two others, because a grid edge is shared by at
    /// most two cells and each cell links it to one edge per contour passing
    /// through. -1 is a free slot.
    private var firstNeighbour: [Int32] = []
    private var secondNeighbour: [Int32] = []

    init(edgeKeyCount: Int) {
        indexByEdgeKey = Array(repeating: -1, count: edgeKeyCount)
    }

    /// The crossing on a grid edge, interpolating it the first time the edge is
    /// asked for. The two cells sharing an edge therefore get the identical
    /// point, and the loops stitch back together exactly.
    mutating func crossingIndex(
        ofEdge key: Int,
        in field: DistanceField,
        at threshold: CGFloat
    ) -> Int {
        if indexByEdgeKey[key] >= 0 { return Int(indexByEdgeKey[key]) }

        let index = points.count
        indexByEdgeKey[key] = Int32(index)
        points.append(field.crossing(onEdge: key, at: threshold))
        firstNeighbour.append(-1)
        secondNeighbour.append(-1)
        return index
    }

    mutating func link(_ one: Int, _ other: Int) {
        attach(other, to: one)
        attach(one, to: other)
    }

    private mutating func attach(_ neighbour: Int, to crossing: Int) {
        if firstNeighbour[crossing] < 0 {
            firstNeighbour[crossing] = Int32(neighbour)
        } else if secondNeighbour[crossing] < 0 {
            secondNeighbour[crossing] = Int32(neighbour)
        }
        // A third link would mean an edge shared by three cells, which the grid
        // cannot produce; dropping it keeps the walk unambiguous either way.
    }

    /// Links crossings into loops. Each crossing has at most two neighbours, so
    /// the walk around a loop is unambiguous. Crossings are visited in the order
    /// the cell scan found them, so the same field always produces the same
    /// contours.
    func stitchLoops(minimumVertices: Int) -> [[CGPoint]] {
        var visited = [Bool](repeating: false, count: points.count)
        var loops: [[CGPoint]] = []

        for startCrossing in points.indices where !visited[startCrossing] {
            var loop: [CGPoint] = []
            var current = startCrossing
            while !visited[current] {
                visited[current] = true
                loop.append(points[current])
                guard let next = unvisitedNeighbour(of: current, visited: visited) else { break }
                current = next
            }
            if loop.count >= minimumVertices { loops.append(loop) }
        }
        return loops
    }

    private func unvisitedNeighbour(of crossing: Int, visited: [Bool]) -> Int? {
        let first = firstNeighbour[crossing]
        if first >= 0, !visited[Int(first)] { return Int(first) }
        let second = secondNeighbour[crossing]
        if second >= 0, !visited[Int(second)] { return Int(second) }
        return nil
    }
}

// MARK: - Distance field

/// A regular grid of samples holding the distance from each sample to the
/// nearest piece of ink. The region's boundary is the `radius` iso-line through
/// it, which is what `SelectionRegion` traces.
///
/// Building it has two stages. Seeding measures the samples in a narrow band
/// either side of the ink exactly; the sweeps then carry those results out
/// across the rest of the grid, so a sample far from the ink is never measured
/// against the ink at all. That is what keeps the cost proportional to the grid
/// rather than to the amount of ink selected.
private struct DistanceField {
    let origin: CGPoint
    let spacing: CGFloat
    /// Counts of sample points, not cells — a grid of N columns has N-1 cells.
    let columns: Int
    let rows: Int

    /// Squared distance to the nearest ink while the field is being built, true
    /// distance once `propagateNearestInk()` has finished. Squared during the
    /// build because comparing squares orders samples identically and spares
    /// every inner loop a square root.
    private var distances: [CGFloat]
    /// The closest point on the ink found so far for each sample. This, rather
    /// than the distance, is what the sweeps propagate: a neighbour's closest
    /// point re-measured from here is a real distance, so the answer stays
    /// accurate however far it travels.
    private var nearestInk: [CGPoint]

    /// How wide a band of samples either side of a piece of ink gets measured
    /// exactly. It has to be wider than the half-diagonal of a cell so that
    /// every piece of ink seeds at least one sample; beyond that the sweeps do
    /// the work, so a wider band is only more measuring.
    private var seedReach: CGFloat { spacing * 1.5 }

    init(covering bounds: CGRect, radius: CGFloat) {
        let idealSpacing = radius / SelectionRegion.samplesPerRadius
        let longestSide = max(bounds.width, bounds.height)
        // Coarsen rather than grow past the ceiling, so cost stays bounded.
        spacing = max(idealSpacing, longestSide / CGFloat(SelectionRegion.maximumGridSide))
        origin = CGPoint(x: bounds.minX, y: bounds.minY)
        columns = Int((bounds.width / spacing).rounded(.up)) + 1
        rows = Int((bounds.height / spacing).rounded(.up)) + 1
        distances = Array(repeating: .infinity, count: columns * rows)
        nearestInk = Array(repeating: .zero, count: columns * rows)
    }

    subscript(column: Int, row: Int) -> CGFloat {
        distances[row * columns + column]
    }

    func position(column: Int, row: Int) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(column) * spacing, y: origin.y + CGFloat(row) * spacing)
    }

    // MARK: Seeding

    mutating func seed(alongPolyline polyline: [CGPoint]) {
        guard let first = polyline.first else { return }
        // A lone sample is a dot: no segment to measure against, so measure to
        // the point itself by treating it as a zero-length segment.
        guard polyline.count >= 2 else { return seed(alongSegmentFrom: first, to: first) }
        for index in 1 ..< polyline.count {
            seed(alongSegmentFrom: polyline[index - 1], to: polyline[index])
        }
    }

    /// Seeds the band around one segment, walking it in cell-sized pieces.
    ///
    /// Taking the segment whole would mean sweeping its bounding box, and a long
    /// diagonal's box grows with the square of its length while the band that
    /// actually matters stays the same width.
    private mutating func seed(alongSegmentFrom start: CGPoint, to end: CGPoint) {
        let pieceCount = max(1, Int((start.distance(to: end) / spacing).rounded(.up)))
        var pieceStart = start
        for piece in 1 ... pieceCount {
            let pieceEnd = start + (end - start) * (CGFloat(piece) / CGFloat(pieceCount))
            seedBand(aroundSegmentFrom: pieceStart, to: pieceEnd)
            pieceStart = pieceEnd
        }
    }

    private mutating func seedBand(aroundSegmentFrom start: CGPoint, to end: CGPoint) {
        let reach = seedReach
        let firstColumn = clampedColumn(for: min(start.x, end.x) - reach, rounding: .down)
        let lastColumn = clampedColumn(for: max(start.x, end.x) + reach, rounding: .up)
        let firstRow = clampedRow(for: min(start.y, end.y) - reach, rounding: .down)
        let lastRow = clampedRow(for: max(start.y, end.y) + reach, rounding: .up)
        guard firstColumn <= lastColumn, firstRow <= lastRow else { return }

        for row in firstRow ... lastRow {
            for column in firstColumn ... lastColumn {
                let sample = position(column: column, row: row)
                let closest = StrokeGeometry.closestPoint(onSegment: start, end, to: sample)
                consider(closest, at: row * columns + column, from: sample)
            }
        }
    }

    /// Keeps a candidate closest point if it beats what the sample already holds.
    private mutating func consider(_ candidate: CGPoint, at index: Int, from sample: CGPoint) {
        let squaredDistance = sample.squaredDistance(to: candidate)
        guard squaredDistance < distances[index] else { return }
        distances[index] = squaredDistance
        nearestInk[index] = candidate
    }

    // MARK: Sweeping

    /// Neighbours already settled when a sample is reached going forwards, and
    /// the mirror set for the backward pass. The two together cover all eight,
    /// which is what makes a single pass in each direction enough.
    private static let forwardNeighbours = [(-1, -1), (0, -1), (1, -1), (-1, 0)]
    private static let backwardNeighbours = [(1, 1), (0, 1), (-1, 1), (1, 0)]

    /// The one neighbour each pass cannot have settled yet, picked up by the
    /// sweep back along the row. Held as arrays so the sweep never builds one
    /// per sample.
    private static let forwardTrailingNeighbours = [(1, 0)]
    private static let backwardTrailingNeighbours = [(-1, 0)]

    /// Carries the seeded closest points out across the whole grid, then turns
    /// the squared distances into real ones.
    ///
    /// This is a vector distance transform: each sample takes the best closest
    /// point any settled neighbour knows about, re-measured from where it
    /// actually is. Two passes cost a fixed handful of operations per sample no
    /// matter how much ink there is — where measuring every sample against every
    /// segment, which is what this replaces, grew with the two multiplied
    /// together and was what made a large selection slow to frame.
    mutating func propagateNearestInk() {
        sweep(rows: Array(0 ..< rows),
              columns: Array(0 ..< columns),
              neighbours: Self.forwardNeighbours,
              trailingNeighbours: Self.forwardTrailingNeighbours)
        sweep(rows: Array((0 ..< rows).reversed()),
              columns: Array((0 ..< columns).reversed()),
              neighbours: Self.backwardNeighbours,
              trailingNeighbours: Self.backwardTrailingNeighbours)

        for index in distances.indices { distances[index] = distances[index].squareRoot() }
    }

    /// One pass over the grid in the given order, followed along each row by a
    /// sweep back the other way. That second sweep is what lets a closest point
    /// travel the full width of a row rather than only in the pass's own
    /// direction.
    private mutating func sweep(
        rows rowOrder: [Int],
        columns columnOrder: [Int],
        neighbours: [(Int, Int)],
        trailingNeighbours: [(Int, Int)]
    ) {
        for row in rowOrder {
            for column in columnOrder {
                relax(column: column, row: row, against: neighbours)
            }
            for column in columnOrder.reversed() {
                relax(column: column, row: row, against: trailingNeighbours)
            }
        }
    }

    private mutating func relax(column: Int, row: Int, against neighbours: [(Int, Int)]) {
        let index = row * columns + column
        let sample = position(column: column, row: row)

        for (columnOffset, rowOffset) in neighbours {
            let neighbourColumn = column + columnOffset
            let neighbourRow = row + rowOffset
            guard neighbourColumn >= 0, neighbourColumn < columns,
                  neighbourRow >= 0, neighbourRow < rows else { continue }

            let neighbourIndex = neighbourRow * columns + neighbourColumn
            guard distances[neighbourIndex] < .infinity else { continue }
            consider(nearestInk[neighbourIndex], at: index, from: sample)
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

    /// One past the largest key `horizontalEdgeKey` or `verticalEdgeKey` can
    /// return, which is how big a table addressed by edge key has to be.
    var edgeKeyCount: Int { columns * rows * 2 }

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
