import CoreGraphics

/// Pure geometry used by the eraser (does this gesture cross a stroke?) and the
/// lasso (is this stroke entirely inside the loop the user drew?).
/// Everything here works in canvas space and has no UI dependencies.
enum StrokeGeometry {

    /// How close the eraser has to pass to a zero-length stroke — a tap-dot — to
    /// count as a hit. Dots have no segment to cross, so proximity is the only test.
    private static let dotHitRadius: CGFloat = 6

    // MARK: - Segment intersection

    /// True when the closed line segments A and B cross or touch.
    static func segmentsIntersect(
        _ firstStart: CGPoint, _ firstEnd: CGPoint,
        _ secondStart: CGPoint, _ secondEnd: CGPoint
    ) -> Bool {
        let firstAgainstSecondStart = orientation(firstStart, firstEnd, secondStart)
        let firstAgainstSecondEnd = orientation(firstStart, firstEnd, secondEnd)
        let secondAgainstFirstStart = orientation(secondStart, secondEnd, firstStart)
        let secondAgainstFirstEnd = orientation(secondStart, secondEnd, firstEnd)

        // General case: each segment straddles the other's infinite line.
        if firstAgainstSecondStart != firstAgainstSecondEnd
            && secondAgainstFirstStart != secondAgainstFirstEnd {
            return true
        }

        // Collinear cases: an endpoint of one segment lies on the other.
        if firstAgainstSecondStart == 0 && isOnSegment(firstStart, firstEnd, secondStart) { return true }
        if firstAgainstSecondEnd == 0 && isOnSegment(firstStart, firstEnd, secondEnd) { return true }
        if secondAgainstFirstStart == 0 && isOnSegment(secondStart, secondEnd, firstStart) { return true }
        if secondAgainstFirstEnd == 0 && isOnSegment(secondStart, secondEnd, firstEnd) { return true }
        return false
    }

    /// Sign of the cross product of (start→end) × (start→probe):
    /// 1 counter-clockwise, -1 clockwise, 0 collinear.
    private static func orientation(_ start: CGPoint, _ end: CGPoint, _ probe: CGPoint) -> Int {
        let cross = (end.x - start.x) * (probe.y - start.y) - (end.y - start.y) * (probe.x - start.x)
        if cross > 0 { return 1 }
        if cross < 0 { return -1 }
        return 0
    }

    /// Whether a point already known to be collinear falls between the endpoints.
    private static func isOnSegment(_ start: CGPoint, _ end: CGPoint, _ probe: CGPoint) -> Bool {
        probe.x >= min(start.x, end.x) && probe.x <= max(start.x, end.x)
            && probe.y >= min(start.y, end.y) && probe.y <= max(start.y, end.y)
    }

    /// Shortest distance from a point to a line segment.
    static func distance(from point: CGPoint, toSegment start: CGPoint, _ end: CGPoint) -> CGFloat {
        let segment = CGPoint(x: end.x - start.x, y: end.y - start.y)
        let lengthSquared = segment.x * segment.x + segment.y * segment.y
        guard lengthSquared > 0 else { return point.distance(to: start) }

        // Projection of the point onto the segment, clamped to the segment's span.
        let rawProjection = ((point.x - start.x) * segment.x + (point.y - start.y) * segment.y) / lengthSquared
        let clamped = min(max(rawProjection, 0), 1)
        let closest = CGPoint(x: start.x + segment.x * clamped, y: start.y + segment.y * clamped)
        return point.distance(to: closest)
    }

    // MARK: - Eraser

    /// Whether an eraser movement — one segment of the erase gesture — crosses a stroke.
    static func stroke(_ stroke: Stroke, isCrossedBy eraserStart: CGPoint, _ eraserEnd: CGPoint) -> Bool {
        // Cheap rejection first: most strokes are nowhere near the eraser.
        let eraserBounds = CGRect(
            x: min(eraserStart.x, eraserEnd.x),
            y: min(eraserStart.y, eraserEnd.y),
            width: abs(eraserEnd.x - eraserStart.x),
            height: abs(eraserEnd.y - eraserStart.y)
        ).insetBy(dx: -dotHitRadius, dy: -dotHitRadius)
        guard stroke.canvasBounds.intersects(eraserBounds) else { return false }

        let positions = stroke.points.map(\.position)
        guard let firstPosition = positions.first else { return false }

        // A single-point stroke is a dot: nothing to cross, so use proximity.
        guard positions.count >= 2 else {
            return distance(from: firstPosition, toSegment: eraserStart, eraserEnd) <= dotHitRadius
        }

        for index in 1 ..< positions.count
        where segmentsIntersect(positions[index - 1], positions[index], eraserStart, eraserEnd) {
            return true
        }
        return false
    }

    // MARK: - Lasso

    /// Ray-casting point-in-polygon test. The polygon is treated as closed, so the
    /// caller does not need to repeat the first vertex at the end.
    static func polygon(_ polygon: [CGPoint], contains point: CGPoint) -> Bool {
        guard polygon.count >= 3 else { return false }

        var isInside = false
        var previousIndex = polygon.count - 1
        for currentIndex in polygon.indices {
            let current = polygon[currentIndex]
            let previous = polygon[previousIndex]
            // Count edges that straddle the point's horizontal ray to its right.
            let straddlesRay = (current.y > point.y) != (previous.y > point.y)
            if straddlesRay {
                let crossingX = (previous.x - current.x) * (point.y - current.y)
                    / (previous.y - current.y) + current.x
                if point.x < crossingX { isInside.toggle() }
            }
            previousIndex = currentIndex
        }
        return isInside
    }

    /// Whether every sample of a stroke falls inside the lasso loop. Strokes that
    /// only partly overlap the loop are deliberately left unselected.
    static func stroke(_ stroke: Stroke, isEnclosedBy lassoPolygon: [CGPoint]) -> Bool {
        guard lassoPolygon.count >= 3, !stroke.points.isEmpty else { return false }
        return stroke.points.allSatisfy { polygon(lassoPolygon, contains: $0.position) }
    }
}
