import CoreGraphics
import Foundation
import Testing
@testable import Tract

/// Pins have to come back with the document, and documents saved before pins
/// existed have to keep opening.
@Suite("Document pin persistence")
@MainActor
struct DocumentPinPersistenceTests {
    private let directory: TemporaryDirectory
    private let store: DocumentFileStore

    init() throws {
        directory = try TemporaryDirectory()
        store = DocumentFileStore(rootDirectory: directory.url)
    }

    @Test("A pin made in a session is there when the document is reopened")
    func pinSurvivesCloseAndReopen() async throws {
        var document = try await store.createDocument(title: "Notes")
        let stroke = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 40, y: 20)])
        document.strokes = [stroke]
        try await store.save(document, thumbnail: .unchanged)

        let session = DocumentEditorSession(metadata: document.metadata, store: store)
        await session.load()
        session.viewModel.pins.pin(
            strokeIDs: [stroke.id],
            inkSize: CGSize(width: 40, height: 20),
            viewport: CGSize(width: 1200, height: 800)
        )
        let pinned = session.viewModel.pins.references
        // Pins are view state, so the save that carries them is the flush on
        // close — exactly as pan and zoom are carried.
        await session.saveNow()

        let reopened = DocumentEditorSession(metadata: document.metadata, store: store)
        await reopened.load()

        #expect(reopened.viewModel.pins.references == pinned)
    }

    @Test("A pin saved by the build that gave pins colours still loads")
    func pinWithRetiredTintDecodes() throws {
        let pinWithTint = #"""
        {"id":"\#(UUID().uuidString)","strokeIDs":["\#(UUID().uuidString)"],\#
        "center":[100,200],"longestSide":250,"tintIndex":2}
        """#

        let reference = try JSONDecoder().decode(PinnedReference.self, from: Data(pinWithTint.utf8))

        #expect(reference.center == CGPoint(x: 100, y: 200))
        #expect(reference.longestSide == 250)
    }

    @Test("A document written before pins existed opens with none")
    func legacyDocumentHasNoPins() throws {
        let legacy = #"""
        {"schemaVersion":5,"id":"\#(UUID().uuidString)","title":"Old","createdAt":0,\#
        "modifiedAt":0,"strokeCount":0,"canvasOrigin":[0,0],"canvasScale":1}
        """#

        let metadata = try JSONDecoder().decode(DocumentMetadata.self, from: Data(legacy.utf8))

        #expect(metadata.pinnedReferences == nil)
    }
}
