import CoreGraphics
import Foundation

/// The room made for the problem being edited, and the shove that makes it.
///
/// Two jobs, both pure. It sizes the box the focused problem gets to itself,
/// and it works out how far every other problem has to move to be clear of it.
///
/// The box is measured from the focused problem's **live ink bounds**, so it
/// keeps growing in proportion as the user writes — half a problem-width of
/// clear paper either side, whatever the problem grows into. Nothing here
/// re-traces a bubble: the whole focus mode is a translation of work that has
/// already been drawn and already been traced.
enum ProblemFocusLayout {

    /// What focusing one problem does to the page.
    struct Result: Equatable, Sendable {
        /// Canvas-space box the focused problem is given to itself. The dashed
        /// frame is drawn on this, and every other problem is pushed clear of it.
        var box: CGRect
        /// The extra shift each *other* problem takes on, on top of the grid's
        /// own placement.
        var pushByNodeID: [UUID: CGPoint]

        /// Nothing focused: no box, and nobody pushed anywhere.
        static let unfocused = Result(box: .null, pushByNodeID: [:])
    }

    /// Works out the box and the shove.
    ///
    /// - Parameters:
    ///   - focusedNodeID: The problem being edited.
    ///   - inkBounds: That problem's live ink bounds *in laid-out space* — the
    ///     grid offset already applied. Grows while the user writes, which is
    ///     what keeps the margins proportional without any re-tracing.
    ///   - arrangement: The grid the focus is happening inside.
    /// - Returns: `.unfocused` when there is no such problem to focus.
    static func resolve(
        focusedNodeID: UUID,
        inkBounds: CGRect,
        arrangement: ProblemLayoutGrid.Arrangement
    ) -> Result {
        guard let focusedCell = arrangement.cells.first(where: { $0.nodeID == focusedNodeID })
        else { return .unfocused }

        let box = box(around: inkBounds)
        return Result(
            box: box,
            pushByNodeID: pushes(
                clearing: box,
                focusedCell: focusedCell,
                arrangement: arrangement
            )
        )
    }

    // MARK: - The box

    /// The focused problem's ink with half its own size of clear paper on every
    /// side, and never less than `minimumFocusMargin`.
    ///
    /// Purely a function of the problem, which is the point: the box has to
    /// mean the same thing at every zoom, and it has to stay put while the page
    /// is panned under it. Anything derived from the viewport fails both.
    static func box(around inkBounds: CGRect) -> CGRect {
        guard !inkBounds.isNull, !inkBounds.isEmpty else { return .null }
        let fraction = ProblemLayoutMetrics.focusMarginFraction
        let floor = ProblemLayoutMetrics.minimumFocusMargin
        return inkBounds.insetBy(
            dx: -max(inkBounds.width * fraction, floor),
            dy: -max(inkBounds.height * fraction, floor)
        )
    }

    // MARK: - The shove

    /// How far each other problem moves to be clear of the box.
    ///
    /// One shift per side rather than one per problem: everything to the right
    /// of the focused problem moves by the same amount, so the row keeps its own
    /// spacing and only the gap around the focused problem opens up.
    ///
    /// The focused problem's own parts are pushed like anything else. Each part
    /// is a problem in its own right, with its own bubble and its own slot in
    /// the row — the box is sized around the work filed directly under the node
    /// that was tapped, and part (b) sitting in it would defeat the point.
    private static func pushes(
        clearing box: CGRect,
        focusedCell: ProblemLayoutCell,
        arrangement: ProblemLayoutGrid.Arrangement
    ) -> [UUID: CGPoint] {
        let displaced = arrangement.cells.filter { $0.nodeID != focusedCell.nodeID }
        let frames = arrangement.framesByNodeID

        let rightShift = clearance(
            of: displaced.filter { $0.row == focusedCell.row && $0.column > focusedCell.column },
            frames: frames
        ) { box.maxX + ProblemLayoutMetrics.columnGutter - $0.minX }

        let leftShift = clearance(
            of: displaced.filter { $0.row == focusedCell.row && $0.column < focusedCell.column },
            frames: frames
        ) { $0.maxX - (box.minX - ProblemLayoutMetrics.columnGutter) }

        let downShift = clearance(
            of: displaced.filter { $0.row > focusedCell.row },
            frames: frames
        ) { box.maxY + ProblemLayoutMetrics.rowGutter - $0.minY }

        let upShift = clearance(
            of: displaced.filter { $0.row < focusedCell.row },
            frames: frames
        ) { $0.maxY - (box.minY - ProblemLayoutMetrics.rowGutter) }

        var pushes: [UUID: CGPoint] = [:]
        for cell in displaced {
            pushes[cell.nodeID] = shift(
                for: cell,
                focusedCell: focusedCell,
                rightShift: rightShift,
                leftShift: leftShift,
                downShift: downShift,
                upShift: upShift
            )
        }
        return pushes
    }

    /// The largest overlap any of these problems has with the box, measured by
    /// `overlap`, and never negative — problems already clear of the box are not
    /// pulled *towards* it to close the gap.
    private static func clearance(
        of cells: [ProblemLayoutCell],
        frames: [UUID: CGRect],
        overlap: (CGRect) -> CGFloat
    ) -> CGFloat {
        let worst = cells.compactMap { frames[$0.nodeID].map(overlap) }.max() ?? 0
        return max(worst, 0)
    }

    /// Which way one problem moves. A problem in another row moves vertically
    /// and a problem beside it in the same row moves sideways, so the grid stays
    /// a grid — nothing travels diagonally into a neighbour's slot.
    private static func shift(
        for cell: ProblemLayoutCell,
        focusedCell: ProblemLayoutCell,
        rightShift: CGFloat,
        leftShift: CGFloat,
        downShift: CGFloat,
        upShift: CGFloat
    ) -> CGPoint {
        if cell.row > focusedCell.row { return CGPoint(x: 0, y: downShift) }
        if cell.row < focusedCell.row { return CGPoint(x: 0, y: -upShift) }
        if cell.column > focusedCell.column { return CGPoint(x: rightShift, y: 0) }
        if cell.column < focusedCell.column { return CGPoint(x: -leftShift, y: 0) }
        // Same slot as the focused problem but not part of it — a sibling
        // stacked under the same column. It moves the way the rows do.
        return CGPoint(x: 0, y: cell.stack > focusedCell.stack ? downShift : -upShift)
    }
}
