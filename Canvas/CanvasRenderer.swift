import SwiftUI

/// Converts `Stroke` data into SwiftUI `Canvas` drawings.
/// Kept separate from the UIKit input layer so rendering can be swapped
/// for Metal later without touching any touch-handling code.
///
/// Ink is drawn on **two** layers. The page's committed strokes are one of them,
/// and the stroke still under the pencil is the other — so a sample arriving at
/// 240 Hz repaints one fresh mark instead of the whole drawing. SwiftUI only
/// re-runs a `Canvas` whose inputs changed, and the committed layer's inputs do
/// not change while a stroke is being drawn.
struct CanvasRenderer: View {
    let strokes: [Stroke]
    let activeStroke: Stroke?
    let transform: CanvasTransform
    /// The strokes a selection drag is currently carrying, and how far. Applied
    /// here rather than written into the ink so a drag costs no data churn and
    /// commits as a single undo step when it ends.
    var selectedStrokeIDs: Set<UUID> = []
    var selectionOffset: CGPoint = .zero
    /// Recolouring and dimming asked for by the problem picker's modes. Handed
    /// in already resolved, so the draw loop stays a lookup per stroke.
    var problemInk: ProblemInkStyling = .inactive

    var body: some View {
        ZStack {
            CommittedInkLayer(
                strokes: strokes,
                transform: transform,
                selectedStrokeIDs: selectedStrokeIDs,
                selectionOffset: selectionOffset,
                problemInk: problemInk
            )
            ActiveInkLayer(stroke: activeStroke, transform: transform)
        }
    }
}

/// One stroke resolved for painting: the path to trace, how to paint it, and
/// whether the live selection drag is carrying it.
private struct ResolvedInkStroke {
    let path: Path
    let color: Color
    let lineWidth: CGFloat
    let isBeingDragged: Bool
}

/// Every stroke already on the page.
private struct CommittedInkLayer: View {
    let strokes: [Stroke]
    let transform: CanvasTransform
    let selectedStrokeIDs: Set<UUID>
    let selectionOffset: CGPoint
    let problemInk: ProblemInkStyling

    /// Kept as view state so it survives the redraws it exists to make cheap.
    @State private var pathCache = StrokePathCache()

    var body: some View {
        Canvas { context, size in
            // Resolving reads the main-actor path cache; painting does not, and
            // the renderer runs on the main thread either way.
            let visibleInk = MainActor.assumeIsolated { resolveVisibleInk(viewSize: size) }
            paint(visibleInk, in: &context)
        }
        // Disable animations on the canvas — strokes must appear instantly.
        .transaction { $0.animation = nil }
    }

    /// Culls to what is actually on screen, then hands back a cached path per
    /// survivor. Everything here is canvas-space, so a pan or a zoom changes
    /// which strokes come back but never re-traces one.
    @MainActor
    private func resolveVisibleInk(viewSize: CGSize) -> [ResolvedInkStroke] {
        let visibleCanvasRect = transform.visibleCanvasRect(inViewOfSize: viewSize)
        var visibleInk: [ResolvedInkStroke] = []
        visibleInk.reserveCapacity(strokes.count)

        for stroke in strokes {
            guard InkDrawing.isDrawable(stroke) else { continue }
            let isBeingDragged = selectedStrokeIDs.contains(stroke.id)
            let dragOffset = isBeingDragged ? selectionOffset : .zero
            guard InkDrawing.bounds(of: stroke, offsetBy: dragOffset).intersects(visibleCanvasRect)
            else { continue }

            visibleInk.append(ResolvedInkStroke(
                path: pathCache.path(for: stroke),
                color: problemInk.color(for: stroke).opacity(problemInk.opacity(for: stroke)),
                lineWidth: stroke.style.lineWidth,
                isBeingDragged: isBeingDragged
            ))
        }
        pruneCacheIfStale()
        return visibleInk
    }

    private func paint(_ visibleInk: [ResolvedInkStroke], in context: inout GraphicsContext) {
        context.concatenate(transform.matrix)
        // A copy of the context carrying the live drag: `GraphicsContext` is a
        // value, so shifting this one leaves the shared transform alone and the
        // selection can be painted in the same pass as everything else.
        var draggedInkContext = context
        draggedInkContext.translateBy(x: selectionOffset.x, y: selectionOffset.y)

        for ink in visibleInk {
            if ink.isBeingDragged {
                InkDrawing.stroke(ink, in: &draggedInkContext)
            } else {
                InkDrawing.stroke(ink, in: &context)
            }
        }
    }

    /// Erasing, undoing and reopening a document all leave paths behind for ink
    /// that is gone. Sweeping only once the cache has grown well past the page
    /// keeps the common frame — where nothing was removed — free of the work.
    @MainActor
    private func pruneCacheIfStale() {
        guard pathCache.cachedPathCount > max(strokes.count * 2, 64) else { return }
        pathCache.prune(keeping: Set(strokes.map(\.id)))
    }
}

/// The stroke currently under the pencil, on its own layer so the page beneath
/// it does not repaint on every sample.
private struct ActiveInkLayer: View {
    let stroke: Stroke?
    let transform: CanvasTransform

    var body: some View {
        Canvas { context, _ in
            guard let stroke, InkDrawing.isDrawable(stroke) else { return }
            context.concatenate(transform.matrix)
            // Never cached: by definition this path changes on every sample.
            InkDrawing.stroke(
                ResolvedInkStroke(
                    path: StrokePathCache.makePath(for: stroke),
                    color: stroke.style.swiftUIColor,
                    lineWidth: stroke.style.lineWidth,
                    isBeingDragged: false
                ),
                in: &context
            )
        }
        .transaction { $0.animation = nil }
    }
}

/// What both ink layers agree on: which strokes leave a mark, how far that mark
/// spreads on the canvas, and how it is painted.
private enum InkDrawing {
    /// The eraser and lasso leave no ink; documents saved before they became
    /// non-drawing tools can still carry such strokes, and a lone sample has no
    /// segment to draw.
    static func isDrawable(_ stroke: Stroke) -> Bool {
        stroke.style.tool.isDrawingTool && stroke.points.count >= 2
    }

    /// Canvas-space rect the drawn mark covers — the samples' own bounds widened
    /// by the half line width the round cap paints either side of them.
    static func bounds(of stroke: Stroke, offsetBy offset: CGPoint) -> CGRect {
        // Never zero: a flat rect intersects nothing at all as far as CoreGraphics
        // is concerned, so a perfectly straight stroke would cull itself away.
        let halfWidth = max(stroke.style.lineWidth / 2, 0.5)
        return stroke.canvasBounds
            .insetBy(dx: -halfWidth, dy: -halfWidth)
            .offsetBy(dx: offset.x, dy: offset.y)
    }

    /// Widths are canvas-space values and the context already carries the zoom,
    /// so the stored width is handed over as-is — the transform magnifies it
    /// along with the geometry.
    static func stroke(_ ink: ResolvedInkStroke, in context: inout GraphicsContext) {
        context.stroke(
            ink.path,
            with: .color(ink.color),
            style: SwiftUI.StrokeStyle(
                lineWidth: ink.lineWidth,
                lineCap: .round,
                lineJoin: .round
            )
        )
    }
}
