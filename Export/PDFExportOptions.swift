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
    /// How many levels of the problem tag get their own cell. Nil gives every
    /// sub-part its own cell; 1 puts all of problem 1's parts in one cell together.
    var groupingDepth: Int?
    /// Renders a problem's tag into its cell heading.
    var tagFormatter: ProblemTagFormatter = .standard

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
}
