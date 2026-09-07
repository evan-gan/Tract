import SwiftUI

/// The shared look of everything in the library grid, so a folder and a document
/// sit on the same shelf rather than looking like two different apps.
enum LibraryTile {
    /// Matches `ThumbnailRenderer.size`, so a document preview is shown at the
    /// aspect it was rendered at and never cropped. Folders adopt it too, which
    /// is what keeps the grid's rows aligned.
    static let aspectRatio: CGFloat = 4.0 / 3.0
    static let cornerRadius: CGFloat = 16
}

extension View {
    /// Crops a tile to the shelf's rounded rectangle and lifts it off the page.
    ///
    /// - Parameter isHighlighted: True while a drag is hovering over the tile;
    ///   draws the accent ring that tells the user this is where the drop lands.
    func libraryTileChrome(isHighlighted: Bool = false) -> some View {
        clipShape(.rect(cornerRadius: LibraryTile.cornerRadius))
            .overlay {
                // A hairline is what separates a white page from a white background;
                // without it the cards dissolve into the sheet in light mode.
                RoundedRectangle(cornerRadius: LibraryTile.cornerRadius)
                    .strokeBorder(isHighlighted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                                  lineWidth: isHighlighted ? 3 : 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            .animation(.easeOut(duration: 0.15), value: isHighlighted)
    }
}

/// The two lines under every tile: what it is called, and one quiet detail.
struct LibraryTileCaption: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }
}
