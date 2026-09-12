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
    /// Where the automatic layout has moved each problem's work to. Applied the
    /// same way the selection drag is — at draw time, never written into the
    /// ink — so the arrangement costs no data churn and can be switched off
    /// exactly.
    var placement: ProblemLayoutPlacement = .identity
    /// The shift the stroke under the pencil is being drawn at, which is the
    /// one belonging to the problem it is being filed under.
    var activePlacementOffset: CGPoint = .zero

    var body: some View {
        ZStack {
            CommittedInkLayer(
                strokes: strokes,
                transform: transform,
                selectedStrokeIDs: selectedStrokeIDs,
                selectionOffset: selectionOffset,
                problemInk: problemInk,
                placement: placement
            )
            ActiveInkLayer(
                stroke: activeStroke,
                transform: transform,
                placementOffset: activePlacementOffset
            )
        }
    }
}

/// One stroke resolved for painting: the path to trace, how to paint it, and
/// how far it is being shifted from where it is stored.
///
/// The shift is one value rather than one per source, because the two sources
/// compose: ink dragged inside a problem the grid has moved carries both the
/// arrangement's offset and the live drag's.
private struct ResolvedInkStroke {
    let path: Path
    let color: Color
    let lineWidth: CGFloat
    let offset: CGPoint
}

/// Every stroke already on the page.
private struct CommittedInkLayer: View {
    let strokes: [Stroke]
    let transform: CanvasTransform
    let selectedStrokeIDs: Set<UUID>
    let selectionOffset: CGPoint
    let problemInk: ProblemInkStyling
    let placement: ProblemLayoutPlacement

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
        // Hashing a UUID per stroke per repaint is not free, and the layout is
        // off for most documents most of the time.
        let isArranged = !placement.isIdentity

        for stroke in strokes {
            guard InkDrawing.isDrawable(stroke) else { continue }
            let dragOffset = selectedStrokeIDs.contains(stroke.id) ? selectionOffset : .zero
            let offset = isArranged ? placement.offset(for: stroke) + dragOffset : dragOffset
            // Culled against where the mark is actually painted, not where it
            // is stored — an arranged problem can be a long way from its own
            // coordinates, and culling on those would blank it.
            guard InkDrawing.bounds(of: stroke, offsetBy: offset).intersects(visibleCanvasRect)
            else { continue }

            visibleInk.append(ResolvedInkStroke(
                path: pathCache.path(for: stroke),
                color: problemInk.color(for: stroke).opacity(problemInk.opacity(for: stroke)),
                lineWidth: stroke.style.lineWidth,
                offset: offset
            ))
        }
        pruneCacheIfStale()
        return visibleInk
    }

    private func paint(_ visibleInk: [ResolvedInkStroke], in context: inout GraphicsContext) {
        context.concatenate(transform.matrix)

        for ink in visibleInk {
            guard ink.offset != .zero else {
                InkDrawing.stroke(ink, in: &context)
                continue
            }
            // A copy of the context carrying this stroke's shift.
            // `GraphicsContext` is a value, so translating a copy leaves the
            // shared transform alone and every stroke is still painted in the
            // one pass, whatever it is offset by.
            var shiftedContext = context
            shiftedContext.translateBy(x: ink.offset.x, y: ink.offset.y)
            InkDrawing.stroke(ink, in: &shiftedContext)
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
    /// The arrangement's shift for the problem this stroke is being filed
    /// under. Samples are stored with it taken off, so it has to go back on
    /// here or the mark would appear away from the nib that is making it.
    var placementOffset: CGPoint = .zero

    var body: some View {
        Canvas { context, _ in
            guard let stroke, InkDrawing.isDrawable(stroke) else { return }
            context.concatenate(transform.matrix)
            context.translateBy(x: placementOffset.x, y: placementOffset.y)
            // Never cached: by definition this path changes on every sample.
            InkDrawing.stroke(
                ResolvedInkStroke(
                    path: StrokePathCache.makePath(for: stroke),
                    color: stroke.style.swiftUIColor,
                    lineWidth: stroke.style.lineWidth,
                    offset: .zero
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
