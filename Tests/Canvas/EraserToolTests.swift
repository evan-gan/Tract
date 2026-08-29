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

    /// Draws one thick horizontal line, wide enough that its visible body extends
    /// well beyond the samples it was recorded from.
    private func canvasWithOneThickLine() -> CanvasViewModel {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.pen)
        viewModel.strokeWidth = 40
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 0, y: 50)))
        viewModel.continueStroke(with: StrokeFixtures.point(at: CGPoint(x: 100, y: 50)))
        viewModel.endStroke()
        return viewModel
    }

    @Test("Touching a thick stroke's visible body erases it without crossing its centre")
    func erasesThickStrokeOnContact() {
        let viewModel = canvasWithOneThickLine()
        // Runs along inside the line's lower half, never reaching y = 50.
        erase(viewModel, from: CGPoint(x: 20, y: 62), to: CGPoint(x: 80, y: 62))
        #expect(viewModel.strokes.isEmpty)
    }

    @Test("Passing outside a thick stroke's visible edge leaves it alone")
    func spareThickStrokeOutsideItsEdge() {
        let viewModel = canvasWithOneThickLine()
        // The drawn edge is at y = 30; this stays clear of it and of the tip.
        erase(viewModel, from: CGPoint(x: 20, y: 15), to: CGPoint(x: 80, y: 15))
        #expect(viewModel.strokes.count == 1)
    }

    @Test("The eraser tip keeps its size on screen as the canvas zooms")
    func eraserTipStaysAScreenSize() {
        let viewModel = canvasWithOneLine()
        // Zoomed in 10x, the tip covers a tenth as much canvas, so a gesture this
        // far off a 2-point line no longer reaches it.
        viewModel.canvasTransform.scale = 10
        erase(viewModel, from: CGPoint(x: 20, y: 53), to: CGPoint(x: 80, y: 53))
        #expect(viewModel.strokes.count == 1)

        viewModel.canvasTransform.scale = 1
        erase(viewModel, from: CGPoint(x: 20, y: 53), to: CGPoint(x: 80, y: 53))
        #expect(viewModel.strokes.isEmpty)
    }

    @Test("An erase gesture that deletes nothing is not worth an undo step")
    func fruitlessEraseAddsNoUndoStep() {
        let viewModel = CanvasViewModel()
        erase(viewModel, from: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10))
        #expect(viewModel.canUndo == false)
    }
}
