import Foundation
import Testing
@testable import Tract

@Suite("Folder persistence")
struct DocumentFolderStoreTests {
    private let directory: TemporaryDirectory
    private let store: DocumentFileStore

    init() throws {
        directory = try TemporaryDirectory()
        store = DocumentFileStore(rootDirectory: directory.url)
    }

    @Test("A library that has never had a folder reads back as an empty tree, not an error")
    func missingFolderFileIsNotAnError() async throws {
        #expect(try await store.loadFolders().isEmpty)
    }

    @Test("Folders survive a round trip with their nesting intact")
    func foldersRoundTrip() async throws {
        let maths = DocumentFolder(name: "Maths")
        let algebra = DocumentFolder(name: "Algebra", parentID: maths.id)
        try await store.saveFolders([maths, algebra])

        let reloaded = try await store.loadFolders()

        #expect(reloaded.count == 2)
        #expect(reloaded.first { $0.id == algebra.id }?.parentID == maths.id)
        #expect(reloaded.first { $0.id == maths.id }?.name == "Maths")
    }

    @Test("A document remembers which folder it was filed in")
    func folderMembershipRoundTrips() async throws {
        let folder = DocumentFolder(name: "Homework")
        try await store.saveFolders([folder])
        let document = try await store.createDocument(title: "Notes", in: folder.id)

        #expect(try await store.loadDocument(id: document.id).metadata.folderID == folder.id)
    }

    @Test("Filing a document into a folder leaves its edit time alone")
    func filingIsNotAnEdit() async throws {
        let folder = DocumentFolder(name: "Homework")
        try await store.saveFolders([folder])
        let document = try await store.createDocument(title: "Notes")

        let moved = try await store.setFolderID(folder.id, forDocument: document.id)

        #expect(moved.folderID == folder.id)
        #expect(abs(moved.modifiedAt.timeIntervalSince(document.metadata.modifiedAt)) < 1)
    }

    @Test("A document can be moved back to the top level")
    func filingBackToTheTopLevel() async throws {
        let folder = DocumentFolder(name: "Homework")
        try await store.saveFolders([folder])
        let document = try await store.createDocument(title: "Notes", in: folder.id)

        _ = try await store.setFolderID(nil, forDocument: document.id)

        #expect(try await store.loadDocument(id: document.id).metadata.folderID == nil)
    }

    @Test("The folder file is not mistaken for a document when listing the library")
    func folderFileIsSkippedWhenListing() async throws {
        try await store.saveFolders([DocumentFolder(name: "Homework")])
        _ = try await store.createDocument(title: "Notes")

        #expect(try await store.listMetadata().count == 1)
    }

    @Test("A damaged folder file fails loudly rather than silently unfiling everything")
    func damagedFolderFileThrows() async throws {
        try Data("not json".utf8).write(to: directory.url.appending(path: "folders.json"))

        await #expect(throws: DocumentStoreError.self) {
            try await store.loadFolders()
        }
    }
}
