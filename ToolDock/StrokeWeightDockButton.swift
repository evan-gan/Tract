import SwiftUI

/// Three lines of increasing thickness — the dock's entry point to the weight
/// picker. Tinting mirrors the tool buttons so an open picker is obvious.
struct StrokeWeightDockButton: View {
    let isPickerOpen: Bool
    let onTapped: () -> Void

    var body: some View {
        Button(action: onTapped) {
            VStack(spacing: 4) {
                Rectangle().frame(height: 1)
                Rectangle().frame(height: 2.5)
                Rectangle().frame(height: 4.5)
            }
            .frame(width: 20)
            .frame(width: DockLayout.itemSize, height: DockLayout.itemSize)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isPickerOpen ? Color.accentColor : Color.secondary)
        .background(isPickerOpen ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: .rect(cornerRadius: 12))
        .accessibilityLabel("Stroke weight")
    }
}
