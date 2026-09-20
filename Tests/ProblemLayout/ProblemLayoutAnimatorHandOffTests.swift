import Testing
import CoreGraphics
@testable import Tract

/// The animator's hand-off moves the open frame's progress onto the closing
/// frame and restarts the focus progress, so one run both closes and opens.
@MainActor
@Suite("Animator focus-frame hand-off")
struct ProblemLayoutAnimatorHandOffTests {

    @Test("A fully open frame hands off as a fully open closing frame, and focus restarts at 0")
    func handOffFromFullyOpen() {
        let animator = ProblemLayoutAnimator()
        animator.settle(to: .identity, focusProgress: 1)

        animator.handOffFocusFrame()

        #expect(animator.closingFrameProgress == 1)
        #expect(animator.focusProgress == 0)
    }

    @Test("A frame caught part way hands off from where it had got to")
    func handOffFromPartWay() {
        let animator = ProblemLayoutAnimator()
        animator.settle(to: .identity, focusProgress: 0.4)

        animator.handOffFocusFrame()

        #expect(animator.closingFrameProgress == 0.4)
    }

    @Test("The run after a hand-off lands with the closing frame shut and the new one open")
    func runLandsClosed() {
        let animator = ProblemLayoutAnimator()
        animator.settle(to: .identity, focusProgress: 1)
        animator.handOffFocusFrame()
        var didFinish = false

        animator.animate(to: .identity, focusProgress: 1, duration: 0) { didFinish = true }

        #expect(didFinish)
        #expect(animator.closingFrameProgress == 0)
        #expect(animator.focusProgress == 1)
    }
}
