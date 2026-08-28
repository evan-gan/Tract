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

    @Test("Panning does not change how wide a stroke is drawn")
    func translationLeavesWidthAlone() {
        var transform = CanvasTransform()
        transform.translation = CGPoint(x: 400, y: -250)
        #expect(transform.toScreen(length: 6) == 6)
    }
}
