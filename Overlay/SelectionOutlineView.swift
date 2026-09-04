import SwiftUI

/// Marching-ants outline around whatever the lasso selected. It hugs the ink —
/// the outline is everything within a quarter inch of a selected stroke — rather
/// than boxing the selection in, and anything further than two standoffs from
/// the rest of the selection gets an outline of its own instead of being roped
/// in by one shared frame.
struct SelectionOutlineView: View {
    /// The traced frame, in canvas space, one closed contour per piece of ink.
    /// Traced by `CanvasViewModel` when the selection changes rather than here:
    /// building a distance field is far too expensive to redo on every frame of
    /// the march, and a view that caches it in its own `@State` has to write that
    /// state during a view update — a write SwiftUI may drop, which is exactly
    /// how this outline used to go missing until the next pinch.
    let contours: [[CGPoint]]
    let transform: CanvasTransform
    /// Live drag translation in canvas space. Applied on top of the traced shape
    /// so moving a selection never re-traces it.
    var dragOffset: CGPoint = .zero

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
    }

    /// Walks the dash pattern back by exactly one cycle every `marchDuration`,
    /// which reads as the ants crawling around the outline.
    private func marchPhase(at date: Date) -> CGFloat {
        let cycles = date.timeIntervalSinceReferenceDate / SelectionStyle.marchDuration
        return -CGFloat(cycles.truncatingRemainder(dividingBy: 1)) * SelectionStyle.dashPeriod
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
