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

    // MARK: - Tool state
    var activeTool: ToolType = .pen
    var strokeColor: SIMD4<Float> = InkColor.white
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
        activeTool = tool
    }

    /// Picking a colour implies drawing with it, so a non-drawing tool hands
    /// back to the last pen rather than leaving the choice with no effect.
    func selectInkColor(_ color: SIMD4<Float>) {
        strokeColor = color
        if !activeTool.isDrawingTool { activeTool = lastDrawingTool }
    }


    // MARK: - Canvas navigation
    var canvasTransform = CanvasTransform()

    // MARK: - Selection
    var isSelectionMode: Bool = false
    var selectedStrokeIDs: Set<UUID> = []

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

    // MARK: - Stroke lifecycle

    func beginStroke(at canvasPoint: CGPoint, force: CGFloat, azimuth: CGFloat,
                     altitude: CGFloat, roll: CGFloat,
                     estimatedMask: Int, updateIndex: Int?) {
        let point = StrokePoint(
            position: canvasPoint,
            force: force,
            azimuth: azimuth,
            altitude: altitude,
            rollAngle: roll,
            estimatedPropertiesMask: estimatedMask,
            estimationUpdateIndex: updateIndex
        )
        var stroke = Stroke(sessionID: sessionID, style: currentStyle())
        stroke.appendPoint(point)
        activeStroke = stroke
    }

    func continueStroke(at canvasPoint: CGPoint, force: CGFloat, azimuth: CGFloat,
                        altitude: CGFloat, roll: CGFloat,
                        estimatedMask: Int, updateIndex: Int?) {
        guard activeStroke != nil else { return }
        let point = StrokePoint(
            position: canvasPoint,
            force: force,
            azimuth: azimuth,
            altitude: altitude,
            rollAngle: roll,
            estimatedPropertiesMask: estimatedMask,
            estimationUpdateIndex: updateIndex
        )
        activeStroke?.appendPoint(point)
    }

    func endStroke() {
        guard var stroke = activeStroke else { return }
        stroke.endTime = .now
        stroke.isComplete = true
        activeStroke = nil

        // Save state for undo before committing the new stroke.
        undoStack.append(strokes)
        redoStack.removeAll()

        if stroke.style.tool == .eraser {
            applyErase(bounds: stroke.canvasBounds)
        } else {
            strokes.append(stroke)
        }
    }

    func cancelStroke() {
        activeStroke = nil
    }

    func updateEstimatedPoint(updateIndex: Int, with point: StrokePoint) {
        guard let strokeIndex = strokes.indices.last else { return }
        strokes[strokeIndex].updatePoint(at: updateIndex, with: point)
    }

    // MARK: - Eraser

    /// Removes completed strokes whose bounding box intersects the eraser path.
    private func applyErase(bounds: CGRect) {
        strokes.removeAll { $0.canvasBounds.intersects(bounds) }
    }

    // MARK: - Undo / redo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(strokes)
        strokes = previous
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(strokes)
        strokes = next
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
