import CoreGraphics

/// How a PDF export is laid out on paper.
struct PDFExportOptions: Sendable {
    /// One inch is the safe default: no consumer printer clips at that margin.
    static let defaultMargin: CGFloat = 72

    var paperSize: PaperSize = .usLetter
    var orientation: PageOrientation = .portrait
    /// Blank border on all four sides, in points.
    var margin: CGFloat = defaultMargin
    /// Ceiling on how far ink may be enlarged to fill its box. 1 reproduces the
    /// drawing at its canvas size; raising it lets small work fill the page.
    var maximumScale: CGFloat = 1
    var layout: PDFPageLayout = .wholeDrawing

    /// Ink written small on an infinite canvas has to grow a long way to fill a
    /// cell a sixth of a page wide. The default ceiling of 1 would leave most
    /// problems as specks in the corner of their box.
    static let problemCellMaximumScale: CGFloat = 12

    /// A worksheet: every tagged problem in its own labelled cell, six to a page,
    /// with anything untagged gathered onto a final page of its own.
    static var problemSheet: PDFExportOptions {
        var options = PDFExportOptions()
        options.layout = .problemTable
        options.maximumScale = problemCellMaximumScale
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
}

enum PDFPageLayout: Sendable {
    /// The whole drawing scaled to fit a single page.
    case wholeDrawing
    /// One labelled cell per tagged problem, flowing across as many pages as needed.
    case problemTable(ProblemTableLayout)

    static var problemTable: PDFPageLayout { .problemTable(ProblemTableLayout()) }

    var isProblemTable: Bool {
        if case .problemTable = self { return true }
        return false
    }
}

/// The grid a problem table is drawn on. All measurements are in points.
struct ProblemTableLayout: Sendable {
    var columns: Int = 2
    var rows: Int = 3
    var cellSpacing: CGFloat = 18
    /// Space reserved at the top of each cell for its problem label.
    var labelHeight: CGFloat = 18
    var labelFontSize: CGFloat = 11
    /// Breathing room between a cell's border and its contents.
    var cellPadding: CGFloat = 8
    var drawsCellBorders: Bool = true
    /// Heading for strokes with no tag. Nil leaves untagged work out of the export.
    var untaggedLabel: String? = "Untagged"
    /// Printed under that heading, so a reader knows the page is leftovers rather
    /// than a problem whose number failed to print.
    var untaggedNote: String = "These strokes are not attributed to any problem."
    var untaggedHeadingFontSize: CGFloat = 15
    var untaggedNoteFontSize: CGFloat = 10
    /// Height reserved for the note line under the untagged page's heading.
    var untaggedNoteHeight: CGFloat = 16
    /// How many levels of the problem tag get their own cell. Nil gives every
    /// sub-part its own cell; 1 puts all of problem 1's parts in one cell together.
    var groupingDepth: Int?
    /// Renders a problem's tag into its cell heading. Compact by default: a cell
    /// heading is small, and "1a" is how the problem is written on the worksheet.
    var tagFormatter: ProblemTagFormatter = .compact

    var cellsPerPage: Int { max(columns, 1) * max(rows, 1) }

    /// Cell frames for one page, in reading order: left to right, top to bottom.
    func cellRects(in contentRect: CGRect) -> [CGRect] {
        let columnCount = max(columns, 1)
        let rowCount = max(rows, 1)
        let cellWidth = (contentRect.width - cellSpacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        let cellHeight = (contentRect.height - cellSpacing * CGFloat(rowCount - 1)) / CGFloat(rowCount)

        return (0 ..< rowCount).flatMap { row in
            (0 ..< columnCount).map { column in
                CGRect(
                    x: contentRect.minX + (cellWidth + cellSpacing) * CGFloat(column),
                    y: contentRect.minY + (cellHeight + cellSpacing) * CGFloat(row),
                    width: cellWidth,
                    height: cellHeight
                )
            }
        }
    }

    /// The part of a cell that ink may occupy: inside the padding, below the label.
    func inkRect(in cell: CGRect) -> CGRect {
        let padded = cell.insetBy(dx: cellPadding, dy: cellPadding)
        return CGRect(
            x: padded.minX,
            y: padded.minY + labelHeight,
            width: padded.width,
            height: max(padded.height - labelHeight, 1)
        )
    }

    func labelRect(in cell: CGRect) -> CGRect {
        let padded = cell.insetBy(dx: cellPadding, dy: cellPadding)
        return CGRect(x: padded.minX, y: padded.minY, width: padded.width, height: labelHeight)
    }

    // MARK: - The untagged page
    //
    // Untagged work gets the whole sheet rather than a cell in the grid: it has
    // no problem to sit beside, and cutting it down to a sixth of a page would
    // only make the one thing nobody labelled the hardest thing to read.

    func untaggedHeadingRect(in contentRect: CGRect) -> CGRect {
        CGRect(x: contentRect.minX, y: contentRect.minY, width: contentRect.width, height: labelHeight)
    }

    func untaggedNoteRect(in contentRect: CGRect) -> CGRect {
        CGRect(
            x: contentRect.minX,
            y: contentRect.minY + labelHeight,
            width: contentRect.width,
            height: untaggedNoteHeight
        )
    }

    func untaggedInkRect(in contentRect: CGRect) -> CGRect {
        let headerHeight = labelHeight + untaggedNoteHeight + cellPadding
        return CGRect(
            x: contentRect.minX,
            y: contentRect.minY + headerHeight,
            width: contentRect.width,
            height: max(contentRect.height - headerHeight, 1)
        )
    }
}
