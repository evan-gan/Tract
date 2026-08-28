import SwiftUI

/// Weight picker shown in a popover from the dock. It draws no background of
/// its own — the popover supplies the glass.
struct StrokeWeightFlyout: View {
    @Binding var selectedWidth: CGFloat
    let onDismiss: () -> Void

    private static let weightOptions: [CGFloat] = [1, 2, 4, 7, 12]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(Self.weightOptions, id: \.self) { width in
                weightDot(width: width)
            }
        }
        .padding(10)
    }

    private func weightDot(width: CGFloat) -> some View {
        let isSelected = selectedWidth == width
        return Circle()
            .fill(isSelected ? Color.accentColor : Color.secondary)
            .frame(width: width * 2.5 + 4, height: width * 2.5 + 4)
            .frame(width: 40, height: 40)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear, in: .circle)
            .contentShape(.circle)
            .onTapGesture { selectWeight(width) }
            .accessibilityLabel("Stroke weight \(Int(width))")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectWeight(_ width: CGFloat) {
        selectedWidth = width
        onDismiss()
    }
}
