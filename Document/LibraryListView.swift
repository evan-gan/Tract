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

    /// A scroll view rather than a `List`: a list row carries UIKit's own drag
    /// and drop interaction, which eats the row's `draggable`/`dropDestination`
    /// so nothing can be filed from the outline. The grid already files things
    /// correctly from a plain scrolling stack, so the outline uses the same one.
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(rows) { row in
                    content(for: row)
                        .padding(.leading, CGFloat(row.depth) * LibraryListRow.indentPerLevel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        // The outline shows nested contents, so something dragged out of an
        // expanded folder needs a way back to this level. Rows sit on top of
        // this and take their own drops first.
        //
        // Deliberately unhighlighted: it stays targeted while the drag is over a
        // row inside it, so tinting it washes the whole page blue on top of the
        // row's own highlight. The grid files things with no background tint either.
        .dropDestination(for: LibraryItemReference.self) { items, _ -> Bool in
            onDrop(items, folderID)
        }
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
                onDelete: { uiState.requestDeletion(of: .folder(folder), in: library) },
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
