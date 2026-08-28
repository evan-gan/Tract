import SwiftUI

/// Shared look of every selection surface — the lasso the user is tracing and
/// the outline that lands around the result. Kept in one place so the two always
/// read as the same idea rather than two similar-looking dashed shapes.
enum SelectionStyle {
    /// Brighter than any ink in the palette, so the marquee stands out against a
    /// drawing rather than blending into it.
    static let color = AppTint.active

    /// Dash on / dash off, in points. Deliberately between a dash and a dot:
    /// short enough to read as a marquee, long enough not to shimmer.
    static let dashLength: CGFloat = 4
    static let gapLength: CGFloat = 4
    static let lineWidth: CGFloat = 1.5

    /// One full dash cycle. Animating the phase by exactly this much and looping
    /// makes the march seamless — the pattern lands back on itself.
    static var dashPeriod: CGFloat { dashLength + gapLength }

    /// iPad renders roughly 132 points per physical inch (264 ppi at 2× scale).
    /// Used to keep the selection outline a real quarter inch off the drawing.
    static let pointsPerInch: CGFloat = 132
    static let standoff: CGFloat = pointsPerInch / 4

    /// Just enough rounding to take the bite off a corner, well short of a
    /// fillet that would pull the outline in against the drawing.
    static let cornerSoftening: CGFloat = 8

    static let marchDuration: Double = 0.5

    /// Fully qualified: the app has its own `StrokeStyle` for ink, which would
    /// otherwise shadow SwiftUI's line style here.
    static func outline(dashPhase: CGFloat = 0) -> SwiftUI.StrokeStyle {
        SwiftUI.StrokeStyle(
            lineWidth: lineWidth,
            lineCap: .round,
            lineJoin: .round,
            dash: [dashLength, gapLength],
            dashPhase: dashPhase
        )
    }
}
