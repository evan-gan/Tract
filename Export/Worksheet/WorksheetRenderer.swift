import UIKit

/// Paints one laid-out worksheet sheet. It makes no placement decisions of its
/// own: every position and scale arrives already decided.
///
/// Everything is in page coordinates — origin at the top-left of the sheet, y
/// down, which is what `UIGraphicsPDFRenderer` hands over and the same sense as
/// Tract's canvas, so ink needs no axis flip.
struct WorksheetRenderer {
    let page: WorksheetPageGeometry
    let options: WorksheetOptions

    private static let separatorWidth: CGFloat = 1.6
    private static let separatorDash: [CGFloat] = [7, 5]
    private static let outlineWidth: CGFloat = 0.75
    private static let outlineDash: [CGFloat] = [4, 3]

    /// Separators first, then ink, then badges — so a neighbour's ink can never
    /// be drawn over a badge.
    func draw(_ sheet: WorksheetSheet, in context: CGContext) {
        if options.drawsSeparators { drawSeparators(for: sheet, in: context) }

        for placement in sheet.placements {
            if options.drawsTensionOutlines { drawTensionOutline(for: placement, in: context) }
            drawInk(for: placement, in: context)
        }

        if options.drawsBadges {
            for placement in sheet.placements { drawBadge(for: placement, in: context) }
        }
    }

    // MARK: - Ink

    private func drawInk(for placement: WorksheetPlacement, in context: CGContext) {
        context.saveGState()
        context.concatenate(placement.inkTransform)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in placement.block.strokes {
            context.setStrokeColor(StrokeRasterizer.strokeColor(from: stroke.style))
            context.setLineWidth(stroke.style.lineWidth)
            context.addPath(StrokeRasterizer.path(through: stroke.points))
            context.strokePath()
        }
        context.restoreGState()
    }

    // MARK: - Page furniture

    /// Every separator is drawn identically. Varying weight by what a line
    /// divided made the page look like some lines were accidents of the drawing
    /// rather than one deliberate grid.
    private func drawSeparators(for sheet: WorksheetSheet, in context: CGContext) {
        let regions = sheet.placements.map { $0.outline(padding: options.padding) }
        let lines = WorksheetSeparators.lines(dividing: regions, page: page)
        guard !lines.isEmpty else { return }

        context.saveGState()
        context.setStrokeColor(WorksheetPalette.separator.cgColor)
        context.setLineWidth(Self.separatorWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineDash(phase: 0, lengths: Self.separatorDash)

        for line in lines where line.count >= 2 {
            context.addLines(between: line)
            context.strokePath()
        }
        context.restoreGState()
    }

    /// The hull the packer worked against, as a dashed outline in the problem's
    /// colour. A debugging aid — normally off.
    private func drawTensionOutline(for placement: WorksheetPlacement, in context: CGContext) {
        let outline = placement.outline(padding: options.padding)
        guard outline.count >= 2 else { return }

        context.saveGState()
        context.setStrokeColor(WorksheetPalette.color(forGroupIndex: placement.block.groupIndex).cgColor)
        context.setLineWidth(Self.outlineWidth)
        context.setLineDash(phase: 0, lengths: Self.outlineDash)
        context.addLines(between: outline + [outline[0]])
        context.strokePath()
        context.restoreGState()
    }

    /// The problem tag: white on a dark rounded plate, ringed in its problem's
    /// colour, at the top-left corner of its own work.
    ///
    /// No search and no fallback — the packer reserved this exact rectangle
    /// before it placed anything, so the badge is always clear of ink and always
    /// in the same place relative to its problem. It is re-derived from the
    /// *placed* ink hull, so the two can never disagree.
    private func drawBadge(for placement: WorksheetPlacement, in context: CGContext) {
        let rect = WorksheetBadge.rect(forInkOutline: placement.inkHull, label: placement.block.label)
        let plate = UIBezierPath(roundedRect: rect, cornerRadius: WorksheetBadge.cornerRadius)

        context.saveGState()
        context.setFillColor(WorksheetPalette.badgePlate.cgColor)
        context.addPath(plate.cgPath)
        context.fillPath()

        context.setStrokeColor(WorksheetPalette.color(forGroupIndex: placement.block.groupIndex).cgColor)
        context.setLineWidth(WorksheetBadge.ringWidth)
        context.addPath(plate.cgPath)
        context.strokePath()
        context.restoreGState()

        drawBadgeText(placement.block.label, in: rect, context: context)
    }

    private func drawBadgeText(_ label: String, in rect: CGRect, context: CGContext) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        // Clipping rather than wrapping or ellipsising: the badge was sized from
        // an upper bound on the text's width, so overflow means the estimate is
        // wrong and a truncated tag would hide that.
        paragraph.lineBreakMode = .byClipping

        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: "Helvetica-Bold", size: WorksheetBadge.fontSize)
                ?? .boldSystemFont(ofSize: WorksheetBadge.fontSize),
            .foregroundColor: WorksheetPalette.badgeText,
            .paragraphStyle: paragraph
        ]

        // UIKit text drawing paints into the *current UIKit context*, which a
        // bare CGContext is not, so it has to be made current for the call.
        UIGraphicsPushContext(context)
        (label as NSString).draw(
            in: CGRect(
                x: rect.minX,
                y: rect.minY + WorksheetBadge.padding,
                width: rect.width,
                height: rect.height - WorksheetBadge.padding
            ),
            withAttributes: attributes
        )
        UIGraphicsPopContext()
    }
}
