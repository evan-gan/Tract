import SwiftUI

/// Filled circle showing the active ink color. Tap opens the color panel.
struct ColorSwatchButton: View {
    @Binding var isColorPanelVisible: Bool
    let color: SIMD4<Float>

    var body: some View {
        Button(action: togglePanel) {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .frame(width: 40, height: 40)
        .accessibilityLabel("Ink color — \(color.swiftUIColor.hexString). Tap to open color panel.")
    }

    private func togglePanel() {
        withAnimation(.spring(duration: 0.3)) {
            isColorPanelVisible.toggle()
        }
    }
}
