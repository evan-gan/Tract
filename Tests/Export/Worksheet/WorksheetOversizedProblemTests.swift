import Testing
import CoreGraphics
@testable import Tract

/// A problem bigger than the paper must be shrunk onto a page of its own rather
/// than cut off at the margin — without changing how problems that already fit
/// are laid out.
@Suite("Worksheet oversized problems")
struct WorksheetOversizedProblemTests {
    private let page = WorksheetFixtures.letterLandscape
    private let options = WorksheetOptions()

    private func isInsideContentBox(_ placement: WorksheetPlacement) -> Bool {
        let bounds = WorksheetPolygon.bounds(of: placement.outline(padding: options.padding))
        return page.contentRect.insetBy(dx: -0.001, dy: -0.001).contains(bounds)
    }

    @Test("A problem too big at the readability floor is shrunk to fit inside the margins")
    func oversizedProblemFitsItsPage() throws {
        let enormous = WorksheetFixtures.block(label: "1", side: 2_000)

        let sheets = WorksheetLayoutEngine.sheets(for: [enormous], page: page, options: options)

        let placement = try #require(sheets.first?.placements.first)
        #expect(sheets.count == 1)
        #expect(placement.scale < options.minimumScale)
        #expect(isInsideContentBox(placement))
    }

    @Test("An oversized problem gets a sheet to itself, and reading order survives around it")
    func oversizedProblemSitsAloneInReadingOrder() throws {
        let blocks = [
            WorksheetFixtures.block(label: "1", groupIndex: 0, side: 120),
            WorksheetFixtures.block(label: "2", groupIndex: 1, side: 2_000),
            WorksheetFixtures.block(label: "3", groupIndex: 2, side: 120)
        ]

        let sheets = WorksheetLayoutEngine.sheets(for: blocks, page: page, options: options)

        #expect(sheets.flatMap { $0.placements.map(\.block.label) } == ["1", "2", "3"])
        let oversizedSheet = try #require(sheets.first { $0.placements.contains { $0.block.label == "2" } })
        #expect(oversizedSheet.placements.count == 1)
        #expect(sheets.flatMap(\.placements).allSatisfy(isInsideContentBox))
    }

    @Test("Problems that fit keep a readable scale when an oversized one shares the export")
    func smallProblemsAreNotShrunkByABigNeighbour() {
        let blocks = [
            WorksheetFixtures.block(label: "1", groupIndex: 0, side: 120),
            WorksheetFixtures.block(label: "2", groupIndex: 1, side: 2_000),
            WorksheetFixtures.block(label: "3", groupIndex: 2, side: 120)
        ]

        let smallPlacements = WorksheetLayoutEngine.sheets(for: blocks, page: page, options: options)
            .flatMap(\.placements)
            .filter { $0.block.label != "2" }

        #expect(smallPlacements.count == 2)
        #expect(smallPlacements.allSatisfy { $0.scale >= options.minimumScale })
    }

    @Test("A single large-but-readable problem is enlarged only as far as the paper allows")
    func loneProblemIsNotEnlargedPastThePaper() throws {
        // Big enough that the old page-count search, seeing one page at every
        // scale, would have picked the 4x maximum and run it off the sheet.
        let large = WorksheetFixtures.block(label: "1", side: 400)

        let sheets = WorksheetLayoutEngine.sheets(for: [large], page: page, options: options)

        let placement = try #require(sheets.first?.placements.first)
        #expect(placement.scale >= options.minimumScale)
        #expect(isInsideContentBox(placement))
    }

    @Test("A lone small problem is still enlarged to fill the page")
    func loneSmallProblemStillGrows() throws {
        let small = WorksheetFixtures.block(label: "1", side: 60)

        let sheets = WorksheetLayoutEngine.sheets(for: [small], page: page, options: options)

        let placement = try #require(sheets.first?.placements.first)
        #expect(placement.scale > 1)
        #expect(isInsideContentBox(placement))
    }

    @Test("The fitting-scale search returns the ceiling for a problem that already fits")
    func fittingScaleIsCeilingForSmallProblem() {
        let tiny = WorksheetFixtures.block(label: "1", side: 20)

        let scale = WorksheetNester.largestScaleFittingEmptyPage(
            tiny,
            page: page,
            padding: options.padding,
            ceiling: 2
        )

        #expect(scale == 2)
    }

    @Test("The fitting-scale search lands just under the size where a big problem overflows")
    func fittingScaleIsTightForBigProblem() throws {
        let enormous = WorksheetFixtures.block(label: "1", side: 2_000)

        let scale = try #require(WorksheetNester.largestScaleFittingEmptyPage(
            enormous,
            page: page,
            padding: options.padding,
            ceiling: options.maximumScale
        ))

        let fits = { (candidate: CGFloat) in
            let sheets = WorksheetNester.nest([enormous], page: self.page, padding: self.options.padding, scale: candidate)
            return sheets.flatMap(\.placements).allSatisfy(self.isInsideContentBox)
        }
        #expect(fits(scale))
        #expect(!fits(scale * 1.02))
    }
}
