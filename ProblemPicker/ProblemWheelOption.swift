import Foundation

/// One row of one wheel column: a level the picker can be pointed at, or the
/// "none" row that leaves that level unset.
///
/// The id is what the scroll view tracks, so it has to be stable while a column
/// is on screen. Sibling index is exactly that: rows are never reordered inside
/// a column, and a row that does not exist yet takes the index it would be
/// created at.
struct ProblemWheelOption: Identifiable, Hashable {
    /// Sibling index within the level, or `noneID` for the row that unsets it.
    let id: Int
    let label: String
    /// A node that has not been created yet. Landing on it is what creates it,
    /// which is the only way the wheel adds to the tree.
    let isUncreated: Bool

    /// Leaves this level — and everything under it — unset. On the first column
    /// that means new ink is untagged.
    static let noneID = -1
    static let noneLabel = "—"

    static let none = ProblemWheelOption(id: noneID, label: noneLabel, isUncreated: false)
}

extension Array {
    /// Index lookup that answers nil instead of trapping — the wheel clamps
    /// indices that come back from a scroll view, and a column can be rebuilt
    /// between the scroll ending and the landing being read.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
