import Testing
import Foundation
@testable import Tract

@Suite("Folding the wheel away when it is not being used")
@MainActor
struct ProblemWheelExpansionTests {
    @Test("The wheel starts collapsed, showing a dash for untagged ink")
    func itStartsCollapsed() {
        let picker = ProblemTaggingModel()

        #expect(!picker.isWheelExpanded)
        #expect(picker.collapsedLabel == "—")
    }

    @Test("Collapsed, the pill reads the address new ink is filed under")
    func theCollapsedPillShowsTheAddress() {
        let picker = ProblemTaggingModel()
        picker.selectOption(0, atLevel: 0)
        picker.selectOption(0, atLevel: 1)

        #expect(picker.collapsedLabel == "1.a")
    }

    @Test("The chevron opens it and shuts it again")
    func togglingOpensAndCloses() {
        let picker = ProblemTaggingModel()

        picker.toggleWheel()
        #expect(picker.isWheelExpanded)

        picker.toggleWheel()
        #expect(!picker.isWheelExpanded)
    }

    @Test("Going back to the page puts it away")
    func aTouchOnTheCanvasCollapsesIt() {
        let viewModel = CanvasViewModel()
        viewModel.problems.expandWheel()

        viewModel.noteCanvasTouch()

        #expect(!viewModel.problems.isWheelExpanded)
    }

    @Test("Opening a document folds the wheel away with the rest of the state")
    func restoringADocumentCollapsesIt() {
        let picker = ProblemTaggingModel()
        picker.expandWheel()

        picker.restore(outline: ProblemOutline())

        #expect(!picker.isWheelExpanded)
    }
}
