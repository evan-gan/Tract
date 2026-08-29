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

    /// Replaces all canvas state with a document loaded from disk. Undo history
    /// belongs to the editing session, not the document, so it starts empty:
    /// there is nothing sensible for a first undo to go back to.
    func restore(strokes loadedStrokes: [Stroke], origin: CGPoint, scale: CGFloat) {
        strokes = loadedStrokes
        activeStroke = nil
        undoStack.removeAll()
        redoStack.removeAll()
        clearSelection()
        canvasTransform.scale = scale
        canvasTransform.translation = origin
        revision = 0
    }

    // MARK: - Tool state
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

    // MARK: - Canvas navigation
    var canvasTransform = CanvasTransform()

    // MARK: - Pencil hover
    /// Where the pencil is hovering above the glass, in screen space, or `nil`
    /// when it is out of range or already touching down.
    private(set) var pencilHoverLocation: CGPoint?

    /// Diameter the hover preview should be drawn at, in screen points. The width
    /// lives in canvas space, so the preview scales with the zoom — what you see
    /// hovering is the size the mark will actually be.
    var pencilPreviewDiameter: CGFloat {
        canvasTransform.toScreen(length: strokeWidth)
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

    var selectedStrokes: [Stroke] {
        strokes.filter { selectedStrokeIDs.contains($0.id) }
    }

    func clearSelection() {
        selectedStrokeIDs.removeAll()
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

    // MARK: - Stroke lifecycle

    func beginStroke(with point: StrokePoint) {
        // The nib is on the glass now, so there is nothing left to preview.
        pencilHoverLocation = nil
        switch activeTool {
        case .pen: beginInkStroke(with: point)
        case .eraser: beginErase(at: point.position)
        case .lasso: beginLasso(at: point.position)
        }
    }

    func continueStroke(with point: StrokePoint) {
        switch activeTool {
        case .pen: activeStroke?.appendPoint(point)
        case .eraser: continueErase(to: point.position)
        case .lasso: lassoPath.append(point.position)
        }
    }

    func endStroke() {
        switch activeTool {
        case .pen: commitInkStroke()
        case .eraser: endErase()
        case .lasso: commitLassoSelection()
        }
    }

    func cancelStroke() {
        activeStroke = nil
        lassoPath.removeAll()
        lastErasePoint = nil
        strokesBeforeErase = nil
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
        var stroke = Stroke(sessionID: sessionID, style: currentStyle())
        stroke.appendPoint(point)
        activeStroke = stroke
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
        lastErasePoint = canvasPoint
        strokes.removeAll { StrokeGeometry.stroke($0, isCrossedBy: previousPoint, canvasPoint) }
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
