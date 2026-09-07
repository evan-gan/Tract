import CoreGraphics

/// Convex-polygon maths for the worksheet layout: the shape a problem actually
/// occupies, as opposed to the rectangle it happens to sit in.
///
/// Think of a rubber band pulled tight around the ink and then held off it by
/// the pen's radius — that is `convexHull` followed by `dilated`. Packing
/// against these instead of bounding boxes is what lets a wedge-shaped problem
/// slide under a slanted neighbour.
///
/// Everything here is plain polygon maths in a y-down space; nothing knows about
/// pages, PDFs or layouts. A polygon is a vertex ring, first vertex adjacent to
/// the last.
enum WorksheetPolygon {
    /// Points closer than this are the same point. Two polygons that merely
    /// share an edge count as *not* intersecting because of it.
    static let coincident: CGFloat = 1e-9

    // MARK: - Building

    /// Convex hull by Andrew's monotone chain, O(n log n).
    ///
    /// - Returns: Hull vertices in order. One or two points come back as-is,
    ///   since a dot or a straight stroke has no area to wrap.
    static func convexHull(_ points: [CGPoint]) -> [CGPoint] {
        let sorted = points.sorted { $0.x != $1.x ? $0.x < $1.x : $0.y < $1.y }
        guard sorted.count >= 3 else { return sorted }

        let hull = monotoneChain(sorted) + monotoneChain(sorted.reversed())
        return hull.count >= 3 ? hull : sorted
    }

    /// One side of the hull. The last point is dropped because it is the first
    /// point of the chain built in the opposite direction.
    private static func monotoneChain(_ ordered: [CGPoint]) -> [CGPoint] {
        var chain: [CGPoint] = []
        for point in ordered {
            while chain.count >= 2,
                  cross(chain[chain.count - 2], chain[chain.count - 1], point) <= 0 {
                chain.removeLast()
            }
            chain.append(point)
        }
        if !chain.isEmpty { chain.removeLast() }
        return chain
    }

    private static func cross(_ origin: CGPoint, _ first: CGPoint, _ second: CGPoint) -> CGFloat {
        (first.x - origin.x) * (second.y - origin.y) - (first.y - origin.y) * (second.x - origin.x)
    }

    /// Grows a convex polygon outward by a radius, with rounded corners — the
    /// Minkowski sum with a disc, approximated by `samples` points per vertex.
    ///
    /// The sample radius is scaled up by `1 / cos(π / samples)` so the
    /// approximation *circumscribes* the true offset: an inscribed one would
    /// leave shapes closer than the clearance asked for, which is the whole
    /// point of the radius.
    static func dilated(_ polygon: [CGPoint], by radius: CGFloat, samples: Int = 8) -> [CGPoint] {
        guard radius > 0, !polygon.isEmpty, samples > 2 else { return polygon }

        let circumscribedRadius = radius / cos(.pi / CGFloat(samples))
        var grown: [CGPoint] = []
        grown.reserveCapacity(polygon.count * samples)
        for vertex in polygon {
            for step in 0 ..< samples {
                let angle = 2 * CGFloat.pi * CGFloat(step) / CGFloat(samples)
                grown.append(
                    CGPoint(
                        x: vertex.x + circumscribedRadius * cos(angle),
                        y: vertex.y + circumscribedRadius * sin(angle)
                    )
                )
            }
        }
        return convexHull(grown)
    }

    static func scaled(_ polygon: [CGPoint], by scale: CGFloat) -> [CGPoint] {
        polygon.map { CGPoint(x: $0.x * scale, y: $0.y * scale) }
    }

    static func translated(_ polygon: [CGPoint], by offset: CGPoint) -> [CGPoint] {
        polygon.map { CGPoint(x: $0.x + offset.x, y: $0.y + offset.y) }
    }

    static func corners(of rect: CGRect) -> [CGPoint] {
        [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
    }

    // MARK: - Measuring

    /// The box around a polygon; `.null` for an empty one, which unions and
    /// intersection tests both already treat as "nothing here".
    static func bounds(of polygon: [CGPoint]) -> CGRect {
        polygon.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    /// Whether a convex polygon contains a point, edges counting as inside.
    ///
    /// A point inside sits on the same side of every edge; *which* side depends
    /// on the winding, which varies here, so the test is that the sides agree
    /// rather than that they are positive.
    static func contains(_ polygon: [CGPoint], _ point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var anyLeft = false
        var anyRight = false

        for index in polygon.indices {
            let from = polygon[index]
            let to = polygon[(index + 1) % polygon.count]
            let side = (to.x - from.x) * (point.y - from.y) - (to.y - from.y) * (point.x - from.x)
            if side > coincident {
                anyLeft = true
            } else if side < -coincident {
                anyRight = true
            }
            if anyLeft && anyRight { return false }
        }
        return true
    }

    /// Zero inside the polygon, otherwise the distance to its nearest edge.
    /// An empty polygon is infinitely far from everything.
    static func distance(from point: CGPoint, to polygon: [CGPoint]) -> CGFloat {
        guard !polygon.isEmpty else { return .greatestFiniteMagnitude }
        if contains(polygon, point) { return 0 }

        var nearest = CGFloat.greatestFiniteMagnitude
        for index in polygon.indices {
            let from = polygon[index]
            let to = polygon[(index + 1) % polygon.count]
            nearest = min(nearest, StrokeGeometry.distance(from: point, toSegment: from, to))
        }
        return nearest
    }

    /// Shoelace area; 0 for a point or a segment. The ink-coverage measure, so a
    /// diagonal problem is not credited for the corners it never touches.
    static func area(of polygon: [CGPoint]) -> CGFloat {
        guard polygon.count >= 3 else { return 0 }
        var doubled: CGFloat = 0
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            doubled += current.x * next.y - next.x * current.y
        }
        return abs(doubled) / 2
    }

    /// Separating-axis test for two convex polygons. Exact for convex shapes and
    /// cheap enough to run inside a scale search once bounding boxes agree the
    /// two might touch. Polygons that merely share an edge do **not** intersect.
    static func intersect(_ first: [CGPoint], _ second: [CGPoint]) -> Bool {
        guard !first.isEmpty, !second.isEmpty else { return false }

        let firstBounds = bounds(of: first)
        let secondBounds = bounds(of: second)
        if firstBounds.maxX <= secondBounds.minX + coincident
            || secondBounds.maxX <= firstBounds.minX + coincident
            || firstBounds.maxY <= secondBounds.minY + coincident
            || secondBounds.maxY <= firstBounds.minY + coincident {
            return false
        }
        return !hasSeparatingAxis(first, second) && !hasSeparatingAxis(second, first)
    }

    private static func hasSeparatingAxis(_ polygon: [CGPoint], _ other: [CGPoint]) -> Bool {
        for index in polygon.indices {
            let current = polygon[index]
            let next = polygon[(index + 1) % polygon.count]
            // Normal of this edge.
            let axis = CGPoint(x: -(next.y - current.y), y: next.x - current.x)
            if abs(axis.x) < coincident && abs(axis.y) < coincident { continue }

            let own = projection(of: polygon, onto: axis)
            let theirs = projection(of: other, onto: axis)
            if own.max <= theirs.min + coincident || theirs.max <= own.min + coincident { return true }
        }
        return false
    }

    private static func projection(
        of polygon: [CGPoint],
        onto axis: CGPoint
    ) -> (min: CGFloat, max: CGFloat) {
        var minimum = CGFloat.greatestFiniteMagnitude
        var maximum = -CGFloat.greatestFiniteMagnitude
        for vertex in polygon {
            let projected = vertex.x * axis.x + vertex.y * axis.y
            minimum = min(minimum, projected)
            maximum = max(maximum, projected)
        }
        return (minimum, maximum)
    }
}
