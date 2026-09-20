import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Re-filing ink under another problem while the page is arranged has to
/// re-flow the grid there and then, not only once focus is left and re-entered.
@Suite("Retagging re-flows the arranged page")
@MainActor
struct ProblemLayoutRetagReflowTests {

    /// Two problems a long way apart, the page arranged, and the first focused.
    private func arrangedCanvas() -> (CanvasViewModel, first: UUID, second: UUID) {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)
        let first = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(viewModel, from: .zero, to: CGPoint(x: 100, y: 0))

        viewModel.problems.selectOption(1, atLevel: 0)
        let second = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 0, y: 2000), to: CGPoint(x: 100, y: 2000))

        viewModel.toggleProblemLayout()
        viewModel.focusProblem(first)
        return (viewModel, first, second)
    }

    /// Picks up the second problem's ink. The animator never steps inside a
    /// unit test, so the live placement is still where it started and the
    /// stored coordinates are also where the ink is drawn.
    private func selectSecondProblem(_ viewModel: CanvasViewModel) {
        #expect(viewModel.handleCanvasDoubleTap(at: CGPoint(x: 50, y: 2000)))
    }

    @Test("Re-filing ink into the focused problem grows its box to take the ink in")
    func reassignIntoFocusedProblemGrowsTheBox() {
        let (viewModel, first, _) = arrangedCanvas()
        let boxBefore = viewModel.problemLayout.focusBox
        selectSecondProblem(viewModel)

        viewModel.reassignSelection(toProblemNode: first)

        #expect(viewModel.problemLayout.focusedNodeID == first)
        #expect(viewModel.problemLayout.focusBox.height > boxBefore.height)
    }

    @Test("Re-filing ink re-arranges the grid without leaving focus")
    func reassignRearrangesTheGrid() {
        let (viewModel, first, _) = arrangedCanvas()
        let placementBefore = viewModel.problemLayout.settledPlacement
        selectSecondProblem(viewModel)

        viewModel.reassignSelection(toProblemNode: first)

        #expect(viewModel.problemLayout.settledPlacement != placementBefore)
        #expect(viewModel.problemLayout.isFocused)
    }

    @Test("Undoing the re-file re-arranges the grid back")
    func undoReflowsBack() {
        let (viewModel, first, _) = arrangedCanvas()
        let boxBefore = viewModel.problemLayout.focusBox
        selectSecondProblem(viewModel)
        viewModel.reassignSelection(toProblemNode: first)

        viewModel.undo()

        #expect(viewModel.problemLayout.focusBox == boxBefore)
    }

    @Test("With the page not arranged, re-filing moves nothing")
    func layoutOffStaysIdentity() {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)
        let first = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(viewModel, from: .zero, to: CGPoint(x: 100, y: 0))
        viewModel.problems.selectOption(1, atLevel: 0)
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 0, y: 2000), to: CGPoint(x: 100, y: 2000))
        selectSecondProblem(viewModel)

        viewModel.reassignSelection(toProblemNode: first)

        #expect(viewModel.problemLayout.settledPlacement.isIdentity)
        #expect(viewModel.hasSelection)
    }
}
