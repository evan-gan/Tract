import Testing
import CoreGraphics
import Foundation
@testable import Tract

@Suite("Tagging ink on the canvas")
@MainActor
struct ProblemRetagTests {
    private func viewModelOnProblemOne() -> CanvasViewModel {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)
        return viewModel
    }

    /// Draws one mark and hands back the node it was filed under.
    private func drawStroke(in viewModel: CanvasViewModel) -> UUID? {
        viewModel.beginStroke(with: StrokeFixtures.point(at: .zero))
        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 40, y: 0)))
        viewModel.endStroke()
        return viewModel.strokes.last?.problemNodeID
    }

    @Test("A stroke is tagged with the picker's selection as it is drawn")
    func newInkTakesTheCurrentTag() {
        let viewModel = viewModelOnProblemOne()

        let tagged = drawStroke(in: viewModel)

        #expect(tagged != nil)
        #expect(tagged == viewModel.problems.selectedNodeID)
    }

    /// The whole chain the export depends on: what the wheel is pointed at, what
    /// the stroke stores, and what that resolves back to on the page.
    @Test("Ink drawn on 1a.I prints under 1.a.I")
    func inkCarriesTheDeepestPickedLevel() {
        let viewModel = CanvasViewModel()
        for level in 0 ... 2 { viewModel.problems.selectOption(0, atLevel: level) }

        let tagged = drawStroke(in: viewModel)

        #expect(viewModel.problems.selectedTag == ProblemTag([
            .number(1), .lowercaseLetter(1), .uppercaseRoman(1)
        ]))
        #expect(tagged == viewModel.problems.selectedNodeID)
        #expect(viewModel.problems.outline.tag(forNode: tagged!) == viewModel.problems.selectedTag)
    }

    /// Every touch on the paper folds the wheel away, and that runs *before* the
    /// stroke starts. It must put the control away without letting go of what the
    /// control was pointed at.
    @Test("Folding the wheel away on the first touch does not untag the stroke")
    func collapsingTheWheelKeepsTheSelection() {
        let viewModel = viewModelOnProblemOne()
        viewModel.problems.expandWheel()
        let selected = viewModel.problems.selectedNodeID

        viewModel.noteCanvasTouch()
        let tagged = drawStroke(in: viewModel)

        #expect(!viewModel.problems.isWheelExpanded)
        #expect(tagged == selected)
    }

    /// A problem opened for the first time files ink under the *problem*: its
    /// parts sit on the dash until one is picked, so nothing is tagged with a
    /// level the user did not choose.
    @Test("Ink drawn on a problem opened for the first time belongs to the problem")
    func inkBelongsToTheLevelActuallyPicked() {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 1])   // problem 1, already carrying a part a
        let viewModel = CanvasViewModel()
        viewModel.restore(strokes: [], outline: builder.outline, origin: .zero, scale: 1)

        viewModel.problems.selectOption(0, atLevel: 0)
        let onTheProblem = drawStroke(in: viewModel)
        viewModel.problems.selectOption(0, atLevel: 1)   // now ask for its part a
        let onThePart = drawStroke(in: viewModel)

        #expect(viewModel.problems.outline.tag(forNode: onTheProblem!) == ProblemTag([.number(1)]))
        #expect(viewModel.problems.outline.tag(forNode: onThePart!)
            == ProblemTag([.number(1), .lowercaseLetter(1)]))
    }

    /// Once a part has been worked on, coming back to its problem returns to it —
    /// so a session spent switching between problems keeps filing ink where the
    /// user left off rather than one level up.
    @Test("Coming back to a problem files ink under the part it was left on")
    func inkFollowsTheRememberedPart() {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)   // problem 1
        viewModel.problems.selectOption(0, atLevel: 1)   // 1a
        viewModel.problems.selectOption(1, atLevel: 0)   // away to problem 2

        viewModel.problems.selectOption(0, atLevel: 0)   // back to problem 1
        let tagged = drawStroke(in: viewModel)

        #expect(viewModel.problems.outline.tag(forNode: tagged!)
            == ProblemTag([.number(1), .lowercaseLetter(1)]))
    }

    /// The dash is how a user goes back to writing something that belongs to no
    /// problem, so it has to reach the ink.
    @Test("Ink drawn after the dash goes back to being untagged")
    func theDashUntagsTheInkAfterIt() {
        let viewModel = viewModelOnProblemOne()
        #expect(drawStroke(in: viewModel) != nil)

        viewModel.problems.selectOption(ProblemWheelOption.noneID, atLevel: 0)

        #expect(drawStroke(in: viewModel) == nil)
    }

    /// A deleted problem takes the picker's aim with it: ink drawn next must not
    /// be filed under an id nothing answers to.
    @Test("Ink drawn after deleting the selected problem is untagged")
    func deletingTheSelectionUntagsTheInkAfterIt() {
        let viewModel = viewModelOnProblemOne()

        viewModel.problems.deleteNode(0, atLevel: 0)

        #expect(drawStroke(in: viewModel) == nil)
    }

    @Test("Ink drawn with nothing selected stays untagged")
    func untaggedInkStaysUntagged() {
        let viewModel = CanvasViewModel()

        viewModel.beginStroke(with: StrokeFixtures.point(at: .zero))
        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 40, y: 0)))
        viewModel.endStroke()

        #expect(viewModel.strokes.last?.problemNodeID == nil)
    }

    @Test("Retagging re-files the stroke under the touch and lays down no ink")
    func retagReassignsTheStrokeItTouches() {
        let viewModel = viewModelOnProblemOne()
        viewModel.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 100, y: 0)])]
        let strokeCountBefore = viewModel.strokes.count

        viewModel.problems.isRetagging = true
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 50, y: 0)))
        viewModel.endStroke()

        #expect(viewModel.strokes.count == strokeCountBefore)
        #expect(viewModel.strokes[0].problemNodeID == viewModel.problems.selectedNodeID)
    }

    @Test("A retag that touched nothing is not an edit and cannot be undone")
    func retagOnBlankPaperChangesNothing() {
        let viewModel = viewModelOnProblemOne()
        viewModel.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 100, y: 0)])]

        viewModel.problems.isRetagging = true
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 50, y: 900)))
        viewModel.endStroke()

        #expect(!viewModel.canUndo)
    }

    @Test("A whole retag sweep undoes in one step")
    func aRetagSweepIsOneUndoStep() {
        let viewModel = viewModelOnProblemOne()
        viewModel.strokes = [
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 100, y: 0)]),
            StrokeFixtures.stroke(through: [CGPoint(x: 0, y: 40), CGPoint(x: 100, y: 40)])
        ]

        viewModel.problems.isRetagging = true
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 50, y: 0)))
        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 50, y: 40)))
        viewModel.endStroke()
        #expect(viewModel.strokes.allSatisfy { $0.problemNodeID != nil })

        viewModel.undo()

        #expect(viewModel.strokes.allSatisfy { $0.problemNodeID == nil })
    }

    @Test("Retagging dims the ink that belongs to other problems")
    func retagModeDimsEverythingElse() {
        let viewModel = viewModelOnProblemOne()
        let mine = StrokeFixtures.stroke(
            through: [.zero, CGPoint(x: 10, y: 0)],
            problemNodeID: viewModel.problems.selectedNodeID
        )
        let theirs = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 0)])
        viewModel.strokes = [mine, theirs]

        viewModel.problems.isRetagging = true
        let styling = viewModel.problemInkStyling

        #expect(!styling.dimmedStrokeIDs.contains(mine.id))
        #expect(styling.dimmedStrokeIDs.contains(theirs.id))
    }

    @Test("Tinting colours by problem number, so parts of one problem match")
    func tintingGroupsPartsUnderTheirProblem() {
        let viewModel = CanvasViewModel()
        var builder = ProblemOutlineBuilder()
        let partA = builder.node([1, 1])
        let partB = builder.node([1, 2])
        let problemTwo = builder.node([2])
        viewModel.restore(strokes: [], outline: builder.outline, origin: .zero, scale: 1)
        viewModel.strokes = [partA, partB, problemTwo].map {
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 0)], problemNodeID: $0)
        }

        viewModel.problems.isTintingByProblem = true
        let styling = viewModel.problemInkStyling
        let colors = viewModel.strokes.map { styling.color(for: $0) }

        #expect(colors[0] == colors[1])
        #expect(colors[0] != colors[2])
    }

    @Test("With no mode on, the canvas paints ink exactly as it was drawn")
    func stylingIsInertWhenNoModeIsOn() {
        let viewModel = viewModelOnProblemOne()
        viewModel.strokes = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 0)])]

        #expect(!viewModel.problemInkStyling.isActive)
    }
}
