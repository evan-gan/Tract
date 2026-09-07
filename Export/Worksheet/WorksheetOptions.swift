import CoreGraphics

/// The knobs on the worksheet layout — everything except the paper itself,
/// which comes from `PDFExportOptions` like it does for any other PDF.
///
/// The defaults are the shipping look, tuned on real homework: landscape letter
/// at a 36pt margin (set by `PDFExportOptions.problemSheet`), problems nested
/// against their tension outlines with 8pt of clearance, and the whole sheet
/// divided by dashed separator lines.
struct WorksheetOptions: Sendable {
    /// Clearance baked into every problem's outline, in page points. Two padded
    /// outlines that do not overlap leave twice this between the ink, so this is
    /// the *only* thing keeping problems apart — there are no gaps between rows.
    var padding: CGFloat = 8
    /// Ramer–Douglas–Peucker tolerance in canvas points. 0 keeps every sample.
    var simplifyTolerance: CGFloat = 0.35
    /// Readability floor: the layout spends another sheet rather than drawing
    /// ink smaller than this share of its canvas size.
    var minimumScale: CGFloat = 0.8
    /// How far ink may be enlarged to fill a page that would otherwise sit empty.
    var maximumScale: CGFloat = 4
    /// Ceiling for both expand-to-fill passes. 1 is the drawing's canvas size.
    var growthCap: CGFloat = 1.25
    /// Re-nest each page's own problems at the largest scale that page allows.
    var refitsPages = true
    /// Let individual problems grow into whatever room their neighbours leave.
    var growsProblems = true
    var drawsSeparators = true
    var drawsBadges = true
    /// The dashed hull the packer worked against. A debugging aid, off by default.
    var drawsTensionOutlines = false
    /// Heading for work carrying no tag. Nil leaves untagged work off the sheet.
    var untaggedLabel: String? = "untagged"
}

/// The sheet a worksheet is laid out on: its size and the box inside the margins
/// that ink is allowed to occupy. Page points, y down, origin top-left.
struct WorksheetPageGeometry: Sendable {
    let size: CGSize
    let margin: CGFloat

    var pageRect: CGRect { CGRect(origin: .zero, size: size) }
    var contentRect: CGRect { pageRect.insetBy(dx: margin, dy: margin) }

    init(size: CGSize, margin: CGFloat) {
        self.size = size
        self.margin = margin
    }

    init(paper: PaperSize, orientation: PageOrientation, margin: CGFloat) {
        self.init(size: paper.size(in: orientation), margin: margin)
    }
}
