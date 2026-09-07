import UIKit

/// Paints PDF pages. Split out from `PDFExporter` so the adapter stays about
/// "what to produce" and this stays about "how the paper looks".
///
/// Every method here works in page coordinates — origin top-left of the sheet,
/// which is what `UIGraphicsPDFRenderer` hands over — never in canvas
/// coordinates. Ink is moved into place with a transform instead.
struct PDFPageRenderer {
    let options: PDFExportOptions
    var paperColor: UIColor = .white

    /// The whole drawing scaled to fit inside one page's margins.
    func drawWholeDrawingPage(strokes: [Stroke], into context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        fillPaper(in: context)
        drawInk(strokes, bounds: StrokeRasterizer.inkedBounds(of: strokes), in: options.contentRect, context: context)
    }

    /// One sheet per laid-out worksheet page. The layout has already decided
    /// what sits where; this only starts the pages and hands each one to
    /// `WorksheetRenderer`.
    func drawWorksheetPages(
        _ sheets: [WorksheetSheet],
        options worksheetOptions: WorksheetOptions,
        into context: UIGraphicsPDFRendererContext
    ) {
        let renderer = WorksheetRenderer(page: options.worksheetPage, options: worksheetOptions)
        for sheet in sheets {
            context.beginPage()
            fillPaper(in: context)
            renderer.draw(sheet, in: context.cgContext)
        }
    }

    // MARK: - Page furniture

    private func fillPaper(in context: UIGraphicsPDFRendererContext) {
        paperColor.setFill()
        context.fill(options.pageRect)
    }

    /// Places ink inside `target`, clipped to it so a wide drawing can never
    /// bleed over the page margin.
    private func drawInk(
        _ strokes: [Stroke],
        bounds inkBounds: CGRect,
        in target: CGRect,
        context: UIGraphicsPDFRendererContext
    ) {
        guard !inkBounds.isNull, !strokes.isEmpty else { return }
        let cgContext = context.cgContext

        cgContext.saveGState()
        cgContext.clip(to: target)
        cgContext.concatenate(
            InkFitTransform.centring(inkBounds, in: target, maximumScale: options.maximumScale)
        )
        StrokeRasterizer.draw(strokes, in: cgContext, offset: inkBounds.origin)
        cgContext.restoreGState()
    }
}
