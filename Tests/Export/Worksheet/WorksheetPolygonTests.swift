import Testing
import CoreGraphics
@testable import Tract

@Suite("Worksheet polygons")
struct WorksheetPolygonTests {
    private let unitSquare = [
        CGPoint(x: 0, y: 0),
        CGPoint(x: 10, y: 0),
        CGPoint(x: 10, y: 10),
        CGPoint(x: 0, y: 10)
    ]

    // MARK: - Hulls

    @Test("The hull of a square keeps its corners and drops anything inside")
    func hullDropsInteriorPoints() {
        let hull = WorksheetPolygon.convexHull(unitSquare + [CGPoint(x: 5, y: 5), CGPoint(x: 2, y: 7)])

        #expect(hull.count == 4)
        for corner in unitSquare {
            #expect(hull.contains { $0 == corner })
        }
    }

    @Test("A dot or a straight stroke has no area, so it comes back as it went in")
    func degenerateHullsAreReturnedUnchanged() {
        let segment = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)]

        #expect(WorksheetPolygon.convexHull(segment).count == 2)
        #expect(WorksheetPolygon.convexHull([CGPoint(x: 1, y: 1)]).count == 1)
        #expect(WorksheetPolygon.convexHull([]).isEmpty)
    }

    // MARK: - Clearance

    @Test("Dilation circumscribes the true offset, so nothing ends up closer than the clearance")
    func dilationNeverFallsShortOfTheRadius() {
        let radius: CGFloat = 8
        let grown = WorksheetPolygon.dilated(unitSquare, by: radius)

        // Sampling around the square: every direction must have been pushed out
        // by at least the radius, never less — an inscribed approximation would
        // fall short between the sample points, which is the bug this guards.
        for degrees in stride(from: 0, to: 360, by: 5) {
            let angle = CGFloat(degrees) * .pi / 180
            let probe = CGPoint(
                x: 5 + (5 + radius) * cos(angle) * 0.999,
                y: 5 + (5 + radius) * sin(angle) * 0.999
            )
            #expect(WorksheetPolygon.contains(grown, probe))
        }
    }

    @Test("A clearance of zero leaves the polygon alone")
    func zeroClearanceIsANoOp() {
        #expect(WorksheetPolygon.dilated(unitSquare, by: 0) == unitSquare)
    }

    // MARK: - Overlap

    @Test("Overlapping squares intersect; separated ones do not")
    func overlapIsDetected() {
        let overlapping = WorksheetPolygon.translated(unitSquare, by: CGPoint(x: 5, y: 5))
        let apart = WorksheetPolygon.translated(unitSquare, by: CGPoint(x: 40, y: 0))

        #expect(WorksheetPolygon.intersect(unitSquare, overlapping))
        #expect(!WorksheetPolygon.intersect(unitSquare, apart))
    }

    @Test("Two shapes that merely share an edge are not overlapping")
    func touchingEdgesDoNotCount() {
        // Packing puts outlines flush against each other constantly; counting a
        // shared edge as a collision would stop the packer dead.
        let flush = WorksheetPolygon.translated(unitSquare, by: CGPoint(x: 10, y: 0))

        #expect(!WorksheetPolygon.intersect(unitSquare, flush))
    }

    @Test("A slanted shape does not claim the empty corners of its own box")
    func slantedShapesNestInsideEachOthersBoxes() {
        // The point of hulls over bounding boxes: these two triangles interlock,
        // and their boxes overlap almost entirely.
        let lower = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 0, y: 20)]
        let upper = [CGPoint(x: 21, y: 1), CGPoint(x: 21, y: 21), CGPoint(x: 1, y: 21)]

        #expect(!WorksheetPolygon.intersect(lower, upper))
        #expect(WorksheetPolygon.bounds(of: lower).intersects(WorksheetPolygon.bounds(of: upper)))
    }

    // MARK: - Measuring

    @Test("Distance is zero inside the shape and the edge distance outside it")
    func distanceMeasuresFromTheNearestEdge() {
        #expect(WorksheetPolygon.distance(from: CGPoint(x: 5, y: 5), to: unitSquare) == 0)
        #expect(WorksheetPolygon.distance(from: CGPoint(x: 14, y: 5), to: unitSquare) == 4)
    }

    @Test("Winding does not change what counts as inside")
    func containmentIgnoresWinding() {
        let reversed = Array(unitSquare.reversed())

        #expect(WorksheetPolygon.contains(reversed, CGPoint(x: 5, y: 5)))
        #expect(!WorksheetPolygon.contains(reversed, CGPoint(x: 15, y: 5)))
    }

    @Test("Area is the shoelace area, and zero for anything without one")
    func areaOfASquareAndOfASegment() {
        #expect(WorksheetPolygon.area(of: unitSquare) == 100)
        #expect(WorksheetPolygon.area(of: [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 5)]) == 0)
    }
}
