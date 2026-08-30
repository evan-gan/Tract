import UIKit

/// Renders strokes onto standard printing paper as a PDF.
///
/// Two layouts, chosen through `PDFExportOptions`:
///
/// - `.wholeDrawing` — the drawing scaled to fit one page inside its margins.
/// - `.problemTable` — strokes grouped by `Stroke.problemTag`, one labelled cell
///   per problem, flowing onto extra pages as needed. This is what turns work
///   scattered across an infinite canvas into a sheet a teacher can read.
struct PDFExporter: ExportAdapter {
    let fileExtension = "pdf"
    let mimeType = "application/pdf"
    let displayName = "PDF"

    var options = PDFExportOptions()

    func export(document: SplineDocument, viewport: CGRect?) throws -> Data {
        let strokes = StrokeRasterizer.inkStrokes(document.strokes, intersecting: viewport)
        guard !strokes.isEmpty else { throw ExportError.noStrokes }

        let renderer = UIGraphicsPDFRenderer(bounds: options.pageRect, format: format(for: document))
        let pageRenderer = PDFPageRenderer(options: options)

        switch options.layout {
        case .wholeDrawing:
            return renderer.pdfData { pageRenderer.drawWholeDrawingPage(strokes: strokes, into: $0) }

        case .problemTable(let tableLayout):
            let groups = ProblemGrouping.groups(
                from: strokes,
                depth: tableLayout.groupingDepth,
                untaggedLabel: tableLayout.untaggedLabel,
                formatter: tableLayout.tagFormatter
            )
            // Every stroke can be excluded here even though the document has ink:
            // an untaggedLabel of nil drops work that was never tagged.
            guard !groups.isEmpty else { throw ExportError.noStrokes }
            return renderer.pdfData {
                pageRenderer.drawProblemTablePages(groups: groups, layout: tableLayout, into: $0)
            }
        }
    }

    /// Fills in the document properties a PDF reader shows in its inspector.
    private func format(for document: SplineDocument) -> UIGraphicsPDFRendererFormat {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: document.title,
            kCGPDFContextCreator as String: "Tract"
        ]
        return format
    }
}
