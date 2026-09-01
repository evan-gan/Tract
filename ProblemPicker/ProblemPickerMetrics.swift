import CoreGraphics
import Foundation

/// Every measurement the problem picker is built from, in one place — the
/// scrolling wheel and the outline it feeds.
enum ProblemPickerMetrics {
    // MARK: - Wheel

    /// One row of a column. Also the snap distance, so it decides how far a
    /// finger or pencil has to travel for one value.
    static let wheelRowHeight: CGFloat = 30
    /// Three rows: the selected value with one neighbour above and below. Enough
    /// to read as a drum without the chrome eating the top of the page.
    static let wheelVisibleRows: CGFloat = 3
    static var wheelHeight: CGFloat { wheelRowHeight * wheelVisibleRows }
    /// Wide enough for "VIII" and for a two-digit problem number, so no column
    /// changes width as the tree grows.
    static let wheelColumnWidth: CGFloat = 46
    static let wheelColumnSpacing: CGFloat = 2
    /// Keeps the collapsed pill from shrinking to the width of "1" and growing
    /// again at "1.b.III", which would shuffle the chrome beside it.
    static let collapsedMinimumWidth: CGFloat = 64
    /// How much of a row a drag must cover before the wheel counts it as
    /// reaching the next one. Short of half because a scroll view holds the
    /// content still for the first few points of a pan, so the drum lags the
    /// finger by that much all the way through the gesture.
    static let wheelSnapFraction: CGFloat = 0.35
    /// Space between the drums and the edge of the tongue they hang in.
    static let wheelPanelPadding: CGFloat = 8
    /// How long a row must be held before it offers to delete itself. Long
    /// enough that a hand resting on the chrome cannot reach it.
    static let deleteHoldSeconds: Double = 0.7
    /// Movement that cancels a pending delete: past this the touch is a scroll,
    /// not a hold.
    static let deleteHoldMovement: CGFloat = 8

    // MARK: - Outline

    static let outlineWidth: CGFloat = 236
    static let outlineMaxHeight: CGFloat = 320
    /// Uniform on purpose: the tree connectors are drawn from row geometry
    /// alone, so they line up without anything having to be measured.
    static let rowHeight: CGFloat = 34
    /// Horizontal space one level of depth costs, and the column the connectors
    /// for that level are drawn in.
    static let levelGutter: CGFloat = 22
    /// Movement past this cancels a pending press in the outline's drag.
    static let dragThreshold: CGFloat = 7
    /// How long a row at a different level must be hovered before the drag
    /// adopts that level. Long enough that sliding past a row never reparents
    /// anything by accident.
    static let levelChangeHoldSeconds: Double = 2
    static var levelChangeHold: Duration { .seconds(levelChangeHoldSeconds) }
    /// What is left of the dragged subtree in place while it is being carried.
    static let draggedRowOpacity: CGFloat = 0.26
}
