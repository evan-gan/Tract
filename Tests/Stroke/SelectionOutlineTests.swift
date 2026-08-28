import Testing
import CoreGraphics
@testable import Tract

@Suite("Convex hull")
struct ConvexHullTests {
    @Test("Points inside the shape are dropped from the hull")
    func dropsInteriorPoints() {
        let square = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        let hull = SelectionOutline.convexHull(of: square + [CGPoint(x: 50, y: 50)])
        #expect(hull.count == 4)
        #expect(hull.contains(CGPoint(x: 50, y: 50)) == false)
    }

    @Test("The hull always comes back counter-clockwise")
    func normalisesWinding() {
        let clockwise = [
            CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 100),
            CGPoint(x: 100, y: 100), CGPoint(x: 100, y: 0),
        ]
        #expect(SelectionOutline.signedArea(of: SelectionOutline.convexHull(of: clockwise)) > 0)
    }

    @Test("Collinear points have no hull and are returned unchanged")
    func collinearPointsAreDegenerate() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 0)]
        #expect(SelectionOutline.convexHull(of: line).count == line.count)
    }
}

@Suite("Outward offset")
struct OutlineOffsetTests {
    private let square = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    /// Shortest distance from a point to any edge of a closed polygon.
    private func distance(from point: CGPoint, toEdgesOf polygon: [CGPoint]) -> CGFloat {
        polygon.indices
            .map {
                StrokeGeometry.distance(
                    from: point,
                    toSegment: polygon[$0],
                    polygon[($0 + 1) % polygon.count]
                )
            }
            .min() ?? .infinity
    }

    @Test("The offset outline grows outward, never inward")
    func growsOutward() {
        let hull = SelectionOutline.convexHull(of: square)
        let expanded = SelectionOutline.offset(polygon: hull, by: 20)
        let expandedBounds = expanded.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        #expect(expandedBounds.minX == -20)
        #expect(expandedBounds.minY == -20)
        #expect(expandedBounds.maxX == 120)
        #expect(expandedBounds.maxY == 120)
    }

    @Test("Every original corner ends up the requested distance from the new outline")
    func holdsTheStandoffDistance() {
        let hull = SelectionOutline.convexHull(of: square)
        let expanded = SelectionOutline.offset(polygon: hull, by: 20)
        for corner in square {
            let standoff = distance(from: corner, toEdgesOf: expanded)
            #expect(abs(standoff - 20) < 0.001)
        }
    }

    @Test("The outline follows the shape instead of boxing it in")
    func followsShape() {
        // A triangle's offset stays a triangle-ish shape: its area must land well
        // short of the bounding box a rectangle frame would have used.
        let triangle = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 50, y: 100)]
        let expanded = SelectionOutline.offset(
            polygon: SelectionOutline.convexHull(of: triangle),
            by: 20
        )
        let outlineArea = abs(SelectionOutline.signedArea(of: expanded)) / 2
        let boundingBoxArea: CGFloat = 140 * 140
        #expect(outlineArea < boundingBoxArea * 0.75)
    }

    @Test("A needle-sharp corner is bevelled rather than spiked")
    func bevelsSharpCorners() {
        let needle = [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 4), CGPoint(x: 0, y: 8)]
        let expanded = SelectionOutline.offset(
            polygon: SelectionOutline.convexHull(of: needle),
            by: 20
        )
        // An unlimited mitre on this corner would run hundreds of points past the tip.
        let furthestX = expanded.map(\.x).max() ?? 0
        #expect(furthestX < 300 + 20 * 2.5)
    }

    @Test("A polygon with fewer than three corners is left alone")
    func ignoresDegeneratePolygons() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)]
        #expect(SelectionOutline.offset(polygon: line, by: 20) == line)
    }
}
