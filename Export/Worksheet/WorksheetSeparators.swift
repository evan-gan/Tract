import CoreGraphics

/// Separator lines: one set of curves that divides the sheet into a region per
/// problem and runs out to the paper's edges.
///
/// Drawing a dashed outline around every problem shows what the packer thought,
/// but it reads as loose shapes floating on a page. Dividing the whole sheet
/// instead — every line either meets another line or reaches an edge — reads as
/// a worksheet: nothing is left dangling, and the space between problems belongs
/// to the page rather than to nobody.
///
/// The partition is the region each point is nearest to, measured to each
/// problem's **padded outline** rather than to its centre, so a long problem
/// holds the ground along its whole length. It is traced on a grid: sample which
/// problem is closest at each grid point, walk the cells where that answer
/// changes, then round off the staircase that leaves.
enum WorksheetSeparators {
    /// Grid resolution. Finer traces closer to the true boundary and costs more.
    private static let sampleStep: CGFloat = 6
    /// How far a line may be moved to straighten it. Tracing on a grid produces
    /// a staircase, and smoothing a staircase only turns it into a wobble;
    /// collapsing the steps first — never more than a cell from the straight run
    /// they approximate — is what gives a clean line.
    private static let straightenTolerance: CGFloat = sampleStep * 1.5
    /// Chaikin rounds applied to what survives straightening.
    private static let smoothingRounds = 3
    /// Two traced crossings this close are the same point.
    private static let coincident: CGFloat = 1e-6

    /// - Parameter regions: One padded outline per problem on the page, in
    ///   placement order.
    /// - Returns: Smooth polylines in page coordinates. Empty for fewer than two
    ///   problems, which have nothing to divide.
    static func lines(dividing regions: [[CGPoint]], page: WorksheetPageGeometry) -> [[CGPoint]] {
        guard regions.count >= 2 else { return [] }

        let grid = nearestRegionGrid(regions: regions, page: page)
        let segments = traceBoundaries(in: grid, page: page)
        return chained(segments).map { chain in
            smoothed(WorksheetPolyline.simplified(chain, tolerance: straightenTolerance))
        }
    }

    // MARK: - Sampling

    /// Which region owns each grid point. Samples span the full sheet, edge to
    /// edge, so a boundary reaches the paper's edge rather than the margin.
    private static func nearestRegionGrid(
        regions: [[CGPoint]],
        page: WorksheetPageGeometry
    ) -> OwnerGrid {
        let columns = Int((page.size.width / sampleStep).rounded(.up)) + 1
        let rows = Int((page.size.height / sampleStep).rounded(.up)) + 1
        let boxes = regions.map { WorksheetPolygon.bounds(of: $0) }

        var owners = [Int](repeating: 0, count: columns * rows)
        for row in 0 ..< rows {
            let y = CGFloat(row) * sampleStep
            for column in 0 ..< columns {
                owners[row * columns + column] = nearestRegion(
                    to: CGPoint(x: CGFloat(column) * sampleStep, y: y),
                    regions: regions,
                    boxes: boxes
                )
            }
        }
        return OwnerGrid(owners: owners, columns: columns, rows: rows)
    }

    private static func nearestRegion(
        to point: CGPoint,
        regions: [[CGPoint]],
        boxes: [CGRect]
    ) -> Int {
        var nearest = 0
        var nearestDistance = CGFloat.greatestFiniteMagnitude
        for index in regions.indices {
            // The bounding box is a lower bound on the polygon distance, so a
            // region whose box is already further than the best answer cannot win.
            if distance(from: point, toBox: boxes[index]) >= nearestDistance { continue }
            let distance = WorksheetPolygon.distance(from: point, to: regions[index])
            if distance < nearestDistance {
                nearestDistance = distance
                nearest = index
            }
        }
        return nearest
    }

    private static func distance(from point: CGPoint, toBox box: CGRect) -> CGFloat {
        guard !box.isNull else { return .greatestFiniteMagnitude }
        let dx = max(box.minX - point.x, 0, point.x - box.maxX)
        let dy = max(box.minY - point.y, 0, point.y - box.maxY)
        return (dx * dx + dy * dy).squareRoot()
    }

    // MARK: - Tracing

    /// Every grid cell whose corners disagree contributes a piece of boundary:
    /// two crossings of the same pair join straight across, and anything else
    /// meets at the cell's centre — which is exactly what a point where three
    /// regions meet looks like.
    private static func traceBoundaries(
        in grid: OwnerGrid,
        page: WorksheetPageGeometry
    ) -> [BoundarySegment] {
        var segments: [BoundarySegment] = []

        for row in 0 ..< max(grid.rows - 1, 0) {
            for column in 0 ..< max(grid.columns - 1, 0) {
                let crossings = self.crossings(inCellAtColumn: column, row: row, of: grid)
                if crossings.isEmpty { continue }

                if crossings.count == 2, crossings[0].pair == crossings[1].pair {
                    segments.append(
                        BoundarySegment(
                            from: crossings[0].point,
                            to: crossings[1].point,
                            pair: crossings[0].pair
                        )
                    )
                    continue
                }
                let centre = CGPoint(
                    x: (CGFloat(column) + 0.5) * sampleStep,
                    y: (CGFloat(row) + 0.5) * sampleStep
                )
                for crossing in crossings {
                    segments.append(
                        BoundarySegment(from: crossing.point, to: centre, pair: crossing.pair)
                    )
                }
            }
        }
        return segments.filter { isOnSheet($0, page: page) }
    }

    private static func crossings(
        inCellAtColumn column: Int,
        row: Int,
        of grid: OwnerGrid
    ) -> [Crossing] {
        let edges = [
            (column, row, column + 1, row),                 // top
            (column + 1, row, column + 1, row + 1),         // right
            (column + 1, row + 1, column, row + 1),         // bottom
            (column, row + 1, column, row)                  // left
        ]

        return edges.compactMap { edge in
            let owner = grid.owner(column: edge.0, row: edge.1)
            let nextOwner = grid.owner(column: edge.2, row: edge.3)
            guard owner != nextOwner else { return nil }
            return Crossing(
                point: CGPoint(
                    x: CGFloat(edge.0 + edge.2) / 2 * sampleStep,
                    y: CGFloat(edge.1 + edge.3) / 2 * sampleStep
                ),
                pair: RegionPair(owner, nextOwner)
            )
        }
    }

    private static func isOnSheet(_ segment: BoundarySegment, page: WorksheetPageGeometry) -> Bool {
        let inside = { (point: CGPoint) in
            point.x >= 0 && point.y >= 0 && point.x <= page.size.width && point.y <= page.size.height
        }
        return inside(segment.from) && inside(segment.to)
    }

    // MARK: - Chaining

    /// Threads the loose segments into polylines, one per pair of neighbouring
    /// problems. Breaking at junctions is deliberate: a line only ever divides
    /// the same two problems along its length.
    private static func chained(_ segments: [BoundarySegment]) -> [[CGPoint]] {
        var order: [RegionPair] = []
        var byPair: [RegionPair: [BoundarySegment]] = [:]
        for segment in segments {
            if byPair[segment.pair] == nil { order.append(segment.pair) }
            byPair[segment.pair, default: []].append(segment)
        }
        // Grouped in first-seen order rather than in the dictionary's: the whole
        // pipeline is deterministic, and hashed order is not.
        return order.flatMap { linkedEndToEnd(byPair[$0] ?? []) }
    }

    /// Greedy walk: keep attaching whichever unused segment starts where this
    /// one ended, at either end of the growing line.
    private static func linkedEndToEnd(_ segments: [BoundarySegment]) -> [[CGPoint]] {
        var used = [Bool](repeating: false, count: segments.count)
        var polylines: [[CGPoint]] = []

        for start in segments.indices where !used[start] {
            used[start] = true
            var points = [segments[start].from, segments[start].to]

            var extended = true
            while extended {
                extended = false
                for index in segments.indices where !used[index] {
                    let candidate = segments[index]
                    guard let extendedPoints = extend(points, with: candidate) else { continue }
                    points = extendedPoints
                    used[index] = true
                    extended = true
                    break
                }
            }
            polylines.append(points)
        }
        return polylines
    }

    private static func extend(_ points: [CGPoint], with segment: BoundarySegment) -> [CGPoint]? {
        guard let head = points.first, let tail = points.last else { return nil }
        if isSamePoint(segment.from, tail) { return points + [segment.to] }
        if isSamePoint(segment.to, tail) { return points + [segment.from] }
        if isSamePoint(segment.to, head) { return [segment.from] + points }
        if isSamePoint(segment.from, head) { return [segment.to] + points }
        return nil
    }

    private static func isSamePoint(_ first: CGPoint, _ second: CGPoint) -> Bool {
        abs(first.x - second.x) < coincident && abs(first.y - second.y) < coincident
    }

    // MARK: - Smoothing

    /// Chaikin corner cutting: replaces every segment with points at 25% and 75%
    /// of it, keeping the two endpoints so a line that reached the paper's edge
    /// still reaches it.
    private static func smoothed(_ points: [CGPoint]) -> [CGPoint] {
        var current = points
        for _ in 0 ..< smoothingRounds {
            guard current.count >= 3 else { return current }
            var next = [current[0]]
            for index in 0 ..< (current.count - 1) {
                let from = current[index]
                let to = current[index + 1]
                next.append(CGPoint(x: from.x * 0.75 + to.x * 0.25, y: from.y * 0.75 + to.y * 0.25))
                next.append(CGPoint(x: from.x * 0.25 + to.x * 0.75, y: from.y * 0.25 + to.y * 0.75))
            }
            next.append(current[current.count - 1])
            current = next
        }
        return current
    }

    // MARK: - Supporting types

    private struct OwnerGrid {
        let owners: [Int]
        let columns: Int
        let rows: Int

        func owner(column: Int, row: Int) -> Int { owners[row * columns + column] }
    }

    private struct Crossing {
        let point: CGPoint
        let pair: RegionPair
    }

    private struct BoundarySegment {
        let from: CGPoint
        let to: CGPoint
        let pair: RegionPair
    }

    /// The two regions a piece of boundary divides, unordered.
    private struct RegionPair: Hashable {
        let lower: Int
        let upper: Int

        init(_ first: Int, _ second: Int) {
            lower = min(first, second)
            upper = max(first, second)
        }
    }
}
