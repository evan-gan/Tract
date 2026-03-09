import SwiftUI

/// Expanding weight picker that slides out below `StrokeWeightButton`.
/// Entirely self-contained — it owns its own open/close animation state.
struct StrokeWeightFlyout: View {
    @Binding var selectedWidth: CGFloat
    @Binding var isVisible: Bool

    private static let weightOptions: [CGFloat] = [1, 2, 4, 7, 12]

    var body: some View {
        VStack(spacing: 8) {
            ForEach(Self.weightOptions, id: \.self) { width in
                weightDot(width: width)
            }
        }
        .padding(8)
        .glassCard(cornerRadius: 14)
        .transition(.scale(scale: 0.8, anchor: .top).combined(with: .opacity))
    }

    private func weightDot(width: CGFloat) -> some View {
        let isSelected = selectedWidth == width
        return Circle()
            .fill(isSelected ? Color.primary : Color.secondary.opacity(0.5))
            .frame(width: width * 2.5 + 4, height: width * 2.5 + 4)
            .overlay {
                if isSelected {
                    Circle()
                        .strokeBorder(.blue, lineWidth: 2)
                        .frame(width: width * 2.5 + 8, height: width * 2.5 + 8)
                }
            }
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
            .onTapGesture { selectWeight(width) }
            .accessibilityLabel("Stroke weight \(Int(width))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectWeight(_ width: CGFloat) {
        selectedWidth = width
        withAnimation(.spring(duration: 0.25)) {
            isVisible = false
        }
    }
}
