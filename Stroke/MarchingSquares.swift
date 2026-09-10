import CoreGraphics

/// Turns a `DistanceField` into closed outlines by tracing one of its
/// iso-lines — the classic marching-squares walk.
///
/// Shared by both region builders: the lasso's frame traces the samples *under*
/// its standoff, and a problem's bounding region traces the samples *over* its
/// curve radius, which is the only difference between the two calls.
enum MarchingSquares {

    /// Walks every cell of the field, collects where the contour cuts each grid
    /// edge, and stitches those crossings into closed loops.
    ///
    /// - Parameters:
    ///   - threshold: The value the traced boundary sits at.
    ///   - insideIsBelow: Whether samples *under* the threshold are the region.
    ///     `false` traces the complement instead — the region of samples at or
    ///     over it.
    ///   - minimumVertices: Loops shorter than this are sampling noise rather
    ///     than shapes.
    /// - Returns: Closed contours, each a vertex loop that does not repeat its
    ///   first point. Outer boundaries and the boundaries of enclosed holes both
    ///   appear.
    static func contours(
        of field: DistanceField,
        at threshold: CGFloat,
        insideIsBelow: Bool,
        minimumVertices: Int
    ) -> [[CGPoint]] {
        var graph = CrossingGraph(edgeKeyCount: field.edgeKeyCount)

        for row in 0 ..< field.rows - 1 {
            for column in 0 ..< field.columns - 1 {
                let segments = cellSegments(
                    in: field,
                    column: column,
                    row: row,
                    threshold: threshold,
                    insideIsBelow: insideIsBelow
                )
                for edgePair in segments {
                    let start = graph.crossingIndex(ofEdge: edgePair.0, in: field, at: threshold)
                    let end = graph.crossingIndex(ofEdge: edgePair.1, in: field, at: threshold)
                    graph.link(start, end)
                }
            }
        }
        return graph.stitchLoops(minimumVertices: minimumVertices)
    }

    /// Which pairs of the cell's four edges the contour joins, decided by which
    /// of its corners fall inside the region.
    private static func cellSegments(
        in field: DistanceField,
        column: Int,
        row: Int,
        threshold: CGFloat,
        insideIsBelow: Bool
    ) -> [(Int, Int)] {
        func isInside(_ value: CGFloat) -> Bool {
            insideIsBelow ? value < threshold : value >= threshold
        }

        var insideCode = 0
        if isInside(field[column, row]) { insideCode |= 8 }              // top left
        if isInside(field[column + 1, row]) { insideCode |= 4 }          // top right
        if isInside(field[column + 1, row + 1]) { insideCode |= 2 }      // bottom right
        if isInside(field[column, row + 1]) { insideCode |= 1 }          // bottom left

        // Every cell wholly on one side of the boundary is one of these two, so
        // it is worth answering before working out four edge keys nothing uses.
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
