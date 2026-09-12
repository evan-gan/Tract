import CoreGraphics
import Foundation

/// One problem's work, as the grid needs to see it: where it sits in the tree,
/// and the patch of canvas its ink actually covers.
///
/// Deliberately *not* the traced bubble from `ProblemBoundsCache`. The bounds
/// here are the union of the strokes' own cached boxes, which every stroke
/// maintains as it is drawn — so the grid can re-measure a problem on every
/// sample of a pencil gesture without a distance field anywhere in sight.
struct ProblemLayoutCell: Equatable, Sendable {
    let nodeID: UUID
    /// Where the node sits in the outline, outermost level first. The grid reads
    /// its row, column and stack position straight out of this.
    let path: ProblemPath
    /// Canvas-space box the problem's ink covers, before any layout is applied.
    let bounds: CGRect

    /// Which row this belongs to — its top-level problem.
    var row: Int { path.first ?? 0 }

    /// Which column: the problem itself is column 0 and its lettered parts
    /// follow, so problem 1 and its part (a) never land on top of one another.
    var column: Int { path.count >= 2 ? path[1] + 1 : 0 }

    /// Where it sits in the vertical stack inside its column. The tree is three
    /// levels deep, so this is only ever non-zero for a sub-sub-problem, which
    /// stacks under the part it belongs to rather than starting a column of its
    /// own — a row is "problem 1 and its parts", not "every node under 1".
    var stack: Int { path.count >= 3 ? path[2] + 1 : 0 }
}
