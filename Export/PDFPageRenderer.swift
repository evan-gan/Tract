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
    var labelColor: UIColor = .black
    var borderColor: UIColor = UIColor(white: 0.75, alpha: 1)

    /// The whole drawing scaled to fit inside one page's margins.
    func drawWholeDrawingPage(strokes: [Stroke], into context: UIGraphicsPDFRendererContext) {
        context.beginPage()
        fillPaper(in: context)
        drawInk(strokes, bounds: StrokeRasterizer.unionBounds(of: strokes), in: options.contentRect, context: context)
    }

    /// One page per `layout.cellsPerPage` groups, each group in its own labelled cell.
    func drawProblemTablePages(
        groups: [ProblemGroup],
        layout: ProblemTableLayout,
        into context: UIGraphicsPDFRendererContext
    ) {
        let cellRects = layout.cellRects(in: options.contentRect)

        for pageGroups in groups.chunked(into: layout.cellsPerPage) {
            context.beginPage()
            fillPaper(in: context)
            for (group, cell) in zip(pageGroups, cellRects) {
                drawCell(for: group, in: cell, layout: layout, context: context)
            }
        }
    }

    // MARK: - Page furniture

    private func fillPaper(in context: UIGraphicsPDFRendererContext) {
        paperColor.setFill()
        context.fill(options.pageRect)
    }

    private func drawCell(
        for group: ProblemGroup,
        in cell: CGRect,
        layout: ProblemTableLayout,
        context: UIGraphicsPDFRendererContext
    ) {
        if layout.drawsCellBorders {
            borderColor.setStroke()
            let border = UIBezierPath(roundedRect: cell, cornerRadius: 6)
            border.lineWidth = 0.5
            border.stroke()
        }
        drawLabel(group.label, in: layout.labelRect(in: cell), fontSize: layout.labelFontSize)
        drawInk(group.strokes, bounds: group.inkBounds, in: layout.inkRect(in: cell), context: context)
    }

    private func drawLabel(_ text: String, in rect: CGRect, fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: labelColor
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    /// Places ink inside `target`, clipped to it so a wide drawing can never
    /// bleed into the neighbouring cell or over the page margin.
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

private extension Array {
    /// Splits into fixed-size batches, the last one short. Used to deal groups
    /// out one page at a time.
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return isEmpty ? [] : [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
