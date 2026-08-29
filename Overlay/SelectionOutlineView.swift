import SwiftUI

/// Marching-ants outline around whatever the lasso selected. It hugs the ink —
/// the outline is everything within a quarter inch of a selected stroke — rather
/// than boxing the selection in, and anything further than two standoffs from
/// the rest of the selection gets an outline of its own instead of being roped
/// in by one shared frame.
struct SelectionOutlineView: View {
    let selectedStrokes: [Stroke]
    let transform: CanvasTransform
    /// How far the frame stands off the ink, in canvas space. Owned by the view
    /// model and fixed when the selection is made — see
    /// `CanvasViewModel.selectionStandoff`.
    let standoff: CGFloat
    /// Live drag translation in canvas space. Applied on top of the cached shape
    /// so moving a selection never re-traces it.
    var dragOffset: CGPoint = .zero

    /// The traced contours, in canvas space. Held as state because building a
    /// distance field is far too expensive to redo on every frame of the march.
    @State private var contours: [[CGPoint]] = []

    var body: some View {
        // A timeline drives the march rather than an animated @State value:
        // `Canvas` redraws from its closure, and only a per-frame date reliably
        // re-runs it. Nothing else on screen animates from this.
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                context.stroke(
                    outlinePath(),
                    with: .color(SelectionStyle.color),
                    style: SelectionStyle.outline(dashPhase: marchPhase(at: timeline.date))
                )
            }
        }
        .allowsHitTesting(false)
        .onChange(of: shapeIdentity, initial: true) { contours = traceContours() }
    }

    /// Walks the dash pattern back by exactly one cycle every `marchDuration`,
    /// which reads as the ants crawling around the outline.
    private func marchPhase(at date: Date) -> CGFloat {
        let cycles = date.timeIntervalSinceReferenceDate / SelectionStyle.marchDuration
        return -CGFloat(cycles.truncatingRemainder(dividingBy: 1)) * SelectionStyle.dashPeriod
    }

    // MARK: - Tracing

    /// Everything that can change the outline's shape: which strokes are
    /// selected, how many samples they hold, and where they sit. Navigation is
    /// deliberately absent — panning and zooming a selection around costs nothing
    /// because neither re-traces it.
    private var shapeIdentity: SelectionShapeIdentity {
        SelectionShapeIdentity(
            strokeIDs: selectedStrokes.map(\.id),
            pointCounts: selectedStrokes.map(\.points.count),
            inkBounds: selectedStrokes.reduce(CGRect.null) { $0.union($1.canvasBounds) },
            standoff: standoff
        )
    }

    /// Traces in canvas space at a standoff that was fixed when the selection was
    /// made, so the contours are plain canvas geometry from then on: zooming
    /// magnifies the frame along with the ink it frames, exactly as it magnifies
    /// stroke width. Re-tracing to hold a literal quarter inch on screen would
    /// mean rebuilding a distance field on every frame of a pinch, which is the
    /// one thing this cache exists to avoid.
    private func traceContours() -> [[CGPoint]] {
        let polylines = selectedStrokes.map { $0.points.map(\.position) }
        guard !polylines.isEmpty else { return [] }
        return SelectionRegion.contours(around: polylines, radius: standoff)
    }

    // MARK: - Drawing

    private func outlinePath() -> Path {
        Path { path in
            for contour in contours {
                appendSmoothedLoop(contour, to: &path)
            }
        }
    }

    /// Traces one contour with midpoint quadratic Béziers. Marching squares lands
    /// its vertices on grid edges, so a raw loop carries a faint staircase;
    /// curving through the midpoints takes it out without pulling the outline off
    /// the shape it is describing.
    private func appendSmoothedLoop(_ canvasContour: [CGPoint], to path: inout Path) {
        guard canvasContour.count >= 3 else { return }
        let screenPoints = canvasContour.map { transform.toScreen($0 + dragOffset) }
        let lastIndex = screenPoints.count - 1

        path.move(to: screenPoints[lastIndex].midpoint(to: screenPoints[0]))
        for index in screenPoints.indices {
            let vertex = screenPoints[index]
            let next = screenPoints[index == lastIndex ? 0 : index + 1]
            path.addQuadCurve(to: vertex.midpoint(to: next), control: vertex)
        }
        path.closeSubpath()
    }
}

/// Fingerprint of a selection's shape. Comparing this is what decides whether
/// the outline has to be traced again.
private struct SelectionShapeIdentity: Equatable {
    let strokeIDs: [UUID]
    let pointCounts: [Int]
    let inkBounds: CGRect
    let standoff: CGFloat
}
