import CoreGraphics
import Foundation

/// Everything the document library needs to draw a card, without touching a
/// single stroke. Stored as its own small JSON file so listing the library
/// never decodes stroke geometry.
struct DocumentMetadata: Codable, Identifiable, Hashable, Sendable {
    /// Bumped whenever the on-disk shape of a document changes. Reading a
    /// document written by a newer build fails loudly instead of silently
    /// dropping the fields this build does not understand.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    let id: UUID
    var title: String
    let createdAt: Date
    var modifiedAt: Date
    /// Shown on the card and used to tell an empty document from one whose
    /// strokes file failed to load.
    var strokeCount: Int
    /// Canvas pan/zoom, restored when the document is reopened.
    var canvasOrigin: CGPoint
    var canvasScale: CGFloat

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        strokeCount: Int = 0,
        canvasOrigin: CGPoint = .zero,
        canvasScale: CGFloat = 1.0
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.strokeCount = strokeCount
        self.canvasOrigin = canvasOrigin
        self.canvasScale = canvasScale
    }
}
