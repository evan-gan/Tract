import SwiftUI

/// Floating color panel to the right of the palette. Assembles preset grid,
/// custom color row, and opacity slider.
struct ColorPanelView: View {
    @Bindable var viewModel: CanvasViewModel
    @State private var activePresetIndex: Int? = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ink color")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ColorPresetGrid(
                selectedColor: $viewModel.strokeColor,
                activePresetIndex: $activePresetIndex
            )

            Divider()

            CustomColorRow(
                selectedColor: $viewModel.strokeColor,
                activePresetIndex: $activePresetIndex
            )

            Divider()

            OpacitySlider(opacity: $viewModel.strokeOpacity)
        }
        .padding(14)
        .frame(width: 196)
        .glassCard(cornerRadius: 16)
    }
}
