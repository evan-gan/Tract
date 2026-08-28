import Testing
import SwiftUI
@testable import Tract

/// The dock snaps to whichever quadrant the drag ends in, where quadrants are
/// the four triangles cut by the container's corner-to-corner diagonals.
@Suite("DockEdge quadrant snapping")
struct DockEdgeQuadrantTests {
    private let container = CGSize(width: 1000, height: 600)

    @Test("A point near the top edge snaps to the top")
    func topQuadrant() {
        #expect(DockEdge.nearest(to: CGPoint(x: 500, y: 40), in: container) == .top)
    }

    @Test("A point near the bottom edge snaps to the bottom")
    func bottomQuadrant() {
        #expect(DockEdge.nearest(to: CGPoint(x: 500, y: 560), in: container) == .bottom)
    }

    @Test("A point near the left edge snaps to leading")
    func leadingQuadrant() {
        #expect(DockEdge.nearest(to: CGPoint(x: 40, y: 300), in: container) == .leading)
    }

    @Test("A point near the right edge snaps to trailing")
    func trailingQuadrant() {
        #expect(DockEdge.nearest(to: CGPoint(x: 960, y: 300), in: container) == .trailing)
    }

    @Test("A corner-adjacent point follows the diagonal, not raw edge distance")
    func cornerFollowsDiagonal() {
        // 100pt from the left and 90pt from the top of a wide container: the
        // nearest edge is the top, but the point sits below the top-left
        // diagonal (y/h = 0.15 > x/w = 0.10), so it belongs to the left.
        #expect(DockEdge.nearest(to: CGPoint(x: 100, y: 90), in: container) == .leading)
    }

    @Test("An off-container point still resolves to the edge it is heading past")
    func pointOutsideContainer() {
        #expect(DockEdge.nearest(to: CGPoint(x: -80, y: 300), in: container) == .leading)
    }

    @Test("A zero-size container falls back to the bottom edge")
    func emptyContainer() {
        #expect(DockEdge.nearest(to: .zero, in: .zero) == .bottom)
    }
}

@Suite("DockEdge layout")
struct DockEdgeLayoutTests {
    @Test("Top and bottom edges lay the dock out horizontally, sides vertically")
    func axisPerEdge() {
        #expect(DockEdge.top.axis == .horizontal)
        #expect(DockEdge.bottom.axis == .horizontal)
        #expect(DockEdge.leading.axis == .vertical)
        #expect(DockEdge.trailing.axis == .vertical)
    }

    @Test("Each edge parks the dock against itself")
    func alignmentPerEdge() {
        #expect(DockEdge.top.alignment == .top)
        #expect(DockEdge.bottom.alignment == .bottom)
        #expect(DockEdge.leading.alignment == .leading)
        #expect(DockEdge.trailing.alignment == .trailing)
    }

    @Test("Tools lift away from whichever edge the dock is parked on")
    func liftPointsIntoTheCanvas() {
        #expect(DockEdge.bottom.liftDirection == CGSize(width: 0, height: -1))
        #expect(DockEdge.top.liftDirection == CGSize(width: 0, height: 1))
        #expect(DockEdge.leading.liftDirection == CGSize(width: 1, height: 0))
        #expect(DockEdge.trailing.liftDirection == CGSize(width: -1, height: 0))
    }
}
