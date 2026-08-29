import SwiftUI

/// Home screen: a grid of document cards, each showing the preview rendered at
/// that document's last save.
///
/// Opening a document presents the canvas full screen rather than in a split
/// view detail column: the canvas owns all four screen edges (the tool dock
/// parks against any of them), and a split view's sidebar would both cover the
/// dock in portrait and swallow drags aimed at it.
struct DocumentLibraryView: View {
    @State private var library = DocumentLibrary()
    @State private var editorSession: DocumentEditorSession?
    @State private var renameTarget: DocumentMetadata?
    @State private var pendingTitle = ""
    @State private var deleteTarget: DocumentMetadata?

    /// Wide enough that a preview reads at a glance, narrow enough for four
    /// columns on an 11-inch iPad in landscape.
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 24)]

    var body: some View {
        NavigationStack {
            documentGrid
                .navigationTitle("Documents")
                .toolbar { newDocumentButton }
        }
        .fullScreenCover(item: $editorSession) { session in
            CanvasContainerView(session: session, onClose: { editorSession = nil })
        }
        .task {
            #if DEBUG
            await SampleLibrarySeeder.seedIfRequested(into: library.store)
            #endif
            await library.refresh()
        }
        .modifier(LibraryDialogs(
            library: library,
            renameTarget: $renameTarget,
            pendingTitle: $pendingTitle,
            deleteTarget: $deleteTarget
        ))
    }

    // MARK: - Subviews

    @ViewBuilder
    private var documentGrid: some View {
        if library.documents.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 28) {
                    ForEach(library.documents) { metadata in
                        DocumentCard(
                            metadata: metadata,
                            store: library.store,
                            onOpen: { open(metadata) },
                            onRename: { beginRename(of: metadata) },
                            onDelete: { deleteTarget = metadata }
                        )
                    }
                }
                .padding(24)
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if library.isLoading {
            ProgressView()
        } else {
            ContentUnavailableView("No documents", systemImage: "doc.text",
                                   description: Text("Tap + to start drawing."))
        }
    }

    @ToolbarContentBuilder
    private var newDocumentButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("New document", systemImage: "plus", action: createDocument)
        }
    }

    // MARK: - Actions

    private func createDocument() {
        Task {
            guard let metadata = await library.createDocument() else { return }
            open(metadata)
        }
    }

    private func open(_ metadata: DocumentMetadata) {
        editorSession = DocumentEditorSession(
            metadata: metadata,
            store: library.store,
            // Folding each save back into the list is what keeps a card's date and
            // preview correct without re-reading the whole library on dismissal.
            onSaved: { library.applySavedMetadata($0) }
        )
    }

    private func beginRename(of metadata: DocumentMetadata) {
        pendingTitle = metadata.title
        renameTarget = metadata
    }
}

/// The library's three modal prompts, lifted out so `DocumentLibraryView.body`
/// stays about layout.
private struct LibraryDialogs: ViewModifier {
    let library: DocumentLibrary
    @Binding var renameTarget: DocumentMetadata?
    @Binding var pendingTitle: String
    @Binding var deleteTarget: DocumentMetadata?

    func body(content: Content) -> some View {
        content
            .alert("Rename document", isPresented: isPresented($renameTarget)) {
                TextField("Name", text: $pendingTitle)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    guard let target = renameTarget else { return }
                    Task { await library.renameDocument(id: target.id, to: pendingTitle) }
                }
            }
            .confirmationDialog(
                "Delete \"\(deleteTarget?.title ?? "")\"?",
                isPresented: isPresented($deleteTarget),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    guard let target = deleteTarget else { return }
                    Task { await library.deleteDocument(id: target.id) }
                }
            } message: {
                Text("This permanently removes the document and its drawing.")
            }
            .alert("Something went wrong", isPresented: .constant(library.errorMessage != nil)) {
                Button("OK", role: .cancel) { library.dismissError() }
            } message: {
                Text(library.errorMessage ?? "")
            }
    }

    /// Bridges an optional "which document is this dialog about" to the boolean
    /// binding SwiftUI's alert and dialog APIs want.
    private func isPresented<Value>(_ target: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })
    }
}

#Preview {
    DocumentLibraryView()
}
