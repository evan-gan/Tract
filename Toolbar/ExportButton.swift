import SwiftUI

/// Accent-coloured button that triggers the export sheet.
struct ExportButton: View {
    let onTapped: () -> Void

    var body: some View {
        Button("Export", systemImage: "square.and.arrow.up", action: onTapped)
            .labelStyle(.titleAndIcon)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
    }
}
