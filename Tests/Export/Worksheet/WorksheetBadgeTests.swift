import Testing
import CoreGraphics
@testable import Tract

@Suite("Worksheet badges")
struct WorksheetBadgeTests {
    @Test("A one-character tag gets a square badge; a longer one gets a wider badge")
    func badgeSizeGrowsWithTheLabel() {
        let short = WorksheetBadge.size(for: "1")
        let long = WorksheetBadge.size(for: "1bIV")

        #expect(short.width == short.height)
        #expect(long.width > short.width)
        #expect(long.height == short.height)
    }

    @Test("The badge is never drawn over its own problem's ink")
    func badgeClearsTheInk() {
        // A square is the worst case: its hull fills its top-left corner, so the
        // badge has to rise all the way clear of it.
        let square = WorksheetPolygon.corners(of: CGRect(x: 100, y: 100, width: 80, height: 80))

        let badge = WorksheetBadge.rect(forInkOutline: square, label: "1a")

        #expect(!WorksheetPolygon.intersect(WorksheetPolygon.corners(of: badge), square))
        #expect(badge.maxY <= 100)
    }

    @Test("The badge drops into the notch a slanted problem leaves at its top-left")
    func badgeSitsInsideACutAwayCorner() {
        // Handwriting that starts to the right of everything below it leaves the
        // top-left corner empty; using it costs the layout nothing, and refusing
        // to use it cost a whole extra page on the sample worksheet.
        let slanted = [CGPoint(x: 200, y: 0), CGPoint(x: 260, y: 0), CGPoint(x: 60, y: 200), CGPoint(x: 0, y: 200)]

        let badge = WorksheetBadge.rect(forInkOutline: slanted, label: "1")

        #expect(!WorksheetPolygon.intersect(WorksheetPolygon.corners(of: badge), slanted))
        // It never had to rise at all: it sits inside the shape's own box, so
        // the problem is no taller for having a badge.
        #expect(badge.minY == WorksheetPolygon.bounds(of: slanted).minY)
    }

    @Test("The badge's left edge lines up with the ink, so the eye learns where to look")
    func badgeIsAlignedWithTheInk() {
        let square = WorksheetPolygon.corners(of: CGRect(x: 100, y: 100, width: 80, height: 80))

        #expect(WorksheetBadge.rect(forInkOutline: square, label: "3").minX == 100)
    }

    @Test("The packed shape reserves the badge, so nothing can be placed on top of it")
    func packedShapeContainsTheBadge() {
        let square = WorksheetPolygon.corners(of: CGRect(x: 100, y: 100, width: 80, height: 80))
        let badge = WorksheetBadge.rect(forInkOutline: square, label: "1a")

        let packed = WorksheetBadge.outlineWithBadge(square, label: "1a")

        for corner in WorksheetPolygon.corners(of: badge) {
            #expect(WorksheetPolygon.contains(packed, corner))
        }
    }

    @Test("The badge is the same size whether its problem was shrunk or grown")
    func badgeDoesNotScaleWithTheDrawing() {
        let small = WorksheetPolygon.corners(of: CGRect(x: 0, y: 0, width: 40, height: 40))
        let large = WorksheetPolygon.corners(of: CGRect(x: 0, y: 0, width: 400, height: 400))

        #expect(WorksheetBadge.rect(forInkOutline: small, label: "2").size
            == WorksheetBadge.rect(forInkOutline: large, label: "2").size)
    }
}
