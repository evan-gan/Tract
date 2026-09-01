import Foundation

/// A complete pen-down → pen-up gesture, including all intermediate samples.
/// `isComplete` is false while the pencil is still in contact with the screen.
struct Stroke: Identifiable, Codable, Sendable {
    let id: UUID
    /// Groups all strokes drawn in the same continuous session — useful for AI features.
    let sessionID: UUID
    let startTime: Date
    /// Set when the pencil lifts (touchesEnded). Wall-clock time, not device uptime.
    var endTime: Date
    var points: [StrokePoint]
    var style: StrokeStyle
    var isComplete: Bool
    /// Bounding box in canvas space, updated incrementally as points arrive.
    /// Used for spatial indexing and export viewport clipping.
    var canvasBounds: CGRect
    /// Which problem this stroke belongs to, as the *identity* of a node in the
    /// document's `ProblemOutline` — never as the label "1b".
    ///
    /// Labels come from position, so a stroke that stored one would be renamed
    /// out from under itself the moment anything above it moved. Pointing at the
    /// node instead means a reorder relabels the work without touching a single
    /// stroke. `ProblemGrouping` resolves these ids back into printable tags at
    /// export time. Nil until the user tags it, and an id whose node has since
    /// been deleted reads as untagged.
    ///
    /// Optional on purpose: the synthesised decoder reads it with
    /// `decodeIfPresent`, so documents saved before tagging existed still load.
    var problemNodeID: UUID?

    init(id: UUID = UUID(), sessionID: UUID, style: StrokeStyle, problemNodeID: UUID? = nil) {
        self.id = id
        self.sessionID = sessionID
        self.startTime = .now
        self.endTime = .now
        self.points = []
        self.style = style
        self.isComplete = false
        self.canvasBounds = .null
        self.problemNodeID = problemNodeID
    }

    /// Appends a point and expands the bounding box to include it.
    mutating func appendPoint(_ point: StrokePoint) {
        points.append(point)
        canvasBounds = canvasBounds == .null
            ? CGRect(origin: point.position, size: .zero)
            : canvasBounds.union(CGRect(origin: point.position, size: .zero))
    }

    /// Slides every sample by the same offset, taking the cached bounds with
    /// them. Used to move a lasso selection: the telemetry on each point is
    /// untouched, only where the mark sits on the canvas changes.
    mutating func translate(by offset: CGPoint) {
        points = points.map { $0.moved(by: offset) }
        canvasBounds = canvasBounds.offsetBy(dx: offset.x, dy: offset.y)
    }

    /// Replaces an estimated point with its final values from UIKit's update pass.
    mutating func updatePoint(at updateIndex: Int, with finalPoint: StrokePoint) {
        guard let idx = points.firstIndex(where: { $0.estimationUpdateIndex == updateIndex }) else {
            return
        }
        points[idx] = finalPoint
    }
}
