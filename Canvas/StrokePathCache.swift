import SwiftUI

/// Canvas-space `Path`s for strokes that are already on the page, so panning and
/// zooming never re-trace ink.
///
/// The renderer draws *through* the canvas→screen transform rather than baking it
/// into the points, which makes a stroke's path a function of its geometry alone:
/// the same path is valid at every zoom, and only a stroke that actually changed
/// has to be rebuilt. Tracing every stroke on every frame of a pinch is what this
/// exists to avoid — it is the same trade the selection outline already makes.
@MainActor
final class StrokePathCache {
    /// Sample count and bounds together fingerprint a stroke's geometry. Points
    /// are only ever appended, patched in place by the pencil's estimation
    /// update, or slid wholesale by a selection drag — the first two move the
    /// count or the bounds, and the third moves the bounds.
    private struct GeometryFingerprint: Equatable {
        let pointCount: Int
        let bounds: CGRect
    }

    private var cachedPaths: [UUID: (fingerprint: GeometryFingerprint, path: Path)] = [:]

    var cachedPathCount: Int { cachedPaths.count }

    func path(for stroke: Stroke) -> Path {
        let fingerprint = GeometryFingerprint(
            pointCount: stroke.points.count,
            bounds: stroke.canvasBounds
        )
        if let cached = cachedPaths[stroke.id], cached.fingerprint == fingerprint {
            return cached.path
        }
        let path = Self.makePath(for: stroke)
        cachedPaths[stroke.id] = (fingerprint, path)
        return path
    }

    /// Forgets strokes that are no longer on the canvas — erased, undone, or
    /// belonging to a document that has since been closed.
    func prune(keeping liveStrokeIDs: Set<UUID>) {
        cachedPaths = cachedPaths.filter { liveStrokeIDs.contains($0.key) }
    }

    /// Builds a smooth path through all stroke points using midpoint quadratic
    /// Béziers. The control point is the actual data point; the curve passes
    /// through midpoints — a cheap technique that looks smooth without cubic math.
    ///
    /// Traced in canvas space. An affine transform maps quadratic Béziers to
    /// quadratic Béziers and midpoints to midpoints, so drawing this through the
    /// canvas transform gives exactly the curve tracing in screen space would.
    static func makePath(for stroke: Stroke) -> Path {
        Path { path in
            let positions = stroke.points.map(\.position)
            guard let firstPosition = positions.first else { return }
            path.move(to: firstPosition)

            for index in 1 ..< positions.count {
                let previous = positions[index - 1]
                let midpoint = previous.midpoint(to: positions[index])
                if index == 1 {
                    // First segment: straight line to first midpoint.
                    path.addLine(to: midpoint)
                } else {
                    path.addQuadCurve(to: midpoint, control: previous)
                }
            }
            path.addLine(to: positions[positions.count - 1])
        }
    }
}
