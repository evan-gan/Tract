import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Undo and redo replay a log of edits rather than swapping page snapshots, so
/// each kind of edit has to come back exactly — ink, depth order, tags, and the
/// pencil telemetry every sample carries.
@Suite("Undo edit log")
@MainActor
struct UndoEditLogTests {

    // MARK: - Fixtures

    /// Horizontal lines from x 0 to 100, one per height, filed in list order.
    private func canvasWithLines(atHeights heights: [CGFloat]) -> CanvasViewModel {
        let viewModel = CanvasViewModel()
        viewModel.strokes = heights.map { height in
            StrokeFixtures.stroke(through: [CGPoint(x: 0, y: height), CGPoint(x: 100, y: height)])
        }
        return viewModel
    }

    /// Runs one eraser gesture through every point in order.
    private func erase(_ viewModel: CanvasViewModel, through path: [CGPoint]) {
        viewModel.selectTool(.eraser)
        viewModel.beginStroke(with: StrokeFixtures.point(at: path[0]))
        for point in path.dropFirst() {
            viewModel.continueStroke(with: StrokeFixtures.point(at: point))
        }
        viewModel.endStroke()
    }

    private func drag(_ viewModel: CanvasViewModel, from start: CGPoint, by offset: CGPoint) {
        viewModel.beginSelectionDrag(at: start)
        viewModel.updateSelectionDrag(to: start + offset)
        viewModel.endSelectionDrag()
    }

    /// A stroke whose every sample has its own telemetry and timestamp, so a
    /// field that got reset or shuffled shows up as a mismatch.
    private func strokeWithDistinctTelemetry() -> Stroke {
        var stroke = Stroke(sessionID: UUID(), style: StrokeFixtures.stroke(through: [.zero]).style)
        for sampleIndex in 0 ..< 6 {
            let step = CGFloat(sampleIndex)
            stroke.appendPoint(StrokePoint(
                position: CGPoint(x: 20 + step * 8, y: 30 + step * 4),
                force: 0.25 + step * 0.1,
                azimuth: 0.5 + step * 0.05,
                altitude: 0.8 + step * 0.02,
                rollAngle: step * 0.3,
                estimatedPropertiesMask: sampleIndex % 3,
                estimationUpdateIndex: 100 + sampleIndex,
                timestamp: 5000 + Double(sampleIndex) * 0.004
            ))
        }
        stroke.isComplete = true
        return stroke
    }

    /// Checks two samples agree on everything but position.
    private func expectSameTelemetry(_ actual: StrokePoint, _ expected: StrokePoint) {
        #expect(actual.force == expected.force)
        #expect(actual.azimuth == expected.azimuth)
        #expect(actual.altitude == expected.altitude)
        #expect(actual.rollAngle == expected.rollAngle)
        #expect(actual.estimatedPropertiesMask == expected.estimatedPropertiesMask)
        #expect(actual.estimationUpdateIndex == expected.estimationUpdateIndex)
        #expect(actual.timestamp == expected.timestamp)
    }

    // MARK: - Draw

    @Test("Undoing a drawn stroke removes it and redo brings back the same stroke")
    func drawUndoesAndRedoes() {
        let viewModel = CanvasViewModel()
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10))
        let drawn = viewModel.strokes[0]

        viewModel.undo()
        #expect(viewModel.strokes.isEmpty)

        viewModel.redo()
        #expect(viewModel.strokes.map(\.id) == [drawn.id])
        #expect(viewModel.strokes[0].points.map(\.position) == drawn.points.map(\.position))
    }

    @Test("Undo only removes the newest stroke, leaving earlier ink alone")
    func drawUndoLeavesEarlierInk() {
        let viewModel = CanvasViewModel()
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10))
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 10, y: 90), to: CGPoint(x: 50, y: 90))
        let firstID = viewModel.strokes[0].id

        viewModel.undo()

        #expect(viewModel.strokes.map(\.id) == [firstID])
    }

    @Test("A new edit after an undo discards the redo history")
    func newEditClearsRedo() {
        let viewModel = CanvasViewModel()
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 10))
        viewModel.undo()
        #expect(viewModel.canRedo)

        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 10, y: 90), to: CGPoint(x: 50, y: 90))

        #expect(viewModel.canRedo == false)
    }

    // MARK: - Erase

    @Test("Undoing an erase puts a middle stroke back at its original depth")
    func eraseUndoRestoresZOrder() {
        let viewModel = canvasWithLines(atHeights: [0, 40, 80])
        let originalOrder = viewModel.strokes.map(\.id)

        erase(viewModel, through: [CGPoint(x: 50, y: 35), CGPoint(x: 50, y: 45)])
        #expect(viewModel.strokes.map(\.id) == [originalOrder[0], originalOrder[2]])

        viewModel.undo()
        #expect(viewModel.strokes.map(\.id) == originalOrder)
    }

    @Test("Strokes erased at different moments of one gesture all return in order")
    func eraseAcrossSamplesRestoresZOrder() {
        let viewModel = canvasWithLines(atHeights: [0, 40, 80, 120])
        let originalOrder = viewModel.strokes.map(\.id)

        // Takes out the line at 40, detours clear of the ink, then the line at 120,
        // so the two removals land in separate passes over the page.
        erase(viewModel, through: [
            CGPoint(x: 50, y: 35), CGPoint(x: 50, y: 45),
            CGPoint(x: 200, y: 45), CGPoint(x: 200, y: 115),
            CGPoint(x: 50, y: 115), CGPoint(x: 50, y: 125),
        ])
        #expect(viewModel.strokes.map(\.id) == [originalOrder[0], originalOrder[2]])

        viewModel.undo()
        #expect(viewModel.strokes.map(\.id) == originalOrder)
    }

    @Test("Several strokes erased in one pass return in order, and redo erases them again")
    func eraseInOnePassUndoesAndRedoes() {
        let viewModel = canvasWithLines(atHeights: [0, 40, 80])
        let originalOrder = viewModel.strokes.map(\.id)

        erase(viewModel, through: [CGPoint(x: 50, y: -10), CGPoint(x: 50, y: 50)])
        #expect(viewModel.strokes.map(\.id) == [originalOrder[2]])

        viewModel.undo()
        #expect(viewModel.strokes.map(\.id) == originalOrder)

        viewModel.redo()
        #expect(viewModel.strokes.map(\.id) == [originalOrder[2]])
    }

    // MARK: - Drag

    @Test("Drag, undo and redo leave every sample's telemetry and timing untouched")
    func dragRoundTripKeepsTelemetry() {
        let viewModel = CanvasViewModel()
        let original = strokeWithDistinctTelemetry()
        viewModel.strokes = [original]
        SelectionFixtures.lassoTheBox(viewModel)
        // Binary-exact values, so the positions can be compared exactly after
        // the move is undone by subtracting the same offset.
        let offset = CGPoint(x: 37.5, y: -12.25)

        drag(viewModel, from: CGPoint(x: 30, y: 35), by: offset)
        viewModel.undo()

        let undone = viewModel.strokes[0]
        #expect(undone.points.map(\.position) == original.points.map(\.position))
        #expect(undone.canvasBounds == original.canvasBounds)

        viewModel.redo()

        let redone = viewModel.strokes[0]
        #expect(redone.id == original.id)
        #expect(redone.sessionID == original.sessionID)
        #expect(redone.startTime == original.startTime)
        #expect(redone.endTime == original.endTime)
        #expect(redone.points.map(\.position) == original.points.map { $0.position + offset })
        #expect(redone.canvasBounds == original.canvasBounds.offsetBy(dx: offset.x, dy: offset.y))
        for (redonePoint, originalPoint) in zip(redone.points, original.points) {
            expectSameTelemetry(redonePoint, originalPoint)
        }
        for (undonePoint, originalPoint) in zip(undone.points, original.points) {
            expectSameTelemetry(undonePoint, originalPoint)
        }
    }

    @Test("Undoing a drag moves only the ink that was dragged")
    func dragUndoLeavesOtherInkAlone() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine(
            alsoDrawing: [(CGPoint(x: 400, y: 400), CGPoint(x: 460, y: 460))]
        )
        drag(viewModel, from: CGPoint(x: 40, y: 40), by: CGPoint(x: 100, y: 0))

        viewModel.undo()

        let positions = viewModel.strokes.map { $0.points[0].position }
        #expect(positions.contains(CGPoint(x: 20, y: 20)))
        #expect(positions.contains(CGPoint(x: 400, y: 400)))
    }

    // MARK: - Delete

    @Test("Undoing a delete restores the selection's ink at its original depth")
    func deleteUndoRestoresZOrder() {
        let viewModel = CanvasViewModel()
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 400, y: 400), to: CGPoint(x: 460, y: 460))
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 60))
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 500, y: 500), to: CGPoint(x: 560, y: 560))
        let originalOrder = viewModel.strokes.map(\.id)
        SelectionFixtures.lassoTheBox(viewModel)

        viewModel.deleteSelection()
        #expect(viewModel.strokes.map(\.id) == [originalOrder[0], originalOrder[2]])

        viewModel.undo()
        #expect(viewModel.strokes.map(\.id) == originalOrder)

        viewModel.redo()
        #expect(viewModel.strokes.map(\.id) == [originalOrder[0], originalOrder[2]])
    }

    // MARK: - Retag and reassign

    @Test("A retag sweep redoes onto the same strokes it re-filed")
    func retagUndoesAndRedoes() {
        let viewModel = canvasWithLines(atHeights: [0, 40, 300])
        viewModel.problems.selectOption(0, atLevel: 0)
        let targetNodeID = viewModel.problems.selectedNodeID

        viewModel.problems.isRetagging = true
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 50, y: 0)))
        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 50, y: 40)))
        viewModel.endStroke()

        viewModel.undo()
        #expect(viewModel.strokes.allSatisfy { $0.problemNodeID == nil })

        viewModel.redo()
        #expect(viewModel.strokes.map(\.problemNodeID) == [targetNodeID, targetNodeID, nil])
    }

    @Test("Reassigning a selection undoes to each stroke's own old tag and redoes")
    func reassignUndoesAndRedoes() {
        let viewModel = CanvasViewModel()
        viewModel.problems.selectOption(0, atLevel: 0)
        let firstProblemID = viewModel.problems.selectedNodeID!
        viewModel.problems.selectOption(1, atLevel: 0)
        let secondProblemID = viewModel.problems.selectedNodeID!

        // Two lines inside the lasso box under different problems, so undo has
        // to restore a per-stroke tag rather than one shared one.
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 20))
        viewModel.problems.selectOption(0, atLevel: 0)
        SelectionFixtures.drawLine(viewModel, from: CGPoint(x: 20, y: 60), to: CGPoint(x: 60, y: 60))
        SelectionFixtures.lassoTheBox(viewModel)
        let tagsBefore = viewModel.strokes.map(\.problemNodeID)
        #expect(tagsBefore == [secondProblemID, firstProblemID])

        viewModel.reassignSelection(toProblemNode: secondProblemID)
        viewModel.undo()
        #expect(viewModel.strokes.map(\.problemNodeID) == tagsBefore)

        viewModel.redo()
        #expect(viewModel.strokes.allSatisfy { $0.problemNodeID == secondProblemID })
    }
}
