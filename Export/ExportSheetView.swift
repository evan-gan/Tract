import SwiftUI

/// Format picker sheet. The user chooses SVG, PDF, or PNG then shares via the
/// system share sheet.
struct ExportSheetView: View {
    let document: SplineDocument
    @Environment(\.dismiss) private var dismiss

    private let adapters: [any ExportAdapter] = [SVGExporter(), PDFExporter(), PNGExporter()]

    @State private var exportedItem: ExportedFileItem?
    @State private var exportError: String?
    @State private var isAlertPresented = false
    @State private var isShowingShareSheet = false

    var body: some View {
        NavigationStack {
            List(adapters, id: \.fileExtension) { adapter in
                Button(adapter.displayName, action: { runExport(using: adapter) })
            }
            .navigationTitle("Export as…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel", action: dismiss.callAsFunction)
                }
            }
            .alert("Export failed", isPresented: $isAlertPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(exportError ?? "")
            }
            .sheet(isPresented: $isShowingShareSheet) {
                if let item = exportedItem {
                    ShareSheet(items: [item.url])
                }
            }
        }
    }

    private func runExport(using adapter: any ExportAdapter) {
        do {
            let data = try adapter.export(document: document, viewport: nil)
            let tempURL = FileManager.default.temporaryDirectory
                .appending(path: "\(document.title).\(adapter.fileExtension)")
            try data.write(to: tempURL)
            exportedItem = ExportedFileItem(url: tempURL)
            isShowingShareSheet = true
        } catch {
            exportError = error.localizedDescription
            isAlertPresented = true
        }
    }
}

private struct ExportedFileItem {
    let url: URL
}

/// Wraps `UIActivityViewController` for sharing a file URL.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
