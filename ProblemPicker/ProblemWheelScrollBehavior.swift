import SwiftUI

/// Stops a wheel column where the hand left it, snapped to a whole row, and
/// reports the row it decided on.
///
/// Deceleration is what this removes — and only that. A thrown column that keeps
/// running passes values nobody looked at, and the last row of a column is the
/// one that *creates* a problem, so a flick could file ink under something that
/// did not exist a moment ago. Dragging stays free: pull the drum through five
/// values in one go and it stops on the fifth, because that is where the hand
/// put it.
///
/// It reports the landing itself rather than leaving that to the scroll
/// position, because the position a scroll view publishes back can still be one
/// it merely passed through — which showed up as a column that needed two
/// swipes to move one value.
struct ProblemWheelScrollBehavior: ScrollTargetBehavior {
    /// A scroll a hand is driving, described by where it started and where it
    /// let go. Nil for the column animating itself to a row the model chose, or
    /// for the target being re-resolved during ordinary layout.
    struct Drag {
        let startOffset: CGFloat
        /// Where the content was on the last frame of the drag — the target
        /// handed to the behaviour already has deceleration added to it, and
        /// this is the only way back to the offset the hand actually chose.
        let offsetAtLift: CGFloat
    }

    let rowHeight: CGFloat
    let rowCount: Int
    let drag: Drag?
    /// The row this scroll will come to rest on. Called during ordinary layout
    /// too, with the row already selected, so it must be safe with no change.
    let onLanding: @MainActor (Int) -> Void

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        guard rowHeight > 0, rowCount > 0 else { return }
        let rowIndex = drag.map { landingRow(for: $0, target: target, context: context) }
            ?? Int((target.rect.minY / rowHeight).rounded())
        let landedIndex = min(max(rowIndex, 0), rowCount - 1)

        target.rect.origin.y = CGFloat(landedIndex) * rowHeight
        // Scroll targets are resolved on the main thread, where the model lives.
        MainActor.assumeIsolated { onLanding(landedIndex) }
    }

    /// The row a drag has reached, counted from the row it began on.
    ///
    /// The threshold is short of half a row on purpose. A scroll view holds the
    /// content still for the first few points of a pan, so the drum always lags
    /// the finger by that much — and rounding at a half row meant a deliberate
    /// one-row pull left the wheel exactly where it was.
    private func landingRow(for drag: Drag, target: ScrollTarget, context: TargetContext) -> Int {
        let restingOffset = context.velocity.dy == 0 ? target.rect.minY : drag.offsetAtLift
        let startRow = (drag.startOffset / rowHeight).rounded()
        let rowsTravelled = (restingOffset - drag.startOffset) / rowHeight

        let wholeRows = rowsTravelled.rounded(.towardZero)
        let remainder = abs(rowsTravelled - wholeRows)
        let extraRow: CGFloat = remainder >= ProblemPickerMetrics.wheelSnapFraction
            ? (rowsTravelled < 0 ? -1 : 1)
            : 0
        return Int(startRow + wholeRows + extraRow)
    }
}
