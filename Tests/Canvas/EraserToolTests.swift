import Testing
import CoreGraphics
@testable import Tract

/// The eraser deletes whole strokes it crosses and never leaves ink of its own.
@Suite("Eraser tool")
@MainActor
struct EraserToolTests {

    /// Draws one horizontal line across the middle of the canvas.
    private func canvasWithOneLine() -> CanvasViewModel {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.pen)
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 0, y: 50)))
        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 100, y: 50)))
        viewModel.endStroke()
        return viewModel
    }

    private func erase(_ viewModel: CanvasViewModel, from start: CGPoint, to end: CGPoint) {
        viewModel.selectTool(.eraser)
        viewModel.beginStroke(with: StrokeFixtures.point(at: start))
        viewModel.continueStroke(with: StrokeFixtures.point(at: end))
        viewModel.endStroke()
    }

    @Test("Crossing a stroke with the eraser deletes it")
    func erasesCrossedStroke() {
        let viewModel = canvasWithOneLine()
        erase(viewModel, from: CGPoint(x: 50, y: 0), to: CGPoint(x: 50, y: 100))
        #expect(viewModel.strokes.isEmpty)
    }

    @Test("An eraser gesture that touches nothing leaves the drawing alone")
    func missingStrokeChangesNothing() {
        let viewModel = canvasWithOneLine()
        erase(viewModel, from: CGPoint(x: 0, y: 300), to: CGPoint(x: 100, y: 300))
        #expect(viewModel.strokes.count == 1)
    }

    @Test("The eraser never adds a stroke of its own")
    func eraserLeavesNoInk() {
        let viewModel = CanvasViewModel()
        erase(viewModel, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 100))
        #expect(viewModel.strokes.isEmpty)
        #expect(viewModel.activeStroke == nil)
    }

    @Test("Undo brings back everything one erase gesture removed")
    func undoRestoresErasedStrokes() {
        let viewModel = canvasWithOneLine()
        erase(viewModel, from: CGPoint(x: 50, y: 0), to: CGPoint(x: 50, y: 100))
        viewModel.undo()
        #expect(viewModel.strokes.count == 1)
    }

    @Test("An erase gesture that deletes nothing is not worth an undo step")
    func fruitlessEraseAddsNoUndoStep() {
        let viewModel = CanvasViewModel()
        erase(viewModel, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))
        #expect(viewModel.canUndo == false)
    }
}
