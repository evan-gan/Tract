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
    ///   - selection: The problems to keep. `.everything` exports the document
    ///     whole, which is what every layout but `.selectedProblems` wants.
    ///   - folderPath: Library folders to prefix onto the file name, outermost
    ///     first. Empty means no prefix.
    ///   - directory: Where the file lands. Defaults to the temporary directory,
    ///     which is what a share sheet wants.
    ///   - onStage: Called as each stage begins, on whatever thread the export is
    ///     running on.
    /// - Returns: The URL of the written file.
    /// - Throws: `ExportError.unsupportedFormat` when the layout does not offer
    ///   the format, `ExportError.emptySelection` when the chosen problems hold
    ///   no ink, whatever the exporter throws, or a file-system error.
    static func writeExport(
        of document: SplineDocument,
        layout: ExportLayout,
        format: ExportFormat,
        selection: ProblemSelection = .everything,
        folderPath: [String] = [],
        into directory: URL = FileManager.default.temporaryDirectory,
        onStage: (ExportStage) -> Void = { _ in }
    ) throws -> URL {
        onStage(.preparing)
        guard let adapter = layout.adapter(for: format) else {
            throw ExportError.unsupportedFormat(layout: layout.name, format: format.displayName)
        }
        // Narrowing the document here is what keeps every exporter unaware of
        // problems: they render whatever strokes they are handed.
        let chosen = selection.applied(to: document)
        guard !selection.limitsTheDocument || !chosen.strokes.isEmpty else {
            throw ExportError.emptySelection
        }

        onStage(.rendering)
        let data = try adapter.export(document: chosen, viewport: nil)

        onStage(.writingFile)
        // The selection's own suffix replaces the adapter's: "Set 3 1a.pdf" says
        // far more about the file than "Set 3 problems.pdf" does.
        let titleSuffix = selection.fileNameSuffix() ?? adapter.fileNameSuffix
        let fileName = ExportFileNaming.fileName(
            title: document.title + titleSuffix,
            folderPath: folderPath,
            fileExtension: adapter.fileExtension
        )
        let destination = directory.appending(path: fileName)
        try data.write(to: destination)
        return destination
    }

    /// Renders a picked export off the main thread, reporting each stage back on
    /// the main actor as it starts.
    ///
    /// Detached rather than awaited in place because the work underneath is
    /// entirely synchronous CoreGraphics: run on the main thread, a worksheet of
    /// a full canvas is seconds of frozen sheet — no spinner turning, nothing to
    /// say the app is still alive.
    ///
    /// - Parameters:
    ///   - request: What to export and how to name it.
    ///   - onStage: Called on the main actor as each stage begins.
    /// - Returns: The URL of the written file, in the temporary directory.
    static func runExport(
        _ request: ExportRequest,
        onStage: @escaping @MainActor @Sendable (ExportStage) -> Void
    ) async throws -> URL {
        let reportStage: @Sendable (ExportStage) -> Void = { stage in
            Task { @MainActor in onStage(stage) }
            #if DEBUG
            // Sleeps the render, not the main thread, so the picker keeps
            // animating — see `debugStageDelay`.
            if let debugStageDelay { Thread.sleep(forTimeInterval: debugStageDelay) }
            #endif
        }

        return try await Task.detached(priority: .userInitiated) {
            try writeExport(
                of: request.document,
                layout: request.layout,
                format: request.format,
                selection: request.problems,
                folderPath: request.folderPath,
                onStage: reportStage
            )
        }.value
    }

    #if DEBUG
    /// How long each stage is held when the app is launched with
    /// `-TractSlowExport`, in seconds; nil when it is not.
    ///
    /// The sample documents a UI test can reach render in milliseconds, so the
    /// picker's progress is gone before a screenshot can be taken of it — there
    /// is otherwise no way to look at that screen. Documents people actually draw
    /// take long enough on their own.
    private static let debugStageDelay: TimeInterval? =
        ProcessInfo.processInfo.arguments.contains("-TractSlowExport") ? 1.2 : nil
    #endif
}
