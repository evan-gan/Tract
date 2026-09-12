import CoreGraphics
import Foundation

/// How far each problem's work is shifted from where it is stored, in canvas
/// space.
///
/// This is the whole of the automatic layout as far as the rest of the app is
/// concerned. **No stroke is ever moved.** The ink keeps the coordinates it was
/// drawn at; the renderer adds the offset for the problem a stroke is filed
/// under when it paints, and every hit test subtracts the same offset before it
/// measures. That is what makes the toggle exact in both directions — switching
/// the layout off is `identity`, not an attempt to put the ink back — and what
/// lets the focus animation run without touching the document at all.
///
/// Untagged ink is not in the map and therefore never moves. It belongs to no
/// problem, so the grid has no row to put it in.
struct ProblemLayoutPlacement: Equatable, Sendable {
    private var offsetsByNodeID: [UUID: CGPoint]

    /// Nothing shifted — the page exactly as it is stored. What the canvas uses
    /// whenever the layout is switched off.
    static let identity = ProblemLayoutPlacement(offsetsByNodeID: [:])

    init(offsetsByNodeID: [UUID: CGPoint] = [:]) {
        self.offsetsByNodeID = offsetsByNodeID
    }

    var isIdentity: Bool { offsetsByNodeID.isEmpty }

    func offset(forNode nodeID: UUID?) -> CGPoint {
        guard let nodeID else { return .zero }
        return offsetsByNodeID[nodeID] ?? .zero
    }

    func offset(for stroke: Stroke) -> CGPoint {
        offset(forNode: stroke.problemNodeID)
    }

    /// Adds a further shift on top of this one — how the focus push-aside is
    /// layered onto the grid without either having to know about the other.
    func adding(_ extra: [UUID: CGPoint]) -> ProblemLayoutPlacement {
        var combined = offsetsByNodeID
        for (nodeID, shift) in extra {
            combined[nodeID] = (combined[nodeID] ?? .zero) + shift
        }
        return ProblemLayoutPlacement(offsetsByNodeID: combined)
    }

    /// A placement part way between two others, for animating from one to the
    /// next. A node missing from either side counts as unshifted there, so a
    /// problem that only exists in the destination slides in from where it is
    /// stored rather than appearing at its destination.
    static func interpolating(
        from start: ProblemLayoutPlacement,
        to end: ProblemLayoutPlacement,
        progress: CGFloat
    ) -> ProblemLayoutPlacement {
        let clamped = min(max(progress, 0), 1)
        var blended: [UUID: CGPoint] = [:]
        for nodeID in Set(start.offsetsByNodeID.keys).union(end.offsetsByNodeID.keys) {
            let from = start.offset(forNode: nodeID)
            let to = end.offset(forNode: nodeID)
            blended[nodeID] = CGPoint(
                x: from.x + (to.x - from.x) * clamped,
                y: from.y + (to.y - from.y) * clamped
            )
        }
        return ProblemLayoutPlacement(offsetsByNodeID: blended)
    }
}
