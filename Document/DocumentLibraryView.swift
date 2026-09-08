import SwiftUI

/// Home screen: a grid of folders and document cards, each document showing the
/// preview rendered at its last save.
///
/// Opening a document presents the canvas full screen rather than in a split
/// view detail column: the canvas owns all four screen edges (the tool dock
/// parks against any of them), and a split view's sidebar would both cover the
/// dock in portrait and swallow drags aimed at it.
struct DocumentLibraryView: View {
    @State private var library = DocumentLibrary()
    @State private var uiState = LibraryUIState()
    @State private var path: [LibraryRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            contents(of: nil)
                .navigationDestination(for: LibraryRoute.self) { route in
                    contents(of: route.folderID)
                }
        }
        .fullScreenCover(item: $uiState.editorSession) { session in
            CanvasContainerView(session: session, onClose: { uiState.editorSession = nil })
        }
        .task {
            #if DEBUG
            await SampleLibrarySeeder.seedIfRequested(into: library.store)
            #endif
            await library.refresh()
        }
        .modifier(LibraryDialogs(library: library, uiState: uiState))
    }

    private func contents(of folderID: UUID?) -> some View {
        LibraryFolderContentsView(
            library: library,
            uiState: uiState,
            folderID: folderID,
            path: $path
        )
    }
}

/// The library's modal prompts, lifted out so `DocumentLibraryView.body` stays
/// about layout. They live above the navigation stack so they read the same from
/// any folder the user has drilled into.
private struct LibraryDialogs: ViewModifier {
    let library: DocumentLibrary
    @Bindable var uiState: LibraryUIState

    func body(content: Content) -> some View {
        content
            .alert(
                uiState.prompt?.title ?? "",
                isPresented: isPresented($uiState.prompt),
                presenting: uiState.prompt
            ) { prompt in
                TextField("Name", text: $uiState.promptText)
                Button("Cancel", role: .cancel) {}
                Button(prompt.confirmLabel) { submit(prompt) }
            }
            .confirmationDialog(
                "Delete \"\(uiState.deletion?.name ?? "")\"?",
                isPresented: isPresented($uiState.deletion),
                titleVisibility: .visible,
                presenting: uiState.deletion
            ) { target in
                Button("Delete", role: .destructive) { confirmDelete(target) }
            } message: { target in
                Text(deletionWarning(for: target))
            }
            .alert("Something went wrong", isPresented: .constant(library.errorMessage != nil)) {
                Button("OK", role: .cancel) { library.dismissError() }
            } message: {
                Text(library.errorMessage ?? "")
            }
    }

    private func submit(_ prompt: LibraryPrompt) {
        let name = uiState.promptText
        Task {
            switch prompt {
            case .renameDocument(let metadata):
                await library.renameDocument(id: metadata.id, to: name)
            case .renameFolder(let folder):
                await library.renameFolder(id: folder.id, to: name)
            case .newFolder(let parentID):
                _ = await library.createFolder(named: name, in: parentID)
            }
        }
    }

    private func confirmDelete(_ target: LibraryDeletion) {
        Task {
            switch target {
            case .document(let metadata): await library.deleteDocument(id: metadata.id)
            case .folder(let folder): await library.deleteFolder(id: folder.id)
            }
        }
    }

    /// Deleting a folder takes everything inside it, so the count is spelled out
    /// rather than left for the user to discover afterwards. An empty folder
    /// never gets here — it is deleted without asking.
    private func deletionWarning(for target: LibraryDeletion) -> String {
        switch target {
        case .document:
            "This permanently removes the document and its drawing."
        case .folder(let folder):
            switch library.documentCount(withinTreeOf: folder.id) {
            case 0: "This permanently removes the folder and the folders inside it."
            case 1: "This permanently removes the folder and the 1 document inside it."
            case let count: "This permanently removes the folder and the \(count) documents inside it."
            }
        }
    }

    /// Bridges an optional "which thing is this dialog about" to the boolean
    /// binding SwiftUI's alert and dialog APIs want.
    private func isPresented<Value>(_ target: Binding<Value?>) -> Binding<Bool> {
        Binding(get: { target.wrappedValue != nil }, set: { if !$0 { target.wrappedValue = nil } })
    }
}

#Preview {
    DocumentLibraryView()
}
