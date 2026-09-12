import SwiftUI

/// The boundary around the problem being edited, part way between that
/// problem's own bubble and the dashed box it opens out into.
///
/// It draws one shape, not two. `ProblemFocusFrame` resamples the bubble and
/// the box onto matching points so the boundary can *travel* between them —
/// a cross-fade would read as the bubble vanishing and a box arriving, which
/// loses the thing the animation is there to say: that this is the same
/// problem, given room.
///
/// A `Canvas` rather than a `Shape`: the loop is recomputed from a progress
/// value the layout animator drives on every display refresh, and the geometry
/// is canvas-space points that have to be re-projected on every frame of a pan
/// regardless.
struct ProblemFocusFrameView: View {
    /// The frozen bubble in canonical form, in stored canvas space.
    let bubbleLoop: [CGPoint]
    /// Where the layout has moved the focused problem to. Added here rather
    /// than baked into `bubbleLoop`, so the frame keeps up while the
    /// arrangement animates underneath it.
    let placementOffset: CGPoint
    /// The dashed box, in canvas space — already laid out.
    let box: CGRect
    /// 0 is the bubble, 1 is the box.
    let progress: CGFloat
    let transform: CanvasTransform
    let tint: Color

    var body: some View {
        Canvas { context, _ in
            let loop = outline()
            guard loop.count >= 3 else { return }

            var path = Path()
            path.addSmoothedLoop(through: loop.map(transform.toScreen))

            context.fill(
                path,
                with: .color(tint.opacity(ProblemFocusFrameStyle.fillOpacity * progress))
            )
            context.stroke(
                path,
                with: .color(tint.opacity(ProblemFocusFrameStyle.strokeOpacity)),
                // Qualified: the app has a `StrokeStyle` of its own, for ink.
                style: SwiftUI.StrokeStyle(
                    lineWidth: ProblemFocusFrameStyle.lineWidth,
                    lineCap: .round,
                    lineJoin: .round,
                    dash: ProblemFocusFrameStyle.dash
                )
            )
        }
        // The frame is a boundary, not a control: tapping inside it has to
        // reach the drawing surface, and tapping outside it is what leaves.
        .allowsHitTesting(false)
    }

    private func outline() -> [CGPoint] {
        let shifted = placementOffset == .zero
            ? bubbleLoop
            : bubbleLoop.map { $0 + placementOffset }
        return ProblemFocusFrame.outline(
            from: shifted,
            to: box,
            // The radius is a screen-space constant, so it has to be taken into
            // canvas units before it can round a canvas-space rect.
            cornerRadius: transform.toCanvas(length: ProblemFocusFrameStyle.cornerRadius),
            progress: progress
        )
    }
}
