import Testing
import CoreGraphics
@testable import Tract

/// The invariants the whole pipeline is judged by: nothing overlaps, nothing
/// leaves the paper, nothing is lost, and the sheet still reads in order.
@Suite("Worksheet layout")
struct WorksheetLayoutTests {
    private let page = WorksheetFixtures.letterLandscape
    private let options = WorksheetOptions()

    @Test("No two problems' outlines ever overlap, on any page")
    func problemsNeverCollide() {
        let sheets = WorksheetLayoutEngine.sheets(
            for: WorksheetFixtures.numberedBlocks(12),
            page: page,
            options: options
        )

        for sheet in sheets {
            let outlines = sheet.placements.map { $0.outline(padding: options.padding) }
            for first in outlines.indices {
                for second in outlines.indices where second > first {
                    #expect(!WorksheetPolygon.intersect(outlines[first], outlines[second]))
                }
            }
        }
    }

    @Test("Ink is kept clear of its neighbour's ink by more than the padding")
    func clearanceIsRealDistanceBetweenInk() throws {
        // Two padded outlines that do not overlap leave twice the padding
        // between the hulls inside them — that is where the whole clearance
        // comes from, since the packer leaves no gaps between rows.
        let sheets = WorksheetLayoutEngine.sheets(
            for: WorksheetFixtures.numberedBlocks(6),
            page: page,
            options: options
        )
        let placements = try #require(sheets.first).placements

        for first in placements.indices {
            for second in placements.indices where second > first {
                let neighbourHull = placements[second].inkHull
                let nearest = placements[first].inkHull
                    .map { WorksheetPolygon.distance(from: $0, to: neighbourHull) }
                    .min() ?? 0
                #expect(nearest > options.padding)
            }
        }
    }

    @Test("No outline crosses a page margin")
    func nothingLeavesTheContentBox() {
        let sheets = WorksheetLayoutEngine.sheets(
            for: WorksheetFixtures.numberedBlocks(12),
            page: page,
            options: options
        )

        for sheet in sheets {
            for placement in sheet.placements {
                let bounds = WorksheetPolygon.bounds(of: placement.outline(padding: options.padding))
                #expect(page.contentRect.insetBy(dx: -0.001, dy: -0.001).contains(bounds))
            }
        }
    }

    @Test("Every problem is placed exactly once")
    func nothingIsLostOrDuplicated() {
        let blocks = WorksheetFixtures.numberedBlocks(12)

        let placed = WorksheetLayoutEngine.sheets(for: blocks, page: page, options: options)
            .flatMap { $0.placements.map(\.block.label) }

        #expect(placed.sorted() == blocks.map(\.label).sorted())
        #expect(Set(placed).count == placed.count)
    }

    @Test("Reading order survives pagination: flattening the pages gives the input order back")
    func readingOrderIsPreservedAcrossPages() {
        // Big blocks, so this really does span several sheets.
        let blocks = WorksheetFixtures.numberedBlocks(9, side: 260)

        let sheets = WorksheetLayoutEngine.sheets(for: blocks, page: page, options: options)

        #expect(sheets.count > 1)
        #expect(sheets.flatMap { $0.placements.map(\.block.label) } == blocks.map(\.label))
    }

    @Test("A problem too big for an empty page is still placed rather than dropped")
    func anOversizedProblemIsStillDrawn() {
        let enormous = WorksheetFixtures.block(label: "1", side: 4_000)

        var noGrowth = options
        noGrowth.refitsPages = false
        noGrowth.growsProblems = false
        let sheets = WorksheetLayoutEngine.sheets(for: [enormous], page: page, options: noGrowth)

        // On its own sheet, and not behind a blank one it never fitted on.
        #expect(sheets.count == 1)
        #expect(sheets.flatMap(\.placements).count == 1)
    }

    @Test("A shape slides under a slanted neighbour instead of sitting below its box")
    func wedgesNestIntoEachOther() throws {
        // The packer's whole reason for existing. These two triangles interlock;
        // dropped against bounding boxes the second would start a full 300pt
        // lower, below the first one's box.
        // The first one's lower edge falls away to the left; the second one's
        // upper edge rises to meet it.
        let cutAwayBelow = WorksheetFixtures.block(
            label: "1",
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0), CGPoint(x: 300, y: 300)]
        )
        let cutAwayAbove = WorksheetFixtures.block(
            label: "2",
            points: [CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 300), CGPoint(x: 0, y: 300)]
        )

        // Paper only wide enough for one of them, so sitting side by side is not
        // an option the packer can take instead.
        let narrowPage = WorksheetPageGeometry(size: CGSize(width: 400, height: 900), margin: 36)
        let sheets = WorksheetNester.nest(
            [cutAwayBelow, cutAwayAbove],
            page: narrowPage,
            padding: options.padding,
            scale: 1
        )

        let placements = try #require(sheets.first).placements
        #expect(placements.count == 2)
        let first = WorksheetPolygon.bounds(of: placements[0].outline(padding: options.padding))
        let second = WorksheetPolygon.bounds(of: placements[1].outline(padding: options.padding))
        #expect(second.minY < first.maxY)
    }

    @Test("Refitting a sparse page enlarges what landed on it")
    func refitFillsAPageThatWasLeftSmall() {
        let blocks = WorksheetFixtures.numberedBlocks(2, side: 120)
        let nested = WorksheetNester.nest(blocks, page: page, padding: options.padding, scale: 0.8)

        let refitted = WorksheetNester.refit(
            nested,
            page: page,
            padding: options.padding,
            cap: options.growthCap
        )

        #expect(refitted.flatMap(\.placements).allSatisfy { $0.scale > 0.8 })
        #expect(refitted.flatMap(\.placements).allSatisfy { $0.scale <= options.growthCap })
    }

    @Test("The chosen scale is the largest that still fits the fewest pages")
    func scaleSearchPrefersPagesThenSize() {
        // A layout that needs a second page past 1x and a third past 2x: the
        // search must land as close to 1x as it can without spilling to two.
        let scale = WorksheetScaleSearch.uniformScale(
            measurePageCount: { $0 > 2 ? 3 : ($0 > 1 ? 2 : 1) },
            minimumScale: 0.8,
            maximumScale: 4
        )

        #expect(scale > 0.99)
        #expect(scale <= 1)
    }
}
