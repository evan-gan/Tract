import SwiftUI

/// The Export control: a prominent tinted button that expands *in place* into
/// its format options, then shares the chosen file.
///
/// Deliberately not a `Menu`. A menu floats a separate panel over the canvas,
/// which is one more surface on a screen whose whole design is a few pieces of
/// glass over paper. Here the button itself widens and its label gives way to the
/// formats, so nothing new appears on top of the drawing.
///
/// It is a filled capsule rather than its own glass, because it now sits *on*
/// the top bar's glass — and glass cannot sample glass, so a second surface
/// stacked on the first reads as a smear rather than a button.
///
/// It owns the whole flow — pick, write, share — rather than reporting a tap
/// upwards, so the canvas does not have to carry share-sheet and error state it
/// has no other use for.
struct ExportMenu: View {
    /// Snapshots the document at the moment a format is chosen, not on every
    /// canvas redraw. The document carries every stroke, so taking it as a value
    /// would copy the whole drawing on each frame while the user is drawing.
    let makeDocument: () -> SplineDocument

    private let adapters: [any ExportAdapter] = [SVGExporter(), PDFExporter(), PNGExporter()]

    /// Both presentations are driven by an optional value rather than by a
    /// separate boolean. A boolean flipped in the same update as the value it
    /// depends on lets SwiftUI present before the value lands, which showed an
    /// empty sheet with nothing in it on the first export of a session.
    @State private var isExpanded = false
    @State private var exportedItem: ExportedFileItem?
    @State private var exportFailure: ExportFailure?

    var body: some View {
        HStack(spacing: 2) {
            if isExpanded {
                ForEach(adapters, id: \.fileExtension) { adapter in
                    formatButton(for: adapter)
                }
            } else {
                collapsedButton
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .foregroundStyle(.white)
        .background(Capsule().fill(Color.accentColor))
        // The surface itself grows; the labels inside cross-fade. Without the
        // transition the three formats pop in at full width before the glass has
        // finished widening, which reads as a flicker rather than an expansion.
        .animation(.snappy(duration: 0.3), value: isExpanded)
        .sheet(item: $exportedItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(
            "Export failed",
            isPresented: isPresentingFailure,
            presenting: exportFailure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    private var collapsedButton: some View {
        Button {
            isExpanded = true
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
                .labelStyle(.titleAndIcon)
                .fontWeight(.medium)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .transition(.opacity)
    }

    private func formatButton(for adapter: any ExportAdapter) -> some View {
        Button {
            isExpanded = false
            runExport(using: adapter)
        } label: {
            Text(adapter.displayName)
                .fontWeight(.medium)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .contentShape(.capsule)
        .transition(.opacity)
        .accessibilityLabel("Export as \(adapter.displayName)")
    }

    /// The alert reads its message from `presenting:` rather than from state of
    /// its own, so the failure text can never lag a beat behind the flag.
    private var isPresentingFailure: Binding<Bool> {
        Binding(
            get: { exportFailure != nil },
            set: { isPresented in if !isPresented { exportFailure = nil } }
        )
    }

    private func runExport(using adapter: any ExportAdapter) {
        let document = makeDocument()
        do {
            let data = try adapter.export(document: document, viewport: nil)
            let fileName = ExportFileNaming.fileName(
                title: document.title,
                fileExtension: adapter.fileExtension
            )
            let temporaryURL = FileManager.default.temporaryDirectory.appending(path: fileName)
            try data.write(to: temporaryURL)
            exportedItem = ExportedFileItem(url: temporaryURL)
        } catch {
            exportFailure = ExportFailure(message: error.localizedDescription)
        }
    }
}

private struct ExportedFileItem: Identifiable {
    let url: URL
    var id: URL { url }
}

private struct ExportFailure: Identifiable {
    let message: String
    var id: String { message }
}

/// Wraps `UIActivityViewController` for sharing a file URL.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
