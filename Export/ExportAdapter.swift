import Foundation

/// Protocol all exporters conform to. The adapter pattern means adding a new
/// format (e.g. JPEG) requires only a new type — no changes to existing code.
protocol ExportAdapter {
    /// Serialises the document into the target format.
    /// - Parameters:
    ///   - document: The document to export.
    ///   - viewport: If non-nil, clips to this rect in canvas space. Nil = all strokes.
    /// - Returns: The file data ready to write or share.
    func export(document: SplineDocument, viewport: CGRect?) throws -> Data
    var fileExtension: String { get }
    var mimeType: String { get }
    var displayName: String { get }
    /// Appended to the document title when naming the file, for formats that a
    /// document can produce more than one of. Empty for most exporters.
    var fileNameSuffix: String { get }
}

extension ExportAdapter {
    var fileNameSuffix: String { "" }
}

enum ExportError: LocalizedError {
    case noStrokes
    case renderingFailed(String)
    /// A layout was asked for a format it cannot produce. Unreachable from the
    /// export picker, which only offers each layout's own formats — this catches
    /// a pairing invented in code.
    case unsupportedFormat(layout: String, format: String)
    /// The picked problems hold no ink. The picker only offers problems that
    /// have some, so this catches a selection made stale by an edit underneath.
    case emptySelection

    var errorDescription: String? {
        switch self {
        case .noStrokes:
            "The document has no strokes to export."
        case .emptySelection:
            "The chosen problems have no ink in them. Pick a problem that has work under it."
        case .renderingFailed(let detail):
            "Export rendering failed: \(detail)"
        case .unsupportedFormat(let layout, let format):
            "\(layout) cannot be exported as \(format)."
        }
    }
}
