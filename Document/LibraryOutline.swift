import Foundation

/// One line of the library's outline: what is on it, and how deep it sits.
struct LibraryOutlineRow: Identifiable, Hashable {
    enum Item: Hashable {
        case folder(DocumentFolder)
        case document(DocumentMetadata)
    }

    let item: Item
    /// How many folders deep this row is, counting from whatever the outline was
    /// rooted at. Drives the indent, nothing else.
    let depth: Int

    var id: UUID {
        switch item {
        case .folder(let folder): folder.id
        case .document(let metadata): metadata.id
        }
    }

    var folder: DocumentFolder? {
        if case .folder(let folder) = item { return folder }
        return nil
    }

    var document: DocumentMetadata? {
        if case .document(let metadata) = item { return metadata }
        return nil
    }
}

/// Flattens the folder tree into the rows the outline draws, expanding only the
/// folders the user has opened.
///
/// Pure, and separate from the view, because "what is on screen when these three
/// folders are expanded" is the part worth testing — `List` renders whatever it
/// is handed.
enum LibraryOutline {
    /// - Parameters:
    ///   - tree: The library's folders.
    ///   - documents: Every document in the library; each row's own folder is
    ///     picked out by `folderID`.
    ///   - root: The folder to start from; nil for the top level.
    ///   - expandedFolderIDs: Folders whose contents should be listed inline.
    /// - Returns: Rows in display order — each folder followed immediately by its
    ///   contents, folders before documents at every level.
    static func rows(
        tree: FolderTree,
        documents: [DocumentMetadata],
        in root: UUID? = nil,
        expandedFolderIDs: Set<UUID> = []
    ) -> [LibraryOutlineRow] {
        let documentsByFolder = Dictionary(grouping: documents) { $0.folderID }
        var rows: [LibraryOutlineRow] = []
        // Guards against a folder cycle in damaged data expanding forever.
        var visited: Set<UUID> = []

        func append(contentsOf folderID: UUID?, depth: Int) {
            for folder in tree.children(of: folderID) {
                rows.append(LibraryOutlineRow(item: .folder(folder), depth: depth))
                guard expandedFolderIDs.contains(folder.id), visited.insert(folder.id).inserted else { continue }
                append(contentsOf: folder.id, depth: depth + 1)
            }
            let contents = documentsByFolder[folderID] ?? []
            for metadata in contents.sorted(by: { $0.modifiedAt > $1.modifiedAt }) {
                rows.append(LibraryOutlineRow(item: .document(metadata), depth: depth))
            }
        }

        append(contentsOf: root, depth: 0)
        return rows
    }
}
