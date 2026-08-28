import SwiftUI

/// Which screen edge the floating tool dock is parked against.
enum DockEdge: String, CaseIterable, Sendable {
    case top, bottom, leading, trailing

    /// The dock lays its contents out along this axis while parked here.
    var axis: Axis {
        switch self {
        case .top, .bottom: .horizontal
        case .leading, .trailing: .vertical
        }
    }

    /// Unit vector pointing from the dock into the canvas. The selected tool
    /// pops out along it, so tools always rise away from the edge they sit on.
    var liftDirection: CGSize {
        switch self {
        case .top: CGSize(width: 0, height: 1)
        case .bottom: CGSize(width: 0, height: -1)
        case .leading: CGSize(width: 1, height: 0)
        case .trailing: CGSize(width: -1, height: 0)
        }
    }

    /// Edge whose quadrant contains `point`, where quadrants are the four
    /// triangles cut by the container's two corner-to-corner diagonals.
    ///
    /// Diagonals (rather than nearest-edge distance) are what make dragging feel
    /// intuitive: the dock commits to the edge you are visibly heading toward,
    /// and the boundary never shifts with the container's aspect ratio.
    ///
    /// - Parameters:
    ///   - point: Location in container coordinates; may fall outside the bounds.
    ///   - size: Size of the container the dock lives in.
    /// - Returns: The edge to snap to. Defaults to `.bottom` for an empty container.
    static func nearest(to point: CGPoint, in size: CGSize) -> DockEdge {
        guard size.width > 0, size.height > 0 else { return .bottom }

        let horizontalFraction = point.x / size.width
        let verticalFraction = point.y / size.height
        // Diagonal from the top-left corner: y = x. Above it means "more top than left".
        let isAboveTopLeftDiagonal = verticalFraction < horizontalFraction
        // Diagonal from the top-right corner: y = 1 - x.
        let isAboveTopRightDiagonal = verticalFraction < 1 - horizontalFraction

        switch (isAboveTopLeftDiagonal, isAboveTopRightDiagonal) {
        case (true, true): return .top
        case (false, false): return .bottom
        case (false, true): return .leading
        case (true, false): return .trailing
        }
    }

    /// Alignment that parks the dock against this edge inside a filling stack.
    var alignment: Alignment {
        switch self {
        case .top: .top
        case .bottom: .bottom
        case .leading: .leading
        case .trailing: .trailing
        }
    }
}
