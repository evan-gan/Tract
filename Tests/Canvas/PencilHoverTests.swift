import Testing
import SwiftUI
@testable import Tract

/// The hover preview shows where the nib will land and how big a mark it will
/// leave, so it has to follow both the pencil and the zoom.
@Suite("Pencil hover preview")
@MainActor
struct PencilHoverTests {

    @Test("Nothing is previewed until the pencil comes into range")
    func noPreviewByDefault() {
        #expect(CanvasViewModel().pencilHoverLocation == nil)
    }

    @Test("The preview follows the hovering pencil")
    func previewTracksHoverLocation() {
        let viewModel = CanvasViewModel()
        viewModel.updatePencilHover(to: CGPoint(x: 120, y: 80))
        #expect(viewModel.pencilHoverLocation == CGPoint(x: 120, y: 80))
    }

    @Test("Leaving hover range clears the preview")
    func previewClearsWhenPencilLeaves() {
        let viewModel = CanvasViewModel()
        viewModel.updatePencilHover(to: CGPoint(x: 10, y: 10))
        viewModel.updatePencilHover(to: nil)
        #expect(viewModel.pencilHoverLocation == nil)
    }

    @Test("Touching down clears the preview, so no dot sits under the nib")
    func drawingClearsThePreview() {
        let viewModel = CanvasViewModel()
        viewModel.updatePencilHover(to: CGPoint(x: 30, y: 30))
        viewModel.beginStroke(with: StrokeFixtures.point(at: CGPoint(x: 30, y: 30)))
        #expect(viewModel.pencilHoverLocation == nil)
    }

    @Test("The preview is drawn at the stroke's own width when unzoomed")
    func previewMatchesStrokeWidth() {
        let viewModel = CanvasViewModel()
        viewModel.strokeWidth = 7
        #expect(viewModel.pencilPreviewDiameter == 7)
    }

    @Test("The preview grows and shrinks with the zoom")
    func previewScalesWithZoom() {
        let viewModel = CanvasViewModel()
        viewModel.strokeWidth = 4
        viewModel.canvasTransform.scale = 2.5
        #expect(viewModel.pencilPreviewDiameter == 10)

        viewModel.canvasTransform.scale = 0.5
        #expect(viewModel.pencilPreviewDiameter == 2)
    }

    @Test("The preview takes the ink colour of the pen about to draw")
    func previewUsesInkColorForDrawingTools() {
        let viewModel = CanvasViewModel()
        viewModel.selectInkColor(InkColor.blue)
        let expectedInk = StrokeStyle(
            color: InkColor.blue,
            lineWidth: viewModel.strokeWidth,
            opacity: viewModel.strokeOpacity,
            tool: .pen
        ).swiftUIColor
        #expect(viewModel.pencilPreviewColor == expectedInk)
    }

    @Test("A tool that lays down no ink previews in neutral grey instead")
    func previewIsNeutralForNonDrawingTools() {
        let viewModel = CanvasViewModel()
        viewModel.selectTool(.eraser)
        #expect(viewModel.pencilPreviewColor == Color.gray)
    }
}
