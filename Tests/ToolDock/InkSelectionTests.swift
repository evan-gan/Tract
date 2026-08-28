import Testing
@testable import Tract

/// The dock's colour rail shows a selection only while ink is actually being laid down.
@Suite("Ink selection state")
@MainActor
struct InkSelectionTests {
    @Test("A fresh canvas starts on white ink")
    func defaultsToWhite() {
        #expect(CanvasViewModel().strokeColor == InkColor.white)
    }

    @Test("A drawing tool reports its ink colour as selected")
    func drawingToolShowsSelection() {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.marker)
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
        viewModel.selectTool(.pencil)
        viewModel.selectTool(.eraser)
        viewModel.selectInkColor(InkColor.blue)
        #expect(viewModel.activeTool == .pencil)
        #expect(viewModel.selectedInkColor == InkColor.blue)
    }

    @Test("Only pen, pencil, and marker count as drawing tools")
    func drawingToolMembership() {
        #expect(ToolType.drawingTools == [.pen, .pencil, .marker])
        #expect(ToolType.eraser.isDrawingTool == false)
    }
}
