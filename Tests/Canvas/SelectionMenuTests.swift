import Testing
import CoreGraphics
@testable import Tract

/// Tapping a selection offers what can be done with it; dragging it must not.
@Suite("Selection action menu")
@MainActor
struct SelectionMenuTests {

    private func canvasWithSelectedLine(alsoDrawing others: [(CGPoint, CGPoint)] = []) -> CanvasViewModel {
        SelectionFixtures.canvasWithSelectedLine(alsoDrawing: others)
    }

    private func drawLine(_ viewModel: CanvasViewModel, from start: CGPoint, to end: CGPoint) {
        SelectionFixtures.drawLine(viewModel, from: start, to: end)
    }

    // MARK: - Opening and closing

    @Test("Tapping the selection opens the action menu at the tap")
    func tapOnSelectionOpensMenu() {
        let viewModel = canvasWithSelectedLine()
        viewModel.handleSelectionTap(at: CGPoint(x: 40, y: 40))

        #expect(viewModel.isSelectionMenuVisible)
        #expect(viewModel.selectionMenuAnchor == CGPoint(x: 40, y: 40))
    }

    @Test("Tapping the selection again closes the menu")
    func secondTapClosesMenu() {
        let viewModel = canvasWithSelectedLine()
        viewModel.handleSelectionTap(at: CGPoint(x: 40, y: 40))
        viewModel.handleSelectionTap(at: CGPoint(x: 40, y: 40))

        #expect(viewModel.isSelectionMenuVisible == false)
    }

    @Test("Tapping off the selection drops it instead of offering a menu")
    func tapOffSelectionDeselects() {
        let viewModel = canvasWithSelectedLine()
        viewModel.handleSelectionTap(at: CGPoint(x: 900, y: 900))

        #expect(viewModel.hasSelection == false)
        #expect(viewModel.isSelectionMenuVisible == false)
    }

    @Test("A tap with nothing selected does nothing")
    func tapWithoutSelectionDoesNothing() {
        let viewModel = CanvasViewModel()
        viewModel.handleSelectionTap(at: CGPoint(x: 40, y: 40))

        #expect(viewModel.isSelectionMenuVisible == false)
    }

    @Test("Dropping the selection takes the menu with it")
    func clearingSelectionClosesMenu() {
        let viewModel = canvasWithSelectedLine()
        viewModel.handleSelectionTap(at: CGPoint(x: 40, y: 40))
        viewModel.clearSelection()

        #expect(viewModel.isSelectionMenuVisible == false)
    }

    // MARK: - Tap versus drag

    @Test("A pencil touch that goes down and straight back up opens the menu")
    func stationaryTouchIsATap() {
        let viewModel = canvasWithSelectedLine()
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 40, y: 40)))
        viewModel.endStroke()

        #expect(viewModel.isSelectionMenuVisible)
        #expect(viewModel.selectionMenuAnchor == CGPoint(x: 40, y: 40))
    }

    @Test("Dragging the selection moves it and opens no menu")
    func dragDoesNotOpenMenu() {
        let viewModel = canvasWithSelectedLine()
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 40, y: 40)))
        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 140, y: 40)))
        viewModel.endStroke()

        #expect(viewModel.isSelectionMenuVisible == false)
        #expect(viewModel.strokes.first?.points.first?.position == CGPoint(x: 120, y: 20))
    }

    @Test("A drag closes a menu that was already open")
    func dragClosesAnOpenMenu() {
        let viewModel = canvasWithSelectedLine()
        viewModel.handleSelectionTap(at: CGPoint(x: 40, y: 40))

        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 140, y: 40))
        #expect(viewModel.isSelectionMenuVisible == false)

        viewModel.endSelectionDrag()
        #expect(viewModel.isSelectionMenuVisible == false)
    }

    @Test("A tap does not nudge the ink it lands on")
    func tapLeavesInkWhereItIs() {
        let viewModel = canvasWithSelectedLine()
        let revisionBeforeTap = viewModel.revision
        // A hand is never perfectly still: a couple of points of jitter is a tap.
        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 42, y: 41))
        viewModel.endSelectionDrag()

        #expect(viewModel.strokes.first?.points.first?.position == CGPoint(x: 20, y: 20))
        #expect(viewModel.revision == revisionBeforeTap)
        #expect(viewModel.isSelectionMenuVisible)
    }

    // MARK: - Delete

    @Test("Deleting the selection removes exactly the selected strokes")
    func deleteRemovesOnlySelectedStrokes() {
        let distantLine = (CGPoint(x: 400, y: 400), CGPoint(x: 460, y: 460))
        let viewModel = canvasWithSelectedLine(alsoDrawing: [distantLine])
        viewModel.deleteSelection()

        #expect(viewModel.strokes.count == 1)
        #expect(viewModel.strokes[0].points[0].position == distantLine.0)
    }

    @Test("A delete leaves nothing selected and no menu on screen")
    func deleteClearsSelectionAndMenu() {
        let viewModel = canvasWithSelectedLine()
        viewModel.handleSelectionTap(at: CGPoint(x: 40, y: 40))
        viewModel.deleteSelection()

        #expect(viewModel.hasSelection == false)
        #expect(viewModel.isSelectionMenuVisible == false)
    }

    @Test("Undo brings back everything a delete removed, in one step")
    func undoRestoresDeletedStrokes() {
        let viewModel = canvasWithSelectedLine()
        viewModel.deleteSelection()
        viewModel.undo()

        #expect(viewModel.strokes.count == 1)
        #expect(viewModel.strokes[0].points[0].position == CGPoint(x: 20, y: 20))
    }

    @Test("A delete is an edit the document has to save")
    func deleteIsRecordedAsAnEdit() {
        let viewModel = canvasWithSelectedLine()
        let revisionBeforeDelete = viewModel.revision
        viewModel.deleteSelection()

        #expect(viewModel.revision > revisionBeforeDelete)
    }

    @Test("Deleting with nothing selected changes nothing")
    func deleteWithoutSelectionDoesNothing() {
        let viewModel = CanvasViewModel()
        drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 60))
        let revisionBeforeDelete = viewModel.revision
        viewModel.deleteSelection()

        #expect(viewModel.strokes.count == 1)
        #expect(viewModel.revision == revisionBeforeDelete)
    }
}
