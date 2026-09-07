import SwiftUI

/// The library as an indented outline, where folders open in place.
///
/// The point of it next to the grid is seeing a hierarchy at once: expanding two
/// folders shows both of their contents without navigating anywhere. Documents
/// still carry their preview — smaller, with the name beside it.
struct LibraryListView: View {
    let library: DocumentLibrary
    let uiState: LibraryUIState
    /// The folder whose contents this outline is rooted at; nil is the top level.
    let folderID: UUID?
    let onOpenDocument: (DocumentMetadata) -> Void
    let onOpenFolder: (DocumentFolder) -> Void
    /// Handles items dropped on a folder. Returns whether anything moved.
    let onDrop: ([LibraryItemReference], UUID?) -> Bool

    var body: some View {
        List(rows) { row in
            content(for: row)
                .padding(.leading, CGFloat(row.depth) * LibraryListRow.indentPerLevel)
                .listRowInsets(.init(top: 2, leading: 16, bottom: 2, trailing: 16))
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: uiState.expandedFolderIDs)
    }

    private var rows: [LibraryOutlineRow] {
        LibraryOutline.rows(
            tree: library.tree,
            documents: library.documents,
            in: folderID,
            expandedFolderIDs: uiState.expandedFolderIDs
        )
    }

    @ViewBuilder
    private func content(for row: LibraryOutlineRow) -> some View {
        switch row.item {
        case .folder(let folder):
            FolderListRow(
                folder: folder,
                itemCount: library.itemCount(in: folder.id),
                isExpanded: uiState.isExpanded(folder.id),
                onToggleExpansion: { uiState.toggleExpansion(of: folder.id) },
                onOpen: { onOpenFolder(folder) },
                onRename: { uiState.ask(.renameFolder(folder)) },
                onDelete: { uiState.deletion = .folder(folder) },
                onDrop: { onDrop($0, folder.id) }
            )
        case .document(let metadata):
            DocumentListRow(
                metadata: metadata,
                store: library.store,
                onOpen: { onOpenDocument(metadata) },
                onRename: { uiState.ask(.renameDocument(metadata)) },
                onDelete: { uiState.deletion = .document(metadata) }
            )
        }
    }
}
