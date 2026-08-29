import SwiftUI

/// One document in the library grid: the preview rendered at its last save, its
/// title, and when it was last edited.
struct DocumentCard: View {
    let metadata: DocumentMetadata
    let store: DocumentFileStore
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void

    /// Matches `ThumbnailRenderer.size`, so the preview is shown at the aspect
    /// it was rendered at and never cropped.
    private static let previewAspectRatio: CGFloat = 4.0 / 3.0

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                preview
                caption
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename", systemImage: "pencil", action: onRename)
            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metadata.title), edited \(metadata.modifiedAt.formatted(.relative(presentation: .named)))")
    }

    private var preview: some View {
        DocumentThumbnailView(
            documentID: metadata.id,
            modifiedAt: metadata.modifiedAt,
            store: store
        )
        .aspectRatio(Self.previewAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            // A hairline is what separates a white page from a white background;
            // without it the cards dissolve into the sheet in light mode.
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metadata.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(metadata.modifiedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}
