import CoreGraphics

/// A regular grid of samples holding the distance from each sample to the
/// nearest seed. Threshold it and you have a region; trace that threshold with
/// `MarchingSquares` and you have its outline.
///
/// Building it has two stages. Seeding measures the samples in a narrow band
/// around each seed exactly; the sweeps then carry those results out across the
/// rest of the grid, so a sample far from every seed is never measured against
/// the seeds at all. That is what keeps the cost proportional to the grid rather
/// than to the amount of geometry seeded into it.
///
/// Two shapes are built from this: the lasso's frame (`SelectionRegion`, seeded
/// with the selected ink) and a problem's bounding region (`ProblemRegion`,
/// which seeds a second field from the first one's own samples).
///
/// Pure geometry: the caller decides which space it works in.
struct DistanceField {
    let origin: CGPoint
    let spacing: CGFloat
    /// Counts of sample points, not cells — a grid of N columns has N-1 cells.
    let columns: Int
    let rows: Int

    /// Squared distance to the nearest seed while the field is being built, true
    /// distance once `propagateNearestSeed()` has finished. Squared during the
    /// build because comparing squares orders samples identically and spares
    /// every inner loop a square root.
    private var distances: [CGFloat]
    /// The closest seed point found so far for each sample. This, rather than the
    /// distance, is what the sweeps propagate: a neighbour's closest point
    /// re-measured from here is a real distance, so the answer stays accurate
    /// however far it travels.
    private var nearestSeed: [CGPoint]

    /// Whether anything has been seeded yet. A field with no seeds stays
    /// infinitely far from everything, which is a shape nobody can trace.
    private(set) var hasSeeds = false

    /// How wide a band of samples either side of a seed gets measured exactly.
    /// It has to be wider than the half-diagonal of a cell so that every seed
    /// reaches at least one sample; beyond that the sweeps do the work, so a
    /// wider band is only more measuring.
    private var seedReach: CGFloat { spacing * 1.5 }

    /// - Parameters:
    ///   - bounds: The area the grid has to cover. Callers pad this out past the
    ///     shape they intend to trace, so the contour is always strictly inside
    ///     the grid with definitely-outside samples beyond it.
    ///   - idealSpacing: How far apart samples should sit — the resolution the
    ///     traced shape is worth spending. Coarser and a curve reads as a
    ///     staircase; finer costs cells quadratically for no visible gain.
    ///   - maximumSide: Hard ceiling on the grid's longest side. A shape spanning
    ///     a whole zoomed-out page must not turn into a million-cell field, so
    ///     the spacing coarsens rather than the grid growing past this.
    init(covering bounds: CGRect, idealSpacing: CGFloat, maximumSide: Int) {
        let longestSide = max(bounds.width, bounds.height)
        spacing = max(idealSpacing, longestSide / CGFloat(maximumSide))
        origin = CGPoint(x: bounds.minX, y: bounds.minY)
        columns = Int((bounds.width / spacing).rounded(.up)) + 1
        rows = Int((bounds.height / spacing).rounded(.up)) + 1
        distances = Array(repeating: .infinity, count: columns * rows)
        nearestSeed = Array(repeating: .zero, count: columns * rows)
    }

    /// An empty field over another one's grid, so the two can be read against
    /// each other sample for sample — which is how `ProblemRegion` seeds its
    /// second field from the first one's answers.
    init(matchingGridOf other: DistanceField) {
        origin = other.origin
        spacing = other.spacing
        columns = other.columns
        rows = other.rows
        distances = Array(repeating: .infinity, count: columns * rows)
        nearestSeed = Array(repeating: .zero, count: columns * rows)
    }

    subscript(column: Int, row: Int) -> CGFloat {
        distances[row * columns + column]
    }

    func position(column: Int, row: Int) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(column) * spacing, y: origin.y + CGFloat(row) * spacing)
    }

    // MARK: - Seeding

    /// Seeds the band around a polyline. Samples closer together than the grid
    /// can resolve are dropped first: pencil telemetry arrives at 240 Hz, and
    /// measuring every one of those costs a great deal for movement the field
    /// could not represent anyway.
    mutating func seed(alongPolyline polyline: [CGPoint]) {
        let sparse = decimated(polyline, minimumSpacing: spacing)
        guard let first = sparse.first else { return }
        hasSeeds = true
        // A lone sample is a dot: no segment to measure against, so measure to
        // the point itself by treating it as a zero-length segment.
        guard sparse.count >= 2 else { return seed(alongSegmentFrom: first, to: first) }
        for index in 1 ..< sparse.count {
            seed(alongSegmentFrom: sparse[index - 1], to: sparse[index])
        }
    }

    /// Seeds one grid sample as being on the geometry itself — distance zero.
    ///
    /// Used to seed a field from a region already described by another field's
    /// samples, where there is no polyline to measure against. The answer is
    /// therefore quantised to the grid, which is fine for a shape deliberately
    /// far smoother than one cell.
    mutating func seedSample(column: Int, row: Int) {
        let index = row * columns + column
        distances[index] = 0
        nearestSeed[index] = position(column: column, row: row)
        hasSeeds = true
    }

    /// Drops samples closer together than the grid can resolve.
    private func decimated(_ polyline: [CGPoint], minimumSpacing: CGFloat) -> [CGPoint] {
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
        nearestSeed[index] = candidate
    }

    // MARK: - Sweeping

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
    /// matter how much geometry there is — where measuring every sample against
    /// every segment grows with the two multiplied together, and was what made a
    /// large selection slow to frame.
    mutating func propagateNearestSeed() {
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
            consider(nearestSeed[neighbourIndex], at: index, from: sample)
        }
    }

    private func clampedColumn(for x: CGFloat, rounding rule: FloatingPointRoundingRule) -> Int {
        min(max(Int(((x - origin.x) / spacing).rounded(rule)), 0), columns - 1)
    }

    private func clampedRow(for y: CGFloat, rounding rule: FloatingPointRoundingRule) -> Int {
        min(max(Int(((y - origin.y) / spacing).rounded(rule)), 0), rows - 1)
    }

    // MARK: - Edges

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
