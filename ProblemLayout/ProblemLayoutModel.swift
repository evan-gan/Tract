import CoreGraphics
import Foundation
import Observation

/// Whether the page is arranged into a grid of problems, which problem is being
/// edited, and where everything therefore sits.
///
/// Held by `CanvasViewModel` alongside the problem tree, because it is canvas
/// state: the placement decides where a stroke is drawn and where a touch lands,
/// so it cannot live in view state that disappears when a view goes away.
///
/// It never touches the ink. Everything here resolves to a
/// `ProblemLayoutPlacement` — a shift per problem, applied at draw time and
/// subtracted at touch time — so switching the layout off restores the document
/// exactly, and nothing the layout does is ever saved.
@Observable
@MainActor
final class ProblemLayoutModel {

    /// Supplies the problems and their ink bounds. A closure rather than stored
    /// state so the model never holds a stale copy of the page: it asks for the
    /// measurements at the moment it needs them.
    @ObservationIgnored var cellsProvider: () -> [ProblemLayoutCell] = { [] }

    /// Supplies a problem's traced bubble, in stored canvas space. Asked for
    /// once, when focus begins — the bubble is frozen for as long as the
    /// problem is focused, so there is nothing to ask again about.
    @ObservationIgnored var contoursProvider: (UUID) -> [[CGPoint]] = { _ in [] }

    private(set) var isEnabled = false

    /// The problem being edited, or nil when the page is simply arranged.
    private(set) var focusedNodeID: UUID?

    var isFocused: Bool { focusedNodeID != nil }

    /// Where every problem sits right now, mid-animation included.
    var placement: ProblemLayoutPlacement { animator.placement }

    /// Where the layout is heading — the same as `placement` at rest. What
    /// incoming pencil samples are stored against, so a stroke drawn during a
    /// transition is not left behind by it.
    var settledPlacement: ProblemLayoutPlacement { animator.targetPlacement }

    /// 0 while the focused problem still wears its own bubble, 1 once the
    /// dashed box has fully opened out.
    var focusFrameProgress: CGFloat { animator.focusProgress }

    /// The dashed box, in canvas space. Null when nothing is focused.
    private(set) var focusBox: CGRect = .null

    /// Whose frame is on screen. Distinct from `focusedNodeID` because leaving a
    /// focus has to keep drawing the box for as long as it takes to close back
    /// onto the problem's own bubble — by the time the animation starts,
    /// nothing is focused any more.
    private(set) var frameNodeID: UUID?

    /// The bubble the frame grows out of and shrinks back into, resampled into
    /// the form the morph needs, in **stored** canvas space — the layout's own
    /// offset is added by the view, so the frame keeps up with the arrangement
    /// moving underneath it without being rebuilt.
    private(set) var focusBubbleLoop: [CGPoint] = []

    /// The frame of the problem focus has just jumped away from, still closing
    /// back onto its bubble while the new one opens. Nil unless a switch is
    /// mid-animation.
    private(set) var closingFrame: ClosingFocusFrame?

    /// 1 when the closing frame is still the full box, 0 once it is back to
    /// its bubble.
    var closingFrameProgress: CGFloat { animator.closingFrameProgress }

    /// Everything needed to keep drawing a frame after focus has left it.
    struct ClosingFocusFrame: Equatable {
        let nodeID: UUID
        let bubbleLoop: [CGPoint]
        let box: CGRect
    }

    // MARK: - The toggle

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        // Same re-read as leaving a focus by tapping out: the frame still has to
        // close onto the shape the work has grown into.
        if !enabled { releaseFocus() }
        rebuild(animated: true)
    }

    func toggle() {
        setEnabled(!isEnabled)
    }

    /// Back to off, nothing focused, nothing animating. What opening a
    /// different document means: the arrangement is a way of looking at one
    /// page and carries nothing over to the next.
    func reset() {
        animator.stop()
        isEnabled = false
        arrangement = .empty
        clearFocusState()
        retireFrame()
        animator.settle(to: .identity, focusProgress: 0)
    }

    // MARK: - Focus

    /// Opens one problem out for editing. Does nothing unless the layout is on:
    /// pushing the neighbours aside only means something once there is a grid
    /// for them to be pushed within.
    ///
    /// - Parameter nodeID: The problem tapped.
    /// - Returns: Whether focus actually moved, so a caller can tell a tap that
    ///   did something from one that did not.
    @discardableResult
    func focus(nodeID: UUID) -> Bool {
        guard isEnabled, focusedNodeID != nodeID else { return false }
        // Seeded with what the problem has already been written, so the first
        // stroke of the session widens the box rather than collapsing it onto
        // that one mark.
        moveFocus(to: nodeID, seedInkBounds: cellsProvider().first { $0.nodeID == nodeID }?.bounds ?? .null)
        focusBubbleLoop = ProblemFocusFrame.canonicalLoop(in: contoursProvider(nodeID))
        rebuild(animated: true)
        return true
    }

    /// Opens a box around a problem the pen has just started in — one with no
    /// earlier ink, so no cell in the grid and no bubble to grow out of.
    ///
    /// Runs inside a pencil gesture, so it does **not** re-measure the grid
    /// (see `rebuild`): the new problem stays unarranged, at offset zero, which
    /// is exactly what its first samples were stored against. It takes a grid
    /// slot when the focus is released, like any other re-flow.
    ///
    /// - Parameters:
    ///   - nodeID: The problem the stroke is filed under.
    ///   - path: Its place in the outline — the row and column the neighbours
    ///     are pushed relative to.
    ///   - inkBounds: The first mark, padded, in stored canvas space.
    /// - Returns: Whether a box was opened. False when the layout is off, the
    ///   problem is already focused, or it already has a place in the grid.
    @discardableResult
    func focusUnarrangedProblem(nodeID: UUID, path: ProblemPath, inkBounds: CGRect) -> Bool {
        guard isEnabled, focusedNodeID != nodeID, !path.isEmpty, !inkBounds.isNull,
              arrangement.framesByNodeID[nodeID] == nil
        else { return false }
        moveFocus(to: nodeID, seedInkBounds: inkBounds)
        unarrangedFocusPath = path
        // No traced bubble exists yet, so the frame grows out of a pill around
        // the first mark — otherwise the box would pop in at full size.
        focusBubbleLoop = ProblemFocusFrame.canonical(ProblemFocusFrame.roundedRectLoop(
            inkBounds,
            cornerRadius: min(inkBounds.width, inkBounds.height) / 2
        ))
        rebuild(animated: true, remeasure: false)
        return true
    }

    /// Whether the grid, as last measured, has a place for this problem.
    func hasGridSlot(for nodeID: UUID) -> Bool {
        arrangement.framesByNodeID[nodeID] != nil
    }

    /// Points the focus at a new problem, handing any frame already on screen
    /// over so it closes while the new one opens.
    private func moveFocus(to nodeID: UUID, seedInkBounds: CGRect) {
        let previousFrameNodeID = frameNodeID
        let previousBox = focusBox
        focusedNodeID = nodeID
        unarrangedFocusPath = nil
        // A frame already on screen for another problem — open, or on its way
        // closed — closes while this one opens instead of vanishing. Read after
        // the focus moves, for the same reason `releaseFocus` reads late: the
        // old problem's bubble is only unfrozen once it is no longer focused.
        if let previousFrameNodeID, previousFrameNodeID != nodeID {
            closingFrame = ClosingFocusFrame(
                nodeID: previousFrameNodeID,
                bubbleLoop: ProblemFocusFrame.canonicalLoop(in: contoursProvider(previousFrameNodeID)),
                box: previousBox
            )
            animator.handOffFocusFrame()
        }
        frameNodeID = nodeID
        // Frozen at the moment of focus: the box is canvas geometry from here
        // on, so it travels and scales with the page the way the ink does.
        liveInkBounds = seedInkBounds
    }

    @discardableResult
    func clearFocus() -> Bool {
        guard focusedNodeID != nil else { return false }
        releaseFocus()
        rebuild(animated: true)
        return true
    }

    /// Drops the focus and re-reads the bubble the frame has to close onto.
    ///
    /// Order matters. The problem's traced shape is frozen for as long as it is
    /// focused, so the bubble must be read *after* the focus is dropped —
    /// reading it first hands back the shape the box opened out of, and the box
    /// then shrinks onto the outline the work had before it was written in
    /// while `ProblemBoundsView` fades the new, larger one in underneath. Two
    /// shapes, one moment, and it reads as a jump.
    private func releaseFocus() {
        guard let releasedNodeID = focusedNodeID else { return }
        clearFocusState()
        focusBubbleLoop = ProblemFocusFrame.canonicalLoop(in: contoursProvider(releasedNodeID))
    }

    // MARK: - Keeping up with the pen

    /// Reports how far the focused problem's ink now reaches, so the box can
    /// grow with it and keep its margins in proportion.
    ///
    /// Cheap on purpose — this is called from inside a pencil gesture. The
    /// bounds are a union of boxes each stroke already maintains, and a report
    /// that does not actually push past the box it already has costs a rect
    /// comparison and nothing else.
    ///
    /// - Parameter canvasBounds: The focused problem's ink bounds in *stored*
    ///   canvas space; the grid's own offset is applied here.
    func noteFocusedInkBounds(_ canvasBounds: CGRect) {
        guard isFocused, !canvasBounds.isNull else { return }
        guard liveInkBounds.isNull || !liveInkBounds.contains(canvasBounds) else { return }
        liveInkBounds = liveInkBounds.isNull ? canvasBounds : liveInkBounds.union(canvasBounds)
        // **Only the box.** The placement is deliberately left untouched here.
        //
        // `placement` is an input to the committed ink layer, and that layer's
        // inputs must not change while a stroke is in flight — the whole reason
        // ink is drawn on two layers is so a sample at 240 Hz repaints one fresh
        // mark instead of every mark on the page. Rebuilding the placement here
        // put the neighbours' shove on that hot path and repainted the entire
        // drawing on every frame of every gesture.
        //
        // The box is its own observable, read only by the focus frame, so it can
        // follow the pen live for the price of redrawing one dashed outline.
        // The shove catches up in `settleNeighbours()` when the stroke ends.
        focusBox = ProblemFocusLayout.box(around: laidOutFocusedInkBounds())
    }

    /// Moves the surrounding problems out of the way of the box the last stroke
    /// grew. Called on pen-up, not per sample — see `noteFocusedInkBounds`.
    func settleNeighbours() {
        guard isEnabled, isFocused else { return }
        rebuild(animated: false, remeasure: false)
    }

    /// Re-measures the focused problem from scratch, so the box can get
    /// *smaller* as well as larger.
    ///
    /// `noteFocusedInkBounds` only ever unions, because it runs inside a pencil
    /// gesture where the ink can only grow and a union is the cheap answer.
    /// Undo, redo, an erase and a delete are the moments a problem can shrink,
    /// and they are rare enough to afford measuring it properly.
    ///
    /// Deliberately `remeasure: false`: the *grid* stays pinned. Re-flowing the
    /// page under an undo would jump every problem sideways, which is not what
    /// undoing a stroke should mean.
    func remeasureFocusedInk(_ canvasBounds: CGRect) {
        guard isFocused else { return }
        liveInkBounds = canvasBounds
        rebuild(animated: false, remeasure: false)
    }

    /// Re-flows the whole grid after ink has been re-filed from one problem to
    /// another, keeping whatever is focused focused.
    ///
    /// A retag is the one edit that changes *which cell* ink belongs to, so the
    /// pinned grid is simply wrong afterwards: the re-filed marks are drawn at
    /// their new problem's old offset, a problem that gained work overlaps its
    /// neighbours, and one that did not exist before has no cell at all.
    ///
    /// Re-measuring here does not reopen the feedback loop `rebuild` warns
    /// about. That loop needs a pencil stroke being stored against the offset
    /// while it moves; this runs once the retag has finished, when nothing is
    /// being written.
    ///
    /// - Parameter focusedInkBounds: The focused problem's ink, measured from
    ///   scratch in stored canvas space — it may have gained or lost marks.
    ///   Ignored when nothing is focused.
    func reflowAfterRetag(focusedInkBounds: CGRect) {
        guard isEnabled else { return }
        if isFocused { liveInkBounds = focusedInkBounds }
        rebuild(animated: true)
    }

    // MARK: - Building

    @ObservationIgnored private let animator = ProblemLayoutAnimator()
    /// The grid as last measured. Held so growing the focus box inside a pencil
    /// gesture does not have to walk the page again.
    @ObservationIgnored private var arrangement: ProblemLayoutGrid.Arrangement = .empty
    /// How far the focused problem's ink has reached since focus began, in
    /// stored canvas space. Accumulated rather than re-measured so the box never
    /// shrinks back under the pen mid-sentence.
    @ObservationIgnored private var liveInkBounds: CGRect = .null
    /// Where the focused problem sits in the outline when it has no cell in the
    /// grid yet — set by `focusUnarrangedProblem`, nil otherwise.
    @ObservationIgnored private var unarrangedFocusPath: ProblemPath?

    /// Drops the focus itself but leaves the frame's geometry standing, so the
    /// box has something to animate *back* to. `retireFrame` clears the rest
    /// once that animation lands.
    private func clearFocusState() {
        focusedNodeID = nil
        unarrangedFocusPath = nil
        liveInkBounds = .null
    }

    /// Run when a transition lands. The closing frame has always finished by
    /// then, whatever the focus is doing.
    private func retireFrame() {
        closingFrame = nil
        guard !isFocused else { return }
        frameNodeID = nil
        focusBox = .null
        focusBubbleLoop = []
    }

    /// - Parameter remeasure: Whether to measure the page again.
    ///
    /// **The grid is measured only on the events that ask for it** —
    /// switching the toggle, entering a focus, leaving one, and the end of a
    /// retag — and never while the user is writing. That is not an optimisation, it is a
    /// correctness requirement.
    ///
    /// A problem's offset is `gridPosition - itsOwnBounds.minX`, and ink is
    /// *stored* with that offset taken off. So re-measuring mid-edit closes a
    /// feedback loop: a mark written past the problem's left edge moves
    /// `bounds.minX`, which changes the offset, which moves every mark in that
    /// problem, which changes where the next sample is stored. It diverges, and
    /// it looks exactly like the pen drawing somewhere other than the nib.
    ///
    /// Pinning the offset for the length of an editing session breaks the loop:
    /// ink lands under the pen because the offset it is stored against is the
    /// same one it is drawn with. The page re-flows once, on focus exit — which
    /// is the moment the user has stopped writing.
    private func rebuild(animated: Bool, remeasure: Bool = true) {
        guard isEnabled else {
            animator.animate(
                to: .identity,
                focusProgress: 0,
                duration: animated ? ProblemLayoutMetrics.arrangeDuration : 0,
                onFinished: { [weak self] in self?.retireFrame() }
            )
            return
        }

        if remeasure { arrangement = ProblemLayoutGrid.arrange(cellsProvider()) }
        let resolved = resolveFocus()
        if isFocused { focusBox = resolved.box }

        let placement = arrangement.placement.adding(resolved.pushByNodeID)
        let frameProgress: CGFloat = isFocused ? 1 : 0
        if animated {
            animator.animate(
                to: placement,
                focusProgress: frameProgress,
                duration: ProblemLayoutMetrics.focusTransitionDuration,
                onFinished: { [weak self] in self?.retireFrame() }
            )
        } else {
            animator.settle(to: placement, focusProgress: frameProgress)
        }
    }

    /// The focused problem's ink where it is actually drawn — its stored bounds
    /// plus the grid's own offset for it.
    private func laidOutFocusedInkBounds() -> CGRect {
        guard let focusedNodeID, !liveInkBounds.isNull else { return .null }
        let gridOffset = arrangement.placement.offset(forNode: focusedNodeID)
        return liveInkBounds.offsetBy(dx: gridOffset.x, dy: gridOffset.y)
    }

    private func resolveFocus() -> ProblemFocusLayout.Result {
        guard let focusedNodeID else { return .unfocused }
        // A problem focused before it had a grid slot stands in with a cell
        // built from its path; the push only reads row, column and stack.
        let focusedCell = arrangement.cells.first { $0.nodeID == focusedNodeID }
            ?? unarrangedFocusPath.map {
                ProblemLayoutCell(nodeID: focusedNodeID, path: $0, bounds: liveInkBounds)
            }
        guard let focusedCell else { return .unfocused }
        return ProblemFocusLayout.resolve(
            focusedCell: focusedCell,
            inkBounds: laidOutFocusedInkBounds(),
            arrangement: arrangement
        )
    }
}
