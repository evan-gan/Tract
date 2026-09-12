import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// The placement is the only thing the rest of the app sees of the layout, so
/// what matters here is that it composes, that it blends, and that an untagged
/// or unknown problem is never shifted by accident.
@Suite("Problem layout placement")
struct ProblemLayoutPlacementTests {

    private let problem = UUID()
    private let other = UUID()

    @Test("Nothing is shifted by the identity placement")
    func identityShiftsNothing() {
        #expect(ProblemLayoutPlacement.identity.offset(forNode: problem) == .zero)
        #expect(ProblemLayoutPlacement.identity.isIdentity)
    }

    @Test("Untagged ink is never shifted")
    func untaggedInkIsNotShifted() {
        let placement = ProblemLayoutPlacement(offsetsByNodeID: [problem: CGPoint(x: 9, y: 9)])
        #expect(placement.offset(forNode: nil) == .zero)
    }

    @Test("A problem the layout has never heard of is not shifted")
    func unknownProblemIsNotShifted() {
        let placement = ProblemLayoutPlacement(offsetsByNodeID: [problem: CGPoint(x: 9, y: 9)])
        #expect(placement.offset(forNode: other) == .zero)
    }

    @Test("The focus push is added on top of the grid's own placement")
    func pushesAddToTheGrid() {
        let grid = ProblemLayoutPlacement(offsetsByNodeID: [problem: CGPoint(x: 10, y: 20)])
        let combined = grid.adding([problem: CGPoint(x: 5, y: -5)])

        #expect(combined.offset(forNode: problem) == CGPoint(x: 15, y: 15))
    }

    @Test("A push on a problem the grid did not place still lands")
    func pushesReachUnplacedProblems() {
        let combined = ProblemLayoutPlacement.identity.adding([problem: CGPoint(x: 5, y: 5)])
        #expect(combined.offset(forNode: problem) == CGPoint(x: 5, y: 5))
    }

    @Test("Blending half way lands half way")
    func interpolationIsLinear() {
        let start = ProblemLayoutPlacement(offsetsByNodeID: [problem: CGPoint(x: 0, y: 0)])
        let end = ProblemLayoutPlacement(offsetsByNodeID: [problem: CGPoint(x: 100, y: 40)])
        let middle = ProblemLayoutPlacement.interpolating(from: start, to: end, progress: 0.5)

        #expect(middle.offset(forNode: problem) == CGPoint(x: 50, y: 20))
    }

    @Test("A problem only in the destination slides in from where it is stored")
    func newProblemsAnimateFromZero() {
        let end = ProblemLayoutPlacement(offsetsByNodeID: [problem: CGPoint(x: 100, y: 0)])
        let quarter = ProblemLayoutPlacement.interpolating(from: .identity, to: end, progress: 0.25)

        #expect(quarter.offset(forNode: problem) == CGPoint(x: 25, y: 0))
    }

    @Test("Unwinding the layout carries every problem back to where it is stored")
    func interpolatingToIdentityReturnsHome() {
        let start = ProblemLayoutPlacement(offsetsByNodeID: [problem: CGPoint(x: 100, y: 40)])
        let landed = ProblemLayoutPlacement.interpolating(from: start, to: .identity, progress: 1)

        #expect(landed.offset(forNode: problem) == .zero)
    }

    @Test("Progress outside 0...1 is clamped rather than overshooting")
    func progressIsClamped() {
        let end = ProblemLayoutPlacement(offsetsByNodeID: [problem: CGPoint(x: 100, y: 0)])

        #expect(
            ProblemLayoutPlacement
                .interpolating(from: .identity, to: end, progress: 4)
                .offset(forNode: problem) == CGPoint(x: 100, y: 0)
        )
        #expect(
            ProblemLayoutPlacement
                .interpolating(from: .identity, to: end, progress: -4)
                .offset(forNode: problem) == .zero
        )
    }

    @Test("The easing starts and ends where it should")
    func easingIsAnchoredAtBothEnds() {
        #expect(ProblemLayoutAnimator.easeInOut(0) == 0)
        #expect(ProblemLayoutAnimator.easeInOut(1) == 1)
        #expect(abs(ProblemLayoutAnimator.easeInOut(0.5) - 0.5) < 0.001)
    }

    @Test("The easing is slower at the ends than in the middle")
    func easingIsSlowAtTheEnds() {
        let firstTenth = ProblemLayoutAnimator.easeInOut(0.1)
        let middleTenth = ProblemLayoutAnimator.easeInOut(0.55)
            - ProblemLayoutAnimator.easeInOut(0.45)

        #expect(firstTenth < middleTenth)
    }
}
