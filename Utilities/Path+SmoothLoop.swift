import SwiftUI

extension Path {
    /// Appends a closed loop through `points`, curved with midpoint quadratic
    /// Béziers.
    ///
    /// Both region outlines come out of marching squares, which lands its
    /// vertices on grid edges — so a raw loop carries a faint staircase. Curving
    /// through the midpoints takes that out without pulling the line off the
    /// shape it is describing, because a quadratic through two midpoints with the
    /// vertex between them as its control point never leaves that corner.
    ///
    /// - Parameter points: The loop's vertices, in the space the path is drawn
    ///   in, not repeating the first point at the end. Fewer than three describe
    ///   no area and are ignored.
    mutating func addSmoothedLoop(through points: [CGPoint]) {
        guard points.count >= 3 else { return }
        let lastIndex = points.count - 1

        move(to: points[lastIndex].midpoint(to: points[0]))
        for index in points.indices {
            let vertex = points[index]
            let next = points[index == lastIndex ? 0 : index + 1]
            addQuadCurve(to: vertex.midpoint(to: next), control: vertex)
        }
        closeSubpath()
    }
}
