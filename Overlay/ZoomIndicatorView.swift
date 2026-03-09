import SwiftUI

/// Small glass pill showing the current zoom level. Tap to reset to 100%.
struct ZoomIndicatorView: View {
    let scale: CGFloat
    let onReset: () -> Void

    var body: some View {
        Button(action: onReset) {
            Text(scale, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .glassCard(cornerRadius: 10)
        .accessibilityLabel("Zoom \(Int(scale * 100))%. Tap to reset.")
    }
}
