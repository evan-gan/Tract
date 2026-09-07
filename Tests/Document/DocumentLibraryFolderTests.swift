import Foundation
import Testing
@testable import Tract

@Suite("Document library folders")
@MainActor
struct DocumentLibraryFolderTests {
    private let directory: TemporaryDirectory
    private let library: DocumentLibrary

    init() throws {
        directory = try TemporaryDirectory()
        library = DocumentLibrary(store: DocumentFileStore(rootDirectory: directory.url))
    }

    @Test("A new folder appears in the library and survives a reload")
    func createdFoldersPersist() async throws {
        let folder = try #require(await library.createFolder(named: "Maths"))

        #expect(library.folders(in: nil).map(\.id) == [folder.id])

        await library.refresh()
        #expect(library.folders(in: nil).map(\.name) == ["Maths"])
    }

    @Test("A blank folder name falls back to a usable one rather than an invisible card")
    func blankFolderNamesAreRejected() async throws {
        let folder = try #require(await library.createFolder(named: "   "))

        #expect(folder.name == "New Folder")
    }

    @Test("A folder created inside another is nested, not left at the top level")
    func foldersNestInsideFolders() async throws {
        let parent = try #require(await library.createFolder(named: "Maths"))
        let child = try #require(await library.createFolder(named: "Algebra", in: parent.id))

        #expect(library.folders(in: nil).map(\.id) == [parent.id])
        #expect(library.folders(in: parent.id).map(\.id) == [child.id])
    }

    @Test("A document created in a folder is listed there and not at the top level")
    func documentsAreCreatedInTheCurrentFolder() async throws {
        let folder = try #require(await library.createFolder(named: "Maths"))
        let document = try #require(await library.createDocument(title: "Notes", in: folder.id))

        #expect(library.documents(in: folder.id).map(\.id) == [document.id])
        #expect(library.documents(in: nil).isEmpty)
    }

    @Test("Dragging a document into a folder moves it, and out again returns it to the top level")
    func documentsCanBeDraggedBetweenFolders() async throws {
        let folder = try #require(await library.createFolder(named: "Maths"))
        let document = try #require(await library.createDocument(title: "Notes"))

        #expect(await library.move(.document(document.id), into: folder.id))
        #expect(library.documents(in: folder.id).map(\.id) == [document.id])

        #expect(await library.move(.document(document.id), into: nil))
        #expect(library.documents(in: nil).map(\.id) == [document.id])
    }

    @Test("Dragging a folder into another folder nests it")
    func foldersCanBeDraggedIntoFolders() async throws {
        let maths = try #require(await library.createFolder(named: "Maths"))
        let algebra = try #require(await library.createFolder(named: "Algebra"))

        #expect(await library.move(.folder(algebra.id), into: maths.id))
        #expect(library.folders(in: maths.id).map(\.id) == [algebra.id])
        #expect(library.folders(in: nil).map(\.id) == [maths.id])
    }

    @Test("A folder cannot be dragged inside itself")
    func aFolderCannotSwallowItself() async throws {
        let maths = try #require(await library.createFolder(named: "Maths"))
        let algebra = try #require(await library.createFolder(named: "Algebra", in: maths.id))

        #expect(await library.move(.folder(maths.id), into: maths.id) == false)
        #expect(await library.move(.folder(maths.id), into: algebra.id) == false)
        #expect(library.folders(in: nil).map(\.id) == [maths.id])
    }

    @Test("Deleting a folder deletes everything nested inside it")
    func deletingAFolderCascades() async throws {
        let maths = try #require(await library.createFolder(named: "Maths"))
        let algebra = try #require(await library.createFolder(named: "Algebra", in: maths.id))
        _ = try #require(await library.createDocument(title: "Nested", in: algebra.id))
        let survivor = try #require(await library.createDocument(title: "Kept"))

        #expect(library.documentCount(withinTreeOf: maths.id) == 1)
        await library.deleteFolder(id: maths.id)

        #expect(library.folders(in: nil).isEmpty)
        #expect(library.documents.map(\.id) == [survivor.id])

        // Reload from disk: the cascade has to have been written, not just
        // applied to the in-memory list.
        await library.refresh()
        #expect(library.folders(in: nil).isEmpty)
        #expect(library.documents.map(\.id) == [survivor.id])
    }

    @Test("A document whose folder has vanished shows at the top level instead of disappearing")
    func orphanedDocumentsSurfaceAtTheTopLevel() async throws {
        let folder = try #require(await library.createFolder(named: "Maths"))
        let document = try #require(await library.createDocument(title: "Notes", in: folder.id))
        // Wipe the folder list the way a damaged file would, leaving the document
        // pointing at a folder nobody can open.
        try await library.store.saveFolders([])

        await library.refresh()

        #expect(library.documents(in: nil).map(\.id) == [document.id])
    }

    @Test("Renaming a folder keeps its contents")
    func renamingAFolderKeepsItsContents() async throws {
        let folder = try #require(await library.createFolder(named: "Maths"))
        let document = try #require(await library.createDocument(title: "Notes", in: folder.id))

        await library.renameFolder(id: folder.id, to: "Algebra")

        #expect(library.folder(id: folder.id)?.name == "Algebra")
        #expect(library.documents(in: folder.id).map(\.id) == [document.id])
    }
}
