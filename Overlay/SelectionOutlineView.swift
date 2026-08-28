import SwiftUI

/// Marching-ants outline around whatever the lasso selected. It follows the
/// shape of the ink — the selection's own outline pushed outward — rather than
/// boxing it in, and stands a quarter inch clear of every stroke.
struct SelectionOutlineView: View {
    let selectedStrokes: [Stroke]
    let transform: CanvasTransform

    var body: some View {
        // A timeline drives the march rather than an animated @State value:
        // `Canvas` redraws from its closure, and only a per-frame date reliably
        // re-runs it. Nothing else on screen animates from this.
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                guard let outline = outlinePath() else { return }
                context.stroke(
                    outline,
                    with: .color(SelectionStyle.color),
                    style: SelectionStyle.outline(dashPhase: marchPhase(at: timeline.date))
                )
            }
        }
        .allowsHitTesting(false)
    }

    /// Walks the dash pattern back by exactly one cycle every `marchDuration`,
    /// which reads as the ants crawling around the outline.
    private func marchPhase(at date: Date) -> CGFloat {
        let cycles = date.timeIntervalSinceReferenceDate / SelectionStyle.marchDuration
        return -CGFloat(cycles.truncatingRemainder(dividingBy: 1)) * SelectionStyle.dashPeriod
    }

    /// The selection's outline in screen space, standing off the ink.
    /// The standoff is applied after the transform so it stays a constant
    /// physical distance instead of shrinking and growing with the zoom.
    private func outlinePath() -> Path? {
        let screenPoints = selectedStrokes
            .flatMap(\.points)
            .map { transform.toScreen($0.position) }
        guard !screenPoints.isEmpty else { return nil }

        let hull = SelectionOutline.convexHull(of: screenPoints)
        // A hull needs three corners to be offset. A single straight stroke does
        // not have them, so it gets a rounded capsule around its extent instead.
        guard hull.count >= 3 else { return degenerateOutline(around: screenPoints) }

        let expanded = SelectionOutline.offset(polygon: hull, by: SelectionStyle.standoff)
        return softenedPath(through: expanded)
    }

    /// Fallback for selections with no area of their own: a dot, or ink that
    /// falls on a single straight line.
    private func degenerateOutline(around screenPoints: [CGPoint]) -> Path {
        let extent = screenPoints.reduce(CGRect.null) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
        let padded = extent.insetBy(dx: -SelectionStyle.standoff, dy: -SelectionStyle.standoff)
        return Path(roundedRect: padded, cornerRadius: SelectionStyle.cornerSoftening,
                    style: .continuous)
    }

    /// Traces the polygon, replacing each hard corner with a short arc. Starting
    /// mid-edge means every corner — including the one at the start — is softened.
    private func softenedPath(through vertices: [CGPoint]) -> Path {
        let radius = softeningRadius(for: vertices)
        return Path { path in
            path.move(to: vertices[vertices.count - 1].midpoint(to: vertices[0]))
            for index in vertices.indices {
                let corner = vertices[index]
                let next = vertices[(index + 1) % vertices.count]
                path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
            }
            path.closeSubpath()
        }
    }

    /// Clamped to half the shortest edge: an arc wider than the edge it sits on
    /// would eat into its neighbour and buckle the outline.
    private func softeningRadius(for vertices: [CGPoint]) -> CGFloat {
        let shortestEdge = vertices.indices
            .map { vertices[$0].distance(to: vertices[($0 + 1) % vertices.count]) }
            .min() ?? 0
        return min(SelectionStyle.cornerSoftening, shortestEdge / 2)
    }
}
