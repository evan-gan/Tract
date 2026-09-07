import CoreGraphics
import Foundation
@testable import Tract

/// Builds worksheet blocks from bare shapes, so a layout test reads as the
/// problems it is packing rather than as pages of stroke telemetry.
enum WorksheetFixtures {
    static let letterLandscape = WorksheetPageGeometry(
        paper: .usLetter,
        orientation: .landscape,
        margin: PDFExportOptions.worksheetMargin
    )

    /// A square problem: one closed square of ink, with the hull and painted box
    /// the real builder would have derived from it.
    static func block(
        label: String,
        groupIndex: Int? = 0,
        side: CGFloat = 120,
        at origin: CGPoint = .zero,
        lineWidth: CGFloat = 4
    ) -> WorksheetBlock {
        let corners = [
            origin,
            CGPoint(x: origin.x + side, y: origin.y),
            CGPoint(x: origin.x + side, y: origin.y + side),
            CGPoint(x: origin.x, y: origin.y + side),
            origin
        ]
        return block(label: label, groupIndex: groupIndex, points: corners, lineWidth: lineWidth)
    }

    /// A problem of any shape — a slanted or wedge-shaped one is what the hull
    /// packing exists for.
    static func block(
        label: String,
        groupIndex: Int? = 0,
        points: [CGPoint],
        lineWidth: CGFloat = 4
    ) -> WorksheetBlock {
        let stroke = WorksheetStroke(
            points: points,
            style: StrokeStyle(color: SIMD4(0, 0, 0, 1), lineWidth: lineWidth, opacity: 1, tool: .pen)
        )
        let centreline = points.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
        let nibRadius = lineWidth / 2

        return WorksheetBlock(
            label: label,
            groupIndex: groupIndex,
            strokes: [stroke],
            bounds: centreline.insetBy(dx: -nibRadius, dy: -nibRadius),
            hull: WorksheetPolygon.dilated(WorksheetPolygon.convexHull(points), by: nibRadius)
        )
    }

    /// `count` square problems labelled 1, 2, 3 … — enough to make a packer work
    /// without making a test unreadable.
    static func numberedBlocks(_ count: Int, side: CGFloat = 120) -> [WorksheetBlock] {
        (1 ... count).map { index in
            block(label: String(index), groupIndex: index - 1, side: side)
        }
    }
}
