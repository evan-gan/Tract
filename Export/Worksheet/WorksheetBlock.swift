import CoreGraphics
import Foundation

/// One stroke as the worksheet layout carries it: its samples thinned once, up
/// front, so hulls, packing and drawing all work on the same reduced polyline.
struct WorksheetStroke {
    /// Canvas space, simplified. Always at least two points.
    let points: [CGPoint]
    let style: StrokeStyle
}

/// One problem's worth of ink, with the geometry the layout reasons about.
///
/// Everything here is in canvas space. Where the block lands on paper is a
/// `WorksheetPlacement`, which the packer decides and this knows nothing about.
struct WorksheetBlock: Identifiable {
    /// The problem as it is written on a worksheet: "1a", "1bIV", "untagged".
    let label: String
    /// Top-level problem number, 0-based — what the colour coding keys off.
    /// Nil for untagged work.
    let groupIndex: Int?
    /// In paint order.
    let strokes: [WorksheetStroke]
    /// The *painted* box: every sample, grown on all sides by half the widest
    /// nib in the block, because a stroke is painted about its centreline and
    /// the ink reaches half a nib past the samples.
    let bounds: CGRect
    /// The tension outline in canvas space: the ink's convex hull held off the
    /// strokes by the same nib radius.
    let hull: [CGPoint]

    var id: String { label }
}

/// Turns a document into the per-problem blocks the worksheet layout packs.
enum WorksheetBlockBuilder {
    /// - Parameters:
    ///   - document: The document to lay out. Its problem outline is what turns
    ///     each stroke's stored node id into the address it prints under today.
    ///   - viewport: If non-nil, only strokes touching this canvas-space rect
    ///     are included — the same clipping every other exporter applies.
    ///   - options: `simplifyTolerance` and `untaggedLabel` are read here; the
    ///     rest of the worksheet options belong to later stages.
    /// - Returns: Blocks in reading order (1a, 1b, 1c, 2a, …, 9 before 10), with
    ///   untagged work last. Empty when nothing would put ink on the page.
    static func blocks(
        from document: SplineDocument,
        viewport: CGRect?,
        options: WorksheetOptions
    ) -> [WorksheetBlock] {
        let groups = ProblemGrouping.groups(
            from: StrokeRasterizer.strokes(document.strokes, intersecting: viewport),
            outline: document.problemOutline,
            untaggedLabel: options.untaggedLabel,
            formatter: .compact
        )
        return groups.compactMap { block(from: $0, simplifyTolerance: options.simplifyTolerance) }
    }

    /// Nil when the group has nothing left to draw once thinning and the
    /// two-sample rule have been applied.
    private static func block(from group: ProblemGroup, simplifyTolerance: CGFloat) -> WorksheetBlock? {
        let strokes = group.strokes.compactMap { stroke -> WorksheetStroke? in
            let points = WorksheetPolyline.simplified(
                stroke.points.map(\.position),
                tolerance: simplifyTolerance
            )
            // A lone sample paints nothing, so it must not widen the block either.
            guard points.count >= 2 else { return nil }
            return WorksheetStroke(points: points, style: stroke.style)
        }
        guard !strokes.isEmpty else { return nil }

        let samples = strokes.flatMap(\.points)
        let centrelineBounds = samples.reduce(CGRect.null) {
            $0.union(CGRect(origin: $1, size: .zero))
        }
        guard !centrelineBounds.isNull else { return nil }

        let nibRadius = (strokes.map(\.style.lineWidth).max() ?? 0) / 2
        return WorksheetBlock(
            label: group.label,
            groupIndex: group.tag?.components.first.map { $0.ordinal - 1 },
            strokes: strokes,
            bounds: centrelineBounds.insetBy(dx: -nibRadius, dy: -nibRadius),
            hull: WorksheetPolygon.dilated(
                WorksheetPolygon.convexHull(samples),
                by: nibRadius
            )
        )
    }
}
