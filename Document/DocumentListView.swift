import SwiftUI

/// File browser / home screen. Displays all saved documents and lets the user
/// open or create new ones.
struct DocumentListView: View {
    @State private var store = DocumentStore()
    @State private var selectedDocument: SplineDocument?
    @State private var documentToDelete: SplineDocument?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        NavigationSplitView {
            documentList
                .navigationTitle("Documents")
                .toolbar { newDocumentButton }
        } detail: {
            if let document = selectedDocument {
                CanvasContainerView()
            } else {
                ContentUnavailableView("Select a document", systemImage: "doc.text")
            }
        }
        .task { await store.loadAllDocuments() }
    }

    // MARK: - Subviews

    private var documentList: some View {
        List(store.documents, selection: $selectedDocument) { document in
            DocumentListRow(document: document)
                .tag(document)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("Delete", role: .destructive) {
                        documentToDelete = document
                        isShowingDeleteConfirmation = true
                    }
                }
        }
        .confirmationDialog(
            "Delete \"\(documentToDelete?.title ?? "")\"?",
            isPresented: $isShowingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let doc = documentToDelete {
                    Task { await store.deleteDocument(doc) }
                }
            }
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
            let doc = await store.createDocument()
            selectedDocument = doc
        }
    }
}

// MARK: - SplineDocument: Hashable for NavigationSplitView selection

extension SplineDocument: Hashable {
    static func == (lhs: SplineDocument, rhs: SplineDocument) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

#Preview {
    DocumentListView()
}
