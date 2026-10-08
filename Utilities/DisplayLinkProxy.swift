import QuartzCore

/// A plain object for `CADisplayLink` to hold a selector on, so the animators
/// driving it do not have to be `NSObject`s.
/// Main-actor isolated in full rather than hopping inside `fire()`: the link is
/// added to the main run loop, so it only ever calls back on the main thread,
/// and saying so is what lets the callback touch the animator at all.
@MainActor
final class DisplayLinkProxy: NSObject {
    private let onFire: () -> Void

    init(onFire: @escaping () -> Void) {
        self.onFire = onFire
    }

    @objc func fire() {
        onFire()
    }
}
