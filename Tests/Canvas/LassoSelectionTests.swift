import Testing
import CoreGraphics
@testable import Tract

/// The lasso selects only what it fully encloses, and selecting is not an edit.
@Suite("Lasso selection")
@MainActor
struct LassoSelectionTests {

    /// Draws a short line inside the box the tests lasso, plus one far outside it.
    private func canvasWithTwoLines() -> CanvasViewModel {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.pen)
        drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 60))
        drawLine(viewModel, from: CGPoint(x: 400, y: 400), to: CGPoint(x: 460, y: 460))
        return viewModel
    }

    private func drawLine(_ viewModel: CanvasViewModel, from start: CGPoint, to end: CGPoint) {
        viewModel.selectTool(.pen)
        viewModel.beginStroke(with: StrokeFixtures.point(at: start))
        viewModel.continueStroke(with: StrokeFixtures.point(at: end))
        viewModel.endStroke()
    }

    /// Traces an open loop; the closing edge back to the start is implied, exactly
    /// as it is when the user lifts the pencil.
    private func lasso(_ viewModel: CanvasViewModel, around corners: [CGPoint]) {
        viewModel.selectTool(.lasso)
        viewModel.beginStroke(with: StrokeFixtures.point(at: corners[0]))
        for corner in corners.dropFirst() {
            viewModel.continueStroke(with: StrokeFixtures.point(at: corner))
        }
        viewModel.endStroke()
    }

    private let boxCorners = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    @Test("Only strokes fully inside the loop are selected")
    func selectsEnclosedStrokesOnly() {
        let viewModel = canvasWithTwoLines()
        lasso(viewModel, around: boxCorners)
        #expect(viewModel.selectedStrokes.count == 1)
        #expect(viewModel.selectedStrokes.first?.canvasBounds.maxX == 60)
    }

    @Test("A stroke that only partly overlaps the loop stays unselected")
    func ignoresPartiallyEnclosedStroke() {
        let viewModel = CanvasViewModel()
        drawLine(viewModel, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 400, y: 50))
        lasso(viewModel, around: boxCorners)
        #expect(viewModel.hasSelection == false)
    }

    @Test("Circling the ink twice still selects it")
    func doubleLapLoopSelects() {
        // Hurrying, people go round more than once. Counted by the even-odd rule
        // the second lap would cancel the first and select nothing.
        let viewModel = canvasWithTwoLines()
        lasso(viewModel, around: boxCorners + boxCorners)
        #expect(viewModel.selectedStrokes.count == 1)
    }

    @Test("A loop that overshoots its own start still selects what it went round")
    func selfCrossingLoopSelects() {
        let viewModel = canvasWithTwoLines()
        // Round the box, then past the start and back across the first edge.
        lasso(viewModel, around: boxCorners + [CGPoint(x: -20, y: -20), CGPoint(x: 50, y: -20)])
        #expect(viewModel.selectedStrokes.count == 1)
    }

    @Test("The in-progress loop is cleared once the pencil lifts")
    func loopClearsAfterCommit() {
        let viewModel = canvasWithTwoLines()
        lasso(viewModel, around: boxCorners)
        #expect(viewModel.lassoPath.isEmpty)
    }

    @Test("The lasso adds no stroke and no undo step")
    func lassoIsNotAnEdit() {
        let viewModel = canvasWithTwoLines()
        let strokeCountBeforeLasso = viewModel.strokes.count
        lasso(viewModel, around: boxCorners)
        #expect(viewModel.strokes.count == strokeCountBeforeLasso)
        // Two pen strokes were drawn, so exactly two undo steps should exist.
        viewModel.undo()
        viewModel.undo()
        #expect(viewModel.canUndo == false)
    }

    @Test("Switching to a drawing tool drops the selection")
    func selectionClearsOnToolChange() {
        let viewModel = canvasWithTwoLines()
        lasso(viewModel, around: boxCorners)
        #expect(viewModel.hasSelection)
        viewModel.selectTool(.pen)
        #expect(viewModel.hasSelection == false)
    }

    @Test("Undoing away a selected stroke drops it from the selection")
    func undoPrunesSelection() {
        let viewModel = CanvasViewModel()
        drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 60))
        lasso(viewModel, around: boxCorners)
        #expect(viewModel.hasSelection)
        viewModel.undo()
        #expect(viewModel.hasSelection == false)
    }
}
