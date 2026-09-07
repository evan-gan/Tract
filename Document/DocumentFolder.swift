import Foundation

/// A folder in the document library.
///
/// Folders are pure organisation and deliberately have no presence on disk of
/// their own: the whole tree lives in one small `folders.json`, and a document's
/// membership is a `folderID` on its own metadata. Moving a document therefore
/// rewrites one tiny file instead of relocating a directory full of pencil
/// telemetry, and a folder can be renamed without touching a single document.
struct DocumentFolder: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    /// The folder this one sits in. `nil` means top level.
    var parentID: UUID?
    let createdAt: Date

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, createdAt: Date = .now) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.createdAt = createdAt
    }
}

/// The on-disk shape of `folders.json`.
///
/// A wrapper rather than a bare array so the file can carry a schema version,
/// for the same reason `DocumentMetadata` does: a newer build's tree must fail
/// loudly here rather than be silently rewritten with fields dropped.
struct FolderIndex: Codable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var folders: [DocumentFolder]

    init(folders: [DocumentFolder] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.folders = folders
    }
}
