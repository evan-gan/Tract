import SwiftUI

/// One folder in the library grid: a tile you can open, drag, and drop other
/// things onto.
///
/// It knows nothing about the library model — the drop is handed straight back
/// to the caller, which is the only part of the app that can say whether a
/// particular move is legal.
struct FolderCard: View {
    let folder: DocumentFolder
    /// How many things sit directly inside, shown under the name.
    let itemCount: Int
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    /// Handles items dropped on this folder. Returns whether anything moved.
    let onDrop: ([LibraryItemReference]) -> Bool

    @State private var isDropTargeted = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                glyph
                LibraryTileCaption(title: folder.name, detail: itemCountDescription)
            }
        }
        .buttonStyle(.plain)
        .draggable(LibraryItemReference.folder(folder.id))
        .dropDestination(for: LibraryItemReference.self) { items, _ in
            onDrop(items)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            Button("Rename", systemImage: "pencil", action: onRename)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Folder \(folder.name), \(itemCountDescription)")
        .accessibilityIdentifier("folderCard-\(folder.name)")
    }

    private var glyph: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: isDropTargeted ? "folder.fill.badge.plus" : "folder.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
        }
        .aspectRatio(LibraryTile.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .libraryTileChrome(isHighlighted: isDropTargeted)
    }

    private var itemCountDescription: String {
        itemCount == 1 ? "1 item" : "\(itemCount) items"
    }
}
