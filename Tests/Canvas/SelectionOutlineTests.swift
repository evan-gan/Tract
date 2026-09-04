import Testing
import CoreGraphics
@testable import Tract

/// The frame around a selection is traced by the view model, not by the view
/// that draws it — so it exists the instant the lasso closes, rather than
/// whenever SwiftUI next happens to update.
@Suite("Selection outline")
@MainActor
struct SelectionOutlineTests {

    private func bounds(of contours: [[CGPoint]]) -> CGRect {
        contours.joined().reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    @Test("Closing the lasso traces the frame straight away")
    func lassoTracesTheOutline() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        #expect(viewModel.selectionContours.isEmpty == false)
    }

    @Test("The frame stands off the ink it holds rather than boxing the loop in")
    func outlineHugsTheInk() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        let frame = bounds(of: viewModel.selectionContours)
        let ink = CGRect(x: 20, y: 20, width: 40, height: 40)

        // Standing off the ink, it is bigger than the ink and smaller than the
        // ink plus two full standoffs on each side.
        #expect(frame.contains(ink))
        #expect(frame.width < ink.width + 4 * viewModel.selectionStandoff)
    }

    @Test("Dropping the selection takes its frame with it")
    func clearingSelectionClearsTheOutline() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.clearSelection()
        #expect(viewModel.selectionContours.isEmpty)
    }

    @Test("Deleting the selection leaves no frame behind")
    func deleteClearsTheOutline() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.deleteSelection()
        #expect(viewModel.selectionContours.isEmpty)
    }

    @Test("A committed drag moves the frame with the ink")
    func dragMovesTheOutline() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        let frameBeforeDrag = bounds(of: viewModel.selectionContours)

        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 140, y: 90))
        viewModel.endSelectionDrag()

        let frameAfterDrag = bounds(of: viewModel.selectionContours)
        #expect(frameAfterDrag.origin.x == frameBeforeDrag.origin.x + 100)
        #expect(frameAfterDrag.origin.y == frameBeforeDrag.origin.y + 50)
        #expect(frameAfterDrag.size == frameBeforeDrag.size)
    }

    @Test("Undoing a drag puts the frame back where the ink went")
    func undoRestoresTheOutline() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        let frameBeforeDrag = bounds(of: viewModel.selectionContours)

        viewModel.beginSelectionDrag(at: CGPoint(x: 40, y: 40))
        viewModel.updateSelectionDrag(to: CGPoint(x: 140, y: 90))
        viewModel.endSelectionDrag()
        viewModel.undo()

        let restoredFrame = bounds(of: viewModel.selectionContours)
        #expect(abs(restoredFrame.origin.x - frameBeforeDrag.origin.x) < 1)
        #expect(abs(restoredFrame.origin.y - frameBeforeDrag.origin.y) < 1)
    }

    @Test("Undoing away the selected ink leaves no frame behind")
    func undoingAwayTheInkClearsTheOutline() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.undo()
        #expect(viewModel.hasSelection == false)
        #expect(viewModel.selectionContours.isEmpty)
    }
}
