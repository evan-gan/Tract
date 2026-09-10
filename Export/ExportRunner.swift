import Foundation

/// Turns a picked layout and format into a file on disk, ready to hand to a
/// share sheet.
///
/// Split out of the export control so the whole path — pick, render, name,
/// write — can be run in a test without a view. The control is then only
/// presentation and error reporting.
enum ExportRunner {
    /// Renders the document and writes it out under its export name.
    ///
    /// - Parameters:
    ///   - document: The document to export, snapshotted by the caller.
    ///   - layout: What to put on the page.
    ///   - format: Which of that layout's formats to write.
    ///   - folderPath: Library folders to prefix onto the file name, outermost
    ///     first. Empty means no prefix.
    ///   - directory: Where the file lands. Defaults to the temporary directory,
    ///     which is what a share sheet wants.
    /// - Returns: The URL of the written file.
    /// - Throws: `ExportError.unsupportedFormat` when the layout does not offer
    ///   the format, whatever the exporter throws, or a file-system error.
    static func writeExport(
        of document: SplineDocument,
        layout: ExportLayout,
        format: ExportFormat,
        folderPath: [String] = [],
        into directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        guard let adapter = layout.adapter(for: format) else {
            throw ExportError.unsupportedFormat(layout: layout.name, format: format.displayName)
        }

        let data = try adapter.export(document: document, viewport: nil)
        let fileName = ExportFileNaming.fileName(
            title: document.title + adapter.fileNameSuffix,
            folderPath: folderPath,
            fileExtension: adapter.fileExtension
        )
        let destination = directory.appending(path: fileName)
        try data.write(to: destination)
        return destination
    }
}
