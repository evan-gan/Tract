import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// The grid's contract: one row per problem, its parts across the row, every
/// row as tall as the tallest thing standing in it, and columns that line up
/// across the whole page.
@Suite("Problem layout grid")
struct ProblemLayoutGridTests {

    /// Cells are built at deliberately scattered coordinates, because the whole
    /// point of the grid is that where a problem *was* written has no bearing
    /// on where it ends up.
    private func cell(_ address: [Int], _ bounds: CGRect) -> ProblemLayoutCell {
        ProblemLayoutCell(
            nodeID: UUID(),
            path: address.map { $0 - 1 },
            bounds: bounds
        )
    }

    private func frame(
        _ arrangement: ProblemLayoutGrid.Arrangement,
        _ cell: ProblemLayoutCell
    ) -> CGRect {
        arrangement.framesByNodeID[cell.nodeID] ?? .null
    }

    @Test("A problem and its parts land on one row")
    func partsShareARow() {
        let problem = cell([1], CGRect(x: 900, y: 40, width: 100, height: 50))
        let partA = cell([1, 1], CGRect(x: -300, y: 700, width: 100, height: 50))
        let partB = cell([1, 2], CGRect(x: 50, y: -900, width: 100, height: 50))
        let arrangement = ProblemLayoutGrid.arrange([partB, problem, partA])

        #expect(frame(arrangement, problem).minY == frame(arrangement, partA).minY)
        #expect(frame(arrangement, partA).minY == frame(arrangement, partB).minY)
    }

    @Test("Parts run left to right in address order, whatever order they arrive in")
    func partsOrderedAcrossTheRow() {
        let problem = cell([1], CGRect(x: 0, y: 0, width: 100, height: 50))
        let partA = cell([1, 1], CGRect(x: 0, y: 0, width: 100, height: 50))
        let partB = cell([1, 2], CGRect(x: 0, y: 0, width: 100, height: 50))
        let arrangement = ProblemLayoutGrid.arrange([partB, partA, problem])

        #expect(frame(arrangement, problem).minX < frame(arrangement, partA).minX)
        #expect(frame(arrangement, partA).minX < frame(arrangement, partB).minX)
    }

    @Test("Problem 2's row starts below the tallest thing in problem 1's")
    func rowIsAsTallAsItsTallestProblem() {
        let short = cell([1], CGRect(x: 0, y: 0, width: 100, height: 40))
        let tall = cell([1, 1], CGRect(x: 0, y: 0, width: 100, height: 400))
        let below = cell([2], CGRect(x: 0, y: 0, width: 100, height: 40))
        let arrangement = ProblemLayoutGrid.arrange([short, tall, below])

        #expect(frame(arrangement, below).minY >= frame(arrangement, tall).maxY)
    }

    @Test("A row is no taller than it needs to be")
    func rowHeightIsExactlyTheTallestPlusTheGutter() {
        let short = cell([1], CGRect(x: 0, y: 0, width: 100, height: 40))
        let tall = cell([1, 1], CGRect(x: 0, y: 0, width: 100, height: 400))
        let below = cell([2], CGRect(x: 0, y: 0, width: 100, height: 40))
        let arrangement = ProblemLayoutGrid.arrange([short, tall, below])

        let rowTop = frame(arrangement, short).minY
        let expected = rowTop + 400 + ProblemLayoutMetrics.rowGutter
        #expect(abs(frame(arrangement, below).minY - expected) < 0.001)
    }

    @Test("Columns line up across rows, so part (a) sits under part (a)")
    func columnsAlignAcrossRows() {
        let cells = [
            cell([1], CGRect(x: 0, y: 0, width: 500, height: 50)),
            cell([1, 1], CGRect(x: 0, y: 0, width: 100, height: 50)),
            cell([2], CGRect(x: 0, y: 0, width: 80, height: 50)),
            cell([2, 1], CGRect(x: 0, y: 0, width: 100, height: 50))
        ]
        let arrangement = ProblemLayoutGrid.arrange(cells)

        #expect(frame(arrangement, cells[1]).minX == frame(arrangement, cells[3]).minX)
    }

    @Test("A column is as wide as the widest problem standing in it")
    func columnWidthComesFromTheWidestMember() {
        let wide = cell([1], CGRect(x: 0, y: 0, width: 500, height: 50))
        let narrow = cell([2], CGRect(x: 0, y: 0, width: 80, height: 50))
        let besideNarrow = cell([2, 1], CGRect(x: 0, y: 0, width: 100, height: 50))
        let arrangement = ProblemLayoutGrid.arrange([wide, narrow, besideNarrow])

        // The first column is sized by problem 1, not by problem 2, so problem
        // 2's part still clears the widest thing in the column to its left.
        let expected = frame(arrangement, wide).minX + 500 + ProblemLayoutMetrics.columnGutter
        #expect(abs(frame(arrangement, besideNarrow).minX - expected) < 0.001)
    }

    @Test("Sub-sub-problems stack under the part they belong to, in order")
    func subSubProblemsStackVertically() {
        let part = cell([1, 1], CGRect(x: 0, y: 0, width: 100, height: 50))
        let first = cell([1, 1, 1], CGRect(x: 0, y: 0, width: 100, height: 50))
        let second = cell([1, 1, 2], CGRect(x: 0, y: 0, width: 100, height: 50))
        let arrangement = ProblemLayoutGrid.arrange([second, first, part])

        #expect(frame(arrangement, part).minX == frame(arrangement, first).minX)
        #expect(frame(arrangement, first).minY > frame(arrangement, part).minY)
        #expect(frame(arrangement, second).minY > frame(arrangement, first).minY)
    }

    @Test("The grid forms where the work already is, not at the canvas origin")
    func anchoredOnTheExistingWork() {
        let first = cell([1], CGRect(x: 4000, y: 2500, width: 100, height: 50))
        let second = cell([2], CGRect(x: 4300, y: 9000, width: 100, height: 50))
        let arrangement = ProblemLayoutGrid.arrange([first, second])

        #expect(frame(arrangement, first).minX == 4000)
        #expect(frame(arrangement, first).minY == 2500)
    }

    @Test("A gap in the numbering costs no empty rows")
    func missingProblemsTakeNoSpace() {
        let first = cell([1], CGRect(x: 0, y: 0, width: 100, height: 50))
        let fifth = cell([5], CGRect(x: 0, y: 0, width: 100, height: 50))
        let arrangement = ProblemLayoutGrid.arrange([first, fifth])

        let expected = frame(arrangement, first).maxY + ProblemLayoutMetrics.rowGutter
        #expect(abs(frame(arrangement, fifth).minY - expected) < 0.001)
    }

    @Test("The offset is exactly what moves a problem from where it is stored")
    func offsetMatchesTheFrameItProduces() {
        let problem = cell([1], CGRect(x: 700, y: -200, width: 100, height: 50))
        let other = cell([2], CGRect(x: 0, y: 0, width: 100, height: 50))
        let arrangement = ProblemLayoutGrid.arrange([problem, other])

        let offset = arrangement.placement.offset(forNode: problem.nodeID)
        let moved = problem.bounds.offsetBy(dx: offset.x, dy: offset.y)
        #expect(moved == frame(arrangement, problem))
    }

    @Test("Nothing to arrange gives no arrangement at all")
    func emptyInputIsEmpty() {
        #expect(ProblemLayoutGrid.arrange([]) == .empty)
    }

    @Test("A problem with no extent is left out rather than placed at a point")
    func degenerateBoundsAreIgnored() {
        let empty = cell([1], .null)
        let real = cell([2], CGRect(x: 0, y: 0, width: 100, height: 50))
        let arrangement = ProblemLayoutGrid.arrange([empty, real])

        #expect(arrangement.framesByNodeID[empty.nodeID] == nil)
        #expect(arrangement.framesByNodeID[real.nodeID] != nil)
    }
}
