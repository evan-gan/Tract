import Foundation

/// One problem in the outline, identified but *unlabelled*.
///
/// A node stores no "1" or "b" of its own: its label is its index among its
/// siblings, resolved by `ProblemOutline` at read time. That is what makes a
/// reorder cheap — moving a node renames it and everything after it without
/// touching a single stored value, and strokes pointing at `id` follow the node
/// to its new label instead of being orphaned by it.
struct ProblemNode: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var children: [ProblemNode]

    init(id: UUID = UUID(), children: [ProblemNode] = []) {
        self.id = id
        self.children = children
    }

    /// 1 for a leaf, otherwise one more than its deepest child — the number of
    /// levels this subtree occupies wherever it is placed.
    var subtreeDepth: Int {
        1 + (children.map(\.subtreeDepth).max() ?? 0)
    }
}

/// Where a node sits, as sibling indices from the outermost level inwards.
/// `[0, 1]` is the second child of the first root — problem 1, part b.
/// An empty path addresses the root list itself, which is also what "no problem
/// selected" means to the picker.
typealias ProblemPath = [Int]
