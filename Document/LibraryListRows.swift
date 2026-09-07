import SwiftUI

/// Shared geometry for the outline's rows, so a folder row and a document row
/// line up down the page however deep they are.
enum LibraryListRow {
    /// How far each level of nesting is indented.
    static let indentPerLevel: CGFloat = 22
    /// The preview's height; its width follows the thumbnail's own aspect.
    static let previewHeight: CGFloat = 44
    static let previewWidth: CGFloat = previewHeight * LibraryTile.aspectRatio
}

/// One folder in the outline: a disclosure chevron, the folder, and what is in it.
///
/// The chevron and the row do different things on purpose — the chevron opens the
/// folder *in place*, the row navigates into it — which is the same split Finder's
/// list view uses.
struct FolderListRow: View {
    let folder: DocumentFolder
    let itemCount: Int
    let isExpanded: Bool
    let onToggleExpansion: () -> Void
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    /// Handles items dropped on this folder. Returns whether anything moved.
    let onDrop: ([LibraryItemReference]) -> Bool

    @State private var isDropTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            disclosureChevron
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    folderPreview
                    LibraryTileCaption(title: folder.name, detail: itemCountDescription)
                    Spacer(minLength: 0)
                }
                // Without a hit-testable background the row only responds on the
                // glyph and the text, not the gap between them.
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .background(isDropTargeted ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear),
                    in: .rect(cornerRadius: 10))
        .draggable(LibraryItemReference.folder(folder.id))
        .dropDestination(for: LibraryItemReference.self) { items, _ in
            onDrop(items)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu {
            Button("Rename", systemImage: "pencil", action: onRename)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .animation(.easeOut(duration: 0.15), value: isDropTargeted)
        // No identifier on this row: one set on a container is inherited by
        // everything inside it, which would wipe out the disclosure button's.
    }

    private var disclosureChevron: some View {
        Button(action: onToggleExpansion) {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: 28, height: 28)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse \(folder.name)" : "Expand \(folder.name)")
        .accessibilityIdentifier("folderDisclosure-\(folder.name)")
    }

    private var folderPreview: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: isDropTargeted ? "folder.fill.badge.plus" : "folder.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .frame(width: LibraryListRow.previewWidth, height: LibraryListRow.previewHeight)
        .clipShape(.rect(cornerRadius: 8))
    }

    private var itemCountDescription: String {
        itemCount == 1 ? "1 item" : "\(itemCount) items"
    }
}

/// One document in the outline: its saved preview, with the name beside it.
struct DocumentListRow: View {
    let metadata: DocumentMetadata
    let store: DocumentFileStore
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                preview
                LibraryTileCaption(title: metadata.title, detail: editedDescription)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        // Aligns the preview with a folder row's, whose chevron sits to its left.
        .padding(.leading, 40)
        .padding(.vertical, 4)
        .draggable(LibraryItemReference.document(metadata.id))
        .contextMenu {
            Button("Rename", systemImage: "pencil", action: onRename)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityLabel("\(metadata.title), edited \(editedDescription)")
    }

    private var preview: some View {
        DocumentThumbnailView(
            documentID: metadata.id,
            modifiedAt: metadata.modifiedAt,
            store: store
        )
        .frame(width: LibraryListRow.previewWidth, height: LibraryListRow.previewHeight)
        .clipShape(.rect(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 0.5)
        }
    }

    private var editedDescription: String {
        metadata.modifiedAt.formatted(.relative(presentation: .named))
    }
}
