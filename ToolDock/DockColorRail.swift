import SwiftUI

/// Quick ink colours on the dock. The active colour is marked with a ring in
/// that same colour — no other swatch carries one, so the selection reads
/// instantly without adding a competing highlight colour to the bar.
///
/// `selectedColor` is nil whenever the active tool lays down no ink, which
/// leaves every swatch unringed.
struct DockColorRail: View {
    let selectedColor: SIMD4<Float>?
    let axis: Axis
    let onSelect: (SIMD4<Float>) -> Void

    private static let swatchDiameter: CGFloat = 24
    private static let ringDiameter: CGFloat = 34

    var body: some View {
        let layout = DockLayout.stack(along: axis, spacing: 0)
        return layout {
            ForEach(InkColor.dockPalette, id: \.self) { color in
                swatch(color)
            }
        }
    }

    private func swatch(_ color: SIMD4<Float>) -> some View {
        let isSelected = selectedColor == color
        return Button { onSelect(color) } label: {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
                .overlay { hairline(inset: 0) }
                .overlay { selectionRing(color).opacity(isSelected ? 1 : 0) }
                .frame(width: DockLayout.itemSize, height: DockLayout.itemSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ink colour \(color.swiftUIColor.hexString)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectionRing(_ color: SIMD4<Float>) -> some View {
        ZStack {
            // The outline keeps a white or pale ring visible against the glass.
            hairline(inset: 0)
                .frame(width: Self.ringDiameter + 2, height: Self.ringDiameter + 2)
            Circle()
                .strokeBorder(color.swiftUIColor, lineWidth: 2)
                .frame(width: Self.ringDiameter, height: Self.ringDiameter)
        }
    }

    private func hairline(inset: CGFloat) -> some View {
        Circle()
            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
            .padding(inset)
    }
}

/// Opens the full colour panel. Shows the current ink over a colour wheel so it
/// reads as "everything else" next to the fixed swatches.
struct InkWheelButton: View {
    let isPanelOpen: Bool
    let onTapped: () -> Void

    var body: some View {
        Button(action: onTapped) {
            Circle()
                .fill(AngularGradient(colors: Self.wheelColors, center: .center))
                .frame(width: 26, height: 26)
                .overlay {
                    Circle().strokeBorder(
                        isPanelOpen ? Color.accentColor : Color.primary.opacity(0.15),
                        lineWidth: isPanelOpen ? 2 : 0.5
                    )
                }
                .frame(width: DockLayout.itemSize, height: DockLayout.itemSize)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More colours")
        .accessibilityAddTraits(isPanelOpen ? .isSelected : [])
    }

    private static let wheelColors: [Color] = [
        .red, .yellow, .green, .cyan, .blue, .purple, .red,
    ]
}
