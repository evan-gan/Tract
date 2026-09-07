import Testing
import CoreGraphics
@testable import Tract

@Suite("Worksheet polyline thinning")
struct WorksheetPolylineTests {
    @Test("Samples that sit on the line between their neighbours are dropped")
    func collinearSamplesCollapse() {
        let straight = (0 ... 10).map { CGPoint(x: CGFloat($0) * 10, y: 0) }

        let simplified = WorksheetPolyline.simplified(straight, tolerance: 0.35)

        #expect(simplified == [straight[0], straight[10]])
    }

    @Test("A sample further from the chord than the tolerance is kept")
    func realDetailSurvives() {
        let kinked = [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 9), CGPoint(x: 100, y: 0)]

        #expect(WorksheetPolyline.simplified(kinked, tolerance: 0.35) == kinked)
        #expect(WorksheetPolyline.simplified(kinked, tolerance: 20).count == 2)
    }

    @Test("The endpoints are never dropped, whatever the tolerance")
    func endpointsAreAlwaysKept() {
        let wobble = (0 ... 20).map { CGPoint(x: CGFloat($0), y: CGFloat($0 % 2)) }

        let simplified = WorksheetPolyline.simplified(wobble, tolerance: 1_000)

        #expect(simplified.first == wobble.first)
        #expect(simplified.last == wobble.last)
        #expect(simplified.count == 2)
    }

    @Test("A tolerance of zero keeps every sample")
    func zeroToleranceKeepsEverything() {
        let points = (0 ... 5).map { CGPoint(x: CGFloat($0), y: 0) }

        #expect(WorksheetPolyline.simplified(points, tolerance: 0) == points)
    }

    @Test("A deeply sampled stroke thins without recursing to a stack overflow")
    func longStrokesAreHandledIteratively() {
        // The reason for the explicit stack: a stroke can carry hundreds of
        // samples, and a spiral splits about as deeply as a polyline can.
        let spiral = (0 ..< 4_000).map { index -> CGPoint in
            let angle = CGFloat(index) * 0.05
            return CGPoint(x: angle * cos(angle), y: angle * sin(angle))
        }

        let simplified = WorksheetPolyline.simplified(spiral, tolerance: 0.35)

        #expect(simplified.count < spiral.count)
        #expect(simplified.count >= 2)
    }
}

@Suite("Worksheet column profiles")
struct WorksheetColumnProfileTests {
    @Test("A rectangle's upper edge is flat and its lower edge is its height")
    func rectangleProfileIsFlat() {
        let rectangle = WorksheetPolygon.corners(of: CGRect(x: 10, y: 20, width: 30, height: 12))

        let profile = WorksheetColumnProfile(polygon: rectangle, columnWidth: 3)

        #expect(profile.columnCount == 10)
        #expect(profile.height == 12)
        #expect(profile.top.allSatisfy { $0 == 0 })
        #expect(profile.bottom.allSatisfy { $0 == 12 })
    }

    @Test("A wedge's upper edge falls away across its columns, which is what lets it nest")
    func wedgeProfileSlopes() {
        let wedge = [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 30), CGPoint(x: 0, y: 30)]

        let profile = WorksheetColumnProfile(polygon: wedge, columnWidth: 3)

        // Left edge reaches the top; the right-hand columns start further down.
        #expect(profile.top[0] == 0)
        #expect(profile.top[profile.columnCount - 1] > profile.top[0])
        #expect(profile.bottom.allSatisfy { $0 == 30 })
    }

    @Test("Offsets are measured from the shape's own top, so a profile can be dropped anywhere")
    func profileIsPositionIndependent() {
        let shape = [CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 10), CGPoint(x: 0, y: 20)]
        let moved = WorksheetPolygon.translated(shape, by: CGPoint(x: 400, y: 250))

        let here = WorksheetColumnProfile(polygon: shape, columnWidth: 3)
        let there = WorksheetColumnProfile(polygon: moved, columnWidth: 3)

        #expect(here.top == there.top)
        #expect(here.bottom == there.bottom)
    }
}
