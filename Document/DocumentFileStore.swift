import Foundation
import OSLog

/// On-disk home for every document. One folder per document, three files inside:
///
/// ```
/// Application Support/Documents/
///     folders.json          — the library's folder tree, in one small file
///     <uuid>/
///         metadata.json     — title, dates, stroke count, canvas pan/zoom, folder
///         strokes.plist     — binary property list of [Stroke]
///         thumbnail.png     — preview rendered at the last save
/// ```
///
/// Note that library folders are *not* directories: document folders stay flat
/// on disk and each document records which library folder it belongs to. Filing
/// a document is then a one-line metadata write rather than moving a directory
/// full of ink, and a half-finished move can never lose a document.
///
/// Three properties make this survivable where the old scheme was not:
///
/// - **Every file is written atomically.** A crash or a force-quit mid-save
///   leaves the previous version intact rather than a truncated file.
/// - **Documents are isolated.** One unreadable folder is skipped during a
///   listing; it cannot take the whole library down with it.
/// - **Metadata is written last.** It is the commit record, so a save that dies
///   part way through never advertises a `modifiedAt` newer than its content.
///
/// An actor rather than a struct: saves are triggered by autosave, by closing a
/// document and by the app being backgrounded, and those can overlap. Serialising
/// them here is what stops two writers interleaving on the same document.
actor DocumentFileStore {
    private let rootDirectory: URL
    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.spline.app", category: "DocumentFileStore")

    /// - Parameter rootDirectory: Where document folders live. Defaults to
    ///   Application Support; tests pass a temporary directory.
    ///
    /// Deliberately non-throwing: the directory is created on first use instead,
    /// so a store can always be constructed and any filesystem trouble surfaces
    /// on the operation that hit it, with a message about what it was doing.
    init(rootDirectory: URL = URL.applicationSupportDirectory.appending(path: "Documents", directoryHint: .isDirectory)) {
        self.rootDirectory = rootDirectory
    }

    // MARK: - Listing

    /// Every readable document's metadata, newest edit first.
    ///
    /// Unreadable folders are logged and skipped: a single damaged document must
    /// never leave the user staring at an empty library.
    func listMetadata() throws -> [DocumentMetadata] {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let entries = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        // Only directories are documents — `folders.json` sits alongside them and
        // would otherwise be logged as an unreadable document on every listing.
        let documentFolders = entries.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }

        let metadata = documentFolders.compactMap { folder -> DocumentMetadata? in
            do {
                return try readMetadata(at: folder)
            } catch {
                logger.error("Skipping unreadable document \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return metadata.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    // MARK: - Reading

    func loadDocument(id: UUID) throws -> SplineDocument {
        let folder = folderURL(for: id)
        let metadata = try readMetadata(at: folder)
        let strokes = try readStrokes(at: folder)
        return SplineDocument(metadata: metadata, strokes: strokes)
    }

    func loadThumbnailData(id: UUID) -> Data? {
        try? Data(contentsOf: folderURL(for: id).appending(path: Filename.thumbnail))
    }

    // MARK: - Writing

    /// Writes a document's strokes, thumbnail and metadata, in that order.
    ///
    /// - Parameters:
    ///   - document: The document to persist. Its `modifiedAt` is used as-is, so
    ///     the caller stamps the time it considers the edit to have happened.
    ///   - thumbnail: What to do with the stored preview image.
    func save(_ document: SplineDocument, thumbnail: ThumbnailUpdate) throws {
        try requireReadableSchema(document.metadata.schemaVersion)

        let folder = folderURL(for: document.id)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

        try writeAtomically(encodeStrokes(document.strokes), to: folder.appending(path: Filename.strokes))
        try apply(thumbnail, in: folder)

        var metadata = document.metadata
        metadata.strokeCount = document.strokes.count
        try writeAtomically(encodeMetadata(metadata), to: folder.appending(path: Filename.metadata))
    }

    /// Creates an empty document on disk so it exists the moment the user makes it,
    /// not only once they have drawn something.
    ///
    /// - Parameter folderID: The library folder to file it in; `nil` is the top level.
    func createDocument(title: String, in folderID: UUID? = nil) throws -> SplineDocument {
        let document = SplineDocument(metadata: DocumentMetadata(title: title, folderID: folderID))
        try save(document, thumbnail: .unchanged)
        return document
    }

    private func apply(_ thumbnail: ThumbnailUpdate, in folder: URL) throws {
        let url = folder.appending(path: Filename.thumbnail)
        switch thumbnail {
        case .unchanged:
            break
        case .replace(let data):
            try writeAtomically(data, to: url)
        case .remove:
            // Absent is the normal case for a document with no ink, so a missing
            // file here is success, not an error worth failing the whole save for.
            try? fileManager.removeItem(at: url)
        }
    }

    /// Retitles a document without touching its strokes — renaming from the
    /// library must not require decoding a page of ink to write one string.
    func renameDocument(id: UUID, to title: String) throws -> DocumentMetadata {
        try updateMetadata(id: id) { metadata in
            metadata.title = title
            metadata.modifiedAt = .now
        }
    }

    /// Files a document into a library folder, or to the top level with `nil`.
    ///
    /// `modifiedAt` is left alone: filing is housekeeping, not an edit, and
    /// bumping it would shuffle the whole library's newest-first order every
    /// time something is dragged.
    func setFolderID(_ folderID: UUID?, forDocument id: UUID) throws -> DocumentMetadata {
        try updateMetadata(id: id) { $0.folderID = folderID }
    }

    /// Reads a document's metadata, applies `change`, and writes it back —
    /// without ever inflating the strokes beside it.
    private func updateMetadata(id: UUID, _ change: (inout DocumentMetadata) -> Void) throws -> DocumentMetadata {
        let folder = folderURL(for: id)
        var metadata = try readMetadata(at: folder)
        change(&metadata)
        try writeAtomically(encodeMetadata(metadata), to: folder.appending(path: Filename.metadata))
        return metadata
    }

    func deleteDocument(id: UUID) throws {
        let folder = folderURL(for: id)
        guard fileManager.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: folder)
    }

    // MARK: - Folders

    /// The library's folder tree.
    ///
    /// A missing file means a library that has never had a folder in it, which
    /// is the normal state on first launch — not an error. A file that is
    /// present but undecodable *is* an error: quietly returning an empty tree
    /// would show every document at the top level and invite the user to file
    /// them all again over the top of a recoverable file.
    func loadFolders() throws -> [DocumentFolder] {
        let url = rootDirectory.appending(path: Filename.folders)
        guard let data = try? Data(contentsOf: url) else { return [] }
        let index: FolderIndex
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            index = try decoder.decode(FolderIndex.self, from: data)
        } catch {
            throw DocumentStoreError.folderIndexUnreadable(underlying: error)
        }
        guard index.schemaVersion <= FolderIndex.currentSchemaVersion else {
            throw DocumentStoreError.unsupportedFolderSchema(
                found: index.schemaVersion,
                supported: FolderIndex.currentSchemaVersion
            )
        }
        return index.folders
    }

    /// Writes the whole tree at once. It is a few hundred bytes even for a
    /// deeply nested library, so one atomic write is both simpler and safer
    /// than patching entries in place.
    func saveFolders(_ folders: [DocumentFolder]) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(FolderIndex(folders: folders))
        try writeAtomically(data, to: rootDirectory.appending(path: Filename.folders))
    }

    // MARK: - Paths

    private enum Filename {
        static let metadata = "metadata.json"
        static let strokes = "strokes.plist"
        static let thumbnail = "thumbnail.png"
        static let folders = "folders.json"
    }

    private func folderURL(for id: UUID) -> URL {
        rootDirectory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    // MARK: - Codecs

    /// JSON for metadata — it is tiny, and being able to read a document's title
    /// out of a sysdiagnose is worth more than the bytes saved by a binary format.
    private func encodeMetadata(_ metadata: DocumentMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(metadata)
    }

    private func readMetadata(at folder: URL) throws -> DocumentMetadata {
        let url = folder.appending(path: Filename.metadata)
        let metadata: DocumentMetadata
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            metadata = try decoder.decode(DocumentMetadata.self, from: Data(contentsOf: url))
        } catch {
            throw DocumentStoreError.metadataUnreadable(folder.lastPathComponent, underlying: error)
        }
        try requireReadableSchema(metadata.schemaVersion)
        return metadata
    }

    /// Binary property list for strokes — a single stroke can carry thousands of
    /// pencil samples, and this is both smaller and markedly faster to decode
    /// than JSON while still being inspectable with `plutil`.
    private func encodeStrokes(_ strokes: [Stroke]) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(strokes)
    }

    /// A missing strokes file means an empty document, which is a legitimate
    /// state. A present but undecodable one is an error the caller must see —
    /// silently opening a blank canvas would invite the user to save over it.
    private func readStrokes(at folder: URL) throws -> [Stroke] {
        let url = folder.appending(path: Filename.strokes)
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try PropertyListDecoder().decode([Stroke].self, from: data)
        } catch {
            throw DocumentStoreError.strokesUnreadable(folder.lastPathComponent, underlying: error)
        }
    }

    private func requireReadableSchema(_ version: Int) throws {
        guard version > DocumentMetadata.currentSchemaVersion else { return }
        throw DocumentStoreError.unsupportedSchema(
            found: version,
            supported: DocumentMetadata.currentSchemaVersion
        )
    }

    /// `.atomic` writes to a temporary file and renames, so a reader never sees
    /// a half-written document however badly the write goes.
    private func writeAtomically(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [.atomic])
    }
}

/// What a save should do with the document's stored preview image.
enum ThumbnailUpdate: Sendable {
    case unchanged
    case replace(Data)
    case remove
}

// MARK: - Errors

enum DocumentStoreError: LocalizedError {
    case metadataUnreadable(String, underlying: Error)
    case strokesUnreadable(String, underlying: Error)
    case folderIndexUnreadable(underlying: Error)
    case unsupportedSchema(found: Int, supported: Int)
    case unsupportedFolderSchema(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .metadataUnreadable(let folder, let underlying):
            "Could not read the details of document \(folder): \(underlying.localizedDescription)"
        case .strokesUnreadable(let folder, let underlying):
            "Document \(folder) has strokes that could not be decoded: \(underlying.localizedDescription). The file may be damaged."
        case .folderIndexUnreadable(let underlying):
            "Your folder list could not be read: \(underlying.localizedDescription). The file may be damaged."
        case .unsupportedSchema(let found, let supported):
            "This document was saved by a newer version of Tract (format \(found); this build reads up to \(supported)). Update the app to open it."
        case .unsupportedFolderSchema(let found, let supported):
            "Your folders were saved by a newer version of Tract (format \(found); this build reads up to \(supported)). Update the app to see them."
        }
    }
}
