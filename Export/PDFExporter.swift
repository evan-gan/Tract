import UIKit

/// Renders strokes as a PDF using `UIGraphicsPDFRenderer`.
struct PDFExporter: ExportAdapter {
    let fileExtension = "pdf"
    let mimeType = "application/pdf"
    let displayName = "PDF"

    func export(document: SplineDocument, viewport: CGRect?) throws -> Data {
        let strokes = StrokeRasterizer.strokes(document.strokes, intersecting: viewport)
        guard !strokes.isEmpty else { throw ExportError.noStrokes }

        let bounds = viewport ?? StrokeRasterizer.unionBounds(of: strokes)
        guard !bounds.isNull else { throw ExportError.noStrokes }

        return UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            StrokeRasterizer.draw(strokes, in: context.cgContext, offset: bounds.origin)
        }
    }
}
