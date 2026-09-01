import CoreGraphics
import Foundation

/// Everything the document library needs to draw a card, without touching a
/// single stroke. Stored as its own small JSON file so listing the library
/// never decodes stroke geometry.
struct DocumentMetadata: Codable, Identifiable, Hashable, Sendable {
    /// Bumped whenever the on-disk shape of a document changes. Reading a
    /// document written by a newer build fails loudly instead of silently
    /// dropping the fields this build does not understand.
    /// 2 added `problemOutline`: an older build would read the file, ignore the
    /// tree, and write the document back with every problem tag destroyed.
    static let currentSchemaVersion = 2

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
    /// The document's problem tree. Kept here rather than beside the strokes so
    /// the picker's structure loads with the card and costs no stroke decoding,
    /// and because it is a few hundred bytes next to a page of pencil telemetry.
    ///
    /// Optional on purpose: the synthesised decoder reads it with
    /// `decodeIfPresent`, so documents written before tagging existed still load.
    var problemOutline: ProblemOutline?

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        createdAt: Date = .now,
        modifiedAt: Date = .now,
        strokeCount: Int = 0,
        canvasOrigin: CGPoint = .zero,
        canvasScale: CGFloat = 1.0,
        problemOutline: ProblemOutline? = nil
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.strokeCount = strokeCount
        self.canvasOrigin = canvasOrigin
        self.canvasScale = canvasScale
        self.problemOutline = problemOutline
    }
}
