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
}

enum ExportError: LocalizedError {
    case noStrokes
    case renderingFailed(String)

    var errorDescription: String? {
        switch self {
        case .noStrokes:
            "The document has no strokes to export."
        case .renderingFailed(let detail):
            "Export rendering failed: \(detail)"
        }
    }
}
