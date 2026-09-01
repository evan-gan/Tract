import Testing
import Foundation
@testable import Tract

@Suite("Pointing the picker with the wheel columns")
@MainActor
struct ProblemWheelSelectionTests {
    private func labels(_ options: [ProblemWheelOption]) -> [String] {
        options.map(\.label)
    }

    @Test("A cold picker offers nothing but the first problem to create")
    func emptyTreeOffersOnlyTheFirstProblem() {
        let picker = ProblemTaggingModel()

        #expect(labels(picker.wheelOptions(atLevel: 0)) == ["—", "1"])
        #expect(picker.wheelOptions(atLevel: 0).last?.isUncreated == true)
        // No problem is picked, so there is nothing for a part to belong to.
        #expect(labels(picker.wheelOptions(atLevel: 1)) == ["—"])
        #expect(labels(picker.wheelOptions(atLevel: 2)) == ["—"])
    }

    @Test("Landing on the uncreated row creates that node and selects it")
    func theUncreatedRowCreates() {
        let picker = ProblemTaggingModel()

        picker.selectOption(0, atLevel: 0)

        #expect(picker.selectedTag == ProblemTag([.number(1)]))
        #expect(picker.outline.roots.count == 1)
        // The row that was uncreated is real now, and a new one has appeared
        // past it.
        #expect(labels(picker.wheelOptions(atLevel: 0)) == ["—", "1", "2"])
    }

    @Test("Each column creates at its own level")
    func everyLevelCreatesThroughItsOwnColumn() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)   // 1
        picker.selectOption(0, atLevel: 1)   // 1a
        picker.selectOption(0, atLevel: 2)   // 1a.I

        #expect(picker.selectedTag == ProblemTag([
            .number(1), .lowercaseLetter(1), .uppercaseRoman(1)
        ]))
    }

    @Test("Picking a later row on a column that has room adds the next sibling")
    func creatingSiblingsInARow() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)
        for siblingIndex in 0 ..< 4 { picker.selectOption(siblingIndex, atLevel: 1) }

        #expect(picker.selectedTag == ProblemTag([.number(1), .lowercaseLetter(4)]))
        #expect(labels(picker.wheelOptions(atLevel: 1)) == ["—", "a", "b", "c", "d", "e"])
    }

    @Test("The dash unsets a level, and everything under it")
    func theNoneRowClearsFromThatLevelDown() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)
        picker.selectOption(0, atLevel: 1)
        picker.selectOption(0, atLevel: 2)   // 1a.I

        picker.selectOption(ProblemWheelOption.noneID, atLevel: 1)

        #expect(picker.selectedTag == ProblemTag([.number(1)]))
        // Unsetting navigates; it must not delete the parts already written.
        #expect(labels(picker.wheelOptions(atLevel: 1)) == ["—", "a", "b"])
    }

    @Test("The dash on the first column leaves new ink untagged")
    func theNoneRowOnTheFirstColumnUntags() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)

        picker.selectOption(ProblemWheelOption.noneID, atLevel: 0)

        #expect(picker.selectedTag == nil)
        #expect(picker.selectedNodeID == nil)
    }

    /// A problem opened for the first time this session points at *itself*, parts
    /// or no parts. Walking into a first part on its own would file ink under
    /// "1a" for someone who asked for "1".
    @Test("A problem never opened lands on itself, with its parts on the dash")
    func anUnvisitedProblemLeavesThePartsOnTheDash() {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 2])   // problem 1, already carrying parts a and b
        let picker = ProblemTaggingModel()
        picker.restore(outline: builder.outline)

        picker.selectOption(0, atLevel: 0)

        #expect(picker.selectedTag == ProblemTag([.number(1)]))
        #expect(picker.selectedOptionID(atLevel: 1) == ProblemWheelOption.noneID)
        // Waiting to be told, not hiding anything: the parts are right there.
        #expect(labels(picker.wheelOptions(atLevel: 1)) == ["—", "a", "b", "c"])
    }

    @Test("Coming back to a problem restores the part last worked on")
    func returningToAProblemRestoresItsLastPart() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)                                  // 1
        for siblingIndex in 0 ..< 4 { picker.selectOption(siblingIndex, atLevel: 1) }  // 1d
        picker.selectOption(1, atLevel: 0)                                  // 2, which has no parts
        #expect(picker.selectedTag == ProblemTag([.number(2)]))

        picker.selectOption(0, atLevel: 0)

        #expect(picker.selectedTag == ProblemTag([.number(1), .lowercaseLetter(4)]))
    }

    @Test("The memory runs the whole way down: 1b.II comes back as 1b.II")
    func theMemoryRestoresEveryLevel() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)   // 1
        picker.selectOption(0, atLevel: 1)   // 1a
        picker.selectOption(1, atLevel: 1)   // 1b
        picker.selectOption(0, atLevel: 2)   // 1b.I
        picker.selectOption(1, atLevel: 2)   // 1b.II
        picker.selectOption(1, atLevel: 0)   // away to problem 2

        picker.selectOption(0, atLevel: 0)

        #expect(picker.selectedTag == ProblemTag([
            .number(1), .lowercaseLetter(2), .uppercaseRoman(2)
        ]))
    }

    /// The dash is a choice like any other. Unsetting the letter to tag a whole
    /// problem, then coming back, must not walk into a part again.
    @Test("A level left on the dash comes back as the dash")
    func theDashIsRememberedToo() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)                          // 1
        picker.selectOption(0, atLevel: 1)                          // 1a
        picker.selectOption(ProblemWheelOption.noneID, atLevel: 1)  // back to the problem itself
        picker.selectOption(1, atLevel: 0)                          // away to problem 2

        picker.selectOption(0, atLevel: 0)

        #expect(picker.selectedTag == ProblemTag([.number(1)]))
    }

    /// The memory holds the part's *id*, so the part it points at is the same
    /// work after a reorder renames it.
    @Test("A remembered part that has since been deleted falls back to the dash")
    func aDeletedPartIsForgotten() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)   // 1
        picker.selectOption(0, atLevel: 1)   // 1a
        picker.selectOption(1, atLevel: 0)   // away to problem 2

        picker.selectOption(0, atLevel: 0)   // back on 1a
        #expect(picker.selectedTag == ProblemTag([.number(1), .lowercaseLetter(1)]))
        picker.deleteNode(0, atLevel: 1)
        picker.selectOption(1, atLevel: 0)   // away again

        picker.selectOption(0, atLevel: 0)

        #expect(picker.selectedTag == ProblemTag([.number(1)]))
    }

    @Test("The third level is the last: it offers no fourth column of rows")
    func theDepthLimitStopsAtThreeLevels() {
        let picker = ProblemTaggingModel()
        for level in 0 ... 2 { picker.selectOption(0, atLevel: level) }

        #expect(picker.selectedPath.count == ProblemLevelNotation.maximumDepth)
        // The deepest column still grows sideways — I, II, III — it just has
        // nothing below it.
        #expect(labels(picker.wheelOptions(atLevel: 2)) == ["—", "I", "II"])
    }

    @Test("A column whose parent is unset cannot be pointed anywhere")
    func columnsWithoutAParentAreInert() {
        let picker = ProblemTaggingModel()

        picker.selectOption(0, atLevel: 1)

        #expect(picker.selectedTag == nil)
        #expect(picker.outline.isEmpty)
    }

    @Test("Creating is reported for saving; moving between existing nodes is not")
    func onlyStructuralEditsAreReported() {
        let picker = ProblemTaggingModel()
        var edits = 0
        picker.onOutlineChanged = { edits += 1 }

        picker.selectOption(0, atLevel: 0)   // creates problem 1
        picker.selectOption(1, atLevel: 0)   // creates problem 2
        #expect(edits == 2)

        picker.selectOption(0, atLevel: 0)   // back to problem 1
        picker.selectOption(ProblemWheelOption.noneID, atLevel: 0)

        #expect(edits == 2)
    }

    @Test("Opening a document resets the selection so ink is not misfiled")
    func restoringADocumentClearsTheSelection() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)

        picker.restore(outline: ProblemOutline(roots: [ProblemNode(), ProblemNode()]))

        #expect(picker.selectedTag == nil)
        #expect(labels(picker.wheelOptions(atLevel: 0)) == ["—", "1", "2", "3"])
    }
}
