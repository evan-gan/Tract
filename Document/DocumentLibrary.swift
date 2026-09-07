import Foundation
import Observation

/// The home screen's model: the folder tree and the list of document cards,
/// plus create, rename, delete and file-into-a-folder. It holds metadata only —
/// strokes are loaded by `DocumentEditorSession` when a document is actually
/// opened, so the library stays cheap however much ink the user has accumulated.
@Observable
@MainActor
final class DocumentLibrary {
    private(set) var documents: [DocumentMetadata] = []
    private(set) var folders: [DocumentFolder] = [] {
        didSet { tree = FolderTree(folders) }
    }
    /// Rebuilt whenever `folders` changes so views can ask about nesting without
    /// paying for a fresh index on every redraw.
    private(set) var tree = FolderTree()
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
            folders = try await store.loadFolders()
            documents = adoptingOrphans(try await store.listMetadata())
        } catch {
            errorMessage = "Could not open your documents folder: \(error.localizedDescription)"
        }
        isLoading = false
    }

    /// Pulls documents whose folder no longer exists back to the top level, so a
    /// damaged or partly written folder list can never make a document invisible.
    ///
    /// In memory only: the document's own file is left alone until something
    /// saves it for a real reason, so a transient read failure never rewrites
    /// the user's filing.
    private func adoptingOrphans(_ metadata: [DocumentMetadata]) -> [DocumentMetadata] {
        let known = Set(folders.map(\.id))
        return metadata.map { document in
            guard let folderID = document.folderID, !known.contains(folderID) else { return document }
            var adopted = document
            adopted.folderID = nil
            return adopted
        }
    }

    // MARK: - Reading

    /// The documents filed directly in `folderID`, newest edit first.
    func documents(in folderID: UUID?) -> [DocumentMetadata] {
        documents.filter { $0.folderID == folderID }
    }

    /// The folders directly inside `folderID`, name-sorted.
    func folders(in folderID: UUID?) -> [DocumentFolder] {
        tree.children(of: folderID)
    }

    func folder(id: UUID) -> DocumentFolder? {
        tree.folder(id: id)
    }

    /// How many things sit directly inside a folder — what its card reports.
    func itemCount(in folderID: UUID) -> Int {
        folders(in: folderID).count + documents(in: folderID).count
    }

    /// Every document that would be destroyed by deleting `folderID`, including
    /// those nested in its subfolders. The delete prompt says the number out
    /// loud, because the alternative is a drag-and-drop app quietly binning work.
    func documentCount(withinTreeOf folderID: UUID) -> Int {
        let doomed = Set([folderID] + tree.descendants(of: folderID))
        return documents.filter { $0.folderID.map(doomed.contains) ?? false }.count
    }

    // MARK: - Documents

    /// - Parameter folderID: Where to file the new document; `nil` is top level.
    /// - Returns: The new document's metadata, or nil if it could not be created
    ///   (in which case `errorMessage` explains why and nothing should be opened).
    func createDocument(title: String = "Untitled", in folderID: UUID? = nil) async -> DocumentMetadata? {
        do {
            let document = try await store.createDocument(title: title, in: folderID)
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
        do {
            applySavedMetadata(try await store.renameDocument(id: id, to: cleanedName(newTitle, fallback: "Untitled")))
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

    // MARK: - Folders

    func createFolder(named name: String, in parentID: UUID? = nil) async -> DocumentFolder? {
        let folder = DocumentFolder(name: cleanedName(name, fallback: "New Folder"), parentID: parentID)
        do {
            try await persist(folders + [folder])
            return folder
        } catch {
            errorMessage = "Could not create that folder: \(error.localizedDescription)"
            return nil
        }
    }

    func renameFolder(id: UUID, to newName: String) async {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        var updated = folders
        updated[index].name = cleanedName(newName, fallback: "New Folder")
        do {
            try await persist(updated)
        } catch {
            errorMessage = "Could not rename that folder: \(error.localizedDescription)"
        }
    }

    /// Deletes a folder along with everything nested inside it.
    ///
    /// Documents go first: if the app dies mid-delete the folders still exist and
    /// are simply emptier, which the user can see and understand. Doing it the
    /// other way round would strand documents in a folder that no longer opens.
    func deleteFolder(id: UUID) async {
        let doomedFolders = Set([id] + tree.descendants(of: id))
        let doomedDocuments = documents.filter { $0.folderID.map(doomedFolders.contains) ?? false }
        let doomedDocumentIDs = Set(doomedDocuments.map(\.id))
        do {
            for document in doomedDocuments {
                try await store.deleteDocument(id: document.id)
            }
            documents.removeAll { doomedDocumentIDs.contains($0.id) }
            try await persist(folders.filter { !doomedFolders.contains($0.id) })
        } catch {
            errorMessage = "Could not delete that folder: \(error.localizedDescription)"
        }
    }

    // MARK: - Filing

    /// Files dragged items into `folderID` (`nil` for the top level).
    ///
    /// - Returns: True if anything actually moved, which is what the drop target
    ///   reports back so an illegal drop animates home instead of vanishing.
    @discardableResult
    func move(_ items: [LibraryItemReference], into folderID: UUID?) async -> Bool {
        var movedAnything = false
        for item in items {
            if await move(item, into: folderID) { movedAnything = true }
        }
        return movedAnything
    }

    @discardableResult
    func move(_ item: LibraryItemReference, into folderID: UUID?) async -> Bool {
        switch item.kind {
        case .document: return await moveDocument(id: item.id, into: folderID)
        case .folder: return await moveFolder(id: item.id, into: folderID)
        }
    }

    private func moveDocument(id: UUID, into folderID: UUID?) async -> Bool {
        guard let current = documents.first(where: { $0.id == id }), current.folderID != folderID else { return false }
        guard folderID == nil || tree.folder(id: folderID!) != nil else { return false }
        do {
            applySavedMetadata(try await store.setFolderID(folderID, forDocument: id))
            return true
        } catch {
            errorMessage = "Could not move \"\(current.title)\": \(error.localizedDescription)"
            return false
        }
    }

    private func moveFolder(id: UUID, into newParentID: UUID?) async -> Bool {
        guard let index = folders.firstIndex(where: { $0.id == id }),
              folders[index].parentID != newParentID,
              tree.canMove(folderID: id, into: newParentID)
        else { return false }

        var updated = folders
        updated[index].parentID = newParentID
        do {
            try await persist(updated)
            return true
        } catch {
            errorMessage = "Could not move \"\(folders[index].name)\": \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Helpers

    /// Writes the tree first and only adopts it once the write succeeded, so a
    /// failed save never leaves the screen showing folders that are not on disk.
    private func persist(_ updated: [DocumentFolder]) async throws {
        try await store.saveFolders(updated)
        folders = updated
    }

    private func cleanedName(_ raw: String, fallback: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
