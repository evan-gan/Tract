import SwiftUI

/// Opacity control slider, 0–100%.
struct OpacitySlider: View {
    @Binding var opacity: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Opacity")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(opacity, format: .percent.precision(.fractionLength(0)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $opacity, in: 0...1)
        }
    }
}
