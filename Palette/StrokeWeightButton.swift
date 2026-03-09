import SwiftUI

/// Three horizontal lines of increasing thickness. Tap opens the weight flyout.
struct StrokeWeightButton: View {
    @Binding var strokeWidth: CGFloat
    @State private var isFlyoutVisible = false

    var body: some View {
        VStack(alignment: .center, spacing: 0) {
            weightIcon
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .onTapGesture { toggleFlyout() }
                .accessibilityLabel("Stroke weight")
                .accessibilityValue("\(Int(strokeWidth))")

            if isFlyoutVisible {
                StrokeWeightFlyout(
                    selectedWidth: $strokeWidth,
                    isVisible: $isFlyoutVisible
                )
                .padding(.top, 4)
            }
        }
    }

    private var weightIcon: some View {
        VStack(spacing: 4) {
            Rectangle().frame(height: 1)
            Rectangle().frame(height: 2.5)
            Rectangle().frame(height: 4.5)
        }
        .frame(width: 22)
        .foregroundStyle(.secondary)
    }

    private func toggleFlyout() {
        withAnimation(.spring(duration: 0.25)) {
            isFlyoutVisible.toggle()
        }
    }
}
