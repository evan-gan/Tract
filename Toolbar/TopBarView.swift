import SwiftUI

/// Document chrome at the top of the screen: back and title in one glass pill,
/// with the Export menu as its own prominent glass surface beside it.
/// Selection lives on the lasso tool in the dock, not up here.
/// Undo/redo live on the movable tool dock instead.
struct TopBarView: View {
    @Binding var title: String
    /// Drives the small "saving" dot. Saving is silent and automatic, so this
    /// is the only signal the user gets that their edit has been recorded.
    let isSaving: Bool
    let glassNamespace: Namespace.ID
    let onClose: () -> Void
    /// Handed to the export menu, which calls it only when a format is picked.
    let makeDocument: () -> SplineDocument

    var body: some View {
        HStack(spacing: 10) {
            controlPill
            ExportMenu(makeDocument: makeDocument)
                .glassEffectID("export", in: glassNamespace)
        }
    }

    private var controlPill: some View {
        HStack(spacing: 12) {
            Button("Documents", systemImage: "chevron.backward", action: onClose)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Divider().frame(height: 20)

            DocumentTitleView(title: $title)

            SaveIndicatorView(isSaving: isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassChrome(cornerRadius: 22)
        .glassEffectID("topBar", in: glassNamespace)
    }
}
