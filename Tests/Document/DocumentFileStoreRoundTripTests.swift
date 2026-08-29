import Foundation
import Testing
@testable import Tract

@Suite("Document file store round trip")
struct DocumentFileStoreRoundTripTests {
    private let directory: TemporaryDirectory
    private let store: DocumentFileStore

    init() throws {
        directory = try TemporaryDirectory()
        store = DocumentFileStore(rootDirectory: directory.url)
    }

    @Test("A saved document reloads with the same strokes, points and style")
    func strokesSurviveARoundTrip() async throws {
        let created = try await store.createDocument(title: "Notes")
        var document = created
        document.strokes = [
            StrokeFixtures.stroke(through: [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 12)]),
            StrokeFixtures.stroke(through: [CGPoint(x: 40, y: 5), CGPoint(x: 41, y: 90)])
        ]
        try await store.save(document, thumbnail: .unchanged)

        let reloaded = try await store.loadDocument(id: document.id)

        #expect(reloaded.strokes.count == 2)
        #expect(reloaded.strokes.map(\.id) == document.strokes.map(\.id))
        #expect(reloaded.strokes[0].points.map(\.position) == [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 12)])
        #expect(reloaded.strokes[1].style.lineWidth == 2)
        #expect(reloaded.strokes[1].canvasBounds == document.strokes[1].canvasBounds)
    }

    @Test("Title, dates and canvas pan/zoom survive a round trip")
    func metadataSurvivesARoundTrip() async throws {
        var document = try await store.createDocument(title: "Notes")
        document.metadata.title = "Field sketches"
        document.metadata.canvasOrigin = CGPoint(x: -120, y: 44)
        document.metadata.canvasScale = 2.5
        try await store.save(document, thumbnail: .unchanged)

        let reloaded = try await store.loadDocument(id: document.id)

        #expect(reloaded.metadata.title == "Field sketches")
        #expect(reloaded.metadata.canvasOrigin == CGPoint(x: -120, y: 44))
        #expect(reloaded.metadata.canvasScale == 2.5)
        // ISO 8601 stores whole seconds, so the reloaded date is the same instant
        // to the precision the format actually carries.
        #expect(abs(reloaded.metadata.createdAt.timeIntervalSince(document.metadata.createdAt)) < 1)
    }

    @Test("Stroke count is recorded from the strokes actually written")
    func strokeCountFollowsTheContent() async throws {
        var document = try await store.createDocument(title: "Notes")
        document.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 1, y: 1)])]
        try await store.save(document, thumbnail: .unchanged)

        #expect(try await store.loadDocument(id: document.id).metadata.strokeCount == 1)
    }

    @Test("A brand new document loads as an empty canvas, not as an error")
    func emptyDocumentLoads() async throws {
        let created = try await store.createDocument(title: "Untitled")
        let reloaded = try await store.loadDocument(id: created.id)
        #expect(reloaded.strokes.isEmpty)
    }

    @Test("Listing returns every document, most recently edited first")
    func listingIsSortedByEditTime() async throws {
        var older = try await store.createDocument(title: "Older")
        var newer = try await store.createDocument(title: "Newer")
        older.metadata.modifiedAt = Date(timeIntervalSince1970: 1_000)
        newer.metadata.modifiedAt = Date(timeIntervalSince1970: 2_000)
        try await store.save(older, thumbnail: .unchanged)
        try await store.save(newer, thumbnail: .unchanged)

        #expect(try await store.listMetadata().map(\.title) == ["Newer", "Older"])
    }

    @Test("A deleted document disappears from the listing and can no longer be loaded")
    func deletingRemovesTheDocument() async throws {
        let document = try await store.createDocument(title: "Doomed")
        try await store.deleteDocument(id: document.id)

        #expect(try await store.listMetadata().isEmpty)
        await #expect(throws: (any Error).self) { try await store.loadDocument(id: document.id) }
    }

    @Test("Renaming rewrites the title without disturbing the strokes")
    func renamingKeepsContent() async throws {
        var document = try await store.createDocument(title: "Untitled")
        document.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 5, y: 5)])]
        try await store.save(document, thumbnail: .unchanged)

        let renamed = try await store.renameDocument(id: document.id, to: "Chapter one")

        #expect(renamed.title == "Chapter one")
        let reloaded = try await store.loadDocument(id: document.id)
        #expect(reloaded.metadata.title == "Chapter one")
        #expect(reloaded.strokes.count == 1)
    }
}
