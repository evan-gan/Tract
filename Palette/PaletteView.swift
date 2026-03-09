import SwiftUI

/// Floating glass pill on the left edge. Stacks all palette items top-to-bottom
/// with separators between logical groups.
struct PaletteView: View {
    @Bindable var viewModel: CanvasViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(spacing: 4) {
                PenToolButton(activeTool: $viewModel.activeTool)
                PencilToolButton(activeTool: $viewModel.activeTool)
                MarkerToolButton(activeTool: $viewModel.activeTool)

                paletteDivider

                EraserToolButton(activeTool: $viewModel.activeTool)
                LassoToolButton(activeTool: $viewModel.activeTool)

                paletteDivider

                StrokeWeightButton(strokeWidth: $viewModel.strokeWidth)

                paletteDivider

                ColorSwatchButton(
                    isColorPanelVisible: $viewModel.isColorPanelVisible,
                    color: viewModel.strokeColor
                )
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 4)

            // Color panel floats to the right of the palette when open.
            if viewModel.isColorPanelVisible {
                ColorPanelView(viewModel: viewModel)
                    .padding(.leading, 8)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .glassCard(cornerRadius: 20)
        .animation(.spring(duration: 0.3), value: viewModel.isColorPanelVisible)
    }

    private var paletteDivider: some View {
        Divider()
            .frame(width: 24)
            .padding(.vertical, 2)
    }
}
