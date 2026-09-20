import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Tapping straight from one focused problem into another has to close the old
/// box while the new one opens, rather than snapping one shut as the other
/// appears.
@MainActor
@Suite("Switching focus between problems")
struct ProblemFocusSwitchTests {

    private let firstNodeID = UUID()
    private let secondNodeID = UUID()

    private func model() -> ProblemLayoutModel {
        let model = ProblemLayoutModel()
        let firstNodeID = firstNodeID
        let secondNodeID = secondNodeID
        model.cellsProvider = {
            [
                ProblemLayoutCell(
                    nodeID: firstNodeID,
                    path: [0],
                    bounds: CGRect(x: 0, y: 0, width: 100, height: 100)
                ),
                ProblemLayoutCell(
                    nodeID: secondNodeID,
                    path: [1],
                    bounds: CGRect(x: 0, y: 1000, width: 100, height: 100)
                )
            ]
        }
        model.contoursProvider = { _ in
            [[CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100)]]
        }
        model.setEnabled(true)
        return model
    }

    @Test("Focusing a first problem leaves no closing frame")
    func firstFocusHasNoClosingFrame() {
        let model = model()
        model.focus(nodeID: firstNodeID)

        #expect(model.closingFrame == nil)
    }

    @Test("Switching keeps the old problem's frame, with the box it had, so it can close")
    func switchingKeepsTheOldFrame() {
        let model = model()
        model.focus(nodeID: firstNodeID)
        let firstBox = model.focusBox

        model.focus(nodeID: secondNodeID)

        #expect(model.closingFrame?.nodeID == firstNodeID)
        #expect(model.closingFrame?.box == firstBox)
        #expect(model.closingFrame?.bubbleLoop.isEmpty == false)
        #expect(model.frameNodeID == secondNodeID)
        #expect(model.focusedNodeID == secondNodeID)
    }

    @Test("A frame still closing from an exit also hands off when another problem is tapped")
    func closingExitFrameHandsOff() {
        let model = model()
        model.focus(nodeID: firstNodeID)
        model.clearFocus()

        model.focus(nodeID: secondNodeID)

        #expect(model.closingFrame?.nodeID == firstNodeID)
    }

    @Test("Refocusing the problem whose frame is closing reverses it instead of handing off")
    func refocusingSameProblemDoesNotHandOff() {
        let model = model()
        model.focus(nodeID: firstNodeID)
        model.clearFocus()

        model.focus(nodeID: firstNodeID)

        #expect(model.closingFrame == nil)
    }

    @Test("Opening another document drops a closing frame")
    func resetClearsClosingFrame() {
        let model = model()
        model.focus(nodeID: firstNodeID)
        model.focus(nodeID: secondNodeID)

        model.reset()

        #expect(model.closingFrame == nil)
        #expect(model.closingFrameProgress == 0)
    }
}
