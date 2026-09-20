import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// On an arranged page, the first mark of a problem that has no ink yet opens
/// that problem's box — animated, pushing the other problems clear — rather
/// than leaving the new work unframed.
@Suite("The first stroke of a new problem opens its box")
@MainActor
struct ProblemFirstStrokeFocusTests {

    /// One inked problem, the page arranged, and the wheel on a fresh second
    /// problem with no ink.
    private func arrangedCanvasOnEmptyProblem() -> (CanvasViewModel, inked: UUID, empty: UUID) {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)
        let inked = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 0, y: 500), to: CGPoint(x: 100, y: 500))

        viewModel.toggleProblemLayout()
        viewModel.problems.selectOption(1, atLevel: 0)
        return (viewModel, inked, viewModel.problems.selectedNodeID!)
    }

    @Test("Starting to draw in an empty problem focuses it and gives it a box")
    func firstStrokeOpensBox() {
        let (viewModel, _, empty) = arrangedCanvasOnEmptyProblem()

        viewModel.selectTool(.pen)
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 0, y: 0)))

        #expect(viewModel.problemLayout.focusedNodeID == empty)
        #expect(!viewModel.problemLayout.focusBox.isNull)
        #expect(viewModel.problemLayout.focusBubbleLoop.isEmpty == false)
    }

    @Test("The box grows with the stroke and the other problem is pushed clear on pen-up")
    func neighboursArePushedOnPenUp() {
        let (viewModel, inked, _) = arrangedCanvasOnEmptyProblem()
        let inkedOffsetBefore = viewModel.problemLayout.settledPlacement.offset(forNode: inked)

        viewModel.selectTool(.pen)
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 0, y: 0)))
        let boxAtStart = viewModel.problemLayout.focusBox
        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 0, y: 400)))
        viewModel.endStroke()

        #expect(viewModel.problemLayout.focusBox.height > boxAtStart.height)
        #expect(viewModel.problemLayout.settledPlacement.offset(forNode: inked) != inkedOffsetBefore)
    }

    @Test("The new problem's ink is stored where it was drawn")
    func firstStrokeLandsUnderTheNib() {
        let (viewModel, _, _) = arrangedCanvasOnEmptyProblem()

        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 10, y: 20), to: CGPoint(x: 60, y: 20))

        #expect(viewModel.strokes.last?.points.first?.position == CGPoint(x: 10, y: 20))
    }

    @Test("Drawing in a problem that already has a grid slot does not focus it")
    func inkedProblemDoesNotOpen() {
        let (viewModel, inked, _) = arrangedCanvasOnEmptyProblem()
        viewModel.problems.selectOption(0, atLevel: 0)

        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 0, y: 520), to: CGPoint(x: 50, y: 520))

        #expect(viewModel.problemLayout.focusedNodeID != inked)
    }

    @Test("Untagged ink never opens a box")
    func untaggedInkDoesNotOpen() {
        let (viewModel, _, _) = arrangedCanvasOnEmptyProblem()
        viewModel.problems.selectOption(ProblemWheelOption.noneID, atLevel: 0)

        SelectionFixtures.drawLine(viewModel, from: .zero, to: CGPoint(x: 50, y: 0))

        #expect(viewModel.problemLayout.focusedNodeID == nil)
    }

    @Test("With the layout off, a first stroke opens nothing")
    func layoutOffDoesNotOpen() {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)

        SelectionFixtures.drawLine(viewModel, from: .zero, to: CGPoint(x: 50, y: 0))

        #expect(viewModel.problemLayout.focusedNodeID == nil)
    }
}
