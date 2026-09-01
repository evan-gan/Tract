import Foundation

/// The document's problem tree, plus the reads and edits the picker needs.
///
/// Labels are never stored. Everything printed — "1", "1b", "2a.III" — is
/// derived from where a node sits, so reordering is a single splice and every
/// stroke pointing at a node id keeps pointing at the right work.
struct ProblemOutline: Codable, Hashable, Sendable {
    /// Level 0 of the tree: the problems themselves.
    private(set) var roots: [ProblemNode] = []

    /// What the user last chose under each parent, so coming back to a problem
    /// returns to the part they were working on. Keyed by `UUID.uuidString`, with
    /// `rootMemoryKey` standing in for the root list, because JSON dictionaries
    /// need string keys.
    ///
    /// Optional so a document written by a build that did not keep this — there
    /// have been some — still opens: a missing key decodes to nil, where a
    /// missing dictionary would throw.
    private var lastChoiceByParent: [String: RememberedChoice]?

    private static let rootMemoryKey = "root"

    /// The choice itself, which is either a child or the deliberate absence of
    /// one. Held as the child's **id** rather than its position: a remembered
    /// index would point at a different node the moment anything was reordered.
    private enum RememberedChoice: Codable, Hashable, Sendable {
        /// A level the user left on the dash. Remembered as firmly as a part is:
        /// unsetting the letter and coming back should not walk into a part
        /// again.
        case unset
        case child(UUID)
    }

    init(roots: [ProblemNode] = []) {
        self.roots = roots
    }

    var isEmpty: Bool { roots.isEmpty }

    // MARK: - Reading

    /// The sibling list a path addresses the children of. An empty path means
    /// the roots, which is what lets every walk start at the top with no case
    /// of its own.
    func children(under parentPath: ProblemPath) -> [ProblemNode] {
        guard let parent = node(at: parentPath) else {
            return parentPath.isEmpty ? roots : []
        }
        return parent.children
    }

    func node(at path: ProblemPath) -> ProblemNode? {
        var siblings = roots
        var found: ProblemNode?
        for index in path {
            guard siblings.indices.contains(index) else { return nil }
            found = siblings[index]
            siblings = siblings[index].children
        }
        return found
    }

    func contains(_ path: ProblemPath) -> Bool {
        !path.isEmpty && node(at: path) != nil
    }

    /// Depth-first search for a node's current position. Used when a stroke or a
    /// selection remembers an id and needs to know what it is called now.
    func path(ofNode nodeID: UUID) -> ProblemPath? {
        func search(_ siblings: [ProblemNode], _ prefix: ProblemPath) -> ProblemPath? {
            for (index, node) in siblings.enumerated() {
                let path = prefix + [index]
                if node.id == nodeID { return path }
                if let deeper = search(node.children, path) { return deeper }
            }
            return nil
        }
        return search(roots, [])
    }

    /// How many levels the subtree rooted at `path` occupies. 0 for a path that
    /// addresses nothing, so callers clamping a drop level get a safe answer.
    func subtreeDepth(at path: ProblemPath) -> Int {
        node(at: path)?.subtreeDepth ?? 0
    }

    /// The written address of a position: `[0, 1]` → "1b" in components.
    func tag(at path: ProblemPath) -> ProblemTag {
        ProblemTag(path.enumerated().map { level, siblingIndex in
            ProblemLevelNotation.component(level: level, siblingIndex: siblingIndex)
        })
    }

    /// The address a stroke's node id resolves to today, or nil if the node has
    /// since been deleted — an id nothing answers to is untagged, not an error.
    func tag(forNode nodeID: UUID) -> ProblemTag? {
        path(ofNode: nodeID).map { tag(at: $0) }
    }

    func label(at path: ProblemPath) -> String? {
        guard let level = path.indices.last else { return nil }
        return ProblemLevelNotation.label(level: level, siblingIndex: path[level])
    }

    // MARK: - Depth rules

    /// Whether a subtree `depth` levels tall may sit at `level`. The tree is
    /// three levels deep, so a leaf goes anywhere and a problem that already has
    /// lettered parts can only be a problem or a part.
    static func canPlace(subtreeDepth depth: Int, atLevel level: Int) -> Bool {
        level >= 0 && depth >= 1 && level + depth <= ProblemLevelNotation.maximumDepth
    }

    /// The deepest level a subtree that tall can legally occupy.
    static func deepestLevel(forSubtreeDepth depth: Int) -> Int {
        ProblemLevelNotation.maximumDepth - depth
    }

    /// Whether a *new* leaf can be created as a child of this path.
    func canAddChild(under parentPath: ProblemPath) -> Bool {
        Self.canPlace(subtreeDepth: 1, atLevel: parentPath.count)
    }

    // MARK: - Editing

    /// Appends a new empty node to a sibling list and returns its path.
    /// Nil when the depth limit forbids another level.
    @discardableResult
    mutating func appendChild(under parentPath: ProblemPath) -> ProblemPath? {
        guard canAddChild(under: parentPath) else { return nil }
        let index = children(under: parentPath).count
        insert(ProblemNode(), under: parentPath, at: index)
        return parentPath + [index]
    }

    /// Splices a node — subtree and all — into a sibling list. The index is
    /// clamped rather than trusted, so a stale drop target cannot crash the app.
    mutating func insert(_ node: ProblemNode, under parentPath: ProblemPath, at index: Int) {
        mutateSiblings(under: parentPath) { siblings in
            siblings.insert(node, at: min(max(index, 0), siblings.count))
        }
    }

    /// Lifts a node out with its children, returning it so a move can put it
    /// back somewhere else.
    @discardableResult
    mutating func removeNode(at path: ProblemPath) -> ProblemNode? {
        guard let index = path.last, contains(path) else { return nil }
        var removed: ProblemNode?
        mutateSiblings(under: ProblemPath(path.dropLast())) { siblings in
            guard siblings.indices.contains(index) else { return }
            removed = siblings.remove(at: index)
        }
        return removed
    }

    /// Moves a node under a new parent. `parentID` is nil for the root list, and
    /// `index` counts only the nodes that remain once the dragged one is lifted
    /// out — which is exactly what makes the "moving down within one list"
    /// off-by-one disappear instead of needing to be corrected for.
    mutating func move(nodeAt path: ProblemPath, toParent parentID: UUID?, at index: Int) {
        guard let moved = node(at: path) else { return }
        // Dropping a node inside itself would detach the whole subtree from the
        // tree; the drop resolver excludes those rows, and this is the backstop.
        guard parentID != moved.id, !isDescendant(parentID, of: moved) else { return }
        removeNode(at: path)
        guard let parentPath = destinationPath(forParent: parentID) else { return }
        insert(moved, under: parentPath, at: index)
    }

    private func destinationPath(forParent parentID: UUID?) -> ProblemPath? {
        guard let parentID else { return [] }
        return path(ofNode: parentID)
    }

    private func isDescendant(_ nodeID: UUID?, of ancestor: ProblemNode) -> Bool {
        guard let nodeID else { return false }
        if ancestor.children.contains(where: { $0.id == nodeID }) { return true }
        return ancestor.children.contains { isDescendant(nodeID, of: $0) }
    }

    /// Applies `transform` to the sibling list under a path, writing the result
    /// back down the same path. Every structural edit goes through here so the
    /// recursion into nested arrays exists in exactly one place.
    private mutating func mutateSiblings(
        under parentPath: ProblemPath,
        _ transform: (inout [ProblemNode]) -> Void
    ) {
        func apply(to siblings: inout [ProblemNode], remaining: ArraySlice<Int>) {
            guard let index = remaining.first else {
                transform(&siblings)
                return
            }
            guard siblings.indices.contains(index) else { return }
            apply(to: &siblings[index].children, remaining: remaining.dropFirst())
        }
        apply(to: &roots, remaining: parentPath[...])
    }

    // MARK: - Last-used memory

    /// Records what was chosen under `parentPath` — a child, or nil for a level
    /// left on the dash.
    mutating func rememberChoice(_ childID: UUID?, under parentPath: ProblemPath) {
        var memory = lastChoiceByParent ?? [:]
        memory[memoryKey(for: parentPath)] = childID.map(RememberedChoice.child) ?? .unset
        lastChoiceByParent = memory
    }

    /// The remembered child's position under `parentPath` today, or nil if the
    /// level was left on the dash, has never been visited, or held a node the
    /// tree has since lost. All three mean the same thing to the picker: stop
    /// here and let the user choose.
    func rememberedChild(under parentPath: ProblemPath) -> Int? {
        guard case .child(let childID)? = lastChoiceByParent?[memoryKey(for: parentPath)] else {
            return nil
        }
        return children(under: parentPath).firstIndex { $0.id == childID }
    }

    /// Walks down from a path following what was last used at each level, so
    /// returning to problem 1 lands on 1d — and stops the moment it reaches a
    /// level the user has not been into, which is where the dash belongs.
    func restoringRememberedDescendants(of path: ProblemPath) -> ProblemPath {
        guard !path.isEmpty else { return path }
        var full = path
        while let remembered = rememberedChild(under: full) {
            full.append(remembered)
        }
        return full
    }

    /// The memory is keyed on node identity, not position, so it survives the
    /// reorder that renamed the node it belongs to.
    private func memoryKey(for parentPath: ProblemPath) -> String {
        if let parent = node(at: parentPath) { return parent.id.uuidString }
        // Only the root list legitimately has no node of its own; a path that
        // addresses nothing must not share the root's memory.
        return parentPath.isEmpty ? Self.rootMemoryKey : "unresolved"
    }

}
