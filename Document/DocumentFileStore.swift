import Foundation
import OSLog

/// On-disk home for every document. One folder per document, three files inside:
///
/// ```
/// Application Support/Documents/<uuid>/
///     metadata.json     — title, dates, stroke count, canvas pan/zoom
///     strokes.plist     — binary property list of [Stroke]
///     thumbnail.png     — preview rendered at the last save
/// ```
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
        let folders = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let metadata = folders.compactMap { folder -> DocumentMetadata? in
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
    func createDocument(title: String) throws -> SplineDocument {
        let document = SplineDocument(metadata: DocumentMetadata(title: title))
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
        let folder = folderURL(for: id)
        var metadata = try readMetadata(at: folder)
        metadata.title = title
        metadata.modifiedAt = .now
        try writeAtomically(encodeMetadata(metadata), to: folder.appending(path: Filename.metadata))
        return metadata
    }

    func deleteDocument(id: UUID) throws {
        let folder = folderURL(for: id)
        guard fileManager.fileExists(atPath: folder.path(percentEncoded: false)) else { return }
        try fileManager.removeItem(at: folder)
    }

    // MARK: - Paths

    private enum Filename {
        static let metadata = "metadata.json"
        static let strokes = "strokes.plist"
        static let thumbnail = "thumbnail.png"
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
    case unsupportedSchema(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .metadataUnreadable(let folder, let underlying):
            "Could not read the details of document \(folder): \(underlying.localizedDescription)"
        case .strokesUnreadable(let folder, let underlying):
            "Document \(folder) has strokes that could not be decoded: \(underlying.localizedDescription). The file may be damaged."
        case .unsupportedSchema(let found, let supported):
            "This document was saved by a newer version of Tract (format \(found); this build reads up to \(supported)). Update the app to open it."
        }
    }
}
