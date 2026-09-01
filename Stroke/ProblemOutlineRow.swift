import Foundation

/// One line of the flattened outline: what to print, where it sits, and the
/// tree connectors it has to draw.
///
/// The connector information is resolved during the flatten rather than by the
/// view, because a row cannot see its siblings — and "does an ancestor two
/// columns to the left still have work below it" is the only question the
/// spine's shape depends on.
struct ProblemOutlineRow: Identifiable, Hashable, Sendable {
    let id: UUID
    let path: ProblemPath
    /// Identity of the parent, or nil for a problem at the top level.
    let parentID: UUID?
    let label: String
    let childCount: Int
    /// Whether the vertical in each *ancestor's* column continues past this row.
    /// One entry per ancestor, outermost first, so column `level` of the row's
    /// gutter reads `ancestorSpines[level]`.
    let ancestorSpines: [Bool]
    /// Last of its siblings, so its own elbow stops at the row's centre instead
    /// of running through to the bottom.
    let isLastSibling: Bool

    /// 0 for a problem, 1 for a lettered part, 2 for a numeral.
    var level: Int { max(path.count - 1, 0) }

    var hasChildren: Bool { childCount > 0 }
}

extension ProblemOutline {
    /// The whole tree as a depth-first list, in the order it is drawn.
    var rows: [ProblemOutlineRow] {
        var flattened: [ProblemOutlineRow] = []
        appendRows(of: roots, parentID: nil, prefix: [], ancestorSpines: [], into: &flattened)
        return flattened
    }

    private func appendRows(
        of siblings: [ProblemNode],
        parentID: UUID?,
        prefix: ProblemPath,
        ancestorSpines: [Bool],
        into flattened: inout [ProblemOutlineRow]
    ) {
        for (index, node) in siblings.enumerated() {
            let path = prefix + [index]
            let isLast = index == siblings.count - 1
            flattened.append(
                ProblemOutlineRow(
                    id: node.id,
                    path: path,
                    parentID: parentID,
                    label: ProblemLevelNotation.label(level: path.count - 1, siblingIndex: index),
                    childCount: node.children.count,
                    ancestorSpines: ancestorSpines,
                    isLastSibling: isLast
                )
            )
            // A child's ancestor columns are this row's, plus whether this row
            // itself still has siblings coming after it.
            appendRows(
                of: node.children,
                parentID: node.id,
                prefix: path,
                ancestorSpines: ancestorSpines + [!isLast],
                into: &flattened
            )
        }
    }
}
