import Foundation
import Observation

/// A prompt asking the user for one name.
///
/// Renaming a document, renaming a folder and creating a folder are the same
/// interaction with different words, so they share one alert rather than three
/// nearly identical ones.
enum LibraryPrompt: Identifiable, Hashable {
    case renameDocument(DocumentMetadata)
    case renameFolder(DocumentFolder)
    case newFolder(parentID: UUID?)

    var id: String {
        switch self {
        case .renameDocument(let metadata): "rename-document-\(metadata.id)"
        case .renameFolder(let folder): "rename-folder-\(folder.id)"
        case .newFolder(let parentID): "new-folder-\(parentID?.uuidString ?? "root")"
        }
    }

    var title: String {
        switch self {
        case .renameDocument: "Rename document"
        case .renameFolder: "Rename folder"
        case .newFolder: "New folder"
        }
    }

    var confirmLabel: String {
        switch self {
        case .renameDocument, .renameFolder: "Rename"
        case .newFolder: "Create"
        }
    }

    /// What the field starts out holding.
    var initialText: String {
        switch self {
        case .renameDocument(let metadata): metadata.title
        case .renameFolder(let folder): folder.name
        case .newFolder: "New Folder"
        }
    }
}

/// Something the user has asked to delete and not yet confirmed.
enum LibraryDeletion: Identifiable, Hashable {
    case document(DocumentMetadata)
    case folder(DocumentFolder)

    var id: UUID {
        switch self {
        case .document(let metadata): metadata.id
        case .folder(let folder): folder.id
        }
    }

    var name: String {
        switch self {
        case .document(let metadata): metadata.title
        case .folder(let folder): folder.name
        }
    }
}

/// The library's transient screen state — which prompt is up, what is being
/// confirmed, which document is open.
///
/// Held in one object rather than a handful of `@State` flags because the grid
/// is now recursive: every folder the user drills into needs to raise the same
/// prompts, and threading five bindings down each level is how that gets ugly.
@Observable
@MainActor
final class LibraryUIState {
    var prompt: LibraryPrompt?
    /// The text field's contents while `prompt` is showing.
    var promptText = ""
    var deletion: LibraryDeletion?
    var editorSession: DocumentEditorSession?

    /// Grid or outline. Shared by every level, so switching inside a folder does
    /// not leave the level above it in the other layout.
    var viewMode: LibraryViewMode {
        didSet { LibraryViewMode.persist(viewMode) }
    }

    /// Which folders are open in the outline. Kept here rather than in the view
    /// so drilling into a folder and coming back does not collapse everything.
    private(set) var expandedFolderIDs: Set<UUID> = []

    init() {
        viewMode = LibraryViewMode.restored()
    }

    func ask(_ prompt: LibraryPrompt) {
        promptText = prompt.initialText
        self.prompt = prompt
    }

    /// Routes a delete request: an empty folder goes straight in the bin, since
    /// there is nothing to lose and nothing worth reading a warning about.
    /// Anything holding work raises the confirmation dialog first.
    func requestDeletion(of target: LibraryDeletion, in library: DocumentLibrary) {
        guard let folderID = folderDeletableWithoutConfirmation(target, in: library) else {
            deletion = target
            return
        }
        Task { await library.deleteFolder(id: folderID) }
    }

    /// - Returns: The folder that may be deleted on the spot, or nil when the
    ///   user has to confirm first.
    func folderDeletableWithoutConfirmation(
        _ target: LibraryDeletion,
        in library: DocumentLibrary
    ) -> UUID? {
        guard case .folder(let folder) = target, library.isEmpty(folderID: folder.id) else { return nil }
        return folder.id
    }

    func toggleExpansion(of folderID: UUID) {
        if expandedFolderIDs.remove(folderID) == nil {
            expandedFolderIDs.insert(folderID)
        }
    }

    func isExpanded(_ folderID: UUID) -> Bool {
        expandedFolderIDs.contains(folderID)
    }
}
