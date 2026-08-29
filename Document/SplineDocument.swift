import CoreGraphics
import Foundation

/// A document with its contents loaded: the metadata card plus every stroke.
/// The library holds `DocumentMetadata` alone; only an open (or exporting)
/// document is ever inflated into this.
struct SplineDocument: Identifiable, Sendable {
    var metadata: DocumentMetadata
    /// Strokes in `startTime` order — the order they were drawn, which is also
    /// the order they must be painted in.
    var strokes: [Stroke]

    var id: UUID { metadata.id }
    var title: String { metadata.title }
    var modifiedAt: Date { metadata.modifiedAt }

    init(metadata: DocumentMetadata = DocumentMetadata(), strokes: [Stroke] = []) {
        self.metadata = metadata
        self.strokes = strokes
    }
}
