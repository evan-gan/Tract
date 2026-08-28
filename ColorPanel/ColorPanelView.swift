import SwiftUI

/// Full colour panel, shown in a popover from the dock's colour wheel. It draws
/// no background of its own — the popover supplies the glass.
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
        .padding(16)
        .frame(width: 210)
    }
}
