import CoreGraphics
import Foundation
import Testing
@testable import Tract

/// Sizing and placing a pinned reference: how big it starts, how far it can be
/// scaled and pushed, and how its ink is fitted inside it.
@Suite("Pinned reference geometry")
struct PinnedReferenceGeometryTests {
    private let landscape = CGSize(width: 1200, height: 800)

    // MARK: - Starting size

    @Test("Wide ink starts a quarter of the screen's width across")
    func wideInkStartsAtAQuarterOfTheWidth() {
        let longestSide = PinnedReferenceGeometry.initialLongestSide(
            inkSize: CGSize(width: 400, height: 100),
            viewport: landscape
        )
        #expect(longestSide == 300)
    }

    @Test("Tall ink starts a quarter of the screen's height tall")
    func tallInkStartsAtAQuarterOfTheHeight() {
        let longestSide = PinnedReferenceGeometry.initialLongestSide(
            inkSize: CGSize(width: 100, height: 400),
            viewport: landscape
        )
        #expect(longestSide == 200)
    }

    @Test("A pin made before the screen is measured still gets a usable size")
    func unmeasuredViewportFallsBackToTheMinimum() {
        let longestSide = PinnedReferenceGeometry.initialLongestSide(
            inkSize: CGSize(width: 400, height: 100),
            viewport: .zero
        )
        #expect(longestSide == PinnedReferenceGeometry.minimumLongestSide)
    }

    // MARK: - Scaling limits

    @Test("A pin cannot be pinched smaller than the minimum")
    func longestSideHasAFloor() {
        #expect(PinnedReferenceGeometry.clampedLongestSide(10, viewport: landscape)
                == PinnedReferenceGeometry.minimumLongestSide)
    }

    @Test("A pin cannot grow past most of the screen's shorter side")
    func longestSideHasACeiling() {
        #expect(PinnedReferenceGeometry.clampedLongestSide(5000, viewport: landscape) == 720)
    }

    // MARK: - Card shape

    @Test("The card keeps the ink's aspect ratio")
    func cardKeepsTheInksAspect() {
        let size = PinnedReferenceGeometry.cardSize(inkSize: CGSize(width: 300, height: 200), longestSide: 150)
        #expect(size == CGSize(width: 150, height: 100))
    }

    @Test("A single line of ink still gets a card tall enough to grab")
    func flatInkGetsAMinimumShortSide() {
        let size = PinnedReferenceGeometry.cardSize(inkSize: CGSize(width: 400, height: 4), longestSide: 200)
        #expect(size == CGSize(width: 200, height: PinnedReferenceGeometry.minimumShortSide))
    }

    // MARK: - Placement

    @Test("A pin pushed past the trailing and top edges stops flush against them")
    func centerIsClampedAgainstTrailingAndTopEdges() {
        let cardSize = CGSize(width: 200, height: 100)
        let clamped = PinnedReferenceGeometry.clampedCenter(
            CGPoint(x: 5000, y: -5000),
            cardSize: cardSize,
            viewport: landscape
        )
        #expect(clamped.x + cardSize.width / 2 == landscape.width)
        #expect(clamped.y - cardSize.height / 2 == 0)
    }

    @Test("A pin pushed past the leading and bottom edges stops flush against them")
    func centerIsClampedAgainstLeadingAndBottomEdges() {
        let cardSize = CGSize(width: 200, height: 100)
        let clamped = PinnedReferenceGeometry.clampedCenter(
            CGPoint(x: -5000, y: 5000),
            cardSize: cardSize,
            viewport: landscape
        )
        #expect(clamped.x - cardSize.width / 2 == 0)
        #expect(clamped.y + cardSize.height / 2 == landscape.height)
    }

    @Test("A pin barely over an edge is pulled fully back on screen")
    func slightlyOffScreenPinIsPulledIn() {
        let cardSize = CGSize(width: 200, height: 100)
        let clamped = PinnedReferenceGeometry.clampedCenter(
            CGPoint(x: 90, y: 400),
            cardSize: cardSize,
            viewport: landscape
        )
        #expect(clamped == CGPoint(x: 100, y: 400))
    }

    @Test("A card wider than a shrunken screen keeps its leading edge on screen")
    func oversizedCardHugsTheLeadingEdge() {
        let cardSize = CGSize(width: 900, height: 100)
        let clamped = PinnedReferenceGeometry.clampedCenter(
            CGPoint(x: 600, y: 400),
            cardSize: cardSize,
            viewport: CGSize(width: 800, height: 1000)
        )
        #expect(clamped.x - cardSize.width / 2 == 0)
    }

    @Test("A pin already on screen is left where it is")
    func onScreenCenterIsUntouched() {
        let center = CGPoint(x: 600, y: 400)
        #expect(PinnedReferenceGeometry.clampedCenter(
            center, cardSize: CGSize(width: 200, height: 100), viewport: landscape
        ) == center)
    }

    @Test("Successive pins are stepped so none lands exactly on another")
    func pinsCascade() {
        let cardSize = CGSize(width: 200, height: 100)
        let first = PinnedReferenceGeometry.initialCenter(cardSize: cardSize, viewport: landscape, existingPinCount: 0)
        let second = PinnedReferenceGeometry.initialCenter(cardSize: cardSize, viewport: landscape, existingPinCount: 1)
        #expect(first != second)
        #expect(first.x + cardSize.width / 2 <= landscape.width)
    }

    @Test("The first pin lands in the top-leading corner, under the top bar")
    func firstPinLandsTopLeading() {
        let cardSize = CGSize(width: 200, height: 100)
        let center = PinnedReferenceGeometry.initialCenter(cardSize: cardSize, viewport: landscape, existingPinCount: 0)
        #expect(center.x - cardSize.width / 2 == PinnedReferenceGeometry.initialEdgeMargin)
        #expect(center.y - cardSize.height / 2 == PinnedReferenceGeometry.initialTopInset)
    }

    @Test("Later pins step right and down from the first, away from the leading edge")
    func laterPinsCascadeInward() {
        let cardSize = CGSize(width: 200, height: 100)
        let first = PinnedReferenceGeometry.initialCenter(cardSize: cardSize, viewport: landscape, existingPinCount: 0)
        let second = PinnedReferenceGeometry.initialCenter(cardSize: cardSize, viewport: landscape, existingPinCount: 1)
        #expect(second.x == first.x + PinnedReferenceGeometry.cascadeStep)
        #expect(second.y == first.y + PinnedReferenceGeometry.cascadeStep)
    }


    // MARK: - Source outline

    private let outlinePadding = ProblemBoundsStyle.padding
    private let outlineCurveRadius = ProblemBoundsStyle.curveRadius

    private func twoLinesOfWriting(problemNodeID: UUID? = nil) -> [Stroke] {
        [
            StrokeFixtures.stroke(through: [CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0)], problemNodeID: problemNodeID),
            StrokeFixtures.stroke(through: [CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50)], problemNodeID: problemNodeID),
        ]
    }

    @Test("The source outline is exactly the shape the page frames a problem with")
    func sourceOutlineMatchesTheProblemFrame() {
        let strokes = twoLinesOfWriting()
        let outlines = PinnedReferenceGeometry.sourceOutlines(
            of: strokes, padding: outlinePadding, curveRadius: outlineCurveRadius
        )
        let problemFrame = ProblemRegion.contours(
            around: strokes.map { $0.points.map(\.position) },
            padding: outlinePadding,
            curveRadius: outlineCurveRadius
        )
        #expect(outlines.count == 1)
        #expect(outlines.first?.contours == problemFrame)
    }

    @Test("The source outline stands clear of the ink it frames")
    func sourceOutlineEnclosesTheInk() throws {
        let outlines = PinnedReferenceGeometry.sourceOutlines(
            of: twoLinesOfWriting(), padding: outlinePadding, curveRadius: outlineCurveRadius
        )
        let outline = try #require(outlines.first)
        let bounds = try #require(PinnedReferenceGeometry.laidOutBounds(of: outline, placement: .identity))
        #expect(bounds.contains(CGRect(x: 0, y: 0, width: 200, height: 50)))
    }

    @Test("Source ink over two problems gets an outline each, so the arrangement can move them apart")
    func sourceAcrossProblemsGetsAnOutlineEach() {
        let firstProblem = UUID()
        let secondProblem = UUID()
        let strokes = twoLinesOfWriting(problemNodeID: firstProblem) + twoLinesOfWriting(problemNodeID: secondProblem)
        let outlines = PinnedReferenceGeometry.sourceOutlines(
            of: strokes, padding: outlinePadding, curveRadius: outlineCurveRadius
        )
        #expect(Set(outlines.map(\.problemNodeID)) == [firstProblem, secondProblem])
    }

    @Test("An outline's laid-out bounds follow the arrangement, not where the ink is stored")
    func laidOutBoundsFollowTheArrangement() throws {
        let problemID = UUID()
        let outline = PinSourceOutline(
            problemNodeID: problemID,
            contours: [[CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 40)]]
        )
        let placement = ProblemLayoutPlacement(offsetsByNodeID: [problemID: CGPoint(x: 500, y: 300)])
        let bounds = try #require(PinnedReferenceGeometry.laidOutBounds(of: outline, placement: placement))
        #expect(bounds == CGRect(x: 500, y: 300, width: 100, height: 40))
    }

    @Test("A pin whose source ink is all erased has nothing to frame")
    func noSourceInkHasNoOutlines() {
        #expect(PinnedReferenceGeometry.sourceOutlines(
            of: [], padding: outlinePadding, curveRadius: outlineCurveRadius
        ).isEmpty)
    }

    // MARK: - Arrival flight

    @Test("Drawn ink bounds include the arrangement's shift and the nib")
    func laidOutInkBoundsFollowTheArrangement() {
        let problemID = UUID()
        let stroke = StrokeFixtures.stroke(
            through: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)],
            lineWidth: 2,
            problemNodeID: problemID
        )
        let placement = ProblemLayoutPlacement(offsetsByNodeID: [problemID: CGPoint(x: 500, y: 300)])
        let bounds = PinnedReferenceGeometry.laidOutInkBounds(of: [stroke], placement: placement)
        #expect(bounds == CGRect(x: 499, y: 299, width: 102, height: 2))
    }

    @Test("Drawn ink bounds span ink the arrangement has moved apart")
    func laidOutInkBoundsSpanEveryProblem() {
        let movedProblem = UUID()
        let strokes = [
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 0)], lineWidth: 2),
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 0)], lineWidth: 2, problemNodeID: movedProblem),
        ]
        let placement = ProblemLayoutPlacement(offsetsByNodeID: [movedProblem: CGPoint(x: 1000, y: 0)])
        let bounds = PinnedReferenceGeometry.laidOutInkBounds(of: strokes, placement: placement)
        #expect(bounds.minX == -1)
        #expect(bounds.maxX == 1011)
    }

    @Test("The fit scale is how much the card magnifies its ink")
    func inkFitScaleMatchesTheCardsMagnification() {
        // 200×100 ink in a 220×120 card leaves exactly 200×100 inside the inset.
        let scale = PinnedReferenceGeometry.inkFitScale(
            inkBounds: CGRect(x: 500, y: 700, width: 200, height: 100),
            cardSize: CGSize(width: 220, height: 120)
        )
        #expect(abs(scale - 1) < 0.001)
        let doubled = PinnedReferenceGeometry.inkFitScale(
            inkBounds: CGRect(x: 0, y: 0, width: 100, height: 50),
            cardSize: CGSize(width: 220, height: 120)
        )
        #expect(abs(doubled - 2) < 0.001)
    }

    // MARK: - Off-screen arrow

    @Test("Ink straight to the left puts the arrow on the leading edge, pointing left")
    func arrowSitsOnTheEdgeFacingTheInk() throws {
        let placement = try #require(PinnedReferenceGeometry.sourceArrowPlacement(
            cardCenter: CGPoint(x: 400, y: 300),
            cardSize: CGSize(width: 200, height: 100),
            toward: CGPoint(x: -1000, y: 300),
            inset: 20
        ))
        #expect(placement.center == CGPoint(x: 320, y: 300))
        #expect(abs(placement.angle - .pi) < 0.001)
    }

    @Test("Ink far below leaves through the bottom edge, pointing down")
    func arrowLeavesThroughTheBottom() throws {
        let placement = try #require(PinnedReferenceGeometry.sourceArrowPlacement(
            cardCenter: CGPoint(x: 400, y: 300),
            cardSize: CGSize(width: 200, height: 100),
            toward: CGPoint(x: 400, y: 5000),
            inset: 20
        ))
        #expect(placement.center == CGPoint(x: 400, y: 330))
        #expect(abs(placement.angle - .pi / 2) < 0.001)
    }

    @Test("A diagonal stays inside the card, on whichever edge the line reaches first")
    func diagonalArrowStaysInside() throws {
        let cardCenter = CGPoint(x: 400, y: 300)
        let placement = try #require(PinnedReferenceGeometry.sourceArrowPlacement(
            cardCenter: cardCenter,
            cardSize: CGSize(width: 200, height: 100),
            toward: CGPoint(x: 1400, y: 1300),
            inset: 20
        ))
        // A 45° line reaches the top/bottom inset (30pt) before the side one (80pt).
        #expect(placement.center == CGPoint(x: 430, y: 330))
    }

    @Test("With no direction to point, there is no arrow")
    func targetAtCentreHasNoArrow() {
        #expect(PinnedReferenceGeometry.sourceArrowPlacement(
            cardCenter: CGPoint(x: 400, y: 300),
            cardSize: CGSize(width: 200, height: 100),
            toward: CGPoint(x: 400, y: 300),
            inset: 20
        ) == nil)
    }

    // MARK: - Pinch resize

    @Test("Pinching keeps the point between the fingers still, like the canvas zoom")
    func pinchScalesAboutItsAnchor() {
        let inkSize = CGSize(width: 200, height: 100)
        let center = CGPoint(x: 400, y: 300)
        // A quarter in from the leading edge, three quarters down: (350, 325).
        let anchor = CGPoint(x: 0.25, y: 0.75)
        let resized = PinnedReferenceGeometry.resizedAboutAnchor(
            center: center,
            longestSide: 200,
            inkSize: inkSize,
            magnification: 1.5,
            anchor: anchor,
            viewport: landscape
        )
        let resizedSize = PinnedReferenceGeometry.cardSize(inkSize: inkSize, longestSide: resized.longestSide)
        let anchorAfter = CGPoint(
            x: resized.center.x - resizedSize.width / 2 + anchor.x * resizedSize.width,
            y: resized.center.y - resizedSize.height / 2 + anchor.y * resizedSize.height
        )

        #expect(resized.longestSide == 300)
        #expect(abs(anchorAfter.x - 350) < 0.001)
        #expect(abs(anchorAfter.y - 325) < 0.001)
    }

    @Test("A pinch at the card's centre scales it in place")
    func centredPinchKeepsTheCentre() {
        let resized = PinnedReferenceGeometry.resizedAboutAnchor(
            center: CGPoint(x: 400, y: 300),
            longestSide: 200,
            inkSize: CGSize(width: 200, height: 100),
            magnification: 0.75,
            anchor: CGPoint(x: 0.5, y: 0.5),
            viewport: landscape
        )
        #expect(resized.center == CGPoint(x: 400, y: 300))
        #expect(resized.longestSide == 150)
    }

    @Test("A pinch past the size limit stops at the limit, still anchored")
    func pinchRespectsTheCeiling() {
        let resized = PinnedReferenceGeometry.resizedAboutAnchor(
            center: CGPoint(x: 400, y: 300),
            longestSide: 200,
            inkSize: CGSize(width: 200, height: 200),
            magnification: 50,
            anchor: .zero,
            viewport: landscape
        )
        #expect(resized.longestSide == 720)
        // Anchored at the top-leading corner, which therefore stays at (300, 200).
        #expect(resized.center == CGPoint(x: 300 + 360, y: 200 + 360))
    }

    // MARK: - Corner resize

    @Test("Dragging the corner handle keeps the opposite corner still")
    func cornerResizeAnchorsTopLeading() {
        let inkSize = CGSize(width: 200, height: 100)
        let center = CGPoint(x: 400, y: 300)
        let resized = PinnedReferenceGeometry.resizedFromCorner(
            center: center,
            longestSide: 200,
            inkSize: inkSize,
            dragTranslation: CGSize(width: 100, height: 50),
            viewport: landscape
        )
        let resizedSize = PinnedReferenceGeometry.cardSize(inkSize: inkSize, longestSide: resized.longestSide)

        #expect(resized.longestSide == 300)
        #expect(resized.center.x - resizedSize.width / 2 == 300)
        #expect(resized.center.y - resizedSize.height / 2 == 250)
    }

    @Test("Dragging the corner handle inward shrinks the card")
    func cornerResizeShrinks() {
        let resized = PinnedReferenceGeometry.resizedFromCorner(
            center: CGPoint(x: 400, y: 300),
            longestSide: 300,
            inkSize: CGSize(width: 300, height: 300),
            dragTranslation: CGSize(width: -100, height: -100),
            viewport: landscape
        )
        #expect(abs(resized.longestSide - 200) < 0.001)
    }

    // MARK: - Ink fit

    @Test("The ink is scaled to fill the card inside its inset, and centred")
    func inkFillsTheInsetCard() {
        let inkBounds = CGRect(x: 500, y: 700, width: 200, height: 100)
        let cardSize = CGSize(width: 220, height: 120)
        let transform = PinnedReferenceGeometry.inkTransform(inkBounds: inkBounds, cardSize: cardSize)

        let inset = PinnedReferenceGeometry.inkInset
        let topLeading = CGPoint(x: inkBounds.minX, y: inkBounds.minY).applying(transform)
        let bottomTrailing = CGPoint(x: inkBounds.maxX, y: inkBounds.maxY).applying(transform)
        #expect(abs(topLeading.x - inset) < 0.001)
        #expect(abs(topLeading.y - inset) < 0.001)
        #expect(abs(bottomTrailing.x - (cardSize.width - inset)) < 0.001)
        #expect(abs(bottomTrailing.y - (cardSize.height - inset)) < 0.001)
    }
}
