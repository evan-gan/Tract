import SwiftUI

/// The file-tree lines down the left of an outline row.
///
/// A `Shape` rather than a stack of rectangles because every segment is decided
/// by the row's own depth and sibling position: given a uniform row height, the
/// connectors of neighbouring rows meet without either row knowing about the
/// other.
struct ProblemTreeConnectors: Shape {
    /// 0 for a problem, 1 for a part, 2 for a numeral.
    let level: Int
    /// Last of its siblings, so its spine stops at the row's centre.
    let isLastSibling: Bool
    /// Whether a spine has to carry on down into this row's own children.
    let hasChildren: Bool
    /// For each ancestor column to the left of this row's elbow, whether that
    /// ancestor still has work below it and its vertical runs the full height.
    let ancestorColumns: [Bool]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY

        for (column, isContinuing) in ancestorColumns.enumerated() where isContinuing {
            let x = centerX(ofColumn: column)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        if level > 0 {
            let elbowX = centerX(ofColumn: level - 1)
            // Down from the parent's spine to this row's centre, carrying on
            // through the row only when siblings still follow.
            path.move(to: CGPoint(x: elbowX, y: rect.minY))
            path.addLine(to: CGPoint(x: elbowX, y: isLastSibling ? midY : rect.maxY))
            // The short run into the label.
            path.move(to: CGPoint(x: elbowX, y: midY))
            path.addLine(to: CGPoint(x: CGFloat(level) * ProblemPickerMetrics.levelGutter, y: midY))
        }

        // The start of the spine down to this row's own children, which live in
        // the rows below and draw the rest of it.
        if hasChildren {
            let childColumnX = centerX(ofColumn: level)
            path.move(to: CGPoint(x: childColumnX, y: midY))
            path.addLine(to: CGPoint(x: childColumnX, y: rect.maxY))
        }
        return path
    }

    private func centerX(ofColumn column: Int) -> CGFloat {
        (CGFloat(column) + 0.5) * ProblemPickerMetrics.levelGutter
    }
}
