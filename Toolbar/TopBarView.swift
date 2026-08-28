import SwiftUI

/// Document chrome at the top of the screen: back and title in one glass pill,
/// with Export as its own prominent glass surface beside it.
/// Selection lives on the lasso tool in the dock, not up here.
/// Undo/redo live on the movable tool dock instead.
struct TopBarView: View {
    let glassNamespace: Namespace.ID
    let onClose: () -> Void
    let onExportTapped: () -> Void

    // Stored separately because the document title lives outside CanvasViewModel.
    @State private var documentTitle: String = "Untitled"

    var body: some View {
        HStack(spacing: 10) {
            controlPill
            ExportButton(onTapped: onExportTapped)
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

            DocumentTitleView(title: $documentTitle)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassChrome(cornerRadius: 22)
        .glassEffectID("topBar", in: glassNamespace)
    }
}
