import SwiftUI

extension View {
    /// Applies the Liquid Glass material shared by every floating chrome surface
    /// (top bar, palette, panels, indicators). Centralising it keeps corner radii,
    /// hit-testing, and interaction behaviour identical across the app.
    ///
    /// - Parameters:
    ///   - cornerRadius: Corner radius of the glass surface.
    ///   - isInteractive: Enables the press/shimmer response. Only use it on
    ///     surfaces that are themselves a single tappable control — an
    ///     interactive surface hosting several buttons reacts to the wrong touches.
    func glassChrome(cornerRadius: CGFloat = 20, isInteractive: Bool = false) -> some View {
        let material: Glass = isInteractive ? .regular.interactive() : .regular
        return self
            .glassEffect(material, in: .rect(cornerRadius: cornerRadius))
            // Glass only hit-tests its content, so taps near the padded edges are
            // otherwise swallowed by whatever sits underneath.
            .contentShape(.rect(cornerRadius: cornerRadius))
    }
}
