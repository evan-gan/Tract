import SwiftUI

/// Small glass pill in the top-right: the current zoom level, and a home button
/// that frames the whole drawing.
///
/// Both controls share one surface rather than sitting in two pills, so the
/// chrome stays a single object in the corner. That is also why the glass is not
/// marked interactive — an interactive surface responds as one control, and this
/// one hosts two.
struct ZoomIndicatorView: View {
    let scale: CGFloat
    /// Disabled when the document has no ink: there is nothing to centre on.
    let canZoomToFit: Bool
    let onReset: () -> Void
    let onZoomToFit: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onReset) {
                Text(scale, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom \(Int(scale * 100))%. Tap to reset.")

            Divider()
                .frame(height: 18)

            Button(action: onZoomToFit) {
                Image(systemName: "house")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(!canZoomToFit)
            .accessibilityLabel("Fit drawing to screen")
            .accessibilityIdentifier("zoomToFitDrawing")
        }
        .glassChrome(cornerRadius: 18)
    }
}
