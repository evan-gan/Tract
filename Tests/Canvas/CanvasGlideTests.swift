import CoreGraphics
import Testing
@testable import Tract

/// The eased path a canvas glide takes from one pan position to another.
@Suite("Canvas glide")
struct CanvasGlideTests {
    private let start = CGPoint(x: 0, y: 0)
    private let end = CGPoint(x: 1000, y: -400)

    @Test("A glide begins exactly where the canvas was")
    func glideStartsAtTheStart() {
        #expect(CanvasGlideAnimator.translation(from: start, to: end, elapsed: 0, duration: 1) == start)
    }

    @Test("A glide finishes exactly on its destination, and stays there after")
    func glideEndsAtTheEnd() {
        #expect(CanvasGlideAnimator.translation(from: start, to: end, elapsed: 1, duration: 1) == end)
        #expect(CanvasGlideAnimator.translation(from: start, to: end, elapsed: 5, duration: 1) == end)
    }

    @Test("Half way through the time, the glide is half way along")
    func glideIsHalfWayAtHalfTime() {
        let middle = CanvasGlideAnimator.translation(from: start, to: end, elapsed: 0.5, duration: 1)
        #expect(abs(middle.x - 500) < 0.001)
        #expect(abs(middle.y + 200) < 0.001)
    }

    @Test("A glide eases away: the first tenth of the time covers far less than a tenth of the way")
    func glideEasesOut() {
        let early = CanvasGlideAnimator.translation(from: start, to: end, elapsed: 0.1, duration: 1)
        #expect(early.x < 100)
        #expect(early.x > 0)
    }

    @Test("A zero-length glide lands immediately")
    func zeroDurationLandsAtOnce() {
        #expect(CanvasGlideAnimator.translation(from: start, to: end, elapsed: 0, duration: 0) == end)
    }
}
