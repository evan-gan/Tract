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
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .glassChrome(cornerRadius: 18, isInteractive: true)
        .accessibilityLabel("Zoom \(Int(scale * 100))%. Tap to reset.")
    }
}
