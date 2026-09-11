import Foundation

/// Where a running export has got to.
///
/// Coarse on purpose. Every exporter renders in one opaque call —
/// `UIGraphicsPDFRenderer.pdfData`, a single string build, one bitmap — so there
/// is no honest fraction to put behind a progress bar, and a bar that jumped
/// 0 → 33 → 100 with all the waiting in the middle would say less than nothing.
/// What can be said truthfully is which of the three things the export is doing,
/// and that it is still doing it.
enum ExportStage: String, CaseIterable, Sendable {
    /// Snapshotting the document and finding the exporter for the pick.
    case preparing
    /// Inside the exporter. The long one: a full canvas or a worksheet is seconds.
    case rendering
    /// Writing the rendered bytes out under the export's file name.
    case writingFile

    static var stepCount: Int { allCases.count }

    /// 1-based position in the run, for "Step 2 of 3".
    var stepNumber: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    /// What the picker says while this stage runs.
    ///
    /// - Parameters:
    ///   - layout: What the export puts on the page.
    ///   - format: The file being written.
    /// - Returns: One line naming the work in progress, in the user's terms.
    func message(layout: ExportLayout, format: ExportFormat) -> String {
        switch self {
        case .preparing: "Preparing the \(layout.name.lowercased())…"
        case .rendering: "Rendering the \(layout.name.lowercased()) as \(format.displayName)…\n(This may take a few moments)"
        case .writingFile: "Writing the \(format.displayName) file…"
        }
    }
}

/// An export in flight, as the picker shows it.
struct RunningExport: Equatable, Sendable {
    let layout: ExportLayout
    let format: ExportFormat
    var stage: ExportStage

    var message: String { stage.message(layout: layout, format: format) }
}
