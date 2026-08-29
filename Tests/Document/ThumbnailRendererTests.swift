import UIKit
import Testing
@testable import Tract

@Suite("Document thumbnail rendering")
struct ThumbnailRendererTests {
    @Test("A document with no strokes has no preview to render")
    func emptyDocumentRendersNothing() {
        #expect(ThumbnailRenderer.renderPNG(strokes: []) == nil)
    }

    @Test("Strokes from non-drawing tools alone produce no preview")
    func nonDrawingStrokesRenderNothing() {
        let lassoOnly = [StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 10)], tool: .lasso)]
        #expect(ThumbnailRenderer.renderPNG(strokes: lassoOnly) == nil)
    }

    @Test("A drawn stroke renders a PNG at the card's fixed size")
    func drawnStrokeRendersAtCardSize() throws {
        let strokes = [StrokeFixtures.stroke(through: [CGPoint(x: 0, y: 0), CGPoint(x: 120, y: 90)])]
        let data = try #require(ThumbnailRenderer.renderPNG(strokes: strokes))
        let image = try #require(UIImage(data: data))

        #expect(image.size == ThumbnailRenderer.size)
    }

    @Test("A drawing far from the canvas origin still lands on the card")
    func distantDrawingIsCentred() throws {
        // Ink 10,000 points out is the normal case on an infinite canvas; a
        // renderer that forgot to offset by the ink bounds would produce blank paper.
        let strokes = [StrokeFixtures.stroke(through: [
            CGPoint(x: 10_000, y: 10_000), CGPoint(x: 10_100, y: 10_080)
        ])]
        let data = try #require(ThumbnailRenderer.renderPNG(strokes: strokes))

        #expect(containsInk(in: try #require(UIImage(data: data))))
    }

    @Test("A perfectly horizontal drawing renders instead of collapsing")
    func zeroHeightDrawingRenders() throws {
        let strokes = [StrokeFixtures.stroke(through: [CGPoint(x: 0, y: 50), CGPoint(x: 200, y: 50)])]
        let data = try #require(ThumbnailRenderer.renderPNG(strokes: strokes))

        #expect(containsInk(in: try #require(UIImage(data: data))))
    }

    /// True when at least one pixel is darker than the white paper it was drawn on.
    private func containsInk(in image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return false }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels.contains { $0 < 200 }
    }
}
