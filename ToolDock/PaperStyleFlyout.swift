import SwiftUI

/// Paper picker shown in a popover from the dock. It draws no background of its
/// own — the popover supplies the glass.
struct PaperStyleFlyout: View {
    let selectedStyle: CanvasBackgroundStyle
    let onSelect: (CanvasBackgroundStyle) -> Void
    let onDismiss: () -> Void

    private static let columns = [GridItem(.fixed(88)), GridItem(.fixed(88))]
    private static let swatchHeight: CGFloat = 56

    var body: some View {
        LazyVGrid(columns: Self.columns, spacing: 12) {
            ForEach(CanvasBackgroundStyle.allCases) { style in
                paperOption(style)
            }
        }
        .padding(14)
    }

    private func paperOption(_ style: CanvasBackgroundStyle) -> some View {
        let isSelected = style == selectedStyle
        return VStack(spacing: 5) {
            CanvasPaperSwatch(style: style)
                .frame(height: Self.swatchHeight)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.2),
                                      lineWidth: isSelected ? 2.5 : 0.5)
                }
            Text(style.displayName)
                .font(.caption2)
                .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .lineLimit(1)
        }
        .contentShape(.rect(cornerRadius: 8))
        .onTapGesture { select(style) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.displayName)
        .accessibilityIdentifier("paperStyleOption-\(style.rawValue)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func select(_ style: CanvasBackgroundStyle) {
        onSelect(style)
        onDismiss()
    }
}
