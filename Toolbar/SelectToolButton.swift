import SwiftUI

/// Toggles selection mode on/off. Tints to the accent colour while active.
struct SelectToolButton: View {
    @Binding var isSelectionMode: Bool

    var body: some View {
        Button("Select", systemImage: "cursorarrow.rays", action: toggle)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .symbolVariant(isSelectionMode ? .fill : .none)
            .foregroundStyle(isSelectionMode ? Color.accentColor : Color.primary)
            .accessibilityLabel(isSelectionMode ? "Deactivate selection" : "Activate selection")
            .accessibilityAddTraits(isSelectionMode ? .isSelected : [])
    }

    private func toggle() {
        withAnimation(.snappy(duration: 0.2)) {
            isSelectionMode.toggle()
        }
    }
}
