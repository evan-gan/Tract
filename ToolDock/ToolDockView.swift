import SwiftUI

/// The dock's contents: history, tools, weight, and ink, in one glass bar that
/// re-flows between a row and a column depending on the edge it is parked on.
/// Positioning and dragging live in `FloatingToolDock`.
struct ToolDockView: View {
    @Bindable var viewModel: CanvasViewModel
    let edge: DockEdge

    var body: some View {
        let layout = DockLayout.stack(along: edge.axis, spacing: 4)
        return layout {
            DockGrabHandle(axis: edge.axis)

            UndoRedoView(
                axis: edge.axis,
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo,
                onUndo: viewModel.undo,
                onRedo: viewModel.redo
            )

            DockDivider(axis: edge.axis)

            ToolCarouselView(
                activeTool: viewModel.activeTool,
                edge: edge,
                onSelect: selectTool
            )

            DockDivider(axis: edge.axis)

            strokeWeightButton

            DockDivider(axis: edge.axis)

            DockColorRail(
                selectedColor: viewModel.selectedInkColor,
                axis: edge.axis,
                onSelect: selectColor
            )

            inkWheelButton
        }
        .padding(edge.axis == .horizontal ? .horizontal : .vertical, 10)
        .padding(edge.axis == .horizontal ? .vertical : .horizontal, 5)
        .glassChrome(cornerRadius: 26)
    }

    // MARK: - Popover hosts

    private var strokeWeightButton: some View {
        StrokeWeightDockButton(
            isPickerOpen: viewModel.isStrokeWeightFlyoutVisible,
            onTapped: viewModel.toggleStrokeWeightFlyout
        )
        .popover(isPresented: $viewModel.isStrokeWeightFlyoutVisible) {
            StrokeWeightFlyout(
                selectedWidth: $viewModel.strokeWidth,
                onDismiss: viewModel.toggleStrokeWeightFlyout
            )
            .presentationCompactAdaptation(.popover)
        }
    }

    private var inkWheelButton: some View {
        InkWheelButton(
            isPanelOpen: viewModel.isColorPanelVisible,
            onTapped: viewModel.toggleColorPanel
        )
        .popover(isPresented: $viewModel.isColorPanelVisible) {
            ColorPanelView(viewModel: viewModel)
                .presentationCompactAdaptation(.popover)
        }
    }

    // MARK: - Actions

    private func selectTool(_ tool: ToolType) {
        withAnimation(.snappy(duration: 0.25)) {
            viewModel.selectTool(tool)
        }
    }

    private func selectColor(_ color: SIMD4<Float>) {
        withAnimation(.snappy(duration: 0.25)) {
            viewModel.selectInkColor(color)
        }
    }
}
