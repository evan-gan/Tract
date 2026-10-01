import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Switching the arrangement on with a problem already picked opens that
/// problem straight away, and a document opens with the page arranged.
@Suite("Arranging the page opens the picked problem")
@MainActor
struct ProblemLayoutToggleFocusTests {

    /// One inked problem, with the wheel still on it.
    private func canvasWithOneInkedProblem() -> (CanvasViewModel, inked: UUID) {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)
        let inked = viewModel.problems.selectedNodeID!
        SelectionFixtures.drawLine(viewModel, from: .zero, to: CGPoint(x: 100, y: 0))
        return (viewModel, inked)
    }

    @Test("Arranging with an inked problem picked opens it")
    func arrangingOpensPickedProblem() {
        let (viewModel, inked) = canvasWithOneInkedProblem()

        viewModel.toggleProblemLayout()

        #expect(viewModel.problemLayout.focusedNodeID == inked)
    }

    @Test("Arranging with an empty problem picked opens nothing")
    func arrangingOnEmptyProblemOpensNothing() {
        let (viewModel, _) = canvasWithOneInkedProblem()
        viewModel.problems.selectOption(1, atLevel: 0)   // problem 2, no ink

        viewModel.toggleProblemLayout()

        #expect(viewModel.problemLayout.isEnabled)
        #expect(viewModel.problemLayout.focusedNodeID == nil)
    }

    @Test("Arranging with the wheel on the dash opens nothing")
    func arrangingWithNothingPickedOpensNothing() {
        let (viewModel, _) = canvasWithOneInkedProblem()
        viewModel.problems.selectOption(ProblemWheelOption.noneID, atLevel: 0)

        viewModel.toggleProblemLayout()

        #expect(viewModel.problemLayout.focusedNodeID == nil)
    }

    @Test("Switching the arrangement off closes the open problem")
    func unarrangingClosesFocus() {
        let (viewModel, _) = canvasWithOneInkedProblem()
        viewModel.toggleProblemLayout()

        viewModel.toggleProblemLayout()

        #expect(!viewModel.problemLayout.isEnabled)
        #expect(viewModel.problemLayout.focusedNodeID == nil)
    }

    @Test("A document loaded from disk opens with the page arranged and settled")
    func restoredDocumentOpensArranged() {
        var builder = ProblemOutlineBuilder()
        let first = builder.node([1])
        let second = builder.node([2])
        let strokes = [
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 100, y: 0)], problemNodeID: first),
            StrokeFixtures.stroke(
                through: [CGPoint(x: 900, y: 3000), CGPoint(x: 1000, y: 3000)],
                problemNodeID: second
            ),
        ]
        let viewModel = CanvasViewModel()

        viewModel.restore(strokes: strokes, outline: builder.outline, origin: .zero, scale: 1)

        #expect(viewModel.problemLayout.isEnabled)
        #expect(viewModel.problemLayout.focusedNodeID == nil)
        // Settled rather than animating in: the live placement is already the
        // grid, not the identity it would start from.
        #expect(!viewModel.problemLayout.placement.isIdentity)
        #expect(viewModel.problemLayout.placement == viewModel.problemLayout.settledPlacement)
    }
}
