import SwiftUI

/// The dock's entry point to the paper picker: a swatch of the paper currently
/// under the ink. Tinting mirrors the tool buttons so an open picker is obvious.
struct PaperStyleDockButton: View {
    let style: CanvasBackgroundStyle
    let isPickerOpen: Bool
    let onTapped: () -> Void

    private static let swatchSize: CGFloat = 22

    var body: some View {
        Button(action: onTapped) {
            CanvasPaperSwatch(style: style, cornerRadius: 5)
                .frame(width: Self.swatchSize, height: Self.swatchSize)
                // The pale papers would vanish into the dock's glass without an
                // edge to sit inside.
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(Color.primary.opacity(0.25), lineWidth: 0.5)
                }
                .frame(width: DockLayout.itemSize, height: DockLayout.itemSize)
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .background(isPickerOpen ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: .rect(cornerRadius: 12))
        .accessibilityLabel("Paper style")
        .accessibilityValue(style.displayName)
        .accessibilityIdentifier("paperStyleButton")
    }
}
