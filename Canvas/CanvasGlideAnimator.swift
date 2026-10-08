import CoreGraphics
import QuartzCore

/// Glides the canvas from one pan position to another over a fixed duration.
///
/// `withAnimation` around the canvas transform does nothing: the ink is painted
/// by a SwiftUI `Canvas` with animations switched off, so it would simply jump.
/// Like `ProblemLayoutAnimator`, this steps the transform once per display
/// refresh and lets the canvas redraw wherever it is handed.
@MainActor
final class CanvasGlideAnimator {
    var isGliding: Bool { displayLink != nil }

    /// Starts a glide, replacing any already running.
    ///
    /// - Parameters:
    ///   - start: The translation to leave from — where the canvas is now.
    ///   - end: The translation to land on.
    ///   - duration: Seconds the glide takes.
    ///   - apply: Writes each frame's translation to the canvas.
    ///   - onFinished: Run once the glide lands, and *not* run if it is stopped
    ///     or replaced first — a glide the user cut short did not arrive.
    func glide(
        from start: CGPoint,
        to end: CGPoint,
        duration: TimeInterval,
        apply: @escaping (CGPoint) -> Void,
        onFinished: @escaping () -> Void = {}
    ) {
        stop()
        self.start = start
        self.end = end
        self.duration = duration
        self.apply = apply
        self.onFinished = onFinished
        startTime = CACurrentMediaTime()

        let proxy = DisplayLinkProxy { [weak self] in self?.step() }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.fire))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Abandons a glide where it is — what a finger landing on the canvas
    /// mid-glide needs, or the next frame would drag the page out from under it.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        apply = nil
        onFinished = nil
    }

    /// The translation a glide has reached after `elapsed` seconds: slow away,
    /// quickest in the middle, slow to land.
    nonisolated static func translation(
        from start: CGPoint,
        to end: CGPoint,
        elapsed: TimeInterval,
        duration: TimeInterval
    ) -> CGPoint {
        let linear = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        let eased = ProblemLayoutAnimator.easeInOut(CGFloat(linear))
        return CGPoint(
            x: start.x + (end.x - start.x) * eased,
            y: start.y + (end.y - start.y) * eased
        )
    }

    // MARK: - State

    private var start: CGPoint = .zero
    private var end: CGPoint = .zero
    private var duration: TimeInterval = 0
    private var startTime: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    private var apply: ((CGPoint) -> Void)?
    private var onFinished: (() -> Void)?

    private func step() {
        let elapsed = CACurrentMediaTime() - startTime
        apply?(Self.translation(from: start, to: end, elapsed: elapsed, duration: duration))
        guard elapsed >= duration else { return }
        // Landed exactly, not on whatever the last frame's easing gave.
        apply?(end)
        let finished = onFinished
        stop()
        finished?()
    }
}
