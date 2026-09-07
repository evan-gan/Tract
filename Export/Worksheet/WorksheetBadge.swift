import CoreGraphics

/// The problem-number badge, as a piece of geometry.
///
/// The badge is part of the problem's shape, not something added to the page
/// afterwards: it sits at the top-left corner of the problem's outline, and the
/// packer includes it when it decides where the problem goes.
///
/// That ordering is what makes it work. Space for the badge is reserved before
/// anything is placed, so a badge can never land on a neighbour's handwriting or
/// have to be squeezed in — and because it is always in the same place relative
/// to its problem, the eye learns where to look instead of hunting for it.
///
/// Sizes here are page points and do **not** scale with the drawing: a badge is
/// the same size whether its problem was shrunk or grown.
enum WorksheetBadge {
    static let fontSize: CGFloat = 18
    /// Breathing room between the text and the plate's edge.
    static let padding: CGFloat = 4
    static let cornerRadius: CGFloat = 5
    /// The problem-colour ring, thick enough to read as colour rather than an edge.
    static let ringWidth: CGFloat = 2.5

    /// Gap left between the badge and the ink it belongs to, once it has risen
    /// clear of it entirely.
    private static let inkOffset: CGFloat = 3
    /// How far the badge rises per attempt while looking for clear paper.
    private static let liftStep: CGFloat = 2

    /// Upper bound on a character's width as a fraction of the font size, for
    /// Helvetica-Bold digits and letters.
    ///
    /// Estimated rather than measured with real font metrics, and deliberately:
    /// the geometry has to be known before there is a page to measure against,
    /// and a narrower measured badge would change the packing. Erring wide is
    /// safe — the text is centred, so a roomy badge just looks deliberate.
    private static let characterWidth: CGFloat = 0.62

    /// Never narrower than it is tall, so a one-character tag stays a square.
    static func size(for label: String) -> CGSize {
        let height = fontSize + padding * 2
        let textWidth = CGFloat(label.count) * fontSize * characterWidth
        return CGSize(width: max(textWidth + padding * 2, height), height: height)
    }

    /// Where the badge sits for a problem: at its top-left corner, lifted just
    /// far enough to clear the ink.
    ///
    /// It starts *inside* the corner and rises only until it is clear, because a
    /// hull around handwriting is nearly always cut away there — the first line
    /// of working rarely starts at the extreme top-left of everything below it,
    /// and dropping the badge into that notch costs the layout nothing. Sitting
    /// every badge fully above its problem instead adds a badge height to every
    /// shape on the sheet, which was a whole extra page on the sample worksheet.
    ///
    /// - Parameter inkOutline: The hull around the ink alone, badge excluded.
    static func rect(forInkOutline inkOutline: [CGPoint], label: String) -> CGRect {
        let size = self.size(for: label)
        let bounds = WorksheetPolygon.bounds(of: inkOutline)
        guard !bounds.isNull else { return CGRect(origin: .zero, size: size) }

        let fullyOutside = bounds.minY - size.height - inkOffset
        for top in stride(from: bounds.minY, through: fullyOutside, by: -liftStep) {
            let candidate = CGRect(origin: CGPoint(x: bounds.minX, y: top), size: size)
            if !WorksheetPolygon.intersect(WorksheetPolygon.corners(of: candidate), inkOutline) {
                return candidate
            }
        }
        return CGRect(origin: CGPoint(x: bounds.minX, y: fullyOutside), size: size)
    }

    /// The problem's outline with its badge folded in — the shape the packer,
    /// the growth pass and the page division all reason about.
    static func outlineWithBadge(_ inkOutline: [CGPoint], label: String) -> [CGPoint] {
        guard !inkOutline.isEmpty else { return inkOutline }
        let badge = rect(forInkOutline: inkOutline, label: label)
        return WorksheetPolygon.convexHull(inkOutline + WorksheetPolygon.corners(of: badge))
    }
}
