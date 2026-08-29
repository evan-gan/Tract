import Testing
import CoreGraphics
@testable import Tract

/// The dot grid is part of the paper, so it has to pan and zoom with the ink —
/// while staying a grid rather than a solid texture at the far end of the zoom.
@Suite("Canvas dot grid")
struct CanvasGridTests {

    @Test("At 100% the dots keep their canvas spacing")
    func unzoomedSpacingIsTheCanvasSpacing() {
        #expect(CanvasGrid.screenSpacing(atScale: 1) == CanvasGrid.canvasSpacing)
    }

    @Test("Zooming in spreads the dots by the same factor as the drawing")
    func zoomingInSpreadsTheDots() {
        #expect(CanvasGrid.screenSpacing(atScale: 3) == CanvasGrid.canvasSpacing * 3)
        #expect(CanvasGrid.screenSpacing(atScale: 5) == CanvasGrid.canvasSpacing * 5)
    }

    @Test("Zoomed far out the grid coarsens instead of crowding into a texture")
    func zoomingOutCoarsensTheGrid() {
        // A literal 48pt grid at 10% would put dots 4.8pt apart.
        let spacing = CanvasGrid.screenSpacing(atScale: 0.1)
        #expect(spacing >= CanvasGrid.minimumScreenSpacing)
        // Coarsening doubles, so the surviving dots stay on canvas coordinates
        // the finer grid used too — they thin out, they do not shift.
        let coarseningFactor = spacing / (CanvasGrid.canvasSpacing * 0.1)
        #expect(coarseningFactor == 4)
    }

    @Test("The coarsened spacing is the smallest doubling that clears the minimum")
    func coarseningStopsAsSoonAsItCan() {
        let spacing = CanvasGrid.screenSpacing(atScale: 0.5)
        #expect(spacing == CanvasGrid.canvasSpacing * 0.5)

        let halved = CanvasGrid.screenSpacing(atScale: 0.25) / 2
        #expect(halved < CanvasGrid.minimumScreenSpacing)
    }

    @Test("A zero or negative scale falls back to the canvas spacing")
    func degenerateScaleDoesNotHang() {
        #expect(CanvasGrid.screenSpacing(atScale: 0) == CanvasGrid.canvasSpacing)
        #expect(CanvasGrid.screenSpacing(atScale: -2) == CanvasGrid.canvasSpacing)
    }

    @Test("Dots grow with the zoom, within limits")
    func dotRadiusTracksZoomWithinLimits() {
        #expect(CanvasGrid.dotRadius(atScale: 1) == CanvasGrid.canvasDotRadius)
        #expect(CanvasGrid.dotRadius(atScale: 2) == 2)
        #expect(CanvasGrid.dotRadius(atScale: 5) == CanvasGrid.maximumDotRadius)
        #expect(CanvasGrid.dotRadius(atScale: 0.1) == CanvasGrid.minimumDotRadius)
    }

    @Test("Panning slides the grid, and the first dot stays within one cell")
    func firstDotFollowsTheTranslation() {
        #expect(CanvasGrid.firstDotOffset(translation: 0, spacing: 24) == 0)
        #expect(CanvasGrid.firstDotOffset(translation: 10, spacing: 24) == 10)
        // A full cell of pan lands the grid back on itself.
        #expect(CanvasGrid.firstDotOffset(translation: 24, spacing: 24) == 0)
        #expect(CanvasGrid.firstDotOffset(translation: 30, spacing: 24) == 6)
    }

    @Test("Panning the other way keeps the first dot on screen, not behind it")
    func negativeTranslationWrapsForward() {
        #expect(CanvasGrid.firstDotOffset(translation: -6, spacing: 24) == 18)
        #expect(CanvasGrid.firstDotOffset(translation: -30, spacing: 24) == 18)
    }

    @Test("A degenerate spacing cannot produce a divide by zero")
    func zeroSpacingIsHandled() {
        #expect(CanvasGrid.firstDotOffset(translation: 40, spacing: 0) == 0)
    }
}
