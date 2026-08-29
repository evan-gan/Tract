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

    init(id: UUID = UUID(), sessionID: UUID, style: StrokeStyle) {
        self.id = id
        self.sessionID = sessionID
        self.startTime = .now
        self.endTime = .now
        self.points = []
        self.style = style
        self.isComplete = false
        self.canvasBounds = .null
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
