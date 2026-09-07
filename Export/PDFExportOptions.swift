import CoreGraphics

/// How a PDF export is laid out on paper.
struct PDFExportOptions: Sendable {
    /// One inch is the safe default: no consumer printer clips at that margin.
    static let defaultMargin: CGFloat = 72
    /// The worksheet packs against its own clearance rather than a printer's, so
    /// it can afford a half-inch border and gains a lot of paper by taking it.
    static let worksheetMargin: CGFloat = 36

    var paperSize: PaperSize = .usLetter
    var orientation: PageOrientation = .portrait
    /// Blank border on all four sides, in points.
    var margin: CGFloat = defaultMargin
    /// Ceiling on how far ink may be enlarged to fill its box, for the layouts
    /// that fit ink to a box. 1 reproduces the drawing at its canvas size.
    var maximumScale: CGFloat = 1
    var layout: PDFPageLayout = .wholeDrawing

    /// A worksheet: every problem nested against its neighbours at one readable
    /// size, badged with its number, the sheet divided by separator lines.
    ///
    /// Landscape because handwriting runs wider than it runs tall, so a
    /// landscape sheet fits more problems side by side at the same text size.
    static var problemSheet: PDFExportOptions {
        var options = PDFExportOptions()
        options.orientation = .landscape
        options.margin = worksheetMargin
        options.layout = .worksheet(WorksheetOptions())
        return options
    }

    /// The page box, always at the origin. A PDF whose media box starts anywhere
    /// else puts (0, 0) off-page, which is why drawing must be positioned within
    /// this rect rather than in canvas coordinates.
    var pageRect: CGRect {
        CGRect(origin: .zero, size: paperSize.size(in: orientation))
    }

    /// The page minus its margins — where ink is allowed to land.
    var contentRect: CGRect {
        pageRect.insetBy(dx: margin, dy: margin)
    }

    /// The same paper, as the worksheet layout describes it.
    var worksheetPage: WorksheetPageGeometry {
        WorksheetPageGeometry(paper: paperSize, orientation: orientation, margin: margin)
    }
}

enum PDFPageLayout: Sendable {
    /// The whole drawing scaled to fit a single page.
    case wholeDrawing
    /// One problem per badged shape, nested to fill the paper, flowing onto as
    /// many pages as the work needs.
    case worksheet(WorksheetOptions)

    static var worksheet: PDFPageLayout { .worksheet(WorksheetOptions()) }

    var isWorksheet: Bool {
        if case .worksheet = self { return true }
        return false
    }
}
