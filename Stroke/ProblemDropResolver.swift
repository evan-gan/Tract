import Foundation

/// Where a dragged node would land: the level it would sit at, whose child it
/// would become, and how far down that parent's list it would go.
struct ProblemDropTarget: Equatable, Sendable {
    /// 0 for a problem, 1 for a part, 2 for a numeral.
    let level: Int
    /// Identity of the parent it would join, nil for the top level.
    let parentID: UUID?
    /// Index among the parent's children *as they stand with the dragged subtree
    /// lifted out* — which is what makes the classic "moved down within the same
    /// list" off-by-one disappear rather than needing to be corrected for.
    let index: Int
}

/// The pure maths behind dragging a row around the outline.
///
/// It works on the visible rows with the dragged subtree already removed. That
/// single decision does three jobs: it stops a node being dropped inside
/// itself, it makes the insertion index directly usable after the node is
/// lifted out, and it keeps the drop marker pointing at rows that will still be
/// there afterwards.
enum ProblemDropResolver {
    /// How many rows sit above the pointer — the gap the insertion line marks.
    /// Counts midpoints, so the marker flips as the pointer passes the middle of
    /// a row rather than its edge.
    static func gapIndex(pointerY: CGFloat, rowCount: Int, rowHeight: CGFloat) -> Int {
        guard rowHeight > 0 else { return 0 }
        let crossed = (0 ..< rowCount).filter { index in
            let midpoint = (CGFloat(index) + 0.5) * rowHeight
            return midpoint < pointerY
        }
        return crossed.count
    }

    /// Resolves a drop, stepping the level up toward the top of the tree until
    /// one actually has a parent at this position. Level 0 always resolves,
    /// since the root list is always there — so a target is always returned and
    /// the marker never points at nothing.
    ///
    /// - Parameters:
    ///   - rows: Visible rows, dragged subtree excluded, in draw order.
    ///   - gapIndex: Result of `gapIndex(pointerY:rowCount:rowHeight:)`.
    ///   - desiredLevel: The level the drag is currently carrying.
    ///   - maximumLevel: `3 - depth(node)`; the deepest the subtree may legally sit.
    static func target(
        rows: [ProblemOutlineRow],
        gapIndex: Int,
        desiredLevel: Int,
        maximumLevel: Int
    ) -> ProblemDropTarget {
        let clampedGap = min(max(gapIndex, 0), rows.count)
        var level = min(max(desiredLevel, 0), max(maximumLevel, 0))

        while level > 0 {
            if let parent = nearestParent(in: rows, above: clampedGap, atLevel: level) {
                return ProblemDropTarget(
                    level: level,
                    parentID: parent.id,
                    index: childCount(of: parent.id, in: rows, before: clampedGap)
                )
            }
            level -= 1
        }
        return ProblemDropTarget(
            level: 0,
            parentID: nil,
            index: childCount(of: nil, in: rows, before: clampedGap)
        )
    }

    /// The nearest row above the gap that is one level shallower — the only row
    /// that could adopt a node dropped at `level` here.
    private static func nearestParent(
        in rows: [ProblemOutlineRow],
        above gapIndex: Int,
        atLevel level: Int
    ) -> ProblemOutlineRow? {
        rows[0 ..< min(gapIndex, rows.count)]
            .last { $0.level == level - 1 }
    }

    private static func childCount(
        of parentID: UUID?,
        in rows: [ProblemOutlineRow],
        before gapIndex: Int
    ) -> Int {
        rows[0 ..< min(gapIndex, rows.count)]
            .count { $0.parentID == parentID }
    }
}

extension ProblemDropResolver {
    /// Maps a gap measured against the rows *on screen* onto the same gap in the
    /// list the resolver works with, where the dragged subtree has been taken
    /// out. The dragged rows stay visible — dimmed in place — so the two lists
    /// do not line up, and the insertion marker and the resolved index would
    /// otherwise disagree by however many dragged rows sit above the pointer.
    static func survivingGap(
        in displayedRows: [ProblemOutlineRow],
        displayedGap: Int,
        excludedIDs: Set<UUID>
    ) -> Int {
        displayedRows[0 ..< min(max(displayedGap, 0), displayedRows.count)]
            .count { !excludedIDs.contains($0.id) }
    }
}
