import Foundation
import Testing
@testable import Tract

/// Which delete requests are worth interrupting the user for. Deleting an empty
/// folder destroys nothing, so it must not raise the confirmation dialog.
@Suite("Library deletion prompting")
@MainActor
struct LibraryDeletionPromptTests {
    private let directory: TemporaryDirectory
    private let library: DocumentLibrary
    private let uiState = LibraryUIState()

    init() throws {
        directory = try TemporaryDirectory()
        library = DocumentLibrary(store: DocumentFileStore(rootDirectory: directory.url))
    }

    @Test("An empty folder is deleted without asking")
    func emptyFoldersSkipConfirmation() async throws {
        let folder = try #require(await library.createFolder(named: "Empty"))

        #expect(uiState.folderDeletableWithoutConfirmation(.folder(folder), in: library) == folder.id)
    }

    @Test("A folder holding a document still asks first")
    func foldersWithDocumentsAreConfirmed() async throws {
        let folder = try #require(await library.createFolder(named: "Maths"))
        _ = try #require(await library.createDocument(title: "Notes", in: folder.id))

        #expect(uiState.folderDeletableWithoutConfirmation(.folder(folder), in: library) == nil)
    }

    @Test("A folder holding only an empty subfolder still asks first")
    func foldersWithSubfoldersAreConfirmed() async throws {
        let parent = try #require(await library.createFolder(named: "Maths"))
        _ = try #require(await library.createFolder(named: "Algebra", in: parent.id))

        #expect(uiState.folderDeletableWithoutConfirmation(.folder(parent), in: library) == nil)
    }

    @Test("Deleting a document always asks first")
    func documentsAreAlwaysConfirmed() async throws {
        let document = try #require(await library.createDocument(title: "Notes"))

        #expect(uiState.folderDeletableWithoutConfirmation(.document(document), in: library) == nil)
    }

    @Test("Requesting an empty folder's deletion removes it and raises no dialog")
    func requestingAnEmptyFolderDeletesIt() async throws {
        let folder = try #require(await library.createFolder(named: "Empty"))

        uiState.requestDeletion(of: .folder(folder), in: library)
        #expect(uiState.deletion == nil)

        // The delete runs in a detached task; give it a bounded window to land.
        for _ in 0..<100 where !library.folders(in: nil).isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(library.folders(in: nil).isEmpty)
    }

    @Test("Requesting a full folder's deletion raises the dialog instead")
    func requestingAFullFolderPromptsInstead() async throws {
        let folder = try #require(await library.createFolder(named: "Maths"))
        _ = try #require(await library.createDocument(title: "Notes", in: folder.id))

        uiState.requestDeletion(of: .folder(folder), in: library)

        #expect(uiState.deletion == .folder(folder))
        #expect(library.folders(in: nil).map(\.id) == [folder.id])
    }
}
