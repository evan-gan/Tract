import Foundation
import Testing
@testable import Tract

/// The chosen paper has to come back with the document — and a document saved
/// before paper styles existed has to keep opening.
@Suite("Document paper persistence")
struct DocumentPaperPersistenceTests {
    private let directory: TemporaryDirectory
    private let store: DocumentFileStore

    init() throws {
        directory = try TemporaryDirectory()
        store = DocumentFileStore(rootDirectory: directory.url)
    }

    @Test("The paper a document was saved with is the paper it reopens on")
    func paperSurvivesASaveAndReload() async throws {
        var document = try await store.createDocument(title: "Blueprint")
        document.metadata.backgroundStyle = .blueprint
        try await store.save(document, thumbnail: .unchanged)

        let reloaded = try await store.loadDocument(id: document.id)

        #expect(reloaded.backgroundStyle == .blueprint)
    }

    @Test("A document written before paper styles existed opens on the dot grid")
    func legacyDocumentFallsBackToDots() throws {
        let legacy = #"""
        {"schemaVersion":4,"id":"\#(UUID().uuidString)","title":"Old","createdAt":0,\#
        "modifiedAt":0,"strokeCount":0,"canvasOrigin":[0,0],"canvasScale":1}
        """#

        let metadata = try JSONDecoder().decode(DocumentMetadata.self, from: Data(legacy.utf8))

        #expect(metadata.backgroundStyle == nil)
        #expect(SplineDocument(metadata: metadata).backgroundStyle == .dots)
    }

    @Test("The paper is stored under a stable name a future build can still read")
    func paperEncodesAsItsRawValue() throws {
        let metadata = DocumentMetadata(title: "Ruled", backgroundStyle: .legalPad)

        let encoded = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(metadata)
        ) as? [String: Any]

        #expect(encoded?["backgroundStyle"] as? String == "legalPad")
    }
}
