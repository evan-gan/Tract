import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Double-tapping a problem's region picks that problem's whole answer up as a
/// selection — the same selection a lasso around it would have made, so the
/// drag, delete and reassign actions all apply to it unchanged.
@Suite("Double tap selects a problem's ink")
@MainActor
struct ProblemDoubleTapSelectionTests {

    /// Two problems, each with a line of work far enough apart that no tap can
    /// land in both regions. Returns the canvas and the two node ids, in order.
    private func canvasWithTwoProblems() -> (CanvasViewModel, first: UUID, second: UUID) {
        let viewModel = CanvasViewModel()

        viewModel.problems.selectOption(0, atLevel: 0)
        let first = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(viewModel, from: .zero, to: CGPoint(x: 100, y: 0))

        viewModel.problems.selectOption(1, atLevel: 0)
        let second = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(
            viewModel,
            from: CGPoint(x: 0, y: 2000),
            to: CGPoint(x: 100, y: 2000)
        )
        return (viewModel, first, second)
    }

    /// A point inside the first problem's region.
    private let insideFirstProblem = CGPoint(x: 50, y: 0)
    /// Comfortably outside both regions, whatever padding they were built with.
    private let blankPaper = CGPoint(x: 5000, y: 5000)

    @Test("Every mark filed under the double-tapped problem ends up selected")
    func selectsTheWholeProblem() {
        let (viewModel, first, _) = canvasWithTwoProblems()
        // A second mark in the same problem: the whole answer is picked up, not
        // just the stroke nearest the tap.
        viewModel.problems.selectNode(first)
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 0, y: 40), to: CGPoint(x: 100, y: 40))

        #expect(viewModel.handleCanvasDoubleTap(at: insideFirstProblem))

        let expected = Set(viewModel.strokes.filter { $0.problemNodeID == first }.map(\.id))
        #expect(viewModel.selectedStrokeIDs == expected)
        #expect(expected.count == 2)
    }

    @Test("Another problem's work is left where it is")
    func leavesOtherProblemsAlone() {
        let (viewModel, _, second) = canvasWithTwoProblems()

        viewModel.handleCanvasDoubleTap(at: insideFirstProblem)

        let otherIDs = Set(viewModel.strokes.filter { $0.problemNodeID == second }.map(\.id))
        #expect(viewModel.selectedStrokeIDs.isDisjoint(with: otherIDs))
    }

    @Test("The selection is framed, so the user can see what they picked up")
    func tracesTheSelectionOutline() {
        let (viewModel, _, _) = canvasWithTwoProblems()

        viewModel.handleCanvasDoubleTap(at: insideFirstProblem)

        #expect(viewModel.hasSelection)
        #expect(viewModel.selectionContours.isEmpty == false)
    }

    @Test("The picker follows the ink that was picked up")
    func pointsThePickerAtTheProblem() {
        let (viewModel, first, second) = canvasWithTwoProblems()
        #expect(viewModel.problems.selectedNodeID == second)

        viewModel.handleCanvasDoubleTap(at: insideFirstProblem)

        #expect(viewModel.problems.selectedNodeID == first)
    }

    @Test("The selection can be dragged, exactly as a lassoed one can")
    func theSelectionIsDraggable() {
        let (viewModel, first, _) = canvasWithTwoProblems()
        viewModel.handleCanvasDoubleTap(at: insideFirstProblem)
        let before = viewModel.strokes.first { $0.problemNodeID == first }!.points[0].position

        viewModel.beginSelectionDrag(at: insideFirstProblem)
        viewModel.updateSelectionDrag(to: CGPoint(x: 90, y: 30))
        viewModel.endSelectionDrag()

        let after = viewModel.strokes.first { $0.problemNodeID == first }!.points[0].position
        #expect(after.x == before.x + 40)
        #expect(after.y == before.y + 30)
    }

    @Test("The selection can be deleted, taking the whole answer with it")
    func theSelectionIsDeletable() {
        let (viewModel, first, _) = canvasWithTwoProblems()
        viewModel.handleCanvasDoubleTap(at: insideFirstProblem)

        viewModel.deleteSelection()

        #expect(viewModel.strokes.contains { $0.problemNodeID == first } == false)
    }

    @Test("A double tap on blank paper selects nothing and clears nothing")
    func blankPaperDoesNothing() {
        let (viewModel, _, second) = canvasWithTwoProblems()

        #expect(viewModel.handleCanvasDoubleTap(at: blankPaper) == false)

        #expect(viewModel.hasSelection == false)
        // The single tap is what steps out of a problem; a double tap that hit
        // nothing must not take the picked tag with it.
        #expect(viewModel.problems.selectedNodeID == second)
    }

    @Test("Double-tapping a second problem replaces the first selection")
    func replacesAnEarlierSelection() {
        let (viewModel, _, second) = canvasWithTwoProblems()
        viewModel.handleCanvasDoubleTap(at: insideFirstProblem)
        // The menu a tap on that selection opened is stale once the selection
        // moves to another problem.
        viewModel.toggleSelectionMenu(at: insideFirstProblem)

        viewModel.handleCanvasDoubleTap(at: CGPoint(x: 50, y: 2000))

        let expected = Set(viewModel.strokes.filter { $0.problemNodeID == second }.map(\.id))
        #expect(viewModel.selectedStrokeIDs == expected)
        #expect(viewModel.isSelectionMenuVisible == false)
    }
}
