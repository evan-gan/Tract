import Foundation

/// Top-level in-memory document model. Lightweight — the canonical persistent
/// representation lives in Core Data via `DocumentStore`.
struct SplineDocument: Identifiable, Sendable {
    let id: UUID
    var title: String
    let createdAt: Date
    var modifiedAt: Date
    /// Strokes in `startTime` order, matching Core Data's ordered relationship.
    var strokes: [Stroke]
    var canvasOrigin: CGPoint
    var canvasScale: CGFloat

    init(
        id: UUID = UUID(),
        title: String = "Untitled",
        strokes: [Stroke] = [],
        canvasOrigin: CGPoint = .zero,
        canvasScale: CGFloat = 1.0
    ) {
        self.id = id
        self.title = title
        self.createdAt = .now
        self.modifiedAt = .now
        self.strokes = strokes
        self.canvasOrigin = canvasOrigin
        self.canvasScale = canvasScale
    }
}
