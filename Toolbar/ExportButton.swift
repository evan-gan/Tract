import SwiftUI

/// Prominent glass button that triggers the export sheet. It is its own glass
/// surface rather than a control inside the top bar, so it reads as the screen's
/// primary action.
struct ExportButton: View {
    let onTapped: () -> Void

    var body: some View {
        Button("Export", systemImage: "square.and.arrow.up", action: onTapped)
            .labelStyle(.titleAndIcon)
            .buttonStyle(.glassProminent)
            .controlSize(.large)
    }
}
