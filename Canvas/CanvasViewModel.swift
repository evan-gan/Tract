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

    init() {
        // Structural edits to the tree have to reach the disk the same way ink
        // does; the picker has no other route to the autosave.
        problems.onOutlineChanged = { [weak self] in self?.recordEdit() }
    }

    /// How the canvas paints its ink under the tagging modes — a tint per
    /// problem, and the dimming that makes the retag target obvious.
    var problemInkStyling: ProblemInkStyling {
        problems.inkStyling(for: strokes, revision: revision)
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
        var changedAnything = false

        for index in strokes.indices {
            guard strokes[index].style.tool.isDrawingTool,
                  strokes[index].problemNodeID != targetNodeID,
                  StrokeGeometry.stroke(strokes[index], contains: canvasPoint, within: radius)
            else { continue }
            strokes[index].problemNodeID = targetNodeID
            changedAnything = true
        }
        if changedAnything { retagGestureChangedInk = true }
    }

    /// Stroke list as it stood before the current retag gesture, so a sweep is
    /// one undo step — and only if it actually re-filed something.
    private var strokesBeforeRetag: [Stroke]?
    private var retagGestureChangedInk = false
    /// Where the sweep was last tested, so samples that have barely moved can be
    /// dropped before they walk the whole page again.
    private var lastRetagPoint: CGPoint?

    private func beginRetag(at canvasPoint: CGPoint) {
        strokesBeforeRetag = strokes
        retagGestureChangedInk = false
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
            strokesBeforeRetag = nil
            retagGestureChangedInk = false
            lastRetagPoint = nil
        }
        guard retagGestureChangedInk, let before = strokesBeforeRetag else { return }
        undoStack.append(before)
        redoStack.removeAll()
        recordEdit()
    }

    /// Replaces all canvas state with a document loaded from disk. Undo history
    /// belongs to the editing session, not the document, so it starts empty:
    /// there is nothing sensible for a first undo to go back to.
    func restore(
        strokes loadedStrokes: [Stroke],
        outline: ProblemOutline,
        origin: CGPoint,
        scale: CGFloat
    ) {
        strokes = loadedStrokes
        problems.restore(outline: outline)
        activeStroke = nil
        undoStack.removeAll()
        redoStack.removeAll()
        clearSelection()
        canvasTransform.scale = scale
        canvasTransform.translation = origin
        revision = 0
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
    private func retraceSelectionOutline() {
        let polylines = selectedStrokes.map { $0.points.map(\.position) }
        selectionContours = polylines.isEmpty
            ? []
            : SelectionRegion.contours(around: polylines, radius: selectionStandoff)
    }

    /// Whether a canvas point lands inside the selection's frame. It measures
    /// against `selectionStandoff` rather than the live zoom, so what can be
    /// grabbed stays exactly what the user can see framed.
    func selectionContains(_ canvasPoint: CGPoint) -> Bool {
        guard hasSelection else { return false }
        return selectedStrokes.contains {
            StrokeGeometry.stroke($0, contains: canvasPoint, within: selectionStandoff)
        }
    }

    // MARK: - Palette flyout visibility
    // Only one palette flyout may be open at a time, so both flags live here
    // rather than in the buttons that trigger them.
    var isColorPanelVisible: Bool = false
    var isStrokeWeightFlyoutVisible: Bool = false

    func toggleColorPanel() {
        withAnimation(.spring(duration: 0.3)) {
            isStrokeWeightFlyoutVisible = false
            isColorPanelVisible.toggle()
        }
    }

    func toggleStrokeWeightFlyout() {
        withAnimation(.spring(duration: 0.3)) {
            isColorPanelVisible = false
            isStrokeWeightFlyoutVisible.toggle()
        }
    }

    // MARK: - Undo / redo
    private var undoStack: [[Stroke]] = []
    private var redoStack: [[Stroke]] = []

    /// Shared session ID groups strokes from the current drawing session.
    private let sessionID = UUID()

    // MARK: - Gesture scratch state

    /// Where the eraser was last sampled, so each move can be tested as a segment.
    private var lastErasePoint: CGPoint?
    /// Stroke list as it stood before the current erase gesture, pushed onto the
    /// undo stack only if the gesture actually removed something.
    private var strokesBeforeErase: [Stroke]?

    /// Where a selection drag was grabbed, in canvas space, or nil when no drag
    /// is in flight. Doubles as the flag for whether one is.
    private var selectionDragOrigin: CGPoint?
    /// Stroke list as it stood before the current selection drag, so the move can
    /// be undone in one step.
    private var strokesBeforeSelectionDrag: [Stroke]?
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
        lassoPath.removeAll()
        lastErasePoint = nil
        strokesBeforeErase = nil
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
        var stroke = Stroke(
            sessionID: sessionID,
            style: currentStyle(),
            problemNodeID: problems.selectedNodeID
        )
        stroke.appendPoint(point)
        activeStroke = stroke
    }

    /// Adds a sample to the stroke being drawn, unless it landed on top of the
    /// last one — see `minimumSampleScreenSpacing`.
    private func appendInkSample(_ point: StrokePoint) {
        if let lastPosition = activeStroke?.points.last?.position,
           isTooCloseToKeep(point.position, after: lastPosition) {
            return
        }
        activeStroke?.appendPoint(point)
    }

    private func commitInkStroke() {
        guard var stroke = activeStroke else { return }
        stroke.endTime = .now
        stroke.isComplete = true
        activeStroke = nil

        undoStack.append(strokes)
        redoStack.removeAll()
        strokes.append(stroke)
        recordEdit()
    }

    // MARK: - Eraser

    /// The eraser lays down no ink at all: it deletes whole strokes the moment
    /// the gesture crosses them, so there is never an active stroke to render.
    private func beginErase(at canvasPoint: CGPoint) {
        clearSelection()
        activeStroke = nil
        strokesBeforeErase = strokes
        lastErasePoint = canvasPoint
    }

    private func continueErase(to canvasPoint: CGPoint) {
        guard let previousPoint = lastErasePoint else { return }
        // A sub-pixel move cannot reach ink the last sample missed, and the test
        // it would trigger walks every stroke on the page.
        guard !isTooCloseToKeep(canvasPoint, after: previousPoint) else { return }
        lastErasePoint = canvasPoint
        let tipRadius = canvasTransform.toCanvas(length: Self.eraserTipScreenRadius)
        strokes.removeAll {
            StrokeGeometry.stroke($0, isTouchedBy: previousPoint, canvasPoint, tipRadius: tipRadius)
        }
    }

    /// Records one undo entry for the whole gesture, and only if it deleted something.
    private func endErase() {
        defer {
            lastErasePoint = nil
            strokesBeforeErase = nil
        }
        guard let before = strokesBeforeErase, before.count != strokes.count else { return }
        undoStack.append(before)
        redoStack.removeAll()
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
        selectedStrokeIDs = Set(
            strokes.filter { StrokeGeometry.stroke($0, isEnclosedBy: loop) }.map(\.id)
        )
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
        strokesBeforeSelectionDrag = strokes
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
        guard let strokesBeforeDrag = strokesBeforeSelectionDrag,
              let dragOrigin = selectionDragOrigin else { return }
        let wasTap = isTapLikeTouch
        cancelSelectionDrag()

        if wasTap {
            toggleSelectionMenu(at: dragOrigin)
            return
        }
        guard offset != .zero else { return }

        undoStack.append(strokesBeforeDrag)
        redoStack.removeAll()
        for index in strokes.indices where selectedStrokeIDs.contains(strokes[index].id) {
            strokes[index].translate(by: offset)
        }
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
        strokesBeforeSelectionDrag = nil
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

    /// Routes a tap on the canvas while something is selected: on the selection
    /// it offers what can be done with it, anywhere else it drops the selection.
    func handleSelectionTap(at canvasPoint: CGPoint) {
        guard hasSelection else { return }
        if selectionContains(canvasPoint) {
            toggleSelectionMenu(at: canvasPoint)
        } else {
            clearSelection()
        }
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

        undoStack.append(strokes)
        redoStack.removeAll()
        strokes.removeAll { doomedStrokeIDs.contains($0.id) }
        clearSelection()
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

        undoStack.append(strokes)
        redoStack.removeAll()
        for index in strokes.indices where reassignedStrokeIDs.contains(strokes[index].id) {
            strokes[index].problemNodeID = nodeID
        }
        hideSelectionMenu()
        recordEdit()
    }

    // MARK: - Undo / redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
        pruneSelection()
        recordEdit()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
        pruneSelection()
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
}
