import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// A problem's offset is `gridPosition - itsOwnBounds.minX`, and its ink is
/// *stored* with that offset taken off. Re-measuring the grid while the user is
/// writing therefore closes a feedback loop — a mark past the left edge moves
/// `bounds.minX`, which changes the offset, which moves every mark in the
/// problem, which changes where the next sample is stored.
///
/// It diverges, and on screen it looks like the pen drawing somewhere other
/// than the nib. These tests pin the invariant that breaks the loop: **while a
/// problem is being edited, its offset does not move.**
@MainActor
@Suite("Problem layout stability")
struct ProblemLayoutStabilityTests {

    private func model(
        nodeID: UUID,
        bounds: @escaping () -> CGRect
    ) -> ProblemLayoutModel {
        let model = ProblemLayoutModel()
        model.cellsProvider = {
            [
                ProblemLayoutCell(nodeID: nodeID, path: [0], bounds: bounds()),
                // A second problem further up and to the left, so the grid's
                // anchor is *not* the problem under test and it therefore gets
                // a non-zero offset. Against a zero offset these tests would
                // pass whatever the code did.
                ProblemLayoutCell(
                    nodeID: UUID(),
                    path: [1],
                    bounds: CGRect(x: 0, y: 0, width: 100, height: 100)
                )
            ]
        }
        return model
    }

    @Test("A problem's offset does not move while it is being written in")
    func offsetIsPinnedWhileEditing() {
        let nodeID = UUID()
        var inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        let atFocus = model.settledPlacement.offset(forNode: nodeID)

        // Writing to the left of and above everything already there — the case
        // that used to make the offset run away.
        inkBounds = CGRect(x: -400, y: -400, width: 900, height: 900)
        model.noteFocusedInkBounds(inkBounds)

        #expect(model.settledPlacement.offset(forNode: nodeID) == atFocus)
    }

    @Test("Writing far outside the problem still does not move it")
    func offsetSurvivesRepeatedGrowth() {
        let nodeID = UUID()
        var inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        let atFocus = model.settledPlacement.offset(forNode: nodeID)

        for step in 1 ... 20 {
            let reach = CGFloat(step) * 200
            inkBounds = CGRect(x: -reach, y: -reach, width: reach * 2, height: reach * 2)
            model.noteFocusedInkBounds(inkBounds)
        }

        #expect(model.settledPlacement.offset(forNode: nodeID) == atFocus)
    }

    /// `placement` is an input to the committed ink layer, and that layer must
    /// not be invalidated while a stroke is in flight — otherwise every mark on
    /// the page repaints on every frame of every gesture. The box is allowed to
    /// follow the pen; the shove around it waits for pen-up.
    @Test("Growing the box while writing does not touch the placement")
    func growthDoesNotInvalidateTheInkLayer() {
        let nodeID = UUID()
        var inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        let before = model.placement

        inkBounds = CGRect(x: 300, y: 300, width: 4000, height: 4000)
        model.noteFocusedInkBounds(inkBounds)

        #expect(model.placement == before)
    }

    @Test("Pen-up moves the neighbours clear of the room the writing took")
    func neighboursSettleOnPenUp() {
        let nodeID = UUID()
        var inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        let before = model.settledPlacement

        inkBounds = CGRect(x: 300, y: 300, width: 4000, height: 4000)
        model.noteFocusedInkBounds(inkBounds)
        model.settleNeighbours()

        #expect(model.settledPlacement != before)
    }

    @Test("The box does grow while the problem is written in, even though the offset does not")
    func boxStillFollowsTheWriting() {
        let nodeID = UUID()
        var inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        let atFocus = model.focusBox

        inkBounds = CGRect(x: 0, y: 0, width: 4000, height: 4000)
        model.noteFocusedInkBounds(inkBounds)

        #expect(model.focusBox.width > atFocus.width)
    }

    @Test("The page re-flows once the problem is closed")
    func leavingFocusRemeasures() {
        let nodeID = UUID()
        var inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        let atFocus = model.settledPlacement.offset(forNode: nodeID)

        inkBounds = CGRect(x: -400, y: -400, width: 900, height: 900)
        model.noteFocusedInkBounds(inkBounds)
        model.clearFocus()

        #expect(model.settledPlacement.offset(forNode: nodeID) != atFocus)
    }

    @Test("Switching the arrangement off shifts nothing at all")
    func disablingRestoresEveryProblem() {
        let nodeID = UUID()
        let inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }

        model.setEnabled(true)
        model.setEnabled(false)

        #expect(model.settledPlacement.offset(forNode: nodeID) == .zero)
    }

    private func squareLoop(side: CGFloat) -> [CGPoint] {
        [
            CGPoint(x: 0, y: 0),
            CGPoint(x: side, y: 0),
            CGPoint(x: side, y: side),
            CGPoint(x: 0, y: side)
        ]
    }

    /// The bubble is frozen while the problem is focused, so it has to be read
    /// again *after* the focus is dropped. Reading it first closes the box onto
    /// the outline the work had before it was written in, while the newly
    /// retraced one fades in underneath — which reads as a shrink and a jump.
    @Test("Closing a problem closes onto the shape it has grown into")
    func exitReReadsTheBubble() {
        let nodeID = UUID()
        let inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }
        var contours = [squareLoop(side: 100)]
        model.contoursProvider = { _ in contours }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        let atFocus = model.focusBubbleLoop
        #expect(!atFocus.isEmpty)

        // Stands in for a session of writing: the problem's traced bubble has
        // grown well past what it was when the box opened out of it.
        contours = [squareLoop(side: 4000)]
        model.clearFocus()

        #expect(model.focusBubbleLoop != atFocus)
    }

    @Test("Switching the arrangement off also closes onto the grown shape")
    func disablingReReadsTheBubble() {
        let nodeID = UUID()
        let inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }
        var contours = [squareLoop(side: 100)]
        model.contoursProvider = { _ in contours }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        let atFocus = model.focusBubbleLoop

        contours = [squareLoop(side: 4000)]
        model.setEnabled(false)

        #expect(model.focusBubbleLoop != atFocus)
    }

    @Test("Opening another document leaves nothing of the last one's arrangement")
    func resetClearsEverything() {
        let nodeID = UUID()
        let inkBounds = CGRect(x: 300, y: 300, width: 100, height: 100)
        let model = model(nodeID: nodeID) { inkBounds }

        model.setEnabled(true)
        model.focus(nodeID: nodeID)
        model.reset()

        #expect(!model.isEnabled)
        #expect(!model.isFocused)
        #expect(model.frameNodeID == nil)
        #expect(model.focusBox.isNull)
        #expect(model.placement.isIdentity)
    }
}
