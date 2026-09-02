import Testing
import CoreGraphics
@testable import Tract

/// Zoom has to magnify the drawing, ink weight included — not just spread its
/// points further apart.
@Suite("Canvas transform scaling")
struct CanvasTransformTests {

    @Test("At 100% a stroke width is drawn at its stored value")
    func unzoomedWidthIsUnchanged() {
        let transform = CanvasTransform()
        #expect(transform.toScreen(length: 4) == 4)
    }

    @Test("Zooming in scales a stroke width up by the same factor as the geometry")
    func zoomedInWidthGrowsWithScale() {
        var transform = CanvasTransform()
        transform.scale = 3

        let spanBetweenPoints = transform.toScreen(CGPoint(x: 10, y: 0)).x
            - transform.toScreen(CGPoint(x: 0, y: 0)).x
        // A 10-wide gap and a 10-wide line must magnify identically, or the ink
        // changes weight relative to the drawing it belongs to.
        #expect(transform.toScreen(length: 10) == spanBetweenPoints)
        #expect(transform.toScreen(length: 4) == 12)
    }

    @Test("Zooming out scales a stroke width down by the same factor")
    func zoomedOutWidthShrinksWithScale() {
        var transform = CanvasTransform()
        transform.scale = 0.25
        #expect(transform.toScreen(length: 8) == 2)
    }

    @Test("Zooming in stops at the maximum")
    func scaleIsCappedAtTheMaximum() {
        var transform = CanvasTransform()
        transform.scale = 40
        #expect(transform.scale == CanvasTransform.maximumScale)
    }

    @Test("Zooming out stops at the minimum")
    func scaleIsFlooredAtTheMinimum() {
        var transform = CanvasTransform()
        transform.scale = 0.001
        #expect(transform.scale == CanvasTransform.minimumScale)
    }

    @Test("A scale inside the range is left exactly as set")
    func scaleInsideTheRangeIsUntouched() {
        var transform = CanvasTransform()
        transform.scale = 2.5
        #expect(transform.scale == 2.5)
    }

    @Test("The zoom range spans 10% to 500%")
    func zoomRangeIsTenToFiveHundredPercent() {
        #expect(CanvasTransform.minimumScale == 0.1)
        #expect(CanvasTransform.maximumScale == 5.0)
    }

    @Test("Panning does not change how wide a stroke is drawn")
    func translationLeavesWidthAlone() {
        var transform = CanvasTransform()
        transform.translation = CGPoint(x: 400, y: -250)
        #expect(transform.toScreen(length: 6) == 6)
    }

    @Test("Unzoomed and unpanned, the visible canvas rect is the view itself")
    func visibleRectMatchesTheViewAtRest() {
        let transform = CanvasTransform()
        let visible = transform.visibleCanvasRect(inViewOfSize: CGSize(width: 800, height: 600))
        #expect(visible == CGRect(x: 0, y: 0, width: 800, height: 600))
    }

    @Test("Zooming in shrinks the visible canvas rect, panning slides it")
    func visibleRectFollowsPanAndZoom() {
        var transform = CanvasTransform()
        transform.scale = 2
        transform.translation = CGPoint(x: -100, y: -100)

        let visible = transform.visibleCanvasRect(inViewOfSize: CGSize(width: 800, height: 600))

        // The screen origin sits 50 canvas points in at 2x, and 800 screen points
        // cover 400 of canvas.
        #expect(visible == CGRect(x: 50, y: 50, width: 400, height: 300))
    }

    @Test("Ink outside the visible rect is what the renderer can skip")
    func visibleRectExcludesOffscreenInk() {
        var transform = CanvasTransform()
        transform.translation = CGPoint(x: -1000, y: 0)

        let visible = transform.visibleCanvasRect(inViewOfSize: CGSize(width: 800, height: 600))

        #expect(!visible.intersects(CGRect(x: 0, y: 0, width: 100, height: 100)))
        #expect(visible.intersects(CGRect(x: 1050, y: 0, width: 100, height: 100)))
    }
}
