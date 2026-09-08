import Testing
import CoreGraphics
@testable import Tract

/// The home button has one job: put every stroke on screen, centred. These cover
/// the fitting maths and the empty-document cases where it must do nothing.
@Suite("Zoom to fit the drawing")
@MainActor
struct CanvasZoomToFitTests {
    private static let viewSize = CGSize(width: 1000, height: 800)
    private static let padding: CGFloat = 48

    // MARK: - The fitting maths

    @Test("The fitted drawing is centred in the view")
    func fittedContentIsCentred() throws {
        let content = CGRect(x: 400, y: -200, width: 100, height: 50)
        let fitted = try #require(
            CanvasTransform.fitting(content, inViewOfSize: Self.viewSize, padding: Self.padding)
        )

        let centreOnScreen = fitted.toScreen(CGPoint(x: content.midX, y: content.midY))
        #expect(abs(centreOnScreen.x - Self.viewSize.width / 2) < 0.001)
        #expect(abs(centreOnScreen.y - Self.viewSize.height / 2) < 0.001)
    }

    @Test("The tighter axis decides the zoom, and the padding is left free")
    func fittedScaleIsBoundedByTheTighterAxis() throws {
        // Tall and narrow: height is what runs out first, so 800 - 2*48 points
        // of view have to hold 400 points of drawing.
        let content = CGRect(x: 0, y: 0, width: 100, height: 400)
        let fitted = try #require(
            CanvasTransform.fitting(content, inViewOfSize: Self.viewSize, padding: Self.padding)
        )

        #expect(abs(fitted.scale - (800 - 96) / 400) < 0.001)

        let onScreen = content.applying(fitted.matrix)
        #expect(abs(onScreen.minY - Self.padding) < 0.001)
        #expect(onScreen.minX > Self.padding)
    }

    @Test("A drawing far larger than the view is zoomed out, not cropped")
    func oversizedContentZoomsOut() throws {
        let fitted = try #require(
            CanvasTransform.fitting(
                CGRect(x: 0, y: 0, width: 8000, height: 6000),
                inViewOfSize: Self.viewSize,
                padding: Self.padding
            )
        )
        #expect(fitted.scale < 1)
    }

    @Test("Fitting never breaks the zoom limits")
    func fittedScaleStaysWithinTheZoomLimits() throws {
        let enormous = try #require(
            CanvasTransform.fitting(
                CGRect(x: 0, y: 0, width: 1_000_000, height: 1_000_000),
                inViewOfSize: Self.viewSize
            )
        )
        #expect(enormous.scale == CanvasTransform.minimumScale)

        // A single dot has no extent to bound the zoom, so it lands on the cap
        // rather than on a division by zero.
        let dot = try #require(
            CanvasTransform.fitting(CGRect(x: 5, y: 5, width: 0, height: 0), inViewOfSize: Self.viewSize)
        )
        #expect(dot.scale == CanvasTransform.maximumScale)
    }

    @Test("There is nothing to fit in an empty box or a view smaller than its padding")
    func unfittableInputsProduceNoTransform() {
        #expect(CanvasTransform.fitting(.null, inViewOfSize: Self.viewSize) == nil)
        #expect(
            CanvasTransform.fitting(
                CGRect(x: 0, y: 0, width: 10, height: 10),
                inViewOfSize: CGSize(width: 40, height: 40),
                padding: Self.padding
            ) == nil
        )
    }

    // MARK: - The button's behaviour on the canvas

    @Test("Fitting brings every stroke on screen")
    func fittingShowsAllStrokes() {
        let viewModel = canvasWithTwoDistantSquares()
        viewModel.canvasTransform.scale = 3
        viewModel.canvasTransform.translation = CGPoint(x: 900, y: 900)

        viewModel.zoomToFitDrawing()

        let visible = viewModel.canvasTransform.visibleCanvasRect(inViewOfSize: Self.viewSize)
        for stroke in viewModel.strokes {
            #expect(visible.contains(stroke.canvasBounds))
        }
    }

    @Test("The home button is offered only once there is ink to centre on")
    func fitIsUnavailableWithoutInk() {
        let viewModel = CanvasViewModel()
        viewModel.noteViewportSize(Self.viewSize)
        #expect(viewModel.canZoomToFitDrawing == false)

        viewModel.strokes = [StrokeFixtures.square(at: CGPoint(x: 0, y: 0))]
        #expect(viewModel.canZoomToFitDrawing)
    }

    @Test("The home button is offered only once the viewport has been measured")
    func fitIsUnavailableBeforeTheViewportIsKnown() {
        let viewModel = CanvasViewModel()
        viewModel.strokes = [StrokeFixtures.square(at: CGPoint(x: 0, y: 0))]
        #expect(viewModel.canZoomToFitDrawing == false)
    }

    @Test("Fitting an empty canvas leaves the view where it was")
    func fittingEmptyCanvasChangesNothing() {
        let viewModel = CanvasViewModel()
        viewModel.noteViewportSize(Self.viewSize)
        viewModel.canvasTransform.scale = 2
        viewModel.canvasTransform.translation = CGPoint(x: 30, y: 40)

        viewModel.zoomToFitDrawing()

        #expect(viewModel.canvasTransform.scale == 2)
        #expect(viewModel.canvasTransform.translation == CGPoint(x: 30, y: 40))
    }

    @Test("Fitting is not an edit — it must not trigger a save")
    func fittingDoesNotBumpTheRevision() {
        let viewModel = canvasWithTwoDistantSquares()
        let revisionBefore = viewModel.revision

        viewModel.zoomToFitDrawing()

        #expect(viewModel.revision == revisionBefore)
    }

    private func canvasWithTwoDistantSquares() -> CanvasViewModel {
        let viewModel = CanvasViewModel()
        viewModel.noteViewportSize(Self.viewSize)
        viewModel.strokes = [
            StrokeFixtures.square(at: CGPoint(x: -600, y: -400)),
            StrokeFixtures.square(at: CGPoint(x: 900, y: 700))
        ]
        return viewModel
    }
}
