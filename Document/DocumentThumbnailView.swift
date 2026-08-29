import SwiftUI

/// The preview image on a document card: the PNG written at the document's last
/// save, or a placeholder when there is none yet.
///
/// Loads its own image rather than taking one from the library model, so a shelf
/// of a hundred documents only decodes the handful of previews actually on
/// screen — `LazyVGrid` never builds the rest.
struct DocumentThumbnailView: View {
    let documentID: UUID
    /// Re-reads the preview whenever the document is saved again.
    let modifiedAt: Date
    let store: DocumentFileStore

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .task(id: modifiedAt) { await loadImage() }
    }

    private var placeholder: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "scribble")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
        }
    }

    private func loadImage() async {
        let data = await store.loadThumbnailData(id: documentID)
        // Decoding is cheap for a 400×300 PNG, but doing it off the main actor
        // keeps a fast scroll from hitching on a screenful of cards at once.
        image = await Task.detached(priority: .userInitiated) {
            data.flatMap(UIImage.init(data:))
        }.value
    }
}
