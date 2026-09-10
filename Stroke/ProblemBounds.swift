import CoreGraphics
import Foundation

/// The patch of canvas one problem's work occupies, as a shape the user can see
/// and tap.
///
/// The shape itself comes from `ProblemRegion` — a box shrunk onto the ink until
/// it touched, curving around what it met — so it reads as a region of the page
/// rather than as an outline of the handwriting. `ProblemBoundsCache` is what
/// builds these from a page of strokes.
struct ProblemBounds: Identifiable, Equatable {
    /// The problem this frames, held by node identity for the same reason a
    /// stroke is: labels come from position in the tree and are renamed by any
    /// reorder, while the id survives one.
    let nodeID: UUID
    /// The address it prints under today — "1.b" — resolved from the outline.
    let tag: ProblemTag
    /// Which top-level problem this belongs to, so every part of problem 2 is
    /// framed in the same colour as problem 2 itself.
    let problemIndex: Int
    /// Closed loops in canvas space. More than one means the problem's work sits
    /// in patches too far apart to be joined by one shape.
    let contours: [[CGPoint]]
    /// The box the whole region fits in. Cheap enough to test first, and it is
    /// what tells two overlapping regions apart when both are hit.
    let extent: CGRect

    var id: UUID { nodeID }

    /// Whether a canvas point lands in the region. A point inside an enclosed
    /// hole counts as inside: the hole is still this problem's patch of page,
    /// and a tap that lands in one is asking for this problem either way.
    func contains(_ canvasPoint: CGPoint) -> Bool {
        guard extent.contains(canvasPoint) else { return false }
        return contours.contains { StrokeGeometry.polygon($0, contains: canvasPoint) }
    }

}
