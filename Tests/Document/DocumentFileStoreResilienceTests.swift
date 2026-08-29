import Foundation
import Testing
@testable import Tract

/// The failure modes that made the old scheme untrustworthy: damaged files,
/// stray folders, and documents written by a build that knows more than this one.
@Suite("Document file store resilience")
struct DocumentFileStoreResilienceTests {
    private let directory: TemporaryDirectory
    private let store: DocumentFileStore

    init() throws {
        directory = try TemporaryDirectory()
        store = DocumentFileStore(rootDirectory: directory.url)
    }

    @Test("One document with unreadable metadata is skipped, not fatal to the listing")
    func damagedDocumentIsSkipped() async throws {
        let healthy = try await store.createDocument(title: "Healthy")
        let damaged = try await store.createDocument(title: "Damaged")
        try Data("not json".utf8).write(to: metadataURL(for: damaged.id))

        let listed = try await store.listMetadata()

        #expect(listed.map(\.id) == [healthy.id])
    }

    @Test("Stray files in the documents folder do not break the listing")
    func strayFilesAreIgnored() async throws {
        let document = try await store.createDocument(title: "Real")
        try Data("junk".utf8).write(to: directory.url.appending(path: "stray.txt"))

        #expect(try await store.listMetadata().map(\.id) == [document.id])
    }

    @Test("A damaged strokes file surfaces as an error rather than an empty canvas")
    func damagedStrokesThrow() async throws {
        var document = try await store.createDocument(title: "Damaged")
        document.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 3, y: 3)])]
        try await store.save(document, thumbnail: .unchanged)
        try Data("not a plist".utf8).write(to: strokesURL(for: document.id))

        await #expect(throws: DocumentStoreError.self) {
            try await store.loadDocument(id: document.id)
        }
    }

    @Test("A document written by a newer schema is refused with an explanatory error")
    func newerSchemaIsRefused() async throws {
        let document = try await store.createDocument(title: "From the future")
        try writeSchemaVersion(DocumentMetadata.currentSchemaVersion + 1, for: document.id)

        await #expect(throws: DocumentStoreError.self) {
            try await store.loadDocument(id: document.id)
        }
    }

    @Test("Removing the thumbnail clears the stored preview")
    func thumbnailCanBeCleared() async throws {
        let document = try await store.createDocument(title: "Erased")
        try await store.save(document, thumbnail: .replace(Data([0x01, 0x02])))
        #expect(await store.loadThumbnailData(id: document.id) != nil)

        try await store.save(document, thumbnail: .remove)

        #expect(await store.loadThumbnailData(id: document.id) == nil)
    }

    @Test("An unchanged thumbnail leaves the existing preview in place")
    func thumbnailIsKeptWhenUnchanged() async throws {
        let document = try await store.createDocument(title: "Kept")
        try await store.save(document, thumbnail: .replace(Data([0xAB])))

        try await store.save(document, thumbnail: .unchanged)

        #expect(await store.loadThumbnailData(id: document.id) == Data([0xAB]))
    }

    // MARK: - Helpers

    private func metadataURL(for id: UUID) -> URL {
        directory.url.appending(path: id.uuidString).appending(path: "metadata.json")
    }

    private func strokesURL(for id: UUID) -> URL {
        directory.url.appending(path: id.uuidString).appending(path: "strokes.plist")
    }

    /// Rewrites just the version field, leaving the rest of the file as the store
    /// wrote it — the point is a real document this build cannot read.
    private func writeSchemaVersion(_ version: Int, for id: UUID) throws {
        let url = metadataURL(for: id)
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] ?? [:]
        json["schemaVersion"] = version
        try JSONSerialization.data(withJSONObject: json).write(to: url)
    }
}
