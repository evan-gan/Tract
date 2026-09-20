import SwiftUI
import Observation

/// Single source of truth for all canvas state. Every component reads from this
/// or calls methods on it — no component owns canvas state directly.
@Observable
@MainActor
final class CanvasViewModel {
    // MARK: - Stroke state
    var strokes: [Stroke] = []
    var activeStroke: Stroke?

    /// Bumped once per committed change to the ink. `DocumentEditorSession`
    /// watches it to decide when to autosave, so it must be incremented by every
    /// mutation that a reload has to reproduce — and by nothing else, or the app
    /// writes to disk while the user is only looking around.
    private(set) var revision = 0

    private func recordEdit() {
        revision += 1
    }

    // MARK: - Problem tagging

    /// The document's problem tree and which node new ink is filed under. Owned
    /// here because both are canvas state: the tree is document content, and the
    /// selection decides what every stroke laid down next is tagged with.
    let problems = ProblemTaggingModel()

    /// Whether the page is arranged into a grid of problems, and which problem
    /// is open for editing. Canvas state like the tree is: the placement it
    /// resolves to decides where a stroke is drawn and where a touch lands.
    let problemLayout = ProblemLayoutModel()

    init() {
        // Structural edits to the tree have to reach the disk the same way ink
        // does; the picker has no other route to the autosave.
        problems.onOutlineChanged = { [weak self] in self?.recordEdit() }
        // The layout measures the page when it needs to rather than being told,
        // so it can never be working from a stale copy of the ink.
        problemLayout.cellsProvider = { [weak self] in self?.problemLayoutCells ?? [] }
        problemLayout.contoursProvider = { [weak self] nodeID in
            self?.problemRegions.first { $0.nodeID == nodeID }?.contours ?? []
        }
        problems.onPickerSelectionChanged = { [weak self] nodeID in
            self?.followPickedProblem(nodeID)
        }
    }

    // MARK: - Automatic layout

    /// Where each problem's ink is shifted to, right now. Every draw and every
    /// hit test goes through this; it is `.identity` whenever the layout is off,
    /// which is what makes the toggle cost nothing when nobody is using it.
    var problemPlacement: ProblemLayoutPlacement { problemLayout.placement }

    /// How far the ink of the problem a stroke is filed under is shifted.
    func placementOffset(for stroke: Stroke) -> CGPoint {
        problemPlacement.offset(for: stroke)
    }

    /// The shift ink being laid down right now is drawn at.
    ///
    /// While a stroke is in flight this is the offset captured when it started,
    /// not the live one — the same value its samples are being stored against,
    /// so the mark cannot drift away from the nib however the layout moves
    /// underneath it.
    var activePlacementOffset: CGPoint {
        activeStroke != nil
            ? activeStrokePlacementOffset
            : problemPlacement.offset(forNode: problems.selectedNodeID)
    }

    /// The layout shift the stroke under the pencil is being stored against,
    /// fixed for the length of the gesture.
    ///
    /// Captured once rather than read per sample so that every point of one
    /// stroke is stored in the same frame of reference. A stroke whose samples
    /// were stored against two different offsets is kinked — it draws a line
    /// from wherever the offset used to put it to wherever it puts it now.
    @ObservationIgnored private var activeStrokePlacementOffset: CGPoint = .zero

    /// One cell per problem that has ink, measured from the strokes' own cached
    /// boxes rather than from a traced bubble.
    ///
    /// That is the whole reason the grid can keep up with a pen: a stroke
    /// maintains `canvasBounds` as it is drawn, so measuring a page of problems
    /// is a walk over rectangles — no distance field, no marching squares.
    /// Padded by the bubble's own standoff so two problems laid side by side
    /// still have their bubbles clear of one another.
    private var problemLayoutCells: [ProblemLayoutCell] {
        var boundsByNodeID: [UUID: CGRect] = [:]
        for stroke in StrokeRasterizer.inkStrokes(strokes) {
            guard let nodeID = stroke.problemNodeID, !stroke.canvasBounds.isNull else { continue }
            boundsByNodeID[nodeID] = boundsByNodeID[nodeID]?.union(stroke.canvasBounds)
                ?? stroke.canvasBounds
        }
        let padding = ProblemBoundsStyle.padding
        return boundsByNodeID.compactMap { nodeID, bounds in
            guard let path = problems.outline.path(ofNode: nodeID) else { return nil }
            return ProblemLayoutCell(
                nodeID: nodeID,
                path: path,
                bounds: bounds.insetBy(dx: -padding, dy: -padding)
            )
        }
    }

    /// Flips the arrangement on or off. The selection is dropped because its
    /// traced frame describes ink at positions that are about to move.
    func toggleProblemLayout() {
        clearSelection()
        problemLayout.toggle()
    }

    /// Opens a problem for editing, pushing its neighbours clear.
    func focusProblem(_ nodeID: UUID) {
        clearSelection()
        problemLayout.focus(nodeID: nodeID)
    }

    /// Closes the focused problem back onto its own bubble.
    func exitProblemFocus() {
        clearSelection()
        problemLayout.clearFocus()
    }

    /// Moves the focus along with the picker. Only while a problem is focused:
    /// the box closes, and the newly picked problem opens only if it has ink
    /// to open around — an empty one opens on its first stroke instead
    /// (`openBoxForFirstStroke`).
    ///
    /// One cheap pass over the ink per picker change, and nothing at all when
    /// nothing is focused.
    private func followPickedProblem(_ nodeID: UUID?) {
        guard problemLayout.isFocused, nodeID != problemLayout.focusedNodeID else { return }
        if let nodeID, StrokeRasterizer.inkStrokes(strokes).contains(where: { $0.problemNodeID == nodeID }) {
            focusProblem(nodeID)
        } else {
            exitProblemFocus()
        }
    }

    /// Opens a box, animated, when the pen starts the first mark of a problem
    /// that has no place in the arranged grid yet. The layout model rejects
    /// anything else with a dictionary lookup, so every other stroke pays
    /// almost nothing for this.
    private func openBoxForFirstStroke(_ stroke: Stroke) {
        guard problemLayout.isEnabled,
              let nodeID = stroke.problemNodeID,
              nodeID != problemLayout.focusedNodeID,
              !problemLayout.hasGridSlot(for: nodeID),
              let path = problems.outline.path(ofNode: nodeID)
        else { return }
        let padding = ProblemBoundsStyle.padding
        problemLayout.focusUnarrangedProblem(
            nodeID: nodeID,
            path: path,
            inkBounds: stroke.canvasBounds.insetBy(dx: -padding, dy: -padding)
        )
    }

    /// The colour the focus frame is drawn in — the focused problem's own tint,
    /// so the box reads as that problem's room rather than as generic chrome.
    /// A problem with no traced region yet takes its tint from its place in the
    /// outline; the attention red is only for a node the outline has lost.
    func focusFrameTint(forNode nodeID: UUID) -> Color {
        guard let problemIndex = problemRegions.first(where: { $0.nodeID == nodeID })?.problemIndex
                ?? problems.outline.path(ofNode: nodeID)?.first
        else { return AppTint.active }
        return ProblemTintPalette.color(forProblemIndex: problemIndex)
    }

    /// How the canvas paints its ink under the tagging modes — a tint per
    /// problem, and the dimming that makes the retag target obvious.
    var problemInkStyling: ProblemInkStyling {
        problems.inkStyling(for: strokes, revision: revision)
    }

    // MARK: - Problem bounding regions

    /// The shape framing each problem's work on the page, in canvas space.
    ///
    /// Rebuilt only when the ink or the tree changes: the regions are traced from
    /// distance fields, which is far too much work to redo on a frame of a pan,
    /// and they are pure canvas geometry so navigation never invalidates them.
    ///
    /// A rebuild is not a retrace. `ProblemBoundsCache` keeps each problem's
    /// shape against its own ink, so writing in problem 7 retraces problem 7
    /// alone, laying down untagged ink retraces nothing, and a reorder only
    /// relabels what is already traced.
    var problemRegions: [ProblemBounds] {
        let key = ProblemRegionKey(
            revision: revision,
            outline: problems.outline,
            frozenNodeID: problemLayout.focusedNodeID
        )
        if let cachedProblemRegions, cachedProblemRegionKey == key { return cachedProblemRegions }

        let regions = problemBoundsCache.regions(
            in: strokes,
            outline: problems.outline,
            padding: ProblemBoundsStyle.padding,
            curveRadius: ProblemBoundsStyle.curveRadius,
            // The problem being edited keeps the bubble it was last traced
            // with. It is hidden behind the focus frame, so re-tracing it while
            // the user writes would be work that never reaches the screen — it
            // traces once, when the focus is released.
            frozenNodeID: problemLayout.focusedNodeID
        )
        cachedProblemRegionKey = key
        cachedProblemRegions = regions
        return regions
    }

    /// The problem regions in the positions they are actually drawn at — the
    /// traced geometry is stored-space, and the layout shifts it.
    ///
    /// The shift is applied by the view as it projects each point, not here:
    /// translating every contour on every frame of an animation would cost far
    /// more than adding an offset to a point that is being transformed anyway.
    func placementOffset(for region: ProblemBounds) -> CGPoint {
        problemPlacement.offset(forNode: region.nodeID)
    }

    /// The problem region a canvas point lands in, or `nil` for blank paper.
    ///
    /// Regions can overlap where two problems were written close together; the
    /// smallest one wins, because it is the more specific answer to "which
    /// problem is here".
    ///
    /// The point is taken back out of the layout, one problem at a time, so a
    /// tap lands on the problem the user can see rather than on wherever that
    /// problem's ink happens to be stored.
    func problemRegion(containing canvasPoint: CGPoint) -> ProblemBounds? {
        problemRegions
            .filter { $0.contains(canvasPoint - placementOffset(for: $0)) }
            .min { $0.extent.width * $0.extent.height < $1.extent.width * $1.extent.height }
    }

    /// Ignored by observation for the same reason the ink styling cache is: a
    /// cache written while a view reads it must not invalidate that view.
    @ObservationIgnored private var cachedProblemRegionKey: ProblemRegionKey?
    @ObservationIgnored private var cachedProblemRegions: [ProblemBounds]?
    /// The per-problem shape memo behind that array, so only the problem being
    /// written in is retraced when the page changes.
    @ObservationIgnored private var problemBoundsCache = ProblemBoundsCache()

    private struct ProblemRegionKey: Equatable {
        let revision: Int
        let outline: ProblemOutline
        /// Part of the key because freezing changes the answer: releasing a
        /// focus has to retrace the problem that was frozen, and nothing else
        /// about the page need have changed for that to be true.
        let frozenNodeID: UUID?
    }

    /// How close, in screen points, a retag tap has to land to a mark to count
    /// as hitting it. Generous on purpose: the target is handwriting, which is
    /// mostly the white space between thin lines.
    private static let retagHitScreenRadius: CGFloat = 12

    /// Files every stroke under the touch with the current tag. Runs on the
    /// touch that starts the gesture and on every sample after it, so a wrong
    /// tag can be swept away rather than tapped away one mark at a time.
    private func retagStrokes(at canvasPoint: CGPoint) {
        let radius = canvasTransform.toCanvas(length: Self.retagHitScreenRadius)
        let targetNodeID = problems.selectedNodeID
        let placement = problemPlacement

        for index in strokes.indices {
            let offset = placement.offset(for: strokes[index])
            guard strokes[index].style.tool.isDrawingTool,
                  strokes[index].problemNodeID != targetNodeID,
                  StrokeGeometry.stroke(
                      strokes[index],
                      contains: canvasPoint - offset,
                      within: radius
                  )
            else { continue }
            // A stroke already carrying the target is skipped above, so each one
            // is re-filed at most once per sweep and its first tag is the original.
            retagChangesInGesture[strokes[index].id] = CanvasEdit.TagChange(
                from: strokes[index].problemNodeID,
                to: targetNodeID
            )
            strokes[index].problemNodeID = targetNodeID
        }
    }

    /// Every stroke the current retag sweep has re-filed, so the sweep is one
    /// undo step — and only if it actually re-filed something.
    private var retagChangesInGesture: [UUID: CanvasEdit.TagChange] = [:]
    /// Where the sweep was last tested, so samples that have barely moved can be
    /// dropped before they walk the whole page again.
    private var lastRetagPoint: CGPoint?

    private func beginRetag(at canvasPoint: CGPoint) {
        retagChangesInGesture.removeAll()
        lastRetagPoint = canvasPoint
        retagStrokes(at: canvasPoint)
    }

    private func continueRetag(at canvasPoint: CGPoint) {
        if let lastPoint = lastRetagPoint, isTooCloseToKeep(canvasPoint, after: lastPoint) {
            return
        }
        lastRetagPoint = canvasPoint
        retagStrokes(at: canvasPoint)
    }

    private func endRetag() {
        defer {
            retagChangesInGesture.removeAll()
            lastRetagPoint = nil
        }
        guard !retagChangesInGesture.isEmpty else { return }
        pushUndoEntry(.retagged(retagChangesInGesture))
        // Once, at the end of the sweep: re-flowing per sample would slide the
        // page out from under the marks still being swept.
        reflowLayoutAfterRetag()
        recordEdit()
    }

    /// Replaces all canvas state with a document loaded from disk. Undo history
    /// belongs to the editing session, not the document, so it starts empty:
    /// there is nothing sensible for a first undo to go back to.
    func restore(
        strokes loadedStrokes: [Stroke],
        outline: ProblemOutline,
        origin: CGPoint,
        scale: CGFloat,
        background: CanvasBackgroundStyle = .dots
    ) {
        strokes = loadedStrokes
        problems.restore(outline: outline)
        // The arrangement describes one page; it does not follow the user into
        // the next document they open.
        problemLayout.reset()
        backgroundStyle = background
        activeStroke = nil
        undoStack.removeAll()
        redoStack.removeAll()
        clearSelection()
        canvasTransform.scale = scale
        canvasTransform.translation = origin
        revision = 0
    }

    // MARK: - Paper

    /// The sheet the document is drawn on. Document content, not a view setting:
    /// changing it records an edit so the choice is autosaved with the ink.
    private(set) var backgroundStyle: CanvasBackgroundStyle = .dots

    /// Switches the paper, moving the pen off an ink colour the new sheet would
    /// swallow — black on blueprint, white on anything pale. Only those two
    /// defaults are touched; a colour the user picked deliberately is left alone.
    func selectBackgroundStyle(_ style: CanvasBackgroundStyle) {
        guard style != backgroundStyle else { return }
        let wasLightInk = backgroundStyle.needsLightInk
        backgroundStyle = style
        if style.needsLightInk, strokeColor == InkColor.black {
            selectInkColor(InkColor.white)
        } else if wasLightInk, !style.needsLightInk, strokeColor == InkColor.white {
            selectInkColor(InkColor.black)
        }
        recordEdit()
    }

    // MARK: - Tool state

    /// Radius of the eraser's contact patch in *screen* points, so it stays the
    /// same size under the hand at every zoom — like a real eraser, which does
    /// not get bigger because the paper was pushed closer.
    private static let eraserTipScreenRadius: CGFloat = 3

    /// How far a selection touch may travel, in screen points, and how long it
    /// may rest, before it stops counting as a tap. Both have to hold: a tap is
    /// on and off again quickly without going anywhere, and anything else is a
    /// drag that must not pop the action menu open under the moving nib.
    private static let selectionTapMovementLimit: CGFloat = 6
    private static let selectionTapDurationLimit: TimeInterval = 0.4

    var activeTool: ToolType = .pen
    // Black by default: the canvas is white paper, so white ink would be invisible.
    var strokeColor: SIMD4<Float> = InkColor.black
    var strokeWidth: CGFloat = 2.0
    var strokeOpacity: CGFloat = 1.0

    /// Remembered so picking a colour while the eraser or lasso is active can
    /// put the user back on the pen they were last drawing with.
    private var lastDrawingTool: ToolType = .pen

    /// The ink colour the picker should mark as selected, or `nil` when the
    /// active tool lays down no ink and therefore has no colour.
    var selectedInkColor: SIMD4<Float>? {
        activeTool.isDrawingTool ? strokeColor : nil
    }

    func selectTool(_ tool: ToolType) {
        if tool.isDrawingTool { lastDrawingTool = tool }
        // A selection only means something while the lasso is in hand.
        if tool != .lasso { clearSelection() }
        activeTool = tool
    }

    /// Apple Pencil's double tap swaps between the pen and the eraser, and nothing
    /// else. Cycling every tool would land on the lasso mid-drawing, which is
    /// never what a double tap in the middle of a stroke is asking for.
    func togglePencilShortcutTool() {
        selectTool(activeTool == .eraser ? lastDrawingTool : .eraser)
    }

    /// Picking a colour implies drawing with it, so a non-drawing tool hands
    /// back to the last pen rather than leaving the choice with no effect.
    func selectInkColor(_ color: SIMD4<Float>) {
        strokeColor = color
        if !activeTool.isDrawingTool { selectTool(lastDrawingTool) }
    }

    /// Any touch on the paper — finger or pencil — puts the problem wheel away.
    /// It is chrome over the page, and a touch here means the user has gone back
    /// to writing.
    func noteCanvasTouch() {
        problems.collapseWheel()
    }

    // MARK: - Canvas navigation
    var canvasTransform = CanvasTransform()

    /// Size of the canvas view in screen points, reported by the view that hosts
    /// it. Zooming to fit is the only thing that needs it: the drawing can only
    /// be centred against a viewport whose size is known.
    private(set) var viewportSize: CGSize = .zero

    func noteViewportSize(_ size: CGSize) {
        viewportSize = size
    }

    // MARK: - Pencil hover
    /// Where the pencil is hovering above the glass, in screen space, or `nil`
    /// when it is out of range or already touching down.
    private(set) var pencilHoverLocation: CGPoint?

    /// Diameter the hover preview should be drawn at, in screen points — the size
    /// of the mark the nib is about to make, or of the patch the eraser will
    /// clear. Ink widths live in canvas space, so that preview scales with the
    /// zoom; the eraser tip is a screen-space size and stays put.
    var pencilPreviewDiameter: CGFloat {
        activeTool == .eraser
            ? Self.eraserTipScreenRadius * 2
            : canvasTransform.toScreen(length: strokeWidth)
    }

    /// Colour of the hover preview: the ink about to be laid down, or a neutral
    /// marker for tools that lay down none.
    var pencilPreviewColor: Color {
        activeTool.isDrawingTool ? currentStyle().swiftUIColor : Color.gray
    }

    func updatePencilHover(to screenPoint: CGPoint?) {
        pencilHoverLocation = screenPoint
    }

    // MARK: - Selection
    /// The loop the user is currently drawing with the lasso, in canvas space.
    /// Empty whenever no lasso gesture is in flight.
    private(set) var lassoPath: [CGPoint] = []
    private(set) var selectedStrokeIDs: Set<UUID> = []

    var hasSelection: Bool { !selectedStrokeIDs.isEmpty }

    /// The canvas-space standoff the current selection's frame is built with.
    /// Fixed at the zoom the selection was made at rather than tracking the live
    /// zoom, so the frame magnifies with the canvas — like ink does — instead of
    /// having to be re-traced on every frame of a pinch.
    private(set) var selectionStandoff: CGFloat = SelectionStyle.standoff

    var selectedStrokes: [Stroke] {
        strokes.filter { selectedStrokeIDs.contains($0.id) }
    }

    /// The traced frame around the selection, in canvas space — one closed
    /// contour per piece of ink the selection splits into.
    ///
    /// Traced here, once, whenever the selection changes, rather than by the
    /// view that draws it: a view computing it into its own `@State` has to write
    /// that state *during* a view update, and SwiftUI is entitled to drop such a
    /// write. It did, roughly one selection in five — the outline then stayed
    /// invisible until the next pinch happened to invalidate the view.
    private(set) var selectionContours: [[CGPoint]] = []

    /// How far the selection has been dragged so far, in canvas space. The ink
    /// itself is left alone until the drag ends and the renderer offsets the
    /// selected strokes by this instead — which keeps a drag free of array churn,
    /// leaves the outline's traced shape valid throughout, and makes the whole
    /// move a single undo step.
    private(set) var selectionDragOffset: CGPoint = .zero

    var isDraggingSelection: Bool { selectionDragOrigin != nil }

    /// Where the selection's floating action menu is anchored, in canvas space,
    /// or `nil` when it is closed. Canvas space rather than screen space so the
    /// menu stays pinned to the ink it acts on while the canvas moves under it.
    private(set) var selectionMenuAnchor: CGPoint?

    var isSelectionMenuVisible: Bool { selectionMenuAnchor != nil }

    func clearSelection() {
        selectedStrokeIDs.removeAll()
        selectionContours = []
        hideSelectionMenu()
        cancelSelectionDrag()
    }

    /// Rebuilds the selection's frame from the ink it holds. Every path that
    /// changes *which* strokes are selected, or moves them, has to end here — the
    /// frame is otherwise left describing a selection that no longer exists.
    /// Traced in *laid-out* space — where the ink is drawn — rather than where
    /// it is stored, because that is where the user can see the frame and grab
    /// it. A selection spanning two problems the grid has moved apart would
    /// otherwise be framed around a shape that is on screen nowhere.
    private func retraceSelectionOutline() {
        let placement = problemPlacement
        let polylines = selectedStrokes.map { stroke in
            let offset = placement.offset(for: stroke)
            return stroke.points.map { $0.position + offset }
        }
        selectionContours = polylines.isEmpty
            ? []
            : SelectionRegion.contours(around: polylines, radius: selectionStandoff)
    }

    /// Whether a canvas point lands inside the selection's frame. It measures
    /// against `selectionStandoff` rather than the live zoom, so what can be
    /// grabbed stays exactly what the user can see framed.
    func selectionContains(_ canvasPoint: CGPoint) -> Bool {
        guard hasSelection else { return false }
        let placement = problemPlacement
        return selectedStrokes.contains { stroke in
            StrokeGeometry.stroke(
                stroke,
                contains: canvasPoint - placement.offset(for: stroke),
                within: selectionStandoff
            )
        }
    }

    // MARK: - Palette flyout visibility
    // Only one palette flyout may be open at a time, so both flags live here
    // rather than in the buttons that trigger them.
    var isColorPanelVisible: Bool = false
    var isStrokeWeightFlyoutVisible: Bool = false
    var isPaperStyleFlyoutVisible: Bool = false

    func toggleColorPanel() {
        toggleFlyout(\.isColorPanelVisible)
    }

    func toggleStrokeWeightFlyout() {
        toggleFlyout(\.isStrokeWeightFlyoutVisible)
    }

    func togglePaperStyleFlyout() {
        toggleFlyout(\.isPaperStyleFlyoutVisible)
    }

    /// Opens one flyout and shuts the rest — two popovers from the same dock at
    /// once would fight over the same corner of the screen.
    private func toggleFlyout(_ flyout: ReferenceWritableKeyPath<CanvasViewModel, Bool>) {
        withAnimation(.spring(duration: 0.3)) {
            let opening = !self[keyPath: flyout]
            isColorPanelVisible = false
            isStrokeWeightFlyoutVisible = false
            isPaperStyleFlyoutVisible = false
            self[keyPath: flyout] = opening
        }
    }

    // MARK: - Undo / redo
    /// Edits in the order they were made, each able to replay itself either way —
    /// see `CanvasEdit` for why these are not snapshots of the page.
    private var undoStack: [CanvasEdit] = []
    private var redoStack: [CanvasEdit] = []

    /// Shared session ID groups strokes from the current drawing session.
    private let sessionID = UUID()

    // MARK: - Gesture scratch state

    /// Where the eraser was last sampled, so each move can be tested as a segment.
    private var lastErasePoint: CGPoint?
    /// Every stroke the current erase gesture has deleted, in the order it went,
    /// pushed onto the undo stack only if the gesture actually removed something.
    private var strokesErasedInGesture: [CanvasEdit.RemovedStroke] = []

    /// Where a selection drag was grabbed, in canvas space, or nil when no drag
    /// is in flight. Doubles as the flag for whether one is.
    private var selectionDragOrigin: CGPoint?
    /// When the current selection touch landed, so a brief one can be told from a
    /// deliberate press that happened not to move.
    private var selectionDragStartTime: Date?

    // MARK: - Stroke lifecycle

    func beginStroke(with point: StrokePoint) {
        // The nib is on the glass now, so there is nothing left to preview.
        pencilHoverLocation = nil
        // Retagging re-files existing ink, so it takes the nib away from every
        // tool rather than being a fourth one — the pen the user was drawing
        // with is still there when they switch the mode back off.
        if problems.isRetagging {
            beginRetag(at: point.position)
            return
        }
        switch activeTool {
        case .pen: beginInkStroke(with: point)
        case .eraser: beginErase(at: point.position)
        case .lasso: beginLassoOrSelectionDrag(at: point.position)
        }
    }

    /// Every sample UIKit coalesced into one touch event. Taken as a batch so a
    /// 240 Hz burst is one call rather than one per sample.
    func continueStroke(with points: [StrokePoint]) {
        for point in points {
            continueStroke(with: point)
        }
    }

    func continueStroke(with point: StrokePoint) {
        if problems.isRetagging {
            continueRetag(at: point.position)
            return
        }
        switch activeTool {
        case .pen: appendInkSample(point)
        case .eraser: continueErase(to: point.position)
        case .lasso: continueLassoOrSelectionDrag(to: point.position)
        }
    }

    /// How far a sample has to land from the one before it, in *screen* points,
    /// to be worth keeping.
    ///
    /// Apple Pencil reports 240 samples a second, so ordinary handwriting piles
    /// up points a fraction of a pixel apart. Each one costs a path segment on
    /// every frame, a hit test on every erase, and bytes on every save, and none
    /// of them is visible. Measured on screen rather than on the canvas so ink
    /// keeps its detail when the user zooms in to write small.
    private static let minimumSampleScreenSpacing: CGFloat = 0.75

    private func isTooCloseToKeep(_ canvasPoint: CGPoint, after previous: CGPoint) -> Bool {
        canvasTransform.toScreen(length: previous.distance(to: canvasPoint))
            < Self.minimumSampleScreenSpacing
    }

    func endStroke() {
        if problems.isRetagging {
            endRetag()
            return
        }
        switch activeTool {
        case .pen: commitInkStroke()
        case .eraser: endErase()
        case .lasso: endLassoOrSelectionDrag()
        }
    }

    func cancelStroke() {
        activeStroke = nil
        activeStrokePlacementOffset = .zero
        lassoPath.removeAll()
        lastErasePoint = nil
        strokesErasedInGesture.removeAll()
        cancelSelectionDrag()
    }

    /// UIKit refines estimated force/azimuth after the fact, and the update can
    /// land either while the gesture is still in flight or after it has been
    /// committed — so patch whichever stroke actually holds that sample.
    func updateEstimatedPoint(updateIndex: Int, with point: StrokePoint) {
        if activeStroke != nil {
            activeStroke?.updatePoint(at: updateIndex, with: point)
            return
        }
        guard let strokeIndex = strokes.indices.last else { return }
        strokes[strokeIndex].updatePoint(at: updateIndex, with: point)
        recordEdit()
    }

    // MARK: - Pen

    private func beginInkStroke(with point: StrokePoint) {
        clearSelection()
        // Tagged as it is drawn: the picker's selection is what "the problem I
        // am working on" means, so nothing has to be tagged after the fact.
        // Fixed for the whole gesture, and taken from the *settled* layout: a
        // sample stored against a position a running transition is about to
        // leave would be out by however far that run had still to travel.
        activeStrokePlacementOffset = problemLayout.settledPlacement
            .offset(forNode: problems.selectedNodeID)
        var stroke = Stroke(
            sessionID: sessionID,
            style: currentStyle(),
            problemNodeID: problems.selectedNodeID
        )
        stroke.appendPoint(stored(point))
        activeStroke = stroke
        // After the offset is captured: a problem with no grid slot sits at
        // offset zero both before and after its box opens, so the mark stays
        // under the nib.
        openBoxForFirstStroke(stroke)
        noteFocusedInkGrowth()
    }

    /// Adds a sample to the stroke being drawn, unless it landed on top of the
    /// last one — see `minimumSampleScreenSpacing`.
    private func appendInkSample(_ point: StrokePoint) {
        let sample = stored(point)
        if let lastPosition = activeStroke?.points.last?.position,
           isTooCloseToKeep(sample.position, after: lastPosition) {
            return
        }
        activeStroke?.appendPoint(sample)
        noteFocusedInkGrowth()
    }

    /// Takes an incoming sample back out of the automatic layout.
    ///
    /// Touches arrive where the user actually put them, which is where the ink
    /// is *drawn*. The layout shifts a problem's work at draw time, so the same
    /// shift has to come off before the sample is stored — otherwise switching
    /// the arrangement off would scatter everything written while it was on.
    private func stored(_ point: StrokePoint) -> StrokePoint {
        let offset = activeStrokePlacementOffset
        return offset == .zero ? point : point.moved(by: CGPoint(x: -offset.x, y: -offset.y))
    }

    /// Re-measures the focused problem so the box follows ink *away* as well as
    /// in. Called from the edits that can make a problem smaller — undo, redo,
    /// an erase, a delete — which the growing-union inside a pencil gesture
    /// cannot notice.
    private func remeasureFocusedProblem() {
        guard let nodeID = problemLayout.focusedNodeID else { return }
        problemLayout.remeasureFocusedInk(inkBounds(ofProblem: nodeID))
    }

    /// Brings the arrangement back in line after ink has been re-filed under a
    /// different problem. Without it the grid stays as it was measured before
    /// the retag until the user leaves and re-enters focus.
    ///
    /// The selection frame is traced where the ink is drawn, so if the page is
    /// about to move it is dropped — the same thing toggling and focusing do —
    /// and if nothing moves it is only retraced, since the re-filed marks are
    /// now drawn at their new problem's offset.
    private func reflowLayoutAfterRetag() {
        guard problemLayout.isEnabled else { return }
        let placementBefore = problemLayout.settledPlacement
        let focusedInkBounds = problemLayout.focusedNodeID.map(inkBounds(ofProblem:)) ?? .null
        problemLayout.reflowAfterRetag(focusedInkBounds: focusedInkBounds)
        if problemLayout.settledPlacement != placementBefore {
            clearSelection()
        } else if hasSelection {
            retraceSelectionOutline()
        }
    }

    /// The layout follow-up an undone or redone edit needs. A retag changes
    /// which cell ink belongs to and so re-flows the grid; anything else keeps
    /// the grid pinned and only lets the focus box resize.
    private func updateLayout(afterReplaying edit: CanvasEdit) {
        if case .retagged = edit {
            reflowLayoutAfterRetag()
        } else {
            remeasureFocusedProblem()
        }
    }

    /// The canvas-space box one problem's ink covers, in stored space, padded to
    /// match the cells the grid is measured from.
    private func inkBounds(ofProblem nodeID: UUID) -> CGRect {
        let bounds = StrokeRasterizer.inkStrokes(strokes)
            .filter { $0.problemNodeID == nodeID }
            .reduce(CGRect.null) { $0.union($1.canvasBounds) }
        guard !bounds.isNull else { return .null }
        let padding = ProblemBoundsStyle.padding
        return bounds.insetBy(dx: -padding, dy: -padding)
    }

    /// Lets the focus box grow with the writing. Cheap by construction: the
    /// active stroke maintains its own bounds, and the layout ignores a report
    /// that does not actually reach past the box it already has.
    private func noteFocusedInkGrowth() {
        guard problemLayout.isFocused,
              let stroke = activeStroke,
              stroke.problemNodeID == problemLayout.focusedNodeID
        else { return }
        problemLayout.noteFocusedInkBounds(stroke.canvasBounds)
    }

    private func commitInkStroke() {
        guard var stroke = activeStroke else { return }
        stroke.endTime = .now
        stroke.isComplete = true
        activeStroke = nil
        activeStrokePlacementOffset = .zero
        // Pen-up is where the neighbours catch up with the room this problem
        // grew into. Doing it per sample would repaint the whole page per frame.
        problemLayout.settleNeighbours()

        strokes.append(stroke)
        pushUndoEntry(.added([stroke]))
        recordEdit()
    }

    // MARK: - Eraser

    /// The eraser lays down no ink at all: it deletes whole strokes the moment
    /// the gesture crosses them, so there is never an active stroke to render.
    private func beginErase(at canvasPoint: CGPoint) {
        clearSelection()
        activeStroke = nil
        strokesErasedInGesture.removeAll()
        lastErasePoint = canvasPoint
    }

    private func continueErase(to canvasPoint: CGPoint) {
        guard let previousPoint = lastErasePoint else { return }
        // A sub-pixel move cannot reach ink the last sample missed, and the test
        // it would trigger walks every stroke on the page.
        guard !isTooCloseToKeep(canvasPoint, after: previousPoint) else { return }
        lastErasePoint = canvasPoint
        let tipRadius = canvasTransform.toCanvas(length: Self.eraserTipScreenRadius)
        let placement = problemPlacement
        // The swept segment is taken back out of each stroke's own layout
        // shift, so the eraser rubs out the mark the user is touching rather
        // than whatever is stored under that coordinate.
        let erased = CanvasEdit.removeStrokes(from: &strokes) { stroke in
            let offset = placement.offset(for: stroke)
            return StrokeGeometry.stroke(
                stroke,
                isTouchedBy: previousPoint - offset,
                canvasPoint - offset,
                tipRadius: tipRadius
            )
        }
        strokesErasedInGesture.append(contentsOf: erased)
    }

    /// Records one undo entry for the whole gesture, and only if it deleted something.
    private func endErase() {
        defer {
            lastErasePoint = nil
            strokesErasedInGesture.removeAll()
        }
        guard !strokesErasedInGesture.isEmpty else { return }
        pushUndoEntry(.removed(strokesErasedInGesture))
        // Rubbing ink out can shrink the problem, which only a fresh
        // measurement will notice.
        remeasureFocusedProblem()
        recordEdit()
    }

    // MARK: - Lasso

    /// A pencil landing inside an existing selection grabs it; anywhere else
    /// starts a fresh loop — which is also what drops the selection when the user
    /// taps the blank paper, since a tap encloses nothing.
    private func beginLassoOrSelectionDrag(at canvasPoint: CGPoint) {
        if selectionContains(canvasPoint) {
            beginSelectionDrag(at: canvasPoint)
        } else {
            beginLasso(at: canvasPoint)
        }
    }

    private func continueLassoOrSelectionDrag(to canvasPoint: CGPoint) {
        if isDraggingSelection {
            updateSelectionDrag(to: canvasPoint)
        } else {
            appendLassoSample(canvasPoint)
        }
    }

    /// Samples that land on top of one another do not change the loop's shape,
    /// but every one of them is another edge in the enclosure test the lasso runs
    /// against each stroke when it closes.
    private func appendLassoSample(_ canvasPoint: CGPoint) {
        if let lastPoint = lassoPath.last, isTooCloseToKeep(canvasPoint, after: lastPoint) {
            return
        }
        lassoPath.append(canvasPoint)
    }

    private func endLassoOrSelectionDrag() {
        if isDraggingSelection {
            endSelectionDrag()
        } else {
            commitLassoSelection()
        }
    }

    private func beginLasso(at canvasPoint: CGPoint) {
        clearSelection()
        activeStroke = nil
        lassoPath = [canvasPoint]
    }

    /// Closes the loop by joining its two ends and selects every stroke that lies
    /// entirely inside. Selection is not an edit, so it never touches undo.
    private func commitLassoSelection() {
        defer { lassoPath.removeAll() }
        let loop = lassoPath
        guard loop.count >= 3 else { return }
        select(strokeIDs: Set(enclosedStrokeIDs(by: loop)))
    }

    /// Which strokes a traced loop encloses, with the layout accounted for.
    ///
    /// The loop is taken back out of the layout once per *problem* rather than
    /// once per stroke: a page has a handful of problems and can have thousands
    /// of marks, so re-projecting the loop for every stroke would do the same
    /// arithmetic over and over for the same answer.
    private func enclosedStrokeIDs(by loop: [CGPoint]) -> [UUID] {
        let placement = problemPlacement
        var loopsByNodeID: [UUID?: [CGPoint]] = [:]

        return strokes.compactMap { stroke in
            let nodeID = stroke.problemNodeID
            let localLoop: [CGPoint]
            if let cached = loopsByNodeID[nodeID] {
                localLoop = cached
            } else {
                let offset = placement.offset(for: stroke)
                localLoop = offset == .zero ? loop : loop.map { $0 - offset }
                loopsByNodeID[nodeID] = localLoop
            }
            return StrokeGeometry.stroke(stroke, isEnclosedBy: localLoop) ? stroke.id : nil
        }
    }

    /// Makes a set of strokes the live selection, framed and ready to be moved,
    /// deleted or re-filed. Every way of picking ink up ends here, so a
    /// selection made by double-tapping a problem behaves exactly like a lassoed
    /// one. Selection is not an edit, so it never touches undo.
    private func select(strokeIDs: Set<UUID>) {
        hideSelectionMenu()
        cancelSelectionDrag()
        selectedStrokeIDs = strokeIDs
        // Captured once, here: the frame is canvas geometry from now on.
        selectionStandoff = SelectionStyle.standoff / max(canvasTransform.scale, .ulpOfOne)
        retraceSelectionOutline()
    }

    // MARK: - Moving a selection

    /// Picks the selection up at a canvas point. Callers that can start a drag
    /// anywhere — the finger gesture — must check `selectionContains(_:)` first;
    /// this only guards against there being nothing to move at all.
    func beginSelectionDrag(at canvasPoint: CGPoint) {
        guard hasSelection else { return }
        selectionDragOrigin = canvasPoint
        selectionDragStartTime = .now
        selectionDragOffset = .zero
    }

    /// Tracked against the grab point in canvas space rather than by accumulating
    /// deltas, so the selection stays glued to the finger or nib even if the
    /// canvas is zoomed underneath it mid-drag.
    func updateSelectionDrag(to canvasPoint: CGPoint) {
        guard let origin = selectionDragOrigin else { return }
        selectionDragOffset = canvasPoint - origin
        // Once the touch is clearly a drag, an open menu is stale chrome sitting
        // in the way of the ink being moved.
        if hasTravelledBeyondATap { hideSelectionMenu() }
    }

    /// Writes the drag into the ink as one undo step — unless the touch was
    /// really a tap, which asks for the action menu instead of moving anything.
    /// A drag that never actually moved anything is not an edit either, so it
    /// pushes nothing.
    func endSelectionDrag() {
        let offset = selectionDragOffset
        guard let dragOrigin = selectionDragOrigin else { return }
        let wasTap = isTapLikeTouch
        cancelSelectionDrag()

        if wasTap {
            toggleSelectionMenu(at: dragOrigin)
            return
        }
        guard offset != .zero else { return }

        let move = CanvasEdit.moved(strokeIDs: selectedStrokeIDs, offset: offset)
        move.apply(to: &strokes)
        pushUndoEntry(move)
        // The ink moved rigidly, so the frame moves with it — tracing it again
        // would rebuild a distance field to arrive at the same shape.
        selectionContours = selectionContours.map { contour in
            contour.map { $0 + offset }
        }
        recordEdit()
    }

    /// Drops the drag without moving anything — the ink was never touched.
    func cancelSelectionDrag() {
        selectionDragOrigin = nil
        selectionDragStartTime = nil
        selectionDragOffset = .zero
    }

    /// Whether the touch in flight has already moved too far to be a tap. Measured
    /// on screen rather than on the canvas so the same flick of the hand reads the
    /// same way at every zoom.
    private var hasTravelledBeyondATap: Bool {
        let travelledOnScreen = canvasTransform.toScreen(
            length: CGPoint.zero.distance(to: selectionDragOffset)
        )
        return travelledOnScreen > Self.selectionTapMovementLimit
    }

    /// Whether the touch that is ending was a tap: on and off again quickly,
    /// without going anywhere.
    private var isTapLikeTouch: Bool {
        guard let startTime = selectionDragStartTime else { return false }
        return !hasTravelledBeyondATap
            && Date.now.timeIntervalSince(startTime) <= Self.selectionTapDurationLimit
    }

    // MARK: - Selection action menu

    /// Routes a tap on the paper.
    ///
    /// A live selection speaks first, because it is the thing the user is holding:
    /// tapping it offers what can be done with it, tapping off it drops it.
    /// Otherwise the tap is about the problem regions — landing in one points the
    /// picker at that problem, and landing on blank paper outside every region
    /// steps back out of the problem the user was in.
    func handleCanvasTap(at canvasPoint: CGPoint) {
        if hasSelection {
            if selectionContains(canvasPoint) {
                toggleSelectionMenu(at: canvasPoint)
            } else {
                clearSelection()
            }
            return
        }
        if problemLayout.isEnabled {
            handleArrangedCanvasTap(at: canvasPoint)
            return
        }
        if let region = problemRegion(containing: canvasPoint) {
            problems.selectNode(region.nodeID)
        } else if pickedProblemHasRegion {
            problems.clearSelection()
        }
    }

    /// A tap on the paper while the page is arranged into a grid.
    ///
    /// Landing in a problem opens it for editing as well as pointing the picker
    /// at it — the arrangement exists to be worked in, so tapping a problem
    /// means "let me at this one". Landing in the strip of paper outside the
    /// focus box is the way back out, which is the whole reason the box stops
    /// short of the screen edge.
    private func handleArrangedCanvasTap(at canvasPoint: CGPoint) {
        if let region = problemRegion(containing: canvasPoint) {
            problems.selectNode(region.nodeID)
            // Tapping the problem already being edited closes it again. The box
            // is sized to the problem rather than to the screen, so a big
            // problem can fill the view with no strip of paper in reach — this
            // is the exit that is always where the user is already looking.
            if region.nodeID == problemLayout.focusedNodeID {
                exitProblemFocus()
            } else {
                focusProblem(region.nodeID)
            }
            return
        }
        // Inside the box but not on any ink is blank working space belonging to
        // the problem being edited — leaving needs a tap outside it.
        if problemLayout.isFocused, problemLayout.focusBox.contains(canvasPoint) {
            return
        }
        // Blank paper. Stepping out of the box is stepping out of the problem,
        // so the picker lets go of it too and the next stroke is untagged —
        // exactly what a tap on blank paper does when the page is not arranged.
        exitProblemFocus()
        if pickedProblemHasRegion { problems.clearSelection() }
    }

    /// Picks up every mark filed under the problem whose region the point lands
    /// in, exactly as though the user had lassoed it.
    ///
    /// A problem's region is already the visible answer to "this patch of paper
    /// is problem 3", so double-tapping it is the shortest way to grab that work
    /// as a whole — to drag it, delete it, or re-file it under another problem —
    /// without tracing a loop the region has effectively already drawn.
    ///
    /// - Parameter canvasPoint: Where the second tap landed, in canvas space.
    /// - Returns: Whether a region was hit and its ink selected. A double tap on
    ///   blank paper does nothing at all, rather than clearing anything: the
    ///   single tap is what steps out of a problem.
    @discardableResult
    func handleCanvasDoubleTap(at canvasPoint: CGPoint) -> Bool {
        guard let nodeID = problemNode(forDoubleTapAt: canvasPoint) else { return false }
        // The wheel follows the ink that was picked up, so whatever the menu's
        // Reassign is measured against is the problem the user is looking at.
        problems.selectNode(nodeID)
        select(strokeIDs: Set(inkFiled(underProblem: nodeID).map(\.id)))
        return true
    }

    /// The problem a double tap at this point would pick up, or nil where a
    /// double tap means nothing.
    ///
    /// The focus box counts as the focused problem's own even where no bubble
    /// reaches: its bubble is frozen at the shape it had when the box opened,
    /// so new work written in the box — and the room around it — lies outside
    /// the traced region, and the box is what the user sees as the problem.
    func problemNode(forDoubleTapAt canvasPoint: CGPoint) -> UUID? {
        if let region = problemRegion(containing: canvasPoint) { return region.nodeID }
        guard let focusedNodeID = problemLayout.focusedNodeID,
              problemLayout.focusBox.contains(canvasPoint)
        else { return nil }
        return focusedNodeID
    }

    /// The ink a problem's region was traced from — drawing tools only, and never
    /// a single-sample tap, matching what `ProblemBoundsCache` frames. Anything
    /// else would put marks in the selection that the user cannot see framed.
    private func inkFiled(underProblem nodeID: UUID) -> [Stroke] {
        StrokeRasterizer.inkStrokes(strokes).filter { $0.problemNodeID == nodeID }
    }

    /// Whether the problem the picker is pointed at is one the user can see
    /// framed on the page.
    ///
    /// Only then is a tap on blank paper an exit. A problem picked but not yet
    /// written in has no region to step out of, and the tap is doing the other
    /// thing a touch on the paper does — folding the wheel away — which must not
    /// throw away the tag the next stroke is about to be filed under.
    private var pickedProblemHasRegion: Bool {
        guard let nodeID = problems.selectedNodeID else { return false }
        return problemRegions.contains { $0.nodeID == nodeID }
    }

    /// A second tap closes the menu again, so the user is never stuck with
    /// chrome over their drawing that only a deselect would clear.
    func toggleSelectionMenu(at canvasPoint: CGPoint) {
        withAnimation(.spring(duration: 0.25)) {
            selectionMenuAnchor = isSelectionMenuVisible ? nil : canvasPoint
        }
    }

    func hideSelectionMenu() {
        guard isSelectionMenuVisible else { return }
        withAnimation(.spring(duration: 0.25)) { selectionMenuAnchor = nil }
    }

    /// Removes every selected stroke in one undo step and drops the selection —
    /// there is nothing left for it to frame.
    func deleteSelection() {
        guard hasSelection else { return }
        let doomedStrokeIDs = selectedStrokeIDs

        let removals = CanvasEdit.removeStrokes(from: &strokes) { doomedStrokeIDs.contains($0.id) }
        // A selection whose ink is already gone has nothing to delete, and an
        // empty entry would make the next undo do nothing visible.
        if !removals.isEmpty { pushUndoEntry(.removed(removals)) }
        clearSelection()
        remeasureFocusedProblem()
        recordEdit()
    }

    /// Files every selected stroke under one problem in a single undo step.
    ///
    /// The selection is kept — the ink is still there and the user may want to
    /// move or re-file it again — but the menu closes, because the choice it was
    /// offering has been made.
    func reassignSelection(toProblemNode nodeID: UUID) {
        guard hasSelection else { return }
        let reassignedStrokeIDs = selectedStrokeIDs

        var changes: [UUID: CanvasEdit.TagChange] = [:]
        for stroke in strokes where reassignedStrokeIDs.contains(stroke.id) {
            changes[stroke.id] = CanvasEdit.TagChange(from: stroke.problemNodeID, to: nodeID)
        }
        let retag = CanvasEdit.retagged(changes)
        retag.apply(to: &strokes)
        pushUndoEntry(retag)
        hideSelectionMenu()
        reflowLayoutAfterRetag()
        recordEdit()
    }

    // MARK: - Undo / redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Records a fresh edit. Any redo history is dropped: it described a future
    /// that branched off before this edit and can no longer be replayed onto it.
    private func pushUndoEntry(_ edit: CanvasEdit) {
        undoStack.append(edit)
        redoStack.removeAll()
    }

    func undo() {
        guard let edit = undoStack.popLast() else { return }
        edit.revert(on: &strokes)
        redoStack.append(edit)
        pruneSelection()
        updateLayout(afterReplaying: edit)
        recordEdit()
    }

    func redo() {
        guard let edit = redoStack.popLast() else { return }
        edit.apply(to: &strokes)
        undoStack.append(edit)
        pruneSelection()
        updateLayout(afterReplaying: edit)
        recordEdit()
    }

    /// Drops selected IDs whose strokes no longer exist after an undo or redo.
    private func pruneSelection() {
        guard hasSelection else { return }
        let survivingIDs = Set(strokes.map(\.id))
        selectedStrokeIDs.formIntersection(survivingIDs)
        // An undo can also have moved the surviving ink back, so the frame is
        // retraced even when the selection itself came through unchanged.
        retraceSelectionOutline()
    }

    // MARK: - Helpers

    private func currentStyle() -> StrokeStyle {
        StrokeStyle(
            color: strokeColor,
            lineWidth: strokeWidth,
            opacity: strokeOpacity,
            tool: activeTool
        )
    }

    func resetZoom() {
        withAnimation(.spring(duration: 0.35)) {
            canvasTransform = CanvasTransform()
        }
    }

    /// The canvas-space box every visible mark fits inside, or `nil` when the
    /// document has no ink to aim at. Nib width is included: fitting to the
    /// centrelines alone would clip the outer half of the widest stroke.
    var inkedBounds: CGRect? {
        let inkStrokes = StrokeRasterizer.inkStrokes(strokes)
        guard !inkStrokes.isEmpty else { return nil }
        let bounds = StrokeRasterizer.inkedBounds(of: inkStrokes)
        return bounds.isNull ? nil : bounds
    }

    /// Whether the home button has somewhere to go. An empty document does not:
    /// there is no drawing to centre on.
    ///
    /// Deliberately cheaper than `inkedBounds` — the zoom pill re-evaluates on
    /// every frame of a pinch, and measuring every point of every stroke that
    /// often would make navigation cost more the more the user has drawn.
    var canZoomToFitDrawing: Bool {
        viewportSize.width > 0
            && strokes.contains { $0.style.tool.isDrawingTool && $0.points.count >= 2 }
    }

    /// Frames the whole drawing: centred in the viewport, zoomed as far in as it
    /// will go. Does nothing when there is no ink, so a stray tap on an empty
    /// canvas cannot throw the view somewhere arbitrary.
    func zoomToFitDrawing() {
        guard
            let bounds = inkedBounds,
            let fitted = CanvasTransform.fitting(bounds, inViewOfSize: viewportSize)
        else { return }

        withAnimation(.spring(duration: 0.35)) {
            canvasTransform = fitted
        }
    }
}
