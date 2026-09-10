import Testing
import CoreGraphics
@testable import Tract

/// A problem's region is a box shrunk onto the ink, so these tests check the two
/// halves of that: it holds its padding where it touches the drawing, and it
/// refuses to follow the drawing into anything narrower than its curve radius —
/// which is the whole difference between it and the lasso's frame.
@Suite("Problem bounding region")
struct ProblemRegionTests {

    private let padding: CGFloat = 30
    private let curveRadius: CGFloat = 100

    private func region(around polylines: [[CGPoint]]) -> [[CGPoint]] {
        ProblemRegion.contours(around: polylines, padding: padding, curveRadius: curveRadius)
    }

    /// Shortest distance from a point to any edge of a closed contour.
    private func distance(from point: CGPoint, toEdgesOf contour: [CGPoint]) -> CGFloat {
        contour.indices
            .map {
                StrokeGeometry.distance(
                    from: point,
                    toSegment: contour[$0],
                    contour[($0 + 1) % contour.count]
                )
            }
            .min() ?? .infinity
    }

    private func horizontalLine(atY y: CGFloat, fromX startX: CGFloat, toX endX: CGFloat) -> [CGPoint] {
        [CGPoint(x: startX, y: y), CGPoint(x: endX, y: y)]
    }

    @Test("One patch of work is framed by one shape")
    func oneStrokeGivesOneContour() {
        #expect(region(around: [horizontalLine(atY: 0, fromX: 0, toX: 400)]).count == 1)
    }

    @Test("The boundary stands off the ink by the padding where it touches it")
    func holdsThePaddingAgainstTheInk() throws {
        // A straight stroke is convex, so nothing is bridged and the boundary is
        // the padding itself all the way round.
        let contour = try #require(region(around: [horizontalLine(atY: 0, fromX: 0, toX: 400)]).first)

        // The shape is built on a sampling grid twice over — once to measure the
        // ink, once to roll the ball — so the boundary lands within a couple of
        // cells of the true offset.
        let tolerance = padding / 2
        for probe in [CGPoint(x: 100, y: 0), CGPoint(x: 300, y: 0)] {
            #expect(abs(distance(from: probe, toEdgesOf: contour) - padding) < tolerance)
        }
    }

    @Test("The ink itself is always inside its own region")
    func containsTheInk() throws {
        let contour = try #require(region(around: [horizontalLine(atY: 0, fromX: 0, toX: 400)]).first)
        #expect(StrokeGeometry.polygon(contour, contains: CGPoint(x: 200, y: 0)))
    }

    @Test("A gap narrower than the curve radius is bridged, not followed into")
    func bridgesANarrowGap() throws {
        // Two lines of writing 200 apart: the channel between their padded edges
        // is 140 wide, which a ball 200 across cannot enter, so the region closes
        // over it as one block.
        let twoLines = [
            horizontalLine(atY: 0, fromX: 0, toX: 400),
            horizontalLine(atY: 200, fromX: 0, toX: 400),
        ]
        let betweenTheLines = CGPoint(x: 200, y: 100)

        let contour = try #require(region(around: twoLines).first)
        #expect(StrokeGeometry.polygon(contour, contains: betweenTheLines))

        // The contrast the feature exists for: the lasso's conforming frame
        // leaves the same point out.
        let lassoFrame = try #require(SelectionRegion.contours(around: twoLines, radius: padding).first)
        #expect(StrokeGeometry.polygon(lassoFrame, contains: betweenTheLines) == false)
    }

    @Test("A notch too tight for the curve is closed over")
    func spansATightNotch() throws {
        // A wide "V". Deep down between the arms the opening is far narrower than
        // the ball, so the region covers it even though there is no ink there.
        let arms = [
            [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 300)],
            [CGPoint(x: 200, y: 300), CGPoint(x: 400, y: 0)],
        ]
        let deepInTheNotch = CGPoint(x: 200, y: 200)

        let contour = try #require(region(around: arms).first)
        #expect(StrokeGeometry.polygon(contour, contains: deepInTheNotch))

        let lassoFrame = try #require(SelectionRegion.contours(around: arms, radius: padding).first)
        #expect(StrokeGeometry.polygon(lassoFrame, contains: deepInTheNotch) == false)
    }

    @Test("An opening wider than the curve is still left open")
    func keepsAWideOpening() throws {
        // The same "V" near its mouth, where the arms are far enough apart for the
        // ball to roll in. A region that closed over this would be a hull, not a
        // box shrunk onto the work.
        let arms = [
            [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 300)],
            [CGPoint(x: 200, y: 300), CGPoint(x: 400, y: 0)],
        ]
        let contour = try #require(region(around: arms).first)
        #expect(StrokeGeometry.polygon(contour, contains: CGPoint(x: 200, y: 20)) == false)
    }

    @Test("Work in two far-apart patches is framed twice")
    func farApartInkIsFramedSeparately() {
        // Further apart than the ball is wide, so nothing bridges them.
        let contours = region(around: [
            horizontalLine(atY: 0, fromX: 0, toX: 200),
            horizontalLine(atY: 1000, fromX: 0, toX: 200),
        ])
        #expect(contours.count == 2)
    }

    @Test("With no curve to roll, the region is the lasso's own frame")
    func noCurveRadiusFallsBackToTheDilation() {
        let line = horizontalLine(atY: 0, fromX: 0, toX: 400)
        let flat = ProblemRegion.contours(around: [line], padding: padding, curveRadius: 0)
        #expect(flat == SelectionRegion.contours(around: [line], radius: padding))
    }

    @Test("Nothing drawn produces no region")
    func emptyInkHasNoContours() {
        #expect(region(around: []).isEmpty)
    }
}
