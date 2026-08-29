import Foundation
import Observation

/// The home screen's model: the list of document cards, plus create, rename and
/// delete. It holds metadata only — strokes are loaded by `DocumentEditorSession`
/// when a document is actually opened, so the library stays cheap however much
/// ink the user has accumulated.
@Observable
@MainActor
final class DocumentLibrary {
    private(set) var documents: [DocumentMetadata] = []
    private(set) var isLoading = true
    /// Set when an operation failed in a way the user needs to know about.
    /// The view presents it and calls `dismissError()`.
    private(set) var errorMessage: String?

    let store: DocumentFileStore

    init(store: DocumentFileStore = DocumentFileStore()) {
        self.store = store
    }

    func dismissError() {
        errorMessage = nil
    }

    // MARK: - Loading

    func refresh() async {
        do {
            documents = try await store.listMetadata()
        } catch {
            errorMessage = "Could not open your documents folder: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Mutations

    /// - Returns: The new document's metadata, or nil if it could not be created
    ///   (in which case `errorMessage` explains why and nothing should be opened).
    func createDocument(title: String = "Untitled") async -> DocumentMetadata? {
        do {
            let document = try await store.createDocument(title: title)
            documents.insert(document.metadata, at: 0)
            return document.metadata
        } catch {
            errorMessage = "Could not create a new document: \(error.localizedDescription)"
            return nil
        }
    }

    /// Blank and whitespace-only titles are rejected here rather than written to
    /// disk, so a card can never end up with nothing to show.
    func renameDocument(id: UUID, to newTitle: String) async {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = trimmed.isEmpty ? "Untitled" : trimmed
        do {
            applySavedMetadata(try await store.renameDocument(id: id, to: title))
        } catch {
            errorMessage = "Could not rename that document: \(error.localizedDescription)"
        }
    }

    func deleteDocument(id: UUID) async {
        do {
            try await store.deleteDocument(id: id)
            documents.removeAll { $0.id == id }
        } catch {
            errorMessage = "Could not delete that document: \(error.localizedDescription)"
        }
    }

    /// Folds a document the editor has just saved back into the list, so the card
    /// shows the new title and edit time without re-reading the whole folder.
    func applySavedMetadata(_ metadata: DocumentMetadata) {
        if let index = documents.firstIndex(where: { $0.id == metadata.id }) {
            documents[index] = metadata
        } else {
            documents.append(metadata)
        }
        documents.sort { $0.modifiedAt > $1.modifiedAt }
    }
}
