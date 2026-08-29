import Testing
import CoreGraphics
@testable import Tract

@Suite("Segment intersection")
struct SegmentIntersectionTests {
    @Test("Two segments that cross are reported as intersecting")
    func crossingSegments() {
        #expect(StrokeGeometry.segmentsIntersect(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10),
            CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 0)
        ))
    }

    @Test("Parallel segments never intersect")
    func parallelSegments() {
        #expect(StrokeGeometry.segmentsIntersect(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5)
        ) == false)
    }

    @Test("Segments whose infinite lines cross beyond their ends do not intersect")
    func crossingOnlyWhenExtended() {
        #expect(StrokeGeometry.segmentsIntersect(
            CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1),
            CGPoint(x: 10, y: 0), CGPoint(x: 10, y: 20)
        ) == false)
    }

    @Test("A segment touching another at a single endpoint counts as intersecting")
    func touchingEndpoint() {
        #expect(StrokeGeometry.segmentsIntersect(
            CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            CGPoint(x: 5, y: 0), CGPoint(x: 5, y: 10)
        ))
    }
}

@Suite("Segment distance")
struct SegmentDistanceTests {
    @Test("Crossing segments are zero apart")
    func crossingSegments() {
        #expect(StrokeGeometry.distance(
            fromSegment: CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10),
            toSegment: CGPoint(x: 0, y: 10), CGPoint(x: 10, y: 0)
        ) == 0)
    }

    @Test("Parallel segments are their perpendicular separation apart")
    func parallelSegments() {
        #expect(StrokeGeometry.distance(
            fromSegment: CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0),
            toSegment: CGPoint(x: 0, y: 4), CGPoint(x: 10, y: 4)
        ) == 4)
    }

    @Test("Segments that never overlap are measured between their nearest endpoints")
    func endpointToEndpoint() {
        #expect(StrokeGeometry.distance(
            fromSegment: CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10),
            toSegment: CGPoint(x: 3, y: 14), CGPoint(x: 3, y: 20)
        ) == 5)
    }
}

@Suite("Point in polygon")
struct PolygonContainmentTests {
    private let square = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    @Test("A point inside the loop is contained")
    func insidePoint() {
        #expect(StrokeGeometry.polygon(square, contains: CGPoint(x: 50, y: 50)))
    }

    @Test("A point outside the loop is not contained")
    func outsidePoint() {
        #expect(StrokeGeometry.polygon(square, contains: CGPoint(x: 150, y: 50)) == false)
    }

    @Test("A concave loop excludes points in its notch")
    func concaveLoop() {
        // A "C" shape opening to the right; (80, 50) sits in the open mouth.
        let cShape = [
            CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 20),
            CGPoint(x: 40, y: 20), CGPoint(x: 40, y: 80), CGPoint(x: 100, y: 80),
            CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
        ]
        #expect(StrokeGeometry.polygon(cShape, contains: CGPoint(x: 20, y: 50)))
        #expect(StrokeGeometry.polygon(cShape, contains: CGPoint(x: 80, y: 50)) == false)
    }

    @Test("A loop with fewer than three points contains nothing")
    func degenerateLoop() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        #expect(StrokeGeometry.polygon(line, contains: CGPoint(x: 5, y: 5)) == false)
    }
}

@Suite("Stroke against lasso and eraser")
struct StrokeHitTests {
    private let square = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    @Test("A stroke entirely inside the loop is enclosed")
    func fullyEnclosedStroke() {
        let stroke = StrokeFixtures.stroke(through: [
            CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 40), CGPoint(x: 80, y: 80),
        ])
        #expect(StrokeGeometry.stroke(stroke, isEnclosedBy: square))
    }

    @Test("A stroke with even one point outside the loop is not enclosed")
    func partiallyEnclosedStroke() {
        let stroke = StrokeFixtures.stroke(through: [
            CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 40), CGPoint(x: 400, y: 40),
        ])
        #expect(StrokeGeometry.stroke(stroke, isEnclosedBy: square) == false)
    }

    /// The eraser's own contact patch, sized as the canvas uses it at 100% zoom.
    private let tipRadius: CGFloat = 3

    @Test("An eraser movement across a stroke is a hit")
    func eraserCrossesStroke() {
        let stroke = StrokeFixtures.stroke(through: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)])
        #expect(StrokeGeometry.stroke(
            stroke, isTouchedBy: CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 100), tipRadius: tipRadius
        ))
    }

    @Test("An eraser movement that misses a stroke is not a hit")
    func eraserMissesStroke() {
        let stroke = StrokeFixtures.stroke(through: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)])
        #expect(StrokeGeometry.stroke(
            stroke, isTouchedBy: CGPoint(x: 0, y: 200), CGPoint(x: 100, y: 200), tipRadius: tipRadius
        ) == false)
    }

    @Test("A single-point dot is erased when the eraser passes close to it")
    func eraserHitsDot() {
        let dot = StrokeFixtures.stroke(through: [CGPoint(x: 50, y: 50)])
        #expect(StrokeGeometry.stroke(
            dot, isTouchedBy: CGPoint(x: 0, y: 52), CGPoint(x: 100, y: 52), tipRadius: tipRadius
        ))
        #expect(StrokeGeometry.stroke(
            dot, isTouchedBy: CGPoint(x: 0, y: 90), CGPoint(x: 100, y: 90), tipRadius: tipRadius
        ) == false)
    }

    @Test("Touching the visible body of a thick stroke erases it without reaching its centreline")
    func eraserHitsInsideAThickStroke() {
        let thickLine = StrokeFixtures.stroke(
            through: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)], lineWidth: 40
        )
        // Ten points off the centreline is still well inside a 40-point line.
        #expect(StrokeGeometry.stroke(
            thickLine, isTouchedBy: CGPoint(x: 40, y: 60), CGPoint(x: 60, y: 60), tipRadius: tipRadius
        ))
    }

    @Test("An eraser passing outside a thick stroke's visible edge leaves it alone")
    func eraserMissesOutsideAThickStroke() {
        let thickLine = StrokeFixtures.stroke(
            through: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)], lineWidth: 40
        )
        // The line's edge is at y = 30; a tip of radius 3 reaches no further than y = 27.
        #expect(StrokeGeometry.stroke(
            thickLine, isTouchedBy: CGPoint(x: 40, y: 20), CGPoint(x: 60, y: 20), tipRadius: tipRadius
        ) == false)
    }

    @Test("A thin stroke is erased by a tip that only grazes it")
    func eraserGrazesThinStroke() {
        let hairline = StrokeFixtures.stroke(
            through: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)], lineWidth: 1
        )
        // 3 points clear of the centreline: outside the ink, inside the tip's reach.
        #expect(StrokeGeometry.stroke(
            hairline, isTouchedBy: CGPoint(x: 40, y: 53), CGPoint(x: 60, y: 53), tipRadius: tipRadius
        ))
    }
}
