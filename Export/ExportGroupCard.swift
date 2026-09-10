import SwiftUI

/// A titled group in the export sheet: a heading, a line on what it is, and its
/// rows on one rounded card.
///
/// Hand-built rather than a `List` section because the sheet sizes itself to its
/// contents — a list is a scroll view, which has no height of its own to give,
/// so the sheet came up scrolling with everything cut off at the bottom.
struct ExportGroupCard<Content: View>: View {
    let title: String
    let symbolName: String
    /// One line under the title on what lands in the file. Nil leaves it off.
    var summary: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbolName)
                .font(.headline)
                .foregroundStyle(.primary)

            if let summary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }
}

/// The hairline between two rows on a card, inset past the row's icon so it
/// starts under the text the way a grouped list's separator does.
struct ExportRowDivider: View {
    var body: some View {
        Divider().padding(.leading, 58)
    }
}
