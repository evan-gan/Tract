import SwiftUI

/// File browser / home screen. Displays all saved documents and lets the user
/// open or create new ones.
///
/// Opening a document presents the canvas full screen rather than in a split
/// view detail column: the canvas owns all four screen edges (the tool dock
/// parks against any of them), and a split view's sidebar would both cover the
/// dock in portrait and swallow drags aimed at it.
struct DocumentListView: View {
    @State private var store = DocumentStore()
    @State private var openDocument: SplineDocument?
    @State private var documentToDelete: SplineDocument?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            documentList
                .navigationTitle("Documents")
                .toolbar { newDocumentButton }
        }
        .fullScreenCover(item: $openDocument) { _ in
            CanvasContainerView(onClose: { openDocument = nil })
        }
        .task { await store.loadAllDocuments() }
    }

    // MARK: - Subviews

    private var documentList: some View {
        List(store.documents) { document in
            Button {
                openDocument = document
            } label: {
                DocumentListRow(document: document)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Delete", role: .destructive) {
                    documentToDelete = document
                    isShowingDeleteConfirmation = true
                }
            }
        }
        .overlay {
            if store.documents.isEmpty {
                ContentUnavailableView("No documents", systemImage: "doc.text",
                                       description: Text("Tap + to start drawing."))
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
            openDocument = await store.createDocument()
        }
    }
}

#Preview {
    DocumentListView()
}
