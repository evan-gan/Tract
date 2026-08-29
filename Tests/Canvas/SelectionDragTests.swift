import Testing
import CoreGraphics
@testable import Tract

/// Dragging a lasso selection moves the ink it holds, and only on release.
@Suite("Selection drag")
@MainActor
struct SelectionDragTests {

    private let boxCorners = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    /// A canvas holding one short line inside the box the tests lasso, already
    /// selected and ready to be dragged. `alsoDrawing` adds further lines first,
    /// so a test can check what the drag leaves alone.
    private func canvasWithSelectedLine(alsoDrawing others: [(CGPoint, CGPoint)] = []) -> CanvasViewModel {
        let viewModel = CanvasViewModel()
        drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 60))
        for (start, end) in others {
            drawLine(viewModel, from: start, to: end)
        }

        lassoTheBox(viewModel)
        return viewModel
    }

    private func lassoTheBox(_ viewModel: CanvasViewModel) {
        viewModel.selectTool(.lasso)
        viewModel.beginStroke(with: StrokeFixtures.point(at: boxCorners[0]))
        for corner in boxCorners.dropFirst() {
            viewModel.continueStroke(with: StrokeFixtures.point(at: corner))
        }
        viewModel.endStroke()
    }

    private func drawLine(_ viewModel: CanvasViewModel, from start: CGPoint, to end: CGPoint) {
        viewModel.selectTool(.pen)
        viewModel.beginStroke(with: StrokeFixtures.point(at: start))
        viewModel.continueStroke(with: StrokeFixtures.point(at: end))
        viewModel.endStroke()
    }

    private func firstPointPosition(_ viewModel: CanvasViewModel) -> CGPoint? {
        viewModel.strokes.first?.points.first?.position
    }

    @Test("A point on the selected ink is inside the selection's frame")
    func selectionContainsItsOwnInk() {
        let viewModel = canvasWithSelectedLine()
        #expect(viewModel.selectionContains(CGPoint(x: 40, y: 40)))
    }

    @Test("Blank paper well clear of the ink is outside the selection's frame")
    func selectionExcludesDistantPoints() {
        let viewModel = canvasWithSelectedLine()
        #expect(viewModel.selectionContains(CGPoint(x: 900, y: 900)) == false)
    }

    @Test("Nothing is inside the frame when nothing is selected")
    func emptySelectionContainsNothing() {
        let viewModel = CanvasViewModel()
        #expect(viewModel.selectionContains(CGPoint(x: 40, y: 40)) == false)
    }

    @Test("The standoff is captured at the zoom the selection was made at")
    func standoffFollowsTheZoomAtSelectionTime() {
        let viewModel = CanvasViewModel()
        viewModel.canvasTransform.scale = 2
        drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 60))
        lassoTheBox(viewModel)

        // Half the screen-space standoff in canvas units, because every canvas
        // unit is now two points on screen.
        #expect(viewModel.selectionStandoff == SelectionStyle.standoff / 2)
    }

    @Test("Zooming after selecting leaves the grab region exactly where it was")
    func grabRegionSurvivesZooming() {
        let viewModel = canvasWithSelectedLine()
        // Comfortably inside the standoff, but far outside the much tighter
        // region a live-zoom standoff would give at 4x.
        let besideTheInk = CGPoint(x: 54, y: 26)
        #expect(viewModel.selectionContains(besideTheInk))

        viewModel.canvasTransform.scale = 4
        #expect(viewModel.selectionContains(besideTheInk))
        #expect(viewModel.selectionStandoff == SelectionStyle.standoff)
    }

    @Test("The ink is left alone until the drag is released")
    func inkOnlyMovesOnRelease() {
        let viewModel = canvasWithSelectedLine()
        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 140, y: 90))

        #expect(viewModel.selectionDragOffset == CGPoint(x: 100, y: 50))
        #expect(firstPointPosition(viewModel) == CGPoint(x: 20, y: 20))

        viewModel.endSelectionDrag()
        #expect(firstPointPosition(viewModel) == CGPoint(x: 120, y: 70))
        #expect(viewModel.selectionDragOffset == .zero)
    }

    @Test("Only the selected strokes move")
    func unselectedStrokesStayPut() {
        let distantLine = (CGPoint(x: 400, y: 400), CGPoint(x: 460, y: 460))
        let viewModel = canvasWithSelectedLine(alsoDrawing: [distantLine])
        #expect(viewModel.selectedStrokes.count == 1)

        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 50, y: 40))
        viewModel.endSelectionDrag()

        #expect(firstPointPosition(viewModel) == CGPoint(x: 30, y: 20))
        #expect(viewModel.strokes[1].points[0].position == distantLine.0)
    }

    @Test("A completed move is one undo step")
    func moveUndoesInOneStep() {
        let viewModel = canvasWithSelectedLine()
        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 140, y: 40))
        viewModel.endSelectionDrag()

        viewModel.undo()
        #expect(firstPointPosition(viewModel) == CGPoint(x: 20, y: 20))
    }

    @Test("A drag that never moved is not an edit")
    func stationaryDragIsNotAnEdit() {
        let viewModel = canvasWithSelectedLine()
        let revisionBeforeDrag = viewModel.revision
        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 40, y: 40))
        viewModel.endSelectionDrag()

        #expect(viewModel.revision == revisionBeforeDrag)
        // The line was the only edit, so undoing it must empty the stack.
        viewModel.undo()
        #expect(viewModel.canUndo == false)
    }

    @Test("A cancelled drag leaves the ink where it was")
    func cancelledDragMovesNothing() {
        let viewModel = canvasWithSelectedLine()
        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 200, y: 200))
        viewModel.cancelSelectionDrag()

        #expect(firstPointPosition(viewModel) == CGPoint(x: 20, y: 20))
        #expect(viewModel.isDraggingSelection == false)
    }

    @Test("A pencil landing on the selection drags it instead of starting a new loop")
    func pencilOnSelectionDragsIt() {
        let viewModel = canvasWithSelectedLine()
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 40, y: 40)))
        #expect(viewModel.isDraggingSelection)
        #expect(viewModel.lassoPath.isEmpty)

        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 90, y: 40)))
        viewModel.endStroke()
        #expect(firstPointPosition(viewModel) == CGPoint(x: 70, y: 20))
        #expect(viewModel.hasSelection)
    }

    @Test("A pencil landing on blank paper starts a fresh loop and drops the selection")
    func pencilOffSelectionStartsANewLoop() {
        let viewModel = canvasWithSelectedLine()
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 900, y: 900)))
        #expect(viewModel.isDraggingSelection == false)
        #expect(viewModel.hasSelection == false)
        #expect(viewModel.lassoPath.isEmpty == false)
    }
}
