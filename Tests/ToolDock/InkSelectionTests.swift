import Testing
@testable import Tract

/// The dock's colour rail shows a selection only while ink is actually being laid down.
@Suite("Ink selection state")
@MainActor
struct InkSelectionTests {
    @Test("A fresh canvas starts on black ink, which is what shows on white paper")
    func defaultsToBlack() {
        #expect(CanvasViewModel().strokeColor == InkColor.black)
    }

    @Test("A drawing tool reports its ink colour as selected")
    func drawingToolShowsSelection() {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.pen)
        viewModel.selectInkColor(InkColor.red)
        #expect(viewModel.selectedInkColor == InkColor.red)
    }

    @Test("The eraser and lasso report no colour selected")
    func nonDrawingToolsShowNoSelection() {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.eraser)
        #expect(viewModel.selectedInkColor == nil)
        viewModel.selectTool(.lasso)
        #expect(viewModel.selectedInkColor == nil)
    }

    @Test("Picking a colour while erasing returns to the last drawing tool")
    func colourPickRestoresDrawingTool() {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.pen)
        viewModel.selectTool(.eraser)
        viewModel.selectInkColor(InkColor.blue)
        #expect(viewModel.activeTool == .pen)
        #expect(viewModel.selectedInkColor == InkColor.blue)
    }

    @Test("The pen is the only tool that lays down ink")
    func drawingToolMembership() {
        #expect(ToolType.allCases == [.pen, .eraser, .lasso])
        #expect(ToolType.drawingTools == [.pen])
        #expect(ToolType.eraser.isDrawingTool == false)
        #expect(ToolType.lasso.isDrawingTool == false)
    }
}
