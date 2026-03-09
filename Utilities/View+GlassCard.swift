import SwiftUI

extension View {
    /// Applies the shared frosted-glass chrome style used by the toolbar,
    /// palette, and all floating panels. Centralising this ensures every chrome
    /// element looks identical and dark-mode is a single-token change.
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}
