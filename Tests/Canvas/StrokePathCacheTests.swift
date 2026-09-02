import Testing
import CoreGraphics
import SwiftUI
@testable import Tract

/// The path cache is what keeps a pan or a pinch from re-tracing every stroke on
/// the page, so what matters is that it hands back the same path until the ink
/// itself changes — and a rebuilt one the moment it does.
@Suite("Stroke path cache")
@MainActor
struct StrokePathCacheTests {

    @Test("A stroke that has not changed is traced once")
    func unchangedStrokeReusesItsPath() {
        let cache = StrokePathCache()
        let stroke = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 10)])

        #expect(cache.path(for: stroke) == cache.path(for: stroke))
        #expect(cache.cachedPathCount == 1)
    }

    @Test("Appending a sample retraces the stroke")
    func appendedSampleRebuildsPath() {
        let cache = StrokePathCache()
        var stroke = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 10)])
        let shortPath = cache.path(for: stroke)

        stroke.appendPoint(StrokeFixtures.point(at: CGPoint(x: 40, y: 40)))

        #expect(cache.path(for: stroke) != shortPath)
    }

    @Test("Dragging a stroke to a new place retraces it")
    func movedStrokeRebuildsPath() {
        let cache = StrokePathCache()
        var stroke = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 10)])
        let pathBeforeMove = cache.path(for: stroke)

        stroke.translate(by: CGPoint(x: 100, y: 0))

        #expect(cache.path(for: stroke) != pathBeforeMove)
    }

    @Test("Pruning forgets strokes that are no longer on the canvas")
    func pruningDropsDeletedStrokes() {
        let cache = StrokePathCache()
        let kept = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 10)])
        let erased = StrokeFixtures.stroke(through: [CGPoint(x: 50, y: 50), CGPoint(x: 60, y: 60)])
        _ = cache.path(for: kept)
        _ = cache.path(for: erased)

        cache.prune(keeping: [kept.id])

        #expect(cache.cachedPathCount == 1)
    }

    @Test("The traced path is the same shape the exporter rasterises")
    func pathMatchesTheRasterisedGeometry() {
        let stroke = StrokeFixtures.stroke(
            through: [.zero, CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 5)]
        )
        // Both draw canvas-space geometry, so a document must look the same on
        // screen and on the page it is exported to.
        let exported = Path(StrokeRasterizer.path(for: stroke, offset: .zero))

        #expect(StrokePathCache.makePath(for: stroke) == exported)
    }
}
