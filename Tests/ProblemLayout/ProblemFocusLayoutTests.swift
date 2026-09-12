import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// Focusing a problem gives it room: a box that stays in proportion to the work
/// as it is written, and a shove that moves everything else clear of it without
/// disturbing the order they are in.
@Suite("Problem focus layout")
struct ProblemFocusLayoutTests {

    private let square = CGRect(x: 0, y: 0, width: 100, height: 100)

    private func cell(_ address: [Int]) -> ProblemLayoutCell {
        ProblemLayoutCell(nodeID: UUID(), path: address.map { $0 - 1 }, bounds: square)
    }

    /// Problem 1 with a part beside it, problem 2 on the row below.
    private struct Page {
        let focused: ProblemLayoutCell
        let partOfFocused: ProblemLayoutCell
        let rightNeighbour: ProblemLayoutCell
        let rowBelow: ProblemLayoutCell
        let arrangement: ProblemLayoutGrid.Arrangement
    }

    private func page() -> Page {
        let focused = cell([1])
        let partOfFocused = cell([1, 1, 1])
        let rightNeighbour = cell([1, 2])
        let rowBelow = cell([2])
        return Page(
            focused: focused,
            partOfFocused: partOfFocused,
            rightNeighbour: rightNeighbour,
            rowBelow: rowBelow,
            arrangement: ProblemLayoutGrid.arrange(
                [focused, partOfFocused, rightNeighbour, rowBelow]
            )
        )
    }

    private func resolve(_ page: Page, inkBounds: CGRect) -> ProblemFocusLayout.Result {
        ProblemFocusLayout.resolve(
            focusedNodeID: page.focused.nodeID,
            inkBounds: inkBounds,
            arrangement: page.arrangement
        )
    }

    /// Big enough that the proportional margin beats the minimum one.
    private var largeInk: CGRect {
        CGRect(
            x: 0,
            y: 0,
            width: ProblemLayoutMetrics.minimumFocusMargin * 10,
            height: ProblemLayoutMetrics.minimumFocusMargin * 8
        )
    }

    // MARK: - The box

    @Test("The box keeps half the problem's own size clear on every side")
    func boxMarginsAreProportional() {
        let ink = largeInk
        let box = ProblemFocusLayout.box(around: ink)

        #expect(box.minX == ink.minX - ink.width / 2)
        #expect(box.maxX == ink.maxX + ink.width / 2)
        #expect(box.minY == ink.minY - ink.height / 2)
        #expect(box.maxY == ink.maxY + ink.height / 2)
    }

    @Test("Writing more widens the box in proportion, not by a fixed amount")
    func boxGrowsWithTheWriting() {
        let small = ProblemFocusLayout.box(around: largeInk)
        let large = ProblemFocusLayout.box(
            around: CGRect(origin: .zero, size: CGSize(
                width: largeInk.width * 2,
                height: largeInk.height
            ))
        )
        #expect(large.width == small.width * 2)
    }

    @Test("A problem that is still one short mark still gets room to write in")
    func smallProblemsGetTheMinimumMargin() {
        let speck = CGRect(x: 0, y: 0, width: 2, height: 2)
        let box = ProblemFocusLayout.box(around: speck)

        #expect(box.minX == -ProblemLayoutMetrics.minimumFocusMargin)
        #expect(box.maxY == 2 + ProblemLayoutMetrics.minimumFocusMargin)
    }

    /// The box used to be unioned with the viewport, which made it grow without
    /// limit as the user zoomed out — and because it is captured as canvas
    /// geometry, it never shrank back. The room a problem gets is a property of
    /// the problem, so it is bounded by the problem's own size.
    @Test("The box is bounded by the problem's own size")
    func boxCannotRunAwayFromTheProblem() {
        let ink = largeInk
        let box = ProblemFocusLayout.box(around: ink)
        let widest = ink.width * 2 + ProblemLayoutMetrics.minimumFocusMargin * 2

        #expect(box.width <= widest)
        #expect(box.height <= ink.height * 2 + ProblemLayoutMetrics.minimumFocusMargin * 2)
    }

    @Test("A problem with nothing written in it has no box")
    func emptyProblemHasNoBox() {
        #expect(ProblemFocusLayout.box(around: .null).isNull)
    }

    // MARK: - The shove

    @Test("The problem beside the focused one moves right, far enough to clear the box")
    func rightNeighbourClearsTheBox() {
        let page = page()
        let result = resolve(page, inkBounds: square)
        let push = result.pushByNodeID[page.rightNeighbour.nodeID] ?? .zero
        let frame = page.arrangement.framesByNodeID[page.rightNeighbour.nodeID]!

        #expect(push.x > 0)
        #expect(push.y == 0)
        #expect(frame.minX + push.x >= result.box.maxX + ProblemLayoutMetrics.columnGutter)
    }

    @Test("The row below moves down, far enough to clear the box")
    func rowBelowClearsTheBox() {
        let page = page()
        let result = resolve(page, inkBounds: square)
        let push = result.pushByNodeID[page.rowBelow.nodeID] ?? .zero
        let frame = page.arrangement.framesByNodeID[page.rowBelow.nodeID]!

        #expect(push.x == 0)
        #expect(push.y > 0)
        #expect(frame.minY + push.y >= result.box.maxY + ProblemLayoutMetrics.rowGutter)
    }

    @Test("The focused problem does not move")
    func focusedProblemStaysPut() {
        let page = page()
        let result = resolve(page, inkBounds: square)

        #expect(result.pushByNodeID[page.focused.nodeID] == nil)
    }

    /// A part is a problem in its own right with its own slot in the row, so
    /// focusing the problem it belongs to has to move it aside like anything
    /// else — the box is sized around the work filed directly under the node
    /// that was tapped, not around the whole subtree.
    @Test("A part of the focused problem is moved aside like any other problem")
    func partsOfTheFocusedProblemArePushed() {
        let page = page()
        let result = resolve(page, inkBounds: square)
        let push = result.pushByNodeID[page.partOfFocused.nodeID] ?? .zero

        #expect(push.x > 0)
    }

    @Test("Writing more pushes the neighbours further")
    func pushGrowsWithTheBox() {
        let page = page()
        let narrow = resolve(page, inkBounds: square)
        let wide = resolve(page, inkBounds: square.insetBy(dx: -400, dy: 0))

        let narrowPush = narrow.pushByNodeID[page.rightNeighbour.nodeID]?.x ?? 0
        let widePush = wide.pushByNodeID[page.rightNeighbour.nodeID]?.x ?? 0
        #expect(widePush > narrowPush)
    }

    @Test("A problem already clear of the box is not dragged towards it")
    func alreadyClearProblemsAreLeftAlone() {
        // A tall first row, so the row below already sits well past anything a
        // speck of ink could ask for.
        let focused = ProblemLayoutCell(
            nodeID: UUID(),
            path: [0],
            bounds: CGRect(x: 0, y: 0, width: 4000, height: 4000)
        )
        let below = ProblemLayoutCell(
            nodeID: UUID(),
            path: [1],
            bounds: CGRect(x: 0, y: 0, width: 10, height: 10)
        )
        let arrangement = ProblemLayoutGrid.arrange([focused, below])
        let result = ProblemFocusLayout.resolve(
            focusedNodeID: focused.nodeID,
            inkBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            arrangement: arrangement
        )

        #expect((result.pushByNodeID[below.nodeID] ?? .zero) == .zero)
    }

    @Test("Focusing a problem that is not on the page does nothing")
    func unknownProblemIsNotFocused() {
        let page = page()
        let result = ProblemFocusLayout.resolve(
            focusedNodeID: UUID(),
            inkBounds: square,
            arrangement: page.arrangement
        )
        #expect(result == .unfocused)
    }
}
