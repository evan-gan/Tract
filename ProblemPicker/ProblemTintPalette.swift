import SwiftUI

/// Colours problems are tinted with when "tint by problem" is on.
///
/// Generated from evenly spaced hues rather than picked by hand, so the tenth
/// problem is as distinct from its neighbours as the second is, and no list has
/// to be extended when someone writes more problems than anyone expected.
enum ProblemTintPalette {
    /// A prime-ish stride around the wheel: consecutive problems land far apart
    /// instead of shading into one another.
    private static let hueStride = 0.27
    private static let startingHue = 0.02

    /// Kept dark and saturated: these replace ink on white paper, so they have
    /// to read as writing rather than as highlighter.
    static func color(forProblemIndex index: Int) -> Color {
        let hue = (startingHue + Double(index) * hueStride).truncatingRemainder(dividingBy: 1)
        return Color(hue: hue, saturation: 0.82, brightness: 0.72)
    }
}
