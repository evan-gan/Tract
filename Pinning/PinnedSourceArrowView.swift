import SwiftUI

/// The arrow a pin shows on its edge when the ink it was lifted from is off
/// screen, pointing the way to pan.
struct PinnedSourceArrowView: View {
    /// Radians, 0 pointing right and increasing clockwise. Nil means no arrow is
    /// wanted — the view still has to be present for the flash to replay.
    let angle: CGFloat?
    let trigger: Int

    static let size: CGFloat = 28
    /// About as long as the double-tap pan, so the arrow is gone just as the ink
    /// it pointed at slides into view — it reads as "found", not as cut off.
    private static let dismissal = Animation.easeOut(duration: 0.45)

    /// The last direction shown, kept so an arrow that stops being wanted — its
    /// ink has come into view — fades out where it was instead of vanishing
    /// mid-flash.
    @State private var lastAngle: CGFloat?

    var body: some View {
        ZStack {
            if let shownAngle = angle ?? lastAngle {
                // A shafted arrow rather than a bare triangle: the tail is what
                // makes the direction read at a glance on a 28pt badge.
                Image(systemName: "arrow.right")
                    .font(.system(size: Self.size * 0.5, weight: .bold))
                    .foregroundStyle(AppTint.active)
                    .rotationEffect(.radians(shownAngle))
                    .frame(width: Self.size, height: Self.size)
                    .background(.regularMaterial, in: .circle)
            }
        }
        .opacity(angle == nil ? 0 : 1)
        .animation(Self.dismissal, value: angle == nil)
        .pinSourceFlash(trigger: trigger)
        .onChange(of: angle, initial: true) { _, newAngle in
            if let newAngle { lastAngle = newAngle }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
