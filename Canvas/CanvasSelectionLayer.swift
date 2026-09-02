import SwiftUI

/// Lasso loop, selection outline and the selection's action menu.
///
/// All three track canvas content rather than the screen, so they stay outside
/// the glass container and never take a glass material. Kept in their own view
/// so a loop being traced repaints only this layer.
struct CanvasSelectionLayer: View {
    let viewModel: CanvasViewModel

    var body: some View {
        ZStack {
            if !viewModel.lassoPath.isEmpty {
                LassoPathView(
                    canvasPoints: viewModel.lassoPath,
                    transform: viewModel.canvasTransform
                )
            }
            if viewModel.hasSelection {
                SelectionOutlineView(
                    selectedStrokes: viewModel.selectedStrokes,
                    transform: viewModel.canvasTransform,
                    standoff: viewModel.selectionStandoff,
                    dragOffset: viewModel.selectionDragOffset
                )
            }
            if let menuAnchor = viewModel.selectionMenuAnchor {
                SelectionActionMenuView(
                    anchor: menuAnchor + viewModel.selectionDragOffset,
                    transform: viewModel.canvasTransform,
                    actions: selectionActions
                )
            }
        }
    }

    /// What the selection's floating menu offers. Held here rather than in the
    /// menu so the menu stays a presentation of whatever actions it is handed.
    private var selectionActions: [SelectionAction] {
        [
            SelectionAction(
                title: "Delete",
                systemImage: "trash",
                isDestructive: true,
                perform: viewModel.deleteSelection
            )
        ]
    }
}
