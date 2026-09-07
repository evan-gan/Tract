import Foundation

/// Pure queries over the flat list of folders: what sits inside what, and which
/// moves would tie the tree in a knot.
///
/// Free of storage and SwiftUI on purpose — the one rule that really matters
/// (a folder can never end up inside itself, at any depth) is worth testing
/// directly rather than through a drag gesture.
///
/// The tree is defensive about damaged data: a folder whose parent is missing
/// is treated as top level, and every walk upwards is cycle-guarded, so a
/// hand-edited or half-written `folders.json` degrades into a flat list instead
/// of hanging the library.
struct FolderTree: Sendable {
    let folders: [DocumentFolder]

    private let foldersByID: [UUID: DocumentFolder]
    private let childrenByParent: [UUID?: [DocumentFolder]]

    init(_ folders: [DocumentFolder] = []) {
        self.folders = folders
        self.foldersByID = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let identifiers = Set(folders.map(\.id))
        let grouped = Dictionary(grouping: folders) { folder -> UUID? in
            // An unknown parent means the folder was orphaned by damaged data;
            // showing it at the top level is the only way the user can reach it.
            guard let parentID = folder.parentID, identifiers.contains(parentID) else { return nil }
            return parentID
        }
        self.childrenByParent = grouped.mapValues { children in
            children.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    func folder(id: UUID) -> DocumentFolder? {
        foldersByID[id]
    }

    /// The folders directly inside `parentID`, name-sorted the way Finder sorts
    /// them (case-insensitive, numerals in numeric order).
    func children(of parentID: UUID?) -> [DocumentFolder] {
        childrenByParent[parentID] ?? []
    }

    /// The chain of folders containing `id`, outermost first, ending with `id`
    /// itself. Empty if no such folder exists.
    func path(to id: UUID) -> [DocumentFolder] {
        var reversedPath: [DocumentFolder] = []
        var visited: Set<UUID> = []
        var cursor: UUID? = id

        while let currentID = cursor, let folder = foldersByID[currentID], visited.insert(currentID).inserted {
            reversedPath.append(folder)
            cursor = folder.parentID
        }
        return reversedPath.reversed()
    }

    /// Every folder nested under `id`, at any depth. The folder itself is not
    /// included.
    func descendants(of id: UUID) -> [UUID] {
        var found: [UUID] = []
        // Cycle-guarded for the same reason `path(to:)` is: a corrupted tree
        // must degrade, not spin forever.
        var visited: Set<UUID> = [id]
        var queue = children(of: id).map(\.id)

        while let next = queue.popLast() {
            guard visited.insert(next).inserted else { continue }
            found.append(next)
            queue.append(contentsOf: children(of: next).map(\.id))
        }
        return found
    }

    /// Whether `folderID` may be dropped into `newParentID`.
    ///
    /// Rejects the two moves that would corrupt the tree — a folder into itself,
    /// and a folder into one of its own descendants — plus a destination that
    /// does not exist. A move that changes nothing is still legal; callers skip
    /// no-ops themselves.
    func canMove(folderID: UUID, into newParentID: UUID?) -> Bool {
        guard foldersByID[folderID] != nil else { return false }
        guard let newParentID else { return true }
        guard foldersByID[newParentID] != nil else { return false }
        guard newParentID != folderID else { return false }
        return !descendants(of: folderID).contains(newParentID)
    }
}
