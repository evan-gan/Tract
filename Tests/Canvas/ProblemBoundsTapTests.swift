import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Each problem gets a region on the page, and a finger tap is how the user
/// moves between them: inside one points the picker at that problem, outside
/// every one of them steps back out.
@Suite("Problem regions on the canvas")
@MainActor
struct ProblemBoundsTapTests {

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

    /// Comfortably outside both regions, whatever padding they were built with.
    private let blankPaper = CGPoint(x: 5000, y: 5000)

    @Test("Every problem with ink on the page gets a region")
    func oneRegionPerProblem() {
        let (viewModel, first, second) = canvasWithTwoProblems()

        #expect(Set(viewModel.problemRegions.map(\.nodeID)) == [first, second])
    }

    @Test("Untagged ink is not framed — there is no problem to name it after")
    func untaggedInkHasNoRegion() {
        let viewModel = CanvasViewModel()

        SelectionFixtures.drawLine(viewModel, from: .zero, to: CGPoint(x: 100, y: 0))

        #expect(viewModel.problemRegions.isEmpty)
    }

    @Test("A tap inside a region switches the picker to that problem")
    func tappingARegionSelectsItsProblem() {
        let (viewModel, first, second) = canvasWithTwoProblems()
        #expect(viewModel.problems.selectedNodeID == second)

        viewModel.handleCanvasTap(at: CGPoint(x: 50, y: 0))

        #expect(viewModel.problems.selectedNodeID == first)
    }

    @Test("The region reaches past the ink by its padding, so a near miss still counts")
    func tappingTheClearPaperInsideARegionCounts() {
        let (viewModel, first, _) = canvasWithTwoProblems()

        // Off the end of the stroke but well inside the padding around it.
        viewModel.handleCanvasTap(at: CGPoint(x: 50, y: ProblemBoundsStyle.padding / 2))

        #expect(viewModel.problems.selectedNodeID == first)
    }

    @Test("A tap on blank paper outside every region steps out of the problem")
    func tappingBlankPaperClearsTheProblem() {
        let (viewModel, _, second) = canvasWithTwoProblems()
        #expect(viewModel.problems.selectedNodeID == second)

        viewModel.handleCanvasTap(at: blankPaper)

        #expect(viewModel.problems.selectedNodeID == nil)
        #expect(viewModel.problems.selectedTag == nil)
    }

    @Test("A problem with nothing written in it yet survives a tap on the paper")
    func tappingBlankPaperKeepsAProblemWithNoRegion() {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)
        let picked = viewModel.problems.selectedNodeID

        // Nothing is drawn, so there is no region to be inside and none to step
        // out of — the tap is only putting the wheel away, and must not take the
        // tag the next stroke is about to be filed under with it.
        viewModel.handleCanvasTap(at: blankPaper)

        #expect(viewModel.problems.selectedNodeID == picked)
    }

    @Test("A live selection still speaks first: tapping off it drops the selection")
    func aSelectionTakesPrecedenceOverTheRegions() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.problems.selectOption(0, atLevel: 0)
        let selected = viewModel.problems.selectedNodeID

        viewModel.handleCanvasTap(at: blankPaper)

        // The tap spent itself dropping the selection rather than reaching the
        // regions underneath, so the picker has not moved.
        #expect(viewModel.hasSelection == false)
        #expect(viewModel.problems.selectedNodeID == selected)
    }

    @Test("New ink re-traces the region it landed in")
    func newInkInvalidatesTheCachedRegions() {
        let (viewModel, _, _) = canvasWithTwoProblems()
        let before = viewModel.problemRegions

        // The regions are cached against the ink revision; a mark that did not
        // invalidate that cache would leave a region framing work that has grown
        // past it.
        SelectionFixtures.drawLine(
            viewModel,
            from: CGPoint(x: 0, y: 2100),
            to: CGPoint(x: 300, y: 2100)
        )

        #expect(viewModel.problemRegions != before)
    }
}
