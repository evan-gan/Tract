import CoreGraphics

/// Builds the shape that frames a selection: the outline of the selected ink,
/// pushed outward so it stands a constant distance clear of every stroke.
/// Pure geometry — the caller decides which space it works in.
enum SelectionOutline {

    /// How far a mitred corner may run past the vertex before it is cut back to a
    /// bevel, as a multiple of the standoff. Without this, a needle-sharp corner
    /// in the drawing would throw a long spike off the outline.
    private static let miterLimit: CGFloat = 2.0

    // MARK: - Convex hull

    /// Andrew's monotone chain. Returns the hull counter-clockwise in a
    /// y-down coordinate space, or the input unchanged when it is degenerate
    /// (fewer than three points, or all of them collinear).
    static func convexHull(of points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 3 else { return points }

        let sorted = points.sorted { $0.x == $1.x ? $0.y < $1.y : $0.x < $1.x }
        let lower = buildChain(through: sorted)
        let upper = buildChain(through: sorted.reversed())
        let hull = lower + upper
        guard hull.count >= 3 else { return points }
        return normalizedWinding(hull)
    }

    /// One half of the hull: walks the sorted points, dropping any vertex that a
    /// later point proves to be inside the chain.
    private static func buildChain(through sequence: [CGPoint]) -> [CGPoint] {
        var chain: [CGPoint] = []
        for point in sequence {
            while chain.count >= 2,
                  crossProduct(chain[chain.count - 2], chain[chain.count - 1], point) <= 0 {
                chain.removeLast()
            }
            chain.append(point)
        }
        // The last point starts the opposite chain, so it would otherwise appear twice.
        chain.removeLast()
        return chain
    }

    private static func crossProduct(_ origin: CGPoint, _ first: CGPoint, _ second: CGPoint) -> CGFloat {
        (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x)
    }

    /// Twice the signed area. Positive means counter-clockwise, which is the
    /// winding `offset(polygon:by:)` assumes when it picks its outward direction.
    static func signedArea(of polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var total: CGFloat = 0
        var previous = polygon[polygon.count - 1]
        for vertex in polygon {
            total += previous.x * vertex.y - vertex.x * previous.y
            previous = vertex
        }
        return total
    }

    private static func normalizedWinding(_ polygon: [CGPoint]) -> [CGPoint] {
        signedArea(of: polygon) < 0 ? polygon.reversed() : polygon
    }

    // MARK: - Outward offset

    /// Grows a convex polygon outward by `distance` on every side, keeping its
    /// shape rather than falling back to a bounding box. Corners are mitred so
    /// they stay recognisably corners; only corners sharp enough to spike are
    /// cut back to a bevel.
    static func offset(polygon: [CGPoint], by distance: CGFloat) -> [CGPoint] {
        guard polygon.count >= 3, distance > 0 else { return polygon }

        var expanded: [CGPoint] = []
        expanded.reserveCapacity(polygon.count + 4)

        for index in polygon.indices {
            let vertex = polygon[index]
            let incomingNormal = outwardNormal(from: polygon[(index + polygon.count - 1) % polygon.count],
                                               to: vertex)
            let outgoingNormal = outwardNormal(from: vertex,
                                               to: polygon[(index + 1) % polygon.count])
            expanded.append(contentsOf: corner(
                at: vertex,
                between: incomingNormal,
                and: outgoingNormal,
                distance: distance
            ))
        }
        return expanded
    }

    /// Unit vector pointing away from a counter-clockwise polygon's interior,
    /// perpendicular to the edge start→end.
    private static func outwardNormal(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let edge = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let length = (edge.x * edge.x + edge.y * edge.y).squareRoot()
        guard length > 0 else { return .zero }
        return CGPoint(x: edge.y / length, y: -edge.x / length)
    }

    /// The one or two points that replace a single vertex once the polygon grows:
    /// a mitre point normally, a two-point bevel when the mitre would spike.
    private static func corner(
        at vertex: CGPoint,
        between incomingNormal: CGPoint,
        and outgoingNormal: CGPoint,
        distance: CGFloat
    ) -> [CGPoint] {
        let bevel = [
            CGPoint(x: vertex.x + incomingNormal.x * distance, y: vertex.y + incomingNormal.y * distance),
            CGPoint(x: vertex.x + outgoingNormal.x * distance, y: vertex.y + outgoingNormal.y * distance),
        ]

        let bisector = CGPoint(x: incomingNormal.x + outgoingNormal.x,
                               y: incomingNormal.y + outgoingNormal.y)
        let bisectorLength = (bisector.x * bisector.x + bisector.y * bisector.y).squareRoot()
        // Opposed normals mean the edges double back on themselves; there is no mitre.
        guard bisectorLength > 0.0001 else { return bevel }

        let unitBisector = CGPoint(x: bisector.x / bisectorLength, y: bisector.y / bisectorLength)
        // cos of half the turn: how much the mitre has to overshoot to reach both offset edges.
        let halfAngleCosine = unitBisector.x * incomingNormal.x + unitBisector.y * incomingNormal.y
        guard halfAngleCosine > 0.0001 else { return bevel }

        let miterLength = distance / halfAngleCosine
        guard miterLength <= distance * miterLimit else { return bevel }

        return [CGPoint(x: vertex.x + unitBisector.x * miterLength,
                        y: vertex.y + unitBisector.y * miterLength)]
    }
}
