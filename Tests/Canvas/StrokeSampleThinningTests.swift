import Testing
import CoreGraphics
@testable import Tract

/// Apple Pencil reports far more samples than a screen can show. Dropping the
/// ones that land on top of each other is what keeps a long stroke cheap — but
/// it must never cost the drawing any detail the user can see.
@Suite("Stroke sample thinning")
@MainActor
struct StrokeSampleThinningTests {

    private func drawStroke(through positions: [CGPoint], on viewModel: CanvasViewModel) {
        guard let first = positions.first else { return }
        viewModel.beginStroke(with: StrokeFixtures.point(at: first))
        for position in positions.dropFirst() {
            viewModel.continueStroke(with: StrokeFixtures.point(at: position))
        }
    }

    @Test("Samples a fraction of a pixel apart are dropped")
    func subPixelSamplesAreDropped() {
        let viewModel = CanvasViewModel()
        drawStroke(
            through: [.zero, CGPoint(x: 0.1, y: 0), CGPoint(x: 0.2, y: 0)],
            on: viewModel
        )

        #expect(viewModel.activeStroke?.points.count == 1)
    }

    @Test("Samples far enough apart to see are all kept")
    func visibleSamplesAreKept() {
        let viewModel = CanvasViewModel()
        drawStroke(
            through: [.zero, CGPoint(x: 4, y: 0), CGPoint(x: 8, y: 0)],
            on: viewModel
        )

        #expect(viewModel.activeStroke?.points.count == 3)
    }

    @Test("Zoomed in, samples closer together on the canvas still count")
    func zoomingInKeepsFinerDetail() {
        let viewModel = CanvasViewModel()
        // At 8x, a canvas step of 0.5 is four points on screen — plainly visible,
        // and exactly the detail someone zooms in to draw.
        viewModel.canvasTransform.scale = 8
        drawStroke(through: [.zero, CGPoint(x: 0.5, y: 0)], on: viewModel)

        #expect(viewModel.activeStroke?.points.count == 2)
    }

    @Test("A coalesced batch is added sample by sample")
    func coalescedBatchIsAppended() {
        let viewModel = CanvasViewModel()
        viewModel.beginStroke(with: StrokeFixtures.point(at: .zero))
        viewModel.continueStroke(with: [
            StrokeFixtures.point(at: CGPoint(x: 5, y: 0)),
            StrokeFixtures.point(at: CGPoint(x: 10, y: 0))
        ])

        #expect(viewModel.activeStroke?.points.count == 3)
    }
}
