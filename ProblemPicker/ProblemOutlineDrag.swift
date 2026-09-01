import CoreGraphics
import Foundation

/// A row being carried around the outline, and everything that can be worked
/// out from where the pointer is.
///
/// Deliberately a value with no view in it: the drop rules are the fiddly part
/// of this control, and they are worth being able to test without a screen.
struct ProblemOutlineDrag: Equatable {
    let nodeID: UUID
    /// Where the node started. Re-resolved on drop, not trusted across edits.
    let path: ProblemPath
    let label: String
    let childCount: Int
    /// `3 - depth(node)`: a leaf reaches any level, a problem whose parts already
    /// carry numerals cannot move down at all.
    let maximumLevel: Int
    /// The node keeps the level it started at until a deliberate hold changes it.
    /// Vertical movement alone never reparents anything, which is what makes the
    /// gesture safe to use quickly.
    var level: Int
    /// Pointer position in the list's coordinate space.
    var pointerY: CGFloat
    /// The dragged row and its whole subtree, which take no part in resolving a
    /// drop — that is also what makes dropping a node inside itself impossible.
    let carriedIDs: Set<UUID>

    /// Builds a drag from the row that was picked up.
    init(row: ProblemOutlineRow, in outline: ProblemOutline, pointerY: CGFloat) {
        self.nodeID = row.id
        self.path = row.path
        self.label = row.label
        self.childCount = row.childCount
        self.maximumLevel = ProblemOutline.deepestLevel(
            forSubtreeDepth: outline.subtreeDepth(at: row.path)
        )
        self.level = row.level
        self.pointerY = pointerY
        self.carriedIDs = Set(
            outline.rows
                .filter { $0.path.count >= row.path.count && Array($0.path.prefix(row.path.count)) == row.path }
                .map(\.id)
        )
    }

    /// The gap between rows *as drawn*, which is where the insertion line goes.
    func displayedGap(rowCount: Int) -> Int {
        ProblemDropResolver.gapIndex(
            pointerY: pointerY,
            rowCount: rowCount,
            rowHeight: ProblemPickerMetrics.rowHeight
        )
    }

    /// Where the node would land if it were dropped now.
    func target(displayedRows: [ProblemOutlineRow]) -> ProblemDropTarget {
        let surviving = displayedRows.filter { !carriedIDs.contains($0.id) }
        let gap = ProblemDropResolver.survivingGap(
            in: displayedRows,
            displayedGap: displayedGap(rowCount: displayedRows.count),
            excludedIDs: carriedIDs
        )
        return ProblemDropResolver.target(
            rows: surviving,
            gapIndex: gap,
            desiredLevel: level,
            maximumLevel: maximumLevel
        )
    }

    /// The row the pointer is actually over — the one whose level a hold adopts.
    func hoveredRow(displayedRows: [ProblemOutlineRow]) -> ProblemOutlineRow? {
        let index = Int(pointerY / ProblemPickerMetrics.rowHeight)
        guard displayedRows.indices.contains(index) else { return nil }
        let row = displayedRows[index]
        return carriedIDs.contains(row.id) ? nil : row
    }

    /// The level a hold on the hovered row would change to, or nil when there is
    /// nothing to offer: the row is already at the drag's level, or at one this
    /// subtree is too tall to occupy.
    func pendingLevel(displayedRows: [ProblemOutlineRow]) -> Int? {
        guard let hovered = hoveredRow(displayedRows: displayedRows) else { return nil }
        guard hovered.level != level, hovered.level <= maximumLevel else { return nil }
        return hovered.level
    }
}
