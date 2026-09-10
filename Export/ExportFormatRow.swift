import SwiftUI

/// One pickable format inside the export sheet: what the file is, what it is
/// like, and the extension it will land under.
///
/// The whole row is the button rather than the name alone — a row that only
/// responds to a tap on its label is a row people tap twice.
struct ExportFormatRow: View {
    let format: ExportFormat
    /// The layout this row exports, used only to say so out loud for
    /// VoiceOver — the same format appears under more than one group.
    let layoutName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: format.symbolName)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    // Fixed width so names line up down the sheet whatever the
                    // glyph's own proportions are.
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(format.displayName)
                        .font(.body.weight(.medium))
                    Text(format.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                Text(".\(format.fileExtension)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Export \(layoutName) as \(format.displayName)")
    }
}
