import SwiftUI

/// Every token the problem bounding regions are built and drawn from.
///
/// The two distances are **canvas-space**, which is what makes the padding scale
/// with distance: a region magnifies along with the ink it frames, exactly as
/// stroke width and the lasso's frame do. A screen-space padding would instead
/// crowd the writing at 400% and swamp it at 10%, and would have to re-trace the
/// whole shape on every frame of a pinch.
enum ProblemBoundsStyle {
    /// How far the shape stands off the ink where it touches it — a third of an
    /// inch of clear paper at 100%, so the frame never reads as part of the work.
    static let padding: CGFloat = SelectionStyle.pointsPerInch / 3

    /// The radius of the curves that carry the boundary over a gap, and with it
    /// how hard the shape refuses to follow the handwriting.
    ///
    /// Comfortably wider than the gaps inside a line of writing and than the
    /// leading between two lines, so a paragraph of work comes back as one
    /// rounded block instead of an outline of its letters. Turn it down towards
    /// the padding to hug the ink; turn it up towards the width of the work to
    /// approach a plain rounded rectangle.
    static let curveRadius: CGFloat = SelectionStyle.pointsPerInch

    /// Line weights in *screen* points: the boundary is chrome, so it stays the
    /// same weight under the hand however far the canvas is zoomed — like the
    /// lasso's dashes, and unlike the shape it traces.
    static let lineWidth: CGFloat = 1.25
    static let selectedLineWidth: CGFloat = 2

    /// Quiet by default. Every problem on the page is framed at once, so an
    /// unselected region has to be legible without competing with the ink.
    static let strokeOpacity: CGFloat = 0.32
    static let selectedStrokeOpacity: CGFloat = 0.95
    static let fillOpacity: CGFloat = 0.04
    static let selectedFillOpacity: CGFloat = 0.10
}
