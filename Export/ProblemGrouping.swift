import CoreGraphics
import Foundation

/// One problem's worth of ink: every stroke sharing a problem tag.
struct ProblemGroup: Identifiable, Sendable {
    /// The address this group was collected under. Nil for the untagged group.
    let tag: ProblemTag?
    /// The heading printed above the group's ink.
    let label: String
    /// In the order they were drawn, so the group paints exactly as it did on canvas.
    let strokes: [Stroke]
    /// Canvas-space box containing the group's ink.
    let inkBounds: CGRect

    var id: String { label }
}

/// Sorts strokes into the problems they were tagged for.
///
/// The workflow this serves: the user writes each problem's work in its own
/// patch of the infinite canvas and tags those strokes, then exports a sheet
/// where every problem sits in its own labelled cell — regardless of how far
/// apart the patches were on the canvas.
enum ProblemGrouping {
    /// - Parameters:
    ///   - strokes: Any strokes; non-drawing tools and single-sample taps are dropped.
    ///   - outline: The document's problem tree, which is what turns a stroke's
    ///     stored node id into the address it prints under today. A stroke whose
    ///     node is gone from the outline counts as untagged.
    ///   - depth: How many levels of the tag to group on. Nil keeps the full
    ///     address, so 1a and 1b are separate groups; 1 collapses every part of
    ///     problem 1 into a single group.
    ///   - untaggedLabel: Heading for strokes carrying no tag. Pass nil to leave
    ///     untagged work out of the result entirely.
    ///   - formatter: Renders each group's tag into its heading.
    ///
    /// Within a group, strokes keep their input order — `SplineDocument.strokes`
    /// is already in drawing order, which is the order they must be painted in.
    /// - Returns: Tagged groups ordered outermost level first (1, 1a, 1a(i), 1b,
    ///   2, 10), with the untagged group, if any, last.
    static func groups(
        from strokes: [Stroke],
        outline: ProblemOutline,
        depth: Int? = nil,
        untaggedLabel: String? = nil,
        formatter: ProblemTagFormatter = .standard
    ) -> [ProblemGroup] {
        var strokesByTag: [ProblemTag: [Stroke]] = [:]
        var untaggedStrokes: [Stroke] = []

        for stroke in StrokeRasterizer.inkStrokes(strokes) {
            if let tag = groupingTag(of: stroke, in: outline, depth: depth) {
                strokesByTag[tag, default: []].append(stroke)
            } else {
                untaggedStrokes.append(stroke)
            }
        }

        let tagged = strokesByTag.keys.sorted().map { tag in
            makeGroup(tag: tag, label: formatter.text(for: tag), strokes: strokesByTag[tag] ?? [])
        }

        guard let untaggedLabel, !untaggedStrokes.isEmpty else { return tagged }
        return tagged + [makeGroup(tag: nil, label: untaggedLabel, strokes: untaggedStrokes)]
    }

    /// The address a stroke is filed under, cut to `depth` levels. An empty tag
    /// carries no more information than no tag at all, so it counts as untagged
    /// rather than becoming a blank-headed cell.
    private static func groupingTag(
        of stroke: Stroke,
        in outline: ProblemOutline,
        depth: Int?
    ) -> ProblemTag? {
        guard let nodeID = stroke.problemNodeID, let tag = outline.tag(forNode: nodeID) else {
            return nil
        }
        let cut = depth.map { tag.prefix($0) } ?? tag
        return cut.isEmpty ? nil : cut
    }

    private static func makeGroup(
        tag: ProblemTag?,
        label: String,
        strokes: [Stroke]
    ) -> ProblemGroup {
        ProblemGroup(
            tag: tag,
            label: label,
            strokes: strokes,
            inkBounds: StrokeRasterizer.unionBounds(of: strokes)
        )
    }
}
