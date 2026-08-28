import Testing
@testable import Tract

/// Apple Pencil's double tap is a two-way switch between drawing and erasing,
/// not a cycle through every tool in the dock.
@Suite("Pencil double-tap tool switch")
@MainActor
struct PencilShortcutToolTests {

    @Test("Double tapping while drawing switches to the eraser")
    func penSwitchesToEraser() {
        let viewModel = CanvasViewModel()
        viewModel.togglePencilShortcutTool()
        #expect(viewModel.activeTool == .eraser)
    }

    @Test("Double tapping again switches straight back to the pen")
    func eraserSwitchesBackToPen() {
        let viewModel = CanvasViewModel()
        viewModel.togglePencilShortcutTool()
        viewModel.togglePencilShortcutTool()
        #expect(viewModel.activeTool == .pen)
    }

    @Test("The lasso is never reached by double tapping, however many times")
    func lassoIsNeverInTheCycle() {
        let viewModel = CanvasViewModel()
        for _ in 0 ..< 7 {
            viewModel.togglePencilShortcutTool()
            #expect(viewModel.activeTool != .lasso)
        }
    }

    @Test("Double tapping out of the lasso goes to the eraser, then back to the pen")
    func lassoLeavesTheCycleOnFirstTap() {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.lasso)

        viewModel.togglePencilShortcutTool()
        #expect(viewModel.activeTool == .eraser)

        viewModel.togglePencilShortcutTool()
        #expect(viewModel.activeTool == .pen)
    }
}
