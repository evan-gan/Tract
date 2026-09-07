import SwiftUI

/// One document in the library grid: the preview rendered at its last save, its
/// title, and when it was last edited. Draggable, so it can be filed into a
/// folder without a menu.
struct DocumentCard: View {
    let metadata: DocumentMetadata
    let store: DocumentFileStore
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                preview
                LibraryTileCaption(title: metadata.title, detail: editedDescription)
            }
        }
        .buttonStyle(.plain)
        .draggable(LibraryItemReference.document(metadata.id))
        .contextMenu {
            Button("Rename", systemImage: "pencil", action: onRename)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metadata.title), edited \(editedDescription)")
    }

    private var preview: some View {
        DocumentThumbnailView(
            documentID: metadata.id,
            modifiedAt: metadata.modifiedAt,
            store: store
        )
        .aspectRatio(LibraryTile.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .libraryTileChrome()
    }

    private var editedDescription: String {
        metadata.modifiedAt.formatted(.relative(presentation: .named))
    }
}
