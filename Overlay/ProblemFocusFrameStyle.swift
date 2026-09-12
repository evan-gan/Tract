import SwiftUI

/// How the frame around the problem being edited is drawn.
///
/// Every weight here is a **screen**-space constant, like the selection's
/// dashes and unlike the bubble's padding: the frame is chrome saying "you are
/// working in here", so it has to stay the same weight under the hand at every
/// zoom. Only the corner radius is converted into canvas units, and only
/// because the shape it rounds is canvas geometry.
enum ProblemFocusFrameStyle {
    static let lineWidth: CGFloat = 2

    /// Longer than the selection's marching ants, which are deliberately
    /// between a dash and a dot. This is a boundary being held open around a
    /// whole screen of work, not a marquee hugging a handful of marks, and at
    /// that size a fine dash reads as a solid line.
    static let dash: [CGFloat] = [10, 7]

    /// Rounded enough to read as a panel rather than as a crop box, and it is
    /// also what the bubble's own curvature has to arrive at without the
    /// corners snapping square at the end of the morph.
    static let cornerRadius: CGFloat = 28

    static let strokeOpacity: CGFloat = 0.85

    /// A wash over the working area, just enough to separate the problem being
    /// edited from the page around it without tinting the handwriting.
    static let fillOpacity: CGFloat = 0.05
}
