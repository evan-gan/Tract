import Foundation

/// Everything one export run needs: what to write, and how to name it.
struct ExportRequest: Sendable {
    let document: SplineDocument
    let layout: ExportLayout
    let format: ExportFormat
    /// The problems to keep. `.everything` for the layouts that export the
    /// document whole.
    var problems: ProblemSelection = .everything
    /// Library folders prefixed onto the file name, outermost first.
    var folderPath: [String] = []
}

/// Renders a request into a file, calling back on the main actor as it reaches
/// each stage. Injected into `ExportSession` so the session's own sequencing can
/// be tested without rendering anything.
typealias ExportWork = @Sendable (
    ExportRequest,
    @escaping @MainActor @Sendable (ExportStage) -> Void
) async throws -> URL

/// One trip through the export flow: picker open, file rendered, share sheet up.
///
/// The order matters and none of it can be driven by a single flag, which is why
/// it lives in a model rather than in the button's view state:
///
/// - The picker **stays up** while the file renders, showing progress. Rendering
///   used to run on the picker's dismissal, on the main thread, which meant a big
///   worksheet froze the app with nothing on screen to say why.
/// - The share sheet is raised only **after** the picker is gone. Two sheets
///   fighting over the same presentation is how this control once ended up
///   showing an empty one.
/// - A finished file is therefore held back until `pickerDismissed()`.
@Observable
@MainActor
final class ExportSession {
    /// The export being rendered, or nil when nothing is running. Non-nil is what
    /// swaps the picker's options out for a spinner.
    private(set) var runningExport: RunningExport?
    var isPickerPresented = false
    var exportedItem: ExportedFileItem?
    var failure: ExportFailure?

    /// The finished run, held back until the picker is off screen.
    private var completedResult: Result<URL, Error>?
    private var runTask: Task<Void, Never>?
    private let performExport: ExportWork

    init(performExport: @escaping ExportWork = ExportRunner.runExport) {
        self.performExport = performExport
    }

    func presentPicker() {
        completedResult = nil
        isPickerPresented = true
    }

    /// Starts rendering a pick, leaving the picker up to report its progress.
    ///
    /// A second call while one is already running is ignored: the picker shows a
    /// spinner instead of its rows by then, but a tap already in flight when the
    /// first one landed would otherwise start a duplicate export.
    func export(_ request: ExportRequest) {
        guard runningExport == nil else { return }
        runningExport = RunningExport(layout: request.layout, format: request.format, stage: .preparing)

        let work = performExport
        runTask = Task { [weak self] in
            let result: Result<URL, Error>
            do {
                result = .success(try await work(request) { stage in
                    self?.advance(to: stage)
                })
            } catch {
                result = .failure(error)
            }
            guard let self, !Task.isCancelled else { return }
            finish(with: result)
        }
    }

    /// Abandons a run in flight and closes the picker.
    ///
    /// The render itself cannot be interrupted — it is one synchronous
    /// CoreGraphics call — so the work finishes unwatched and its result is
    /// dropped. Any file it wrote lands in the temporary directory, which the
    /// system reclaims on its own.
    func cancel() {
        runTask?.cancel()
        runTask = nil
        runningExport = nil
        completedResult = nil
        isPickerPresented = false
    }

    /// Run when the picker has left the screen: raises the share sheet, or the
    /// failure alert, for whatever the run produced.
    func pickerDismissed() {
        // Swiping the sheet away mid-render means nobody is waiting for the file.
        if runningExport != nil {
            cancel()
            return
        }
        guard let completedResult else { return }
        self.completedResult = nil

        switch completedResult {
        case .success(let url):
            exportedItem = ExportedFileItem(url: url)
        case .failure(let error):
            failure = ExportFailure(message: error.localizedDescription)
        }
    }

    private func advance(to stage: ExportStage) {
        runningExport?.stage = stage
    }

    private func finish(with result: Result<URL, Error>) {
        completedResult = result
        runningExport = nil
        runTask = nil
        // Closing the picker is what raises the share sheet — see pickerDismissed.
        isPickerPresented = false
    }
}

/// A written export, identified by where it landed so a sheet cannot be presented
/// without one.
struct ExportedFileItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ExportFailure: Identifiable {
    let message: String
    var id: String { message }
}
