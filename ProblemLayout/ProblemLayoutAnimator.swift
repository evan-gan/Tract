import QuartzCore
import Observation

/// Drives the layout from one arrangement to the next over a fixed duration.
///
/// The ink is painted by a SwiftUI `Canvas` with animations switched off — it
/// has to be, or every pencil sample would animate into place — so a
/// `withAnimation` around the placement would do nothing at all. The transition
/// is therefore driven here, one step per display refresh, and the canvas simply
/// redraws at whatever placement it is handed.
///
/// A display link rather than a timer: this is painting on every frame, and it
/// should be painting on the frames the screen is actually about to show.
@Observable
@MainActor
final class ProblemLayoutAnimator {

    /// Where every problem sits right now. What the renderer and every hit test
    /// read.
    private(set) var placement: ProblemLayoutPlacement = .identity

    /// How far the focus frame has opened out: 0 is the problem's own bubble, 1
    /// is the dashed box. Animated alongside the placement so the boundary
    /// finishes travelling exactly as the other problems finish moving.
    private(set) var focusProgress: CGFloat = 0

    /// How open the frame focus was just *taken from* still is, when focus
    /// jumps straight from one problem to another. Only ever eases towards 0:
    /// a frame handed off never reopens, so every run closes it the rest of the
    /// way, and it costs nothing once it has landed there.
    private(set) var closingFrameProgress: CGFloat = 0

    var isAnimating: Bool { displayLink != nil }

    /// Where every problem is *heading*. The same as `placement` at rest.
    ///
    /// Ink laid down mid-transition has to be stored against this rather than
    /// against the live placement: a sample stored against a position the
    /// animation is about to leave would be permanently out by however far the
    /// run had left to travel. Stored against the destination, the mark trails
    /// the nib for the rest of the transition and then lands exactly right.
    var targetPlacement: ProblemLayoutPlacement { isAnimating ? target : placement }

    // MARK: - Driving

    /// Snaps straight to an arrangement, with no transition.
    ///
    /// This is the path taken while a focused problem is being written in: the
    /// box grows by a stroke's width at a time, and easing each of those over
    /// three quarters of a second would leave the layout permanently lagging
    /// behind the pen.
    func settle(to placement: ProblemLayoutPlacement, focusProgress: CGFloat) {
        if isAnimating {
            // Mid-transition, a live measurement is new information about the
            // *destination*, not a reason to restart. Retargeting keeps the
            // elapsed time and lets the run finish where it now should.
            target = placement
            targetFocusProgress = focusProgress
            return
        }
        self.placement = placement
        self.focusProgress = focusProgress
        closingFrameProgress = 0
    }

    /// Passes the open frame's progress over to the closing one and starts the
    /// focus progress again from nothing, so the next `animate` closes the old
    /// frame while the new one opens — both on the same run, and so the same
    /// display link, rather than one frame snapping shut as the other appears.
    ///
    /// Takes the progress as it stands, so a switch made mid-transition closes
    /// the old frame from wherever it had actually got to.
    func handOffFocusFrame() {
        closingFrameProgress = focusProgress
        focusProgress = 0
    }

    /// Eases from wherever the layout is now to a new arrangement.
    ///
    /// Starting from the *current* placement rather than from the previous
    /// target is what makes an interrupted transition reverse smoothly — leaving
    /// a focus half way into it picks up the shapes as they actually are.
    /// - Parameter onFinished: Run once the transition lands, and *not* run if
    ///   another transition replaces this one first — which is what lets a
    ///   caller tear down chrome only when it has finished animating away.
    func animate(
        to placement: ProblemLayoutPlacement,
        focusProgress: CGFloat,
        duration: TimeInterval,
        onFinished: (@MainActor () -> Void)? = nil
    ) {
        // The run being replaced never landed, so its completion must not fire.
        self.onFinished = onFinished
        guard duration > 0 else {
            stop()
            settle(to: placement, focusProgress: focusProgress)
            self.onFinished = nil
            onFinished?()
            return
        }
        origin = self.placement
        originFocusProgress = self.focusProgress
        originClosingFrameProgress = closingFrameProgress
        target = placement
        targetFocusProgress = focusProgress
        startTime = CACurrentMediaTime()
        self.duration = duration
        start()
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
    }

    // MARK: - State

    @ObservationIgnored private var origin: ProblemLayoutPlacement = .identity
    @ObservationIgnored private var target: ProblemLayoutPlacement = .identity
    @ObservationIgnored private var originFocusProgress: CGFloat = 0
    @ObservationIgnored private var targetFocusProgress: CGFloat = 0
    @ObservationIgnored private var originClosingFrameProgress: CGFloat = 0
    @ObservationIgnored private var startTime: CFTimeInterval = 0
    @ObservationIgnored private var duration: TimeInterval = 0
    @ObservationIgnored private var displayLink: CADisplayLink?
    @ObservationIgnored private var onFinished: (@MainActor () -> Void)?

    private func start() {
        guard displayLink == nil else { return }
        let proxy = DisplayLinkProxy { [weak self] in self?.step() }
        let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.fire))
        // Retained by the run loop through the link, and released with it — the
        // proxy exists only so a `CADisplayLink` target need not be this class.
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func step() {
        let elapsed = CACurrentMediaTime() - startTime
        let linear = duration > 0 ? min(max(elapsed / duration, 0), 1) : 1
        let eased = Self.easeInOut(CGFloat(linear))

        placement = .interpolating(from: origin, to: target, progress: eased)
        focusProgress = originFocusProgress
            + (targetFocusProgress - originFocusProgress) * eased
        // Skipped when there is no handed-off frame, so an ordinary transition
        // does not publish an unchanged value to observers every frame.
        if originClosingFrameProgress > 0 {
            closingFrameProgress = originClosingFrameProgress * (1 - eased)
        }

        guard linear >= 1 else { return }
        stop()
        // Landed exactly, rather than on whatever the last frame's easing gave —
        // a placement a fraction short of its target would leave the page
        // permanently a hair out of line.
        placement = target
        focusProgress = targetFocusProgress
        if closingFrameProgress != 0 { closingFrameProgress = 0 }
        let finished = onFinished
        onFinished = nil
        finished?()
    }

    /// Slow at both ends, quickest in the middle — the standard cubic. Written
    /// out rather than taken from SwiftUI because this runs outside the
    /// animation system entirely.
    ///
    /// `nonisolated` because it is arithmetic on a number: it touches nothing on
    /// the animator, and the class's own isolation would otherwise keep it off
    /// limits to a test.
    nonisolated static func easeInOut(_ progress: CGFloat) -> CGFloat {
        let clamped = min(max(progress, 0), 1)
        if clamped < 0.5 { return 4 * clamped * clamped * clamped }
        let remaining = -2 * clamped + 2
        return 1 - (remaining * remaining * remaining) / 2
    }
}

/// A plain object for `CADisplayLink` to hold a selector on, so the animator
/// itself does not have to be an `NSObject`.
/// Main-actor isolated in full rather than hopping inside `fire()`: the link is
/// added to the main run loop, so it only ever calls back on the main thread,
/// and saying so is what lets the callback touch the animator at all.
@MainActor
private final class DisplayLinkProxy: NSObject {
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
    }

    @objc func fire() {
        onFire()
    }
}
