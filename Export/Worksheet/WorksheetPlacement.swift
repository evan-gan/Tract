import CoreGraphics

/// One problem, sized and put somewhere on a sheet.
///
/// `origin` is where the block's *painted box* top-left lands in page
/// coordinates — not where its hull lands, and not where its badge lands. Every
/// other shape is derived from that one anchor, so the packer, the growth pass
/// and the renderer can never disagree about where a problem is.
struct WorksheetPlacement {
    let block: WorksheetBlock
    var origin: CGPoint
    var scale: CGFloat

    /// Canvas → page. Translate first, then scale, so stroke coordinates can be
    /// emitted unchanged inside it.
    var inkTransform: CGAffineTransform {
        CGAffineTransform(translationX: origin.x - block.bounds.minX * scale,
                          y: origin.y - block.bounds.minY * scale)
            .scaledBy(x: scale, y: scale)
    }

    /// The ink's tension outline where it actually sits — no badge, no
    /// clearance. This is what the badge is positioned against, so a badge's
    /// place on the page is decided by the handwriting rather than by its own
    /// reserved corner.
    var inkHull: [CGPoint] {
        let scaled = WorksheetPolygon.scaled(block.hull, by: scale)
        return WorksheetPolygon.translated(
            scaled,
            by: CGPoint(x: origin.x - block.bounds.minX * scale,
                        y: origin.y - block.bounds.minY * scale)
        )
    }

    /// The shape everything downstream works on: the ink hull, the badge folded
    /// in, and `padding` of clearance around both.
    func outline(padding: CGFloat) -> [CGPoint] {
        WorksheetPolygon.dilated(
            WorksheetBadge.outlineWithBadge(inkHull, label: block.label),
            by: padding
        )
    }

    /// The same placement at a different scale, with one point of its painted
    /// box held still. Used by the growth pass: a problem hemmed in on the right
    /// can still expand leftwards by anchoring its top-right corner.
    func resized(to newScale: CGFloat, anchor: WorksheetGrowthAnchor) -> WorksheetPlacement {
        let growth = CGPoint(
            x: block.bounds.width * (newScale - scale),
            y: block.bounds.height * (newScale - scale)
        )
        var resized = self
        resized.scale = newScale
        resized.origin = CGPoint(
            x: origin.x - growth.x * anchor.horizontalShare,
            y: origin.y - growth.y * anchor.verticalShare
        )
        return resized
    }
}

/// Which point of a growing problem's box stays put. The shares say how much of
/// the growth comes off the origin: none for a left/top anchor, all of it for a
/// right/bottom one, half each way for the centre.
enum WorksheetGrowthAnchor: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight, center

    var horizontalShare: CGFloat {
        switch self {
        case .topLeft, .bottomLeft: 0
        case .topRight, .bottomRight: 1
        case .center: 0.5
        }
    }

    var verticalShare: CGFloat {
        switch self {
        case .topLeft, .topRight: 0
        case .bottomLeft, .bottomRight: 1
        case .center: 0.5
        }
    }
}

/// One laid-out sheet of paper.
struct WorksheetSheet {
    var placements: [WorksheetPlacement] = []
}
