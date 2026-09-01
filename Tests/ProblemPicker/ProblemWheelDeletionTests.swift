import Testing
import Foundation
@testable import Tract

@Suite("Deleting a problem from a held wheel row")
@MainActor
struct ProblemWheelDeletionTests {
    /// Builds problems 1, 2, 3 and leaves the picker on problem 1.
    private func pickerWithThreeProblems() -> ProblemTaggingModel {
        let picker = ProblemTaggingModel()
        for siblingIndex in 0 ..< 3 { picker.selectOption(siblingIndex, atLevel: 0) }
        picker.selectOption(0, atLevel: 0)
        return picker
    }

    @Test("The confirmation is named after the address it would remove")
    func theConfirmationNamesTheProblem() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)
        picker.selectOption(0, atLevel: 1)   // 1a
        picker.selectOption(1, atLevel: 1)   // 1b

        #expect(picker.deletionLabel(for: 1, atLevel: 1) == "1.b")
    }

    @Test("The dash and the uncreated row have nothing to delete")
    func rowsWithoutANodeCannotBeDeleted() {
        let picker = pickerWithThreeProblems()

        #expect(!picker.canDelete(ProblemWheelOption.noneID, atLevel: 0))
        #expect(!picker.canDelete(3, atLevel: 0))   // the uncreated fourth problem
        #expect(picker.canDelete(2, atLevel: 0))
    }

    @Test("Deleting a problem renumbers the ones after it")
    func deletingRenumbersTheSiblingsBelow() {
        let picker = pickerWithThreeProblems()

        picker.deleteNode(1, atLevel: 0)   // problem 2

        #expect(picker.outline.roots.count == 2)
        #expect(picker.wheelOptions(atLevel: 0).map(\.label) == ["—", "1", "2", "3"])
    }

    @Test("A selection above the deleted problem keeps its node, under its new name")
    func theSelectionFollowsItsOwnNode() {
        let picker = pickerWithThreeProblems()
        picker.selectOption(2, atLevel: 0)   // on problem 3

        picker.deleteNode(0, atLevel: 0)     // remove problem 1

        // The node that was 3 is 2 now; the picker is still pointed at it.
        #expect(picker.selectedTag == ProblemTag([.number(2)]))
    }

    @Test("Deleting the selected problem leaves the picker on its parent")
    func deletingTheSelectionFallsBackToTheParent() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)
        picker.selectOption(0, atLevel: 1)   // 1a

        picker.deleteNode(0, atLevel: 1)

        #expect(picker.selectedTag == ProblemTag([.number(1)]))
    }

    @Test("Deleting the last problem leaves new ink untagged")
    func deletingEverythingUntags() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)

        picker.deleteNode(0, atLevel: 0)

        #expect(picker.selectedTag == nil)
        #expect(picker.outline.isEmpty)
    }

    @Test("A delete takes the whole subtree, and is reported for saving")
    func deletingTakesTheSubtreeAndIsSaved() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)
        picker.selectOption(0, atLevel: 1)
        picker.selectOption(0, atLevel: 2)   // 1a.I
        var edits = 0
        picker.onOutlineChanged = { edits += 1 }

        picker.deleteNode(0, atLevel: 0)     // problem 1, parts and all

        #expect(picker.outline.isEmpty)
        #expect(edits == 1)
    }
}
