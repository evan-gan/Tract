import SwiftUI

/// Single row in the document list showing title and last-modified date.
struct DocumentListRow: View {
    let document: SplineDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(document.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(document.modifiedAt, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
