import SwiftUI

/// How the canvas paints ink while a tagging mode is on: a colour per stroke,
/// and which strokes are pushed back out of the way.
///
/// A value rather than a rule the renderer runs, so the maps are built once per
/// change instead of once per stroke per frame.
struct ProblemInkStyling: Equatable {
    /// Overrides a stroke's own colour. Absent means "paint it as drawn".
    var tintByStrokeID: [UUID: Color] = [:]
    /// Strokes belonging to another problem, faded so the current group stands out.
    var dimmedStrokeIDs: Set<UUID> = []

    /// Faint enough that the current group reads as the only live ink, strong
    /// enough that the dimmed work is still there to aim at.
    static let dimmedOpacity: CGFloat = 0.22

    static let inactive = ProblemInkStyling()

    var isActive: Bool { !tintByStrokeID.isEmpty || !dimmedStrokeIDs.isEmpty }

    func color(for stroke: Stroke) -> Color {
        tintByStrokeID[stroke.id] ?? stroke.style.swiftUIColor
    }

    func opacity(for stroke: Stroke) -> CGFloat {
        dimmedStrokeIDs.contains(stroke.id) ? Self.dimmedOpacity : 1
    }

    /// - Parameters:
    ///   - tintByProblem: Colours each stroke by its problem *number* — the top
    ///     level of its tag — so parts of the same problem share a colour.
    ///   - focusedNodeID: The tag being worked on. Anything else is dimmed when
    ///     `dimsUnfocused` is set.
    static func make(
        strokes: [Stroke],
        outline: ProblemOutline,
        tintByProblem: Bool,
        focusedNodeID: UUID?,
        dimsUnfocused: Bool
    ) -> ProblemInkStyling {
        guard tintByProblem || dimsUnfocused else { return .inactive }

        var styling = ProblemInkStyling()
        // One lookup per node id rather than per stroke: resolving a path is a
        // walk of the tree, and a page holds far more strokes than problems.
        var problemNumberByNodeID: [UUID: Int] = [:]

        for stroke in strokes {
            let nodeID = stroke.problemNodeID
            if dimsUnfocused, nodeID != focusedNodeID {
                styling.dimmedStrokeIDs.insert(stroke.id)
            }
            guard tintByProblem, let nodeID else { continue }
            let problemNumber = problemNumberByNodeID[nodeID] ?? {
                let resolved = outline.path(ofNode: nodeID)?.first
                problemNumberByNodeID[nodeID] = resolved ?? -1
                return resolved ?? -1
            }()
            guard problemNumber >= 0 else { continue }
            styling.tintByStrokeID[stroke.id] = ProblemTintPalette.color(forProblemIndex: problemNumber)
        }
        return styling
    }
}
