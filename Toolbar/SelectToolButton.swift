import SwiftUI

/// Toggles selection mode on/off. Shows as active (filled) when selection is on.
struct SelectToolButton: View {
    @Binding var isSelectionMode: Bool

    var body: some View {
        Button("Select", systemImage: "cursorarrow.rays", action: toggle)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(isSelectionMode ? .blue : .primary)
            .accessibilityLabel(isSelectionMode ? "Deactivate selection" : "Activate selection")
    }

    private func toggle() {
        isSelectionMode.toggle()
    }
}
