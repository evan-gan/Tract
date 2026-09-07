import Testing
import CoreGraphics
@testable import Tract

@Suite("Worksheet separators")
struct WorksheetSeparatorsTests {
    private let page = WorksheetPageGeometry(size: CGSize(width: 400, height: 400), margin: 36)

    /// Two problems side by side, so the boundary between them is the vertical
    /// line halfway across the sheet.
    private var twoRegionsSideBySide: [[CGPoint]] {
        [
            WorksheetPolygon.corners(of: CGRect(x: 50, y: 100, width: 100, height: 200)),
            WorksheetPolygon.corners(of: CGRect(x: 250, y: 100, width: 100, height: 200))
        ]
    }

    @Test("One problem on a page has nothing to be divided from")
    func aSingleRegionProducesNoLines() {
        let single = [WorksheetPolygon.corners(of: CGRect(x: 50, y: 50, width: 100, height: 100))]

        #expect(WorksheetSeparators.lines(dividing: single, page: page).isEmpty)
        #expect(WorksheetSeparators.lines(dividing: [], page: page).isEmpty)
    }

    @Test("A boundary that really is straight comes out straight, not as a staircase")
    func straightBoundariesStayStraight() throws {
        // Tracing on a grid produces steps; straightening before smoothing is
        // what collapses them back to the line they approximate.
        let line = try #require(WorksheetSeparators.lines(dividing: twoRegionsSideBySide, page: page).first)

        let horizontalSpread = (line.map(\.x).max() ?? 0) - (line.map(\.x).min() ?? 0)
        #expect(line.count >= 2)
        #expect(horizontalSpread < 1)
        #expect(abs((line.first?.x ?? 0) - 200) <= 6)
    }

    @Test("Separators run out to the edges of the sheet, not just to the margins")
    func linesReachTheSheetEdges() {
        let lines = WorksheetSeparators.lines(dividing: twoRegionsSideBySide, page: page)
        let heights = lines.flatMap { $0.map(\.y) }

        // A line that stopped at the content box would leave the page looking
        // like the problems float rather than like the sheet is divided.
        #expect((heights.min() ?? .greatestFiniteMagnitude) <= 6)
        #expect((heights.max() ?? 0) >= page.size.height - 12)
    }

    @Test("Three problems meet at a junction rather than crossing each other's lines")
    func junctionsBreakLinesApart() {
        // Each line divides exactly one pair of problems along its length, so
        // three problems around a point give three lines meeting there.
        let regions = [
            WorksheetPolygon.corners(of: CGRect(x: 40, y: 40, width: 80, height: 80)),
            WorksheetPolygon.corners(of: CGRect(x: 280, y: 40, width: 80, height: 80)),
            WorksheetPolygon.corners(of: CGRect(x: 160, y: 280, width: 80, height: 80))
        ]

        let lines = WorksheetSeparators.lines(dividing: regions, page: page)

        #expect(lines.count >= 3)
        #expect(lines.allSatisfy { $0.count >= 2 })
    }
}
