import Testing
import CoreGraphics
@testable import Tract

/// The selection frame is a dilation of the ink, so these tests check the two
/// things that follow from that: it holds its standoff, and ink far enough apart
/// comes back framed separately.
@Suite("Selection region")
struct SelectionRegionTests {

    private let standoff: CGFloat = 30

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

    private func bounds(of contour: [CGPoint]) -> CGRect {
        contour.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    private func horizontalLine(atY y: CGFloat, fromX startX: CGFloat, toX endX: CGFloat) -> [CGPoint] {
        [CGPoint(x: startX, y: y), CGPoint(x: endX, y: y)]
    }

    @Test("A single stroke is framed by exactly one outline")
    func singleStrokeGivesOneContour() {
        let contours = SelectionRegion.contours(
            around: [horizontalLine(atY: 100, fromX: 0, toX: 200)],
            radius: standoff
        )
        #expect(contours.count == 1)
    }

    @Test("The outline stands off the ink by the requested distance")
    func holdsTheStandoffDistance() throws {
        let line = horizontalLine(atY: 100, fromX: 0, toX: 200)
        let contours = SelectionRegion.contours(around: [line], radius: standoff)
        let contour = try #require(contours.first)

        // Sampling grid resolution is the radius over a handful of cells, so the
        // traced boundary lands within a cell of the true offset.
        let tolerance = standoff / 4
        for probe in [CGPoint(x: 50, y: 100), CGPoint(x: 150, y: 100)] {
            #expect(abs(distance(from: probe, toEdgesOf: contour) - standoff) < tolerance)
        }
    }

    @Test("A long diagonal holds its standoff along the whole length")
    func holdsTheStandoffAlongADiagonal() throws {
        // The field is seeded in a band around the ink and swept outwards from
        // there, so a stroke far longer than one grid cell is the case where a
        // gap in that band would show up as the outline pinching in or out.
        let diagonal = [CGPoint(x: 0, y: 0), CGPoint(x: 400, y: 400)]
        let contours = SelectionRegion.contours(around: [diagonal], radius: standoff)
        let contour = try #require(contours.first)

        let tolerance = standoff / 4
        for step in stride(from: CGFloat(50), through: 350, by: 50) {
            let probe = CGPoint(x: step, y: step)
            #expect(abs(distance(from: probe, toEdgesOf: contour) - standoff) < tolerance)
        }
    }

    @Test("Every sample outside the frame is further from the ink than every sample inside")
    func theFrameSeparatesInsideFromOutside() throws {
        let line = horizontalLine(atY: 100, fromX: 0, toX: 200)
        let contour = try #require(SelectionRegion.contours(around: [line], radius: standoff).first)
        let tolerance = standoff / 4

        // Well inside and well outside the standoff, in both axes, so a sweep
        // that lost track of the nearest ink anywhere would show up here.
        #expect(StrokeGeometry.polygon(contour, contains: CGPoint(x: 100, y: 100)))
        #expect(StrokeGeometry.polygon(contour, contains: CGPoint(x: -standoff + tolerance, y: 100)))
        #expect(StrokeGeometry.polygon(contour, contains: CGPoint(x: 100, y: 100 + standoff - tolerance)))
        #expect(StrokeGeometry.polygon(contour, contains: CGPoint(x: 100, y: 100 + standoff + tolerance)) == false)
        #expect(StrokeGeometry.polygon(contour, contains: CGPoint(x: 200 + standoff + tolerance, y: 100)) == false)
    }

    @Test("Two lines further apart than twice the standoff get an outline each")
    func farApartInkIsFramedSeparately() {
        let contours = SelectionRegion.contours(
            around: [
                horizontalLine(atY: 0, fromX: 0, toX: 200),
                horizontalLine(atY: standoff * 3, fromX: 0, toX: 200),
            ],
            radius: standoff
        )
        #expect(contours.count == 2)
    }

    @Test("Two lines closer than twice the standoff share one outline")
    func nearbyInkIsFramedTogether() {
        let contours = SelectionRegion.contours(
            around: [
                horizontalLine(atY: 0, fromX: 0, toX: 200),
                horizontalLine(atY: standoff, fromX: 0, toX: 200),
            ],
            radius: standoff
        )
        #expect(contours.count == 1)
    }

    @Test("The outline follows a concave shape instead of boxing it in")
    func hugsAConcaveShape() throws {
        // A wide, flat "V". A hull-based frame would span the notch; a dilation
        // dips into it, so the point midway between the arms stays outside.
        let arms = [
            [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 300)],
            [CGPoint(x: 200, y: 300), CGPoint(x: 400, y: 0)],
        ]
        let contours = SelectionRegion.contours(around: arms, radius: standoff)
        let contour = try #require(contours.first)
        // Well inside the notch and far from either arm.
        let insideTheNotch = CGPoint(x: 200, y: 60)
        #expect(StrokeGeometry.polygon(contour, contains: insideTheNotch) == false)
    }

    @Test("A dot is framed by a ring at the standoff radius")
    func framesADot() throws {
        let contours = SelectionRegion.contours(around: [[CGPoint(x: 0, y: 0)]], radius: standoff)
        let contour = try #require(contours.first)
        let extent = bounds(of: contour)
        // A circle of the standoff radius, within the grid's resolution.
        #expect(abs(extent.width - standoff * 2) < standoff / 3)
        #expect(abs(extent.height - standoff * 2) < standoff / 3)
    }

    /// A closed square of ink, which dilates into a frame with a hole in it.
    private func squareLoop(side: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: 0, y: 0), CGPoint(x: side, y: 0),
            CGPoint(x: side, y: side), CGPoint(x: 0, y: side),
            CGPoint(x: 0, y: 0),
        ]
    }

    @Test("A pocket barely wider than the standoff is dropped as a blip")
    func dropsEnclosedBlips() {
        // The square's middle clears the ink by 45 — just past the standoff — so
        // it leaves a speck of a hole that is litter rather than a shape.
        let contours = SelectionRegion.contours(around: [squareLoop(side: 90)], radius: standoff)
        #expect(contours.count == 1)
    }

    @Test("A hole big enough to be deliberate is kept")
    func keepsGenuineHoles() {
        let contours = SelectionRegion.contours(around: [squareLoop(side: 400)], radius: standoff)
        #expect(contours.count == 2)
    }

    @Test("A small piece of ink standing on its own keeps its outline")
    func keepsSmallFreestandingRegions() {
        // Same speck-sized region, but nothing encloses it, so it is a separate
        // object the split rule is meant to show — not a blip.
        let contours = SelectionRegion.contours(
            around: [
                horizontalLine(atY: 0, fromX: 0, toX: 200),
                [CGPoint(x: 100, y: standoff * 4)],
            ],
            radius: standoff
        )
        #expect(contours.count == 2)
    }

    @Test("Nothing selected produces no outline")
    func emptySelectionHasNoContours() {
        #expect(SelectionRegion.contours(around: [], radius: standoff).isEmpty)
    }
}
