import SwiftUI

extension View {
    /// Applies the Liquid Glass material shared by every floating chrome surface
    /// (top bar, palette, panels, indicators). Centralising it keeps corner radii,
    /// hit-testing, interaction behaviour, and colour scheme identical across the app.
    ///
    /// - Parameters:
    ///   - cornerRadius: Corner radius of the glass surface.
    ///   - isInteractive: Enables the press/shimmer response. Only use it on
    ///     surfaces that are themselves a single tappable control — an
    ///     interactive surface hosting several buttons reacts to the wrong touches.
    func glassChrome(cornerRadius: CGFloat = 20, isInteractive: Bool = false) -> some View {
        modifier(GlassChrome(cornerRadius: cornerRadius, isInteractive: isInteractive))
    }
}

/// Liquid Glass takes its appearance from whatever sits behind it, and behind this
/// app's chrome is a canvas that stays white in every colour scheme. Left alone the
/// glass reads that white backdrop as a light one, tints itself light, and — the
/// part that actually breaks — flips its *content* to the light scheme too, so every
/// label and icon comes out black even in dark mode.
///
/// Re-stamping `colorScheme` on the content is not enough to fix that — the glass
/// sets its content's appearance below wherever that lands, so semantic colours keep
/// resolving light. What does hold is giving the chrome **literal** label colours,
/// which no appearance derivation can reinterpret. Every chrome surface therefore
/// gets its primary and secondary levels set here, and the views inside are expected
/// to ask for `.primary` / `.secondary` *hierarchically* so they inherit them —
/// never as `Color.primary` / `Color.secondary`, which resolve by scheme instead.
private struct GlassChrome: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    let cornerRadius: CGFloat
    let isInteractive: Bool

    /// Deep enough to carry white labels over white paper, sheer enough that the
    /// surface still reads as glass rather than a solid slab. Light mode needs no
    /// counterpart: there the paper already matches the scheme, so untinted glass
    /// is both correct and the more honest material.
    private static let darkTint = Color(white: 0.09).opacity(0.82)

    func body(content: Content) -> some View {
        content
            .foregroundStyle(primaryLabel, secondaryLabel)
            // Does not fix the labels — that is what the literal styles above are
            // for — but system-drawn parts (dividers, the title's caret) do follow it.
            .environment(\.colorScheme, colorScheme)
            .glassEffect(glass, in: .rect(cornerRadius: cornerRadius))
            // Glass only hit-tests its content, so taps near the padded edges are
            // otherwise swallowed by whatever sits underneath.
            .contentShape(.rect(cornerRadius: cornerRadius))
    }

    private var primaryLabel: Color {
        colorScheme == .dark ? .white : .black
    }

    private var secondaryLabel: Color {
        colorScheme == .dark ? Color(white: 1).opacity(0.62) : Color(white: 0).opacity(0.55)
    }

    private var glass: Glass {
        let base: Glass = isInteractive ? .regular.interactive() : .regular
        return colorScheme == .dark ? base.tint(Self.darkTint) : base
    }
}
