import SwiftUI

/// Floating glass pill anchored at the top of the screen.
/// Assembles the toolbar components left-to-right with separators between groups.
struct TopBarView: View {
    @Bindable var viewModel: CanvasViewModel
    let onExportTapped: () -> Void

    // Stored separately because the document title lives outside CanvasViewModel.
    @State private var documentTitle: String = "Untitled"

    var body: some View {
        HStack(spacing: 12) {
            DocumentTitleView(title: $documentTitle)

            Divider().frame(height: 20)

            UndoRedoView(
                canUndo: viewModel.canUndo,
                canRedo: viewModel.canRedo,
                onUndo: viewModel.undo,
                onRedo: viewModel.redo
            )

            Divider().frame(height: 20)

            SelectToolButton(isSelectionMode: $viewModel.isSelectionMode)

            Divider().frame(height: 20)

            ExportButton(onTapped: onExportTapped)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 20)
    }
}
