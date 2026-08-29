import Foundation
import Testing
@testable import Tract

@Suite("Document editor session")
@MainActor
struct DocumentEditorSessionTests {
    private let directory: TemporaryDirectory
    private let store: DocumentFileStore

    init() throws {
        directory = try TemporaryDirectory()
        store = DocumentFileStore(rootDirectory: directory.url)
    }

    @Test("Opening a document puts its saved strokes and canvas position back on the canvas")
    func loadRestoresTheCanvas() async throws {
        var document = try await store.createDocument(title: "Notes")
        document.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 8, y: 8)])]
        document.metadata.canvasOrigin = CGPoint(x: 30, y: -60)
        document.metadata.canvasScale = 1.75
        try await store.save(document, thumbnail: .unchanged)

        let session = makeSession(for: document.metadata)
        await session.load()

        #expect(session.loadState == .ready)
        #expect(session.viewModel.strokes.count == 1)
        #expect(session.viewModel.canvasTransform.translation == CGPoint(x: 30, y: -60))
        #expect(session.viewModel.canvasTransform.scale == 1.75)
    }

    @Test("A stroke drawn after loading is written back to disk")
    func editsArePersisted() async throws {
        let document = try await store.createDocument(title: "Notes")
        let session = makeSession(for: document.metadata)
        await session.load()

        draw(on: session.viewModel, through: [CGPoint(x: 1, y: 1), CGPoint(x: 9, y: 4)])
        await session.saveNow()

        let reloaded = try await store.loadDocument(id: document.id)
        #expect(reloaded.strokes.count == 1)
        #expect(session.hasUnsavedChanges == false)
    }

    @Test("Saving before the load finishes cannot blank the document")
    func saveBeforeLoadIsRefused() async throws {
        var document = try await store.createDocument(title: "Notes")
        document.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 4, y: 4)])]
        try await store.save(document, thumbnail: .unchanged)

        // A session that has never loaded holds an empty view model — exactly the
        // state that used to overwrite real work.
        let session = makeSession(for: document.metadata)
        await session.saveNow()

        #expect(try await store.loadDocument(id: document.id).strokes.count == 1)
    }

    @Test("A document whose strokes cannot be decoded is never saved over")
    func failedLoadIsNeverSavedOver() async throws {
        var document = try await store.createDocument(title: "Damaged")
        document.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 4, y: 4)])]
        try await store.save(document, thumbnail: .unchanged)
        let strokesURL = directory.url.appending(path: document.id.uuidString).appending(path: "strokes.plist")
        let damagedBytes = Data("not a plist".utf8)
        try damagedBytes.write(to: strokesURL)

        let session = makeSession(for: document.metadata)
        await session.load()
        draw(on: session.viewModel, through: [CGPoint(x: 2, y: 2), CGPoint(x: 3, y: 3)])
        await session.saveNow()

        #expect(session.loadState != .ready)
        #expect(try Data(contentsOf: strokesURL) == damagedBytes)
    }

    @Test("Renaming from the canvas updates the title on disk")
    func titleIsPersisted() async throws {
        let document = try await store.createDocument(title: "Untitled")
        let session = makeSession(for: document.metadata)
        await session.load()

        session.title = "Survey notes"
        await session.saveNow()

        #expect(try await store.loadDocument(id: document.id).metadata.title == "Survey notes")
    }

    @Test("Panning does not push the document to the top of the library")
    func panningDoesNotCountAsAnEdit() async throws {
        let document = try await store.createDocument(title: "Notes")
        let session = makeSession(for: document.metadata)
        await session.load()
        let originalEditTime = session.metadata.modifiedAt

        session.viewModel.canvasTransform.translation = CGPoint(x: 100, y: 100)
        await session.saveNow()

        #expect(session.metadata.modifiedAt == originalEditTime)
        #expect(try await store.loadDocument(id: document.id).metadata.canvasOrigin == CGPoint(x: 100, y: 100))
    }

    @Test("A save with nothing new to record makes no changes")
    func redundantSaveIsSkipped() async throws {
        let document = try await store.createDocument(title: "Notes")
        let session = makeSession(for: document.metadata)
        await session.load()
        let originalEditTime = session.metadata.modifiedAt

        await session.saveNow()

        #expect(session.metadata.modifiedAt == originalEditTime)
    }

    // MARK: - Helpers

    private func makeSession(for metadata: DocumentMetadata) -> DocumentEditorSession {
        DocumentEditorSession(metadata: metadata, store: store)
    }

    /// Replays a pen gesture through the view model so the test exercises the same
    /// path a real stroke takes, including the revision bump autosave depends on.
    private func draw(on viewModel: CanvasViewModel, through positions: [CGPoint]) {
        viewModel.selectTool(.pen)
        viewModel.beginStroke(with: StrokeFixtures.point(at: positions[0]))
        for position in positions.dropFirst() {
            viewModel.continueStroke(with: StrokeFixtures.point(at: position))
        }
        viewModel.endStroke()
    }
}
