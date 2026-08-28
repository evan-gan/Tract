import SwiftUI

/// Named ink colours shared by the tool dock and the canvas defaults.
/// Stored as `SIMD4<Float>` to match `StrokeStyle.color` with no conversion.
enum InkColor {
    static let white = SIMD4<Float>(1, 1, 1, 1)
    static let black = SIMD4<Float>(0.05, 0.05, 0.05, 1)
    static let red = SIMD4<Float>(0.85, 0.15, 0.15, 1)
    static let yellow = SIMD4<Float>(0.95, 0.75, 0.1, 1)
    static let green = SIMD4<Float>(0.1, 0.7, 0.25, 1)
    static let blue = SIMD4<Float>(0.05, 0.45, 0.95, 1)

    /// The quick palette shown inline on the tool dock. Anything beyond these
    /// comes from the full colour panel behind the colour-wheel button.
    static let dockPalette: [SIMD4<Float>] = [white, black, blue, green, yellow, red]
}
