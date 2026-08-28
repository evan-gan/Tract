import SwiftUI

/// Preview of where the pencil is about to draw, shown while it hovers above the
/// glass. Drawn at the size the mark itself will be, so it doubles as a read-out
/// of the current weight at the current zoom.
struct PencilHoverDotView: View {
    /// Screen-space position of the hovering nib.
    let location: CGPoint
    /// Screen-space diameter of the mark this stroke weight would leave.
    let diameter: CGFloat
    let color: Color

    /// A hairline weight zoomed out is sub-pixel; below this the dot would vanish
    /// exactly when the user most needs to know where the nib is pointing.
    private static let minimumDiameter: CGFloat = 4
    private static let ringWidth: CGFloat = 1

    private var drawnDiameter: CGFloat {
        max(diameter, Self.minimumDiameter)
    }

    var body: some View {
        Circle()
            .fill(color.opacity(0.35))
            // The ring keeps the dot legible over ink of its own colour, which a
            // translucent fill on its own would disappear into.
            .overlay {
                Circle().strokeBorder(color.opacity(0.9), lineWidth: Self.ringWidth)
            }
            .frame(width: drawnDiameter, height: drawnDiameter)
            .position(location)
            .allowsHitTesting(false)
            // The dot must sit exactly under the nib; an animated catch-up would
            // read as lag in the pencil itself.
            .transaction { $0.animation = nil }
    }
}
