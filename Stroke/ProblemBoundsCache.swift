import CoreGraphics
import Foundation

/// Builds the problems' bounding regions, remembering each traced shape so a
/// change to one problem's ink does not retrace every other problem on the page.
///
/// Tracing one region is two distance-field sweeps over a sampling grid (see
/// `ProblemRegion`) — far too much work to repeat for problem 1 because a mark
/// was just added to problem 7. Each shape is held against a fingerprint of the
/// ink it was traced from, so a commit retraces exactly the problem that was
/// written in, and nothing at all when the new ink is untagged.
struct ProblemBoundsCache {

    /// The expensive half of a region: the geometry `ProblemRegion` traced, kept
    /// apart from the tag and the colour, which come from the tree and are cheap
    /// to resolve again on every read. That split is what stops a reorder —
    /// which renames every problem after the one that moved — retracing anything.
    private struct TracedShape {
        let contours: [[CGPoint]]
        let extent: CGRect
    }

    /// `shape` is nil for a problem whose ink traced to nothing, so a degenerate
    /// one is not retraced on every read.
    private struct Entry {
        let ink: ProblemInkFingerprint
        let shape: TracedShape?
    }

    private var entriesByNodeID: [UUID: Entry] = [:]

    /// How many shapes this cache has actually traced. The whole point of the
    /// cache is that this stays flat while the page is edited elsewhere, and
    /// that is only checkable by counting the traces.
    private(set) var traceCount = 0

    /// Builds one region per problem that has ink on the page, retracing only
    /// the problems whose own ink has changed since the last call.
    ///
    /// - Parameters:
    ///   - strokes: Any strokes; non-drawing tools and single-sample taps are
    ///     dropped, and untagged ink is left unframed — there is no problem to
    ///     name it after.
    ///   - outline: The tree that turns a stroke's stored node id into the
    ///     address it prints under. A stroke whose node is gone counts as
    ///     untagged.
    ///   - padding: How far the shape stands off the ink where it touches it.
    ///   - curveRadius: How much the shape refuses to follow the ink into a gap.
    /// - Returns: One region per tagged problem, ordered outermost level first
    ///   (1, 1a, 1a(i), 1b, 2) so the drawing order never shuffles between
    ///   frames.
    mutating func regions(
        in strokes: [Stroke],
        outline: ProblemOutline,
        padding: CGFloat,
        curveRadius: CGFloat
    ) -> [ProblemBounds] {
        let inkByNodeID = Self.inkGroupedByProblem(in: strokes)
        // Nothing on the page is filed under a problem, so there is no shape to
        // trace and nothing worth remembering either.
        guard !inkByNodeID.isEmpty else {
            entriesByNodeID.removeAll()
            return []
        }
        // A problem whose ink was erased or re-filed will be traced afresh if it
        // ever comes back, so its shape is not worth holding on to.
        entriesByNodeID = entriesByNodeID.filter { inkByNodeID.keys.contains($0.key) }

        return inkByNodeID
            .compactMap { nodeID, ink in
                region(
                    forNode: nodeID,
                    ink: ink,
                    outline: outline,
                    padding: padding,
                    curveRadius: curveRadius
                )
            }
            .sorted { $0.tag < $1.tag }
    }

    private mutating func region(
        forNode nodeID: UUID,
        ink: [Stroke],
        outline: ProblemOutline,
        padding: CGFloat,
        curveRadius: CGFloat
    ) -> ProblemBounds? {
        guard let path = outline.path(ofNode: nodeID), let problemIndex = path.first else {
            return nil
        }
        guard let shape = shape(
            forNode: nodeID,
            ink: ink,
            padding: padding,
            curveRadius: curveRadius
        ) else { return nil }

        return ProblemBounds(
            nodeID: nodeID,
            tag: outline.tag(at: path),
            problemIndex: problemIndex,
            contours: shape.contours,
            extent: shape.extent
        )
    }

    /// The traced geometry for one problem, from the cache when that problem's
    /// ink is untouched and from `ProblemRegion` when it is not.
    private mutating func shape(
        forNode nodeID: UUID,
        ink: [Stroke],
        padding: CGFloat,
        curveRadius: CGFloat
    ) -> TracedShape? {
        let fingerprint = ProblemInkFingerprint(strokes: ink)
        if let entry = entriesByNodeID[nodeID], entry.ink == fingerprint { return entry.shape }

        // Reached only on a miss, so the samples are mapped for the one problem
        // being retraced rather than for every problem on the page.
        traceCount += 1
        let polylines = ink.map { $0.points.map(\.position) }
        let contours = ProblemRegion.contours(
            around: polylines,
            padding: padding,
            curveRadius: curveRadius
        )
        let shape = SelectionRegion.boundingBox(of: contours).map {
            TracedShape(contours: contours, extent: $0)
        }
        entriesByNodeID[nodeID] = Entry(ink: fingerprint, shape: shape)
        return shape
    }

    /// Every problem's ink, keyed by the node it is filed under. Ink pointing at
    /// a node the tree no longer has is grouped like any other and dropped later,
    /// when the tag is resolved — one lookup per problem instead of one per mark.
    private static func inkGroupedByProblem(in strokes: [Stroke]) -> [UUID: [Stroke]] {
        var inkByNodeID: [UUID: [Stroke]] = [:]
        for stroke in StrokeRasterizer.inkStrokes(strokes) {
            guard let nodeID = stroke.problemNodeID else { continue }
            inkByNodeID[nodeID, default: []].append(stroke)
        }
        return inkByNodeID
    }
}

/// What a problem's cached shape was traced from, cheap enough to rebuild on
/// every read.
///
/// Stroke identity alone would not do: a lasso drag slides a stroke's samples
/// across the page without changing its id, and an estimated sample is rewritten
/// in place when UIKit finalises it. The sample count and the stroke's own cached
/// bounds move with all of that, and neither costs a walk over the points.
struct ProblemInkFingerprint: Equatable {
    private struct StrokeMark: Equatable {
        let strokeID: UUID
        let sampleCount: Int
        let canvasBounds: CGRect
    }

    private let marks: [StrokeMark]

    init(strokes: [Stroke]) {
        marks = strokes.map {
            StrokeMark(
                strokeID: $0.id,
                sampleCount: $0.points.count,
                canvasBounds: $0.canvasBounds
            )
        }
    }
}
