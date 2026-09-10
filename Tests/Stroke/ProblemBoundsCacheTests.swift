import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Tracing a region is two distance-field sweeps, so the cache's job is to do
/// that for the problem being written in and for nothing else. These tests count
/// the traces rather than inspect the shapes: the shapes are `ProblemRegion`'s
/// business, and what matters here is how often they are rebuilt.
@Suite("Problem bounds cache")
struct ProblemBoundsCacheTests {

    private let padding: CGFloat = 30
    private let curveRadius: CGFloat = 60

    /// Two problems with a line of work each, far enough apart to be separate
    /// regions.
    private struct Page {
        var outline: ProblemOutline
        var strokes: [Stroke]
        let firstProblem: UUID
        let secondProblem: UUID
    }

    private func page() -> Page {
        var builder = ProblemOutlineBuilder()
        let firstProblem = builder.node([1])
        let secondProblem = builder.node([2])
        return Page(
            outline: builder.outline,
            strokes: [
                line(atY: 0, taggedAs: firstProblem),
                line(atY: 2000, taggedAs: secondProblem)
            ],
            firstProblem: firstProblem,
            secondProblem: secondProblem
        )
    }

    private func line(atY y: CGFloat, taggedAs problemNodeID: UUID?) -> Stroke {
        StrokeFixtures.stroke(
            through: [CGPoint(x: 0, y: y), CGPoint(x: 100, y: y)],
            problemNodeID: problemNodeID
        )
    }

    private func traceRegions(
        of page: Page,
        in cache: inout ProblemBoundsCache
    ) -> [ProblemBounds] {
        cache.regions(
            in: page.strokes,
            outline: page.outline,
            padding: padding,
            curveRadius: curveRadius
        )
    }

    @Test("Every problem with ink on the page is traced once")
    func tracesEachProblemOnce() {
        var cache = ProblemBoundsCache()
        let page = page()

        let framed = traceRegions(of: page, in: &cache)

        #expect(Set(framed.map(\.nodeID)) == [page.firstProblem, page.secondProblem])
        #expect(cache.traceCount == 2)
    }

    @Test("An unchanged page is not traced again")
    func reusesEveryShapeWhenNothingChanged() {
        var cache = ProblemBoundsCache()
        let page = page()

        let firstRead = traceRegions(of: page, in: &cache)
        let secondRead = traceRegions(of: page, in: &cache)

        #expect(cache.traceCount == 2)
        #expect(firstRead == secondRead)
    }

    @Test("New ink retraces only the problem it was filed under")
    func retracesOnlyTheProblemBeingWrittenIn() {
        var cache = ProblemBoundsCache()
        var page = page()
        _ = traceRegions(of: page, in: &cache)

        page.strokes.append(line(atY: 40, taggedAs: page.firstProblem))
        _ = traceRegions(of: page, in: &cache)

        #expect(cache.traceCount == 3)
    }

    @Test("Moving a problem's ink retraces it, even though its strokes keep their ids")
    func retracesInkThatWasDragged() {
        var cache = ProblemBoundsCache()
        var page = page()
        _ = traceRegions(of: page, in: &cache)

        page.strokes[0].translate(by: CGPoint(x: 500, y: 0))
        let framed = traceRegions(of: page, in: &cache)

        #expect(cache.traceCount == 3)
        let moved = framed.first { $0.nodeID == page.firstProblem }
        #expect((moved?.extent.midX ?? 0) > 400)
    }

    @Test("Untagged ink is traced not at all — there is no problem to frame it as")
    func untaggedInkTracesNothing() {
        var cache = ProblemBoundsCache()
        var page = page()
        _ = traceRegions(of: page, in: &cache)

        page.strokes.append(line(atY: 4000, taggedAs: nil))
        let framed = traceRegions(of: page, in: &cache)

        #expect(cache.traceCount == 2)
        #expect(framed.count == 2)
    }

    @Test("A page with no problem assigned to anything traces nothing at all")
    func pageOfUntaggedInkTracesNothing() {
        var cache = ProblemBoundsCache()
        var page = page()
        page.strokes = [line(atY: 0, taggedAs: nil), line(atY: 2000, taggedAs: nil)]

        #expect(traceRegions(of: page, in: &cache).isEmpty)
        #expect(cache.traceCount == 0)
    }

    @Test("Reordering the tree relabels the regions without retracing them")
    func reorderRelabelsWithoutRetracing() throws {
        var cache = ProblemBoundsCache()
        var page = page()
        _ = traceRegions(of: page, in: &cache)

        // Problem 2 becomes problem 1's part a: the same ink, a new address.
        let movedPath = try #require(page.outline.path(ofNode: page.secondProblem))
        page.outline.move(nodeAt: movedPath, toParent: page.firstProblem, at: 0)
        let framed = traceRegions(of: page, in: &cache)

        #expect(cache.traceCount == 2)
        #expect(page.outline.path(ofNode: page.secondProblem) == [0, 0])
        let moved = framed.first { $0.nodeID == page.secondProblem }
        #expect(moved?.tag == page.outline.tag(at: [0, 0]))
        #expect(moved?.problemIndex == 0)
    }

    @Test("Erasing a problem's ink drops its region")
    func erasedProblemLosesItsRegion() {
        var cache = ProblemBoundsCache()
        var page = page()
        _ = traceRegions(of: page, in: &cache)

        let erasedProblem = page.secondProblem
        page.strokes.removeAll { $0.problemNodeID == erasedProblem }
        let framed = traceRegions(of: page, in: &cache)

        #expect(framed.map(\.nodeID) == [page.firstProblem])
        #expect(cache.traceCount == 2)
    }
}
