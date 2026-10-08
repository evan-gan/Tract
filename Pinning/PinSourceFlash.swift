import SwiftUI

/// The pulse-then-fade shared by everything that shows where a pin's ink lives:
/// the outline on the page and the arrow on the card. One definition so the two
/// can never drift out of step.
///
/// Hidden until `trigger` changes, and hidden again once the fade ends. The
/// view stays in the hierarchy throughout — a keyframe animator only plays on a
/// *change* of its trigger, so a view inserted already carrying the new value
/// would never animate at all.
struct PinSourceFlash: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, opacity in
            view.opacity(opacity)
        } keyframes: { _ in
            KeyframeTrack {
                // In, one dip and back to catch the eye, a beat to look, then out.
                CubicKeyframe(1, duration: 0.15)
                CubicKeyframe(0.35, duration: 0.25)
                CubicKeyframe(1, duration: 0.25)
                LinearKeyframe(1, duration: 0.9)
                CubicKeyframe(0, duration: 0.7)
            }
        }
    }
}

extension View {
    func pinSourceFlash(trigger: Int) -> some View {
        modifier(PinSourceFlash(trigger: trigger))
    }
}
