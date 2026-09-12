import CoreGraphics
import Foundation

/// Every distance and duration the automatic problem layout is built from.
///
/// The spacings are **canvas-space**, like `ProblemBoundsStyle`'s: the grid is a
/// rearrangement of the page itself, so it has to magnify with the ink rather
/// than staying a fixed size under the hand. Only the focus frame's dash pattern
/// is a screen-space constant, and that lives in `ProblemFocusFrameStyle`.
enum ProblemLayoutMetrics {
    /// Clear paper between two problems side by side in a row, and between two
    /// rows. Comfortably wider than a problem's own bubble padding, so the gap
    /// between two problems always reads as wider than the gap inside one.
    static let columnGutter: CGFloat = SelectionStyle.pointsPerInch
    static let rowGutter: CGFloat = SelectionStyle.pointsPerInch

    /// Clear paper between a sub-sub-problem and the part above it. Tighter than
    /// `rowGutter`, because a stack is one problem's parts rather than two
    /// separate problems.
    static let stackGutter: CGFloat = SelectionStyle.pointsPerInch / 2

    /// How much of the focused problem's own size is kept clear on each side of
    /// it while it is being edited. A half either way, so the room around a
    /// problem stays in proportion to the problem as it is written.
    static let focusMarginFraction: CGFloat = 0.5

    /// The least room a focused problem gets, whatever its size — so a problem
    /// that is still one short mark is not boxed in at arm's length.
    ///
    /// Canvas units, like everything else here. It was briefly the *viewport*,
    /// which was wrong in a way worth recording: the visible canvas rect is the
    /// screen divided by the zoom, so zooming out inflated the box without
    /// limit, and because the box is captured as canvas geometry it never
    /// recovered. The room a problem needs is a property of the problem, not of
    /// how far away the user happens to be standing.
    static let minimumFocusMargin: CGFloat = SelectionStyle.pointsPerInch * 1.5

    /// How long the bubble takes to become the box, and the box the bubble.
    static let focusTransitionDuration: TimeInterval = 0.75

    /// How long the grid takes to form or to unwind when the toggle is flipped.
    /// The same duration as the focus transition, so the two never read as two
    /// different animations when a toggle happens to interrupt a focus.
    static let arrangeDuration: TimeInterval = 0.75
}
