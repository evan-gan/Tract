import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// The lasso menu's "Reassign": filing a whole selection under a different
/// problem in one step, rather than sweeping over it in retag mode.
@Suite("Reassigning a selection to another problem")
@MainActor
struct SelectionReassignTests {

    /// A canvas with two problems in its tree, a line drawn under the first, and
    /// that line selected. Returns the node ids of problems 1 and 2.
    private func canvasWithTwoProblems() -> (CanvasViewModel, first: UUID, second: UUID) {
        let viewModel = CanvasViewModel()
        // Landing on the uncreated row is how the wheel grows the tree.
        viewModel.problems.selectOption(0, atLevel: 0)
        let firstProblemID = viewModel.problems.selectedNodeID!
        viewModel.problems.selectOption(1, atLevel: 0)
        let secondProblemID = viewModel.problems.selectedNodeID!

        viewModel.problems.selectOption(0, atLevel: 0)
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 60))
        SelectionFixtures.lassoTheBox(viewModel)
        return (viewModel, firstProblemID, secondProblemID)
    }

    @Test("Reassigning files every selected stroke under the chosen problem")
    func reassignRetagsTheSelection() {
        let (viewModel, first, second) = canvasWithTwoProblems()
        #expect(viewModel.strokes[0].problemNodeID == first)

        viewModel.reassignSelection(toProblemNode: second)

        #expect(viewModel.strokes[0].problemNodeID == second)
    }

    @Test("Ink outside the selection keeps the tag it had")
    func reassignLeavesUnselectedInkAlone() {
        let (viewModel, first, second) = canvasWithTwoProblems()
        SelectionFixtures.drawLine(
            viewModel, from: CGPoint(x: 400, y: 400), to: CGPoint(x: 460, y: 460)
        )
        viewModel.reassignSelection(toProblemNode: second)

        let untouched = viewModel.strokes.first { $0.points[0].position == CGPoint(x: 400, y: 400) }
        #expect(untouched?.problemNodeID == first)
    }

    @Test("Undo puts the whole selection back under its old problem in one step")
    func undoRestoresTheOldTags() {
        let (viewModel, first, second) = canvasWithTwoProblems()
        viewModel.reassignSelection(toProblemNode: second)
        viewModel.undo()

        #expect(viewModel.strokes[0].problemNodeID == first)
    }

    @Test("Reassigning closes the menu but keeps the selection")
    func reassignClosesMenuAndKeepsSelection() {
        let (viewModel, _, second) = canvasWithTwoProblems()
        viewModel.handleSelectionTap(at: CGPoint(x: 40, y: 40))
        viewModel.reassignSelection(toProblemNode: second)

        #expect(viewModel.isSelectionMenuVisible == false)
        #expect(viewModel.hasSelection)
    }

    @Test("A reassign is an edit the document has to save")
    func reassignIsRecordedAsAnEdit() {
        let (viewModel, _, second) = canvasWithTwoProblems()
        let revisionBeforeReassign = viewModel.revision
        viewModel.reassignSelection(toProblemNode: second)

        #expect(viewModel.revision > revisionBeforeReassign)
    }

    @Test("Reassigning with nothing selected changes nothing")
    func reassignWithoutSelectionDoesNothing() {
        let (viewModel, first, second) = canvasWithTwoProblems()
        viewModel.clearSelection()
        let revisionBeforeReassign = viewModel.revision
        viewModel.reassignSelection(toProblemNode: second)

        #expect(viewModel.strokes[0].problemNodeID == first)
        #expect(viewModel.revision == revisionBeforeReassign)
    }

    @Test("The menu offers every problem in the tree, in outline order")
    func outlineRowsAreOfferedInOrder() {
        let (viewModel, first, second) = canvasWithTwoProblems()
        // A lettered part under problem 1, so the order under test is 1, 1.a, 2.
        viewModel.problems.select([0])
        viewModel.problems.selectOption(0, atLevel: 1)

        let rows = viewModel.problems.outline.rows
        let labels = rows.map { ProblemTagFormatter.standard.text(for: viewModel.problems.outline.tag(at: $0.path)) }
        #expect(labels == ["1", "1.a", "2"])
        #expect(rows.first?.id == first)
        #expect(rows.last?.id == second)
    }
}
