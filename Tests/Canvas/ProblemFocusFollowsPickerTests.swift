import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Picking another problem in the wheel while one is focused has to move the
/// focus with it: close the current box, and open the new problem's only if it
/// has ink to open around.
@Suite("The focus follows the problem picker")
@MainActor
struct ProblemFocusFollowsPickerTests {

    /// Two inked problems far apart, an empty third, the page arranged, and the
    /// first focused with the wheel pointed at it.
    private func focusedCanvas() -> (CanvasViewModel, first: UUID, second: UUID) {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)
        let first = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(viewModel, from: .zero, to: CGPoint(x: 100, y: 0))

        viewModel.problems.selectOption(1, atLevel: 0)
        let second = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 0, y: 2000), to: CGPoint(x: 100, y: 2000))

        viewModel.toggleProblemLayout()
        viewModel.problems.selectOption(0, atLevel: 0)
        viewModel.focusProblem(first)
        return (viewModel, first, second)
    }

    @Test("Picking another problem with ink closes the current box and opens that one")
    func pickingInkedProblemSwitchesFocus() {
        let (viewModel, first, second) = focusedCanvas()

        viewModel.problems.selectOption(1, atLevel: 0)

        #expect(viewModel.problemLayout.focusedNodeID == second)
        #expect(viewModel.problemLayout.closingFrame?.nodeID == first)
    }

    @Test("Picking a problem with no ink just closes the current box")
    func pickingEmptyProblemClosesFocus() {
        let (viewModel, _, _) = focusedCanvas()

        viewModel.problems.selectOption(2, atLevel: 0)   // creates problem 3, which is empty

        #expect(viewModel.problemLayout.focusedNodeID == nil)
    }

    @Test("Setting the wheel back to the dash closes the box")
    func pickingNothingClosesFocus() {
        let (viewModel, _, _) = focusedCanvas()

        viewModel.problems.selectOption(ProblemWheelOption.noneID, atLevel: 0)

        #expect(viewModel.problemLayout.focusedNodeID == nil)
    }

    @Test("Picking a problem while nothing is focused opens nothing")
    func pickingWithoutFocusDoesNothing() {
        let (viewModel, _, _) = focusedCanvas()
        viewModel.exitProblemFocus()

        viewModel.problems.selectOption(1, atLevel: 0)

        #expect(viewModel.problemLayout.focusedNodeID == nil)
    }

    /// A canvas tap selects the node before deciding focus; if that selection
    /// fired the picker hook, the tap would focus the problem and then see it
    /// as "already focused" and close it straight back.
    @Test("Tapping another problem on the canvas focuses it once, not open-then-closed")
    func canvasTapIsNotDoubledByThePickerHook() {
        let (viewModel, first, _) = focusedCanvas()
        viewModel.problems.selectOption(1, atLevel: 0)
        #expect(viewModel.problemLayout.focusedNodeID != first)

        // The animator does not step in a unit test, so stored and drawn
        // positions still agree and the first problem's ink is at the origin.
        viewModel.handleCanvasTap(at: CGPoint(x: 50, y: 0))

        #expect(viewModel.problemLayout.focusedNodeID == first)
    }
}
