import CoreGraphics
import Foundation

/// Arranges every tagged problem into a grid: one row per top-level problem,
/// one column per lettered part, and a row exactly as tall as the tallest thing
/// standing in it.
///
/// Pure maths over `ProblemLayoutCell`s — no view, no view model, no ink. It
/// answers "where should each problem sit" and nothing else, so the whole
/// arrangement is testable without a canvas.
enum ProblemLayoutGrid {

    /// Where the grid puts every problem, and the structure behind that — which
    /// the focus layout needs in order to know what is beside what.
    struct Arrangement: Equatable, Sendable {
        var placement: ProblemLayoutPlacement
        /// The laid-out box each problem ends up occupying, in canvas space.
        var framesByNodeID: [UUID: CGRect]
        /// The cells the arrangement was built from, so a caller can ask which
        /// row or column something landed in without re-deriving it.
        var cells: [ProblemLayoutCell]

        static let empty = Arrangement(
            placement: .identity,
            framesByNodeID: [:],
            cells: []
        )
    }

    /// Lays the cells out and reports where each one went.
    ///
    /// - Parameter cells: One per problem that has ink. Order does not matter;
    ///   position in the grid comes from each cell's path, never from the order
    ///   they arrive in.
    /// - Returns: The offset and final frame for every cell. Empty input gives
    ///   `.empty`, which reads as "nothing to arrange" rather than as a grid of
    ///   no problems anchored at the origin.
    static func arrange(_ cells: [ProblemLayoutCell]) -> Arrangement {
        let usableCells = cells.filter { !$0.bounds.isNull && !$0.bounds.isEmpty }
        guard !usableCells.isEmpty else { return .empty }

        let stacks = stacks(in: usableCells)
        let columnWidths = columnWidths(of: stacks)
        let rowHeights = rowHeights(of: stacks)
        let origin = anchor(of: usableCells)

        let columnLefts = runningStarts(
            sizes: columnWidths,
            gutter: ProblemLayoutMetrics.columnGutter,
            from: origin.x
        )
        let rowTops = runningStarts(
            sizes: rowHeights,
            gutter: ProblemLayoutMetrics.rowGutter,
            from: origin.y
        )

        return build(stacks, columnLefts: columnLefts, rowTops: rowTops, cells: usableCells)
    }

    // MARK: - Grouping

    /// A row/column slot and the cells stacked inside it, top to bottom.
    private struct Stack {
        let row: Int
        let column: Int
        var cells: [ProblemLayoutCell]

        /// The stack is as wide as its widest member and as tall as all of them
        /// plus the gaps between.
        var size: CGSize {
            let width = cells.map(\.bounds.width).max() ?? 0
            let height = cells.map(\.bounds.height).reduce(0, +)
                + ProblemLayoutMetrics.stackGutter * CGFloat(max(cells.count - 1, 0))
            return CGSize(width: width, height: height)
        }
    }

    private static func stacks(in cells: [ProblemLayoutCell]) -> [Stack] {
        var bySlot: [[Int]: [ProblemLayoutCell]] = [:]
        for cell in cells {
            bySlot[[cell.row, cell.column], default: []].append(cell)
        }
        return bySlot
            .map { slot, members in
                // Sorted by stack position so a sub-sub-problem never renders
                // above the part it belongs to just because of dictionary order.
                Stack(row: slot[0], column: slot[1], cells: members.sorted { $0.stack < $1.stack })
            }
            .sorted { ($0.row, $0.column) < ($1.row, $1.column) }
    }

    // MARK: - Measuring

    /// Columns are sized across the *whole* grid, not per row, so part (b) of
    /// problem 1 lines up under part (b) of problem 2. That alignment is what
    /// makes the arrangement read as a table of work rather than as a set of
    /// unrelated rows.
    private static func columnWidths(of stacks: [Stack]) -> [Int: CGFloat] {
        var widths: [Int: CGFloat] = [:]
        for stack in stacks {
            widths[stack.column] = max(widths[stack.column] ?? 0, stack.size.width)
        }
        return widths
    }

    /// A row is as tall as the tallest problem standing in it.
    private static func rowHeights(of stacks: [Stack]) -> [Int: CGFloat] {
        var heights: [Int: CGFloat] = [:]
        for stack in stacks {
            heights[stack.row] = max(heights[stack.row] ?? 0, stack.size.height)
        }
        return heights
    }

    /// The top-left the grid is built out from — where the tagged work already
    /// sits. Anchoring here rather than at the canvas origin means switching the
    /// layout on tidies the page in place instead of throwing it somewhere the
    /// user then has to go and find.
    private static func anchor(of cells: [ProblemLayoutCell]) -> CGPoint {
        CGPoint(
            x: cells.map(\.bounds.minX).min() ?? 0,
            y: cells.map(\.bounds.minY).min() ?? 0
        )
    }

    /// Turns a sparse map of track sizes into the start coordinate of each
    /// track. Indices with nothing in them take no space at all, so a document
    /// whose only work is problem 5 does not open on four empty rows.
    private static func runningStarts(
        sizes: [Int: CGFloat],
        gutter: CGFloat,
        from start: CGFloat
    ) -> [Int: CGFloat] {
        var starts: [Int: CGFloat] = [:]
        var cursor = start
        for index in sizes.keys.sorted() {
            starts[index] = cursor
            cursor += (sizes[index] ?? 0) + gutter
        }
        return starts
    }

    // MARK: - Placing

    private static func build(
        _ stacks: [Stack],
        columnLefts: [Int: CGFloat],
        rowTops: [Int: CGFloat],
        cells: [ProblemLayoutCell]
    ) -> Arrangement {
        var offsets: [UUID: CGPoint] = [:]
        var frames: [UUID: CGRect] = [:]

        for stack in stacks {
            let left = columnLefts[stack.column] ?? 0
            var top = rowTops[stack.row] ?? 0
            for cell in stack.cells {
                let target = CGPoint(x: left, y: top)
                offsets[cell.nodeID] = CGPoint(
                    x: target.x - cell.bounds.minX,
                    y: target.y - cell.bounds.minY
                )
                frames[cell.nodeID] = CGRect(origin: target, size: cell.bounds.size)
                top += cell.bounds.height + ProblemLayoutMetrics.stackGutter
            }
        }

        return Arrangement(
            placement: ProblemLayoutPlacement(offsetsByNodeID: offsets),
            framesByNodeID: frames,
            cells: cells
        )
    }
}
