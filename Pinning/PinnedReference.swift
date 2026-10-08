import CoreGraphics
import Foundation

/// A piece of earlier work floated over the canvas, so it can be read while
/// writing somewhere else on the page without zooming back and forth.
///
/// It points at strokes by id rather than holding copies of them. That keeps it
/// a *view* of the page — ink corrected after pinning shows up corrected in the
/// pin — and costs a few ids on disk instead of a second copy of the pencil
/// telemetry.
///
/// Its frame is in **screen** points, not canvas ones: the whole point is that it
/// holds still while the page is panned and zoomed beneath it.
struct PinnedReference: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var strokeIDs: Set<UUID>
    /// Centre of the card, in the canvas view's coordinates.
    var center: CGPoint
    /// Length of the card's longer side. The shorter one follows from the
    /// pinned ink's aspect ratio, so the two can never disagree.
    var longestSide: CGFloat

    init(id: UUID = UUID(), strokeIDs: Set<UUID>, center: CGPoint, longestSide: CGFloat) {
        self.id = id
        self.strokeIDs = strokeIDs
        self.center = center
        self.longestSide = longestSide
    }
}
