import Observation
import SwiftUI

/// Everything the problem picker knows: the document's tree, which node new ink
/// is filed under, and the two recovery modes that make a wrong tag cheap.
///
/// Held by `CanvasViewModel` rather than by the wheel, because the outline is
/// document content and the selection decides what every new stroke is tagged
/// with — neither can live in view state that disappears when a view goes away.
@Observable
@MainActor
final class ProblemTaggingModel {
    /// The document's problem tree.
    private(set) var outline = ProblemOutline()

    /// Where the picker is pointed. Empty means nothing is selected, so new ink
    /// goes untagged.
    private(set) var selectedPath: ProblemPath = []

    /// Called for changes that must reach the disk — structural edits to the
    /// tree. Deliberately *not* called for the last-visited memory, which is
    /// navigation rather than content and rides along with the next real save,
    /// the way pan and zoom do.
    var onOutlineChanged: (() -> Void)?

    /// Bumped on every selection or structure change, with the level that moved.
    /// The wheel watches it so a change made anywhere else — a document opening,
    /// a drop in the outline — scrolls the columns to match.
    private(set) var changeTick = 0
    private(set) var lastChangedLevel: Int?

    // MARK: - Modes

    /// Whether the wheel is showing its three columns. Shut, it is one value on
    /// the bar, so the chrome stays off the page until it is asked for.
    private(set) var isWheelExpanded = false

    var isOutlineVisible = false
    /// Tapping a stroke reassigns it to the current tag.
    var isRetagging = false
    /// Colours ink by problem number, so tag boundaries can be seen without
    /// reading the picker.
    var isTintingByProblem = false

    // MARK: - Reading

    var selectedNodeID: UUID? { outline.node(at: selectedPath)?.id }

    var selectedTag: ProblemTag? {
        selectedPath.isEmpty ? nil : outline.tag(at: selectedPath)
    }

    // MARK: - Wheel columns

    /// The rows one column offers: the "none" row, every sibling that exists at
    /// that level, and one uncreated row past the end so the wheel can add to
    /// the tree without a separate button.
    ///
    /// A level whose parent is not selected yet offers only "none" — there is
    /// nothing to number under a problem that has not been picked.
    func wheelOptions(atLevel level: Int) -> [ProblemWheelOption] {
        guard selectedPath.count >= level else { return [.none] }
        let parentPath = ProblemPath(selectedPath.prefix(level))
        let siblingCount = outline.children(under: parentPath).count

        var options: [ProblemWheelOption] = [.none]
        options += (0 ..< siblingCount).map { siblingIndex in
            ProblemWheelOption(
                id: siblingIndex,
                label: ProblemLevelNotation.label(level: level, siblingIndex: siblingIndex),
                isUncreated: false
            )
        }
        if outline.canAddChild(under: parentPath) {
            options.append(ProblemWheelOption(
                id: siblingCount,
                label: ProblemLevelNotation.label(level: level, siblingIndex: siblingCount),
                isUncreated: true
            ))
        }
        return options
    }

    /// Which row a column is parked on. `ProblemWheelOption.noneID` when the
    /// selection does not reach this level.
    func selectedOptionID(atLevel level: Int) -> Int {
        selectedPath.indices.contains(level) ? selectedPath[level] : ProblemWheelOption.noneID
    }

    /// Points the picker at the row a column landed on. Landing on the uncreated
    /// row creates that node — the wheel is both how the tree is navigated and
    /// how it is grown, so there is one control to learn instead of two.
    ///
    /// The levels below come back to whatever was last used under the node
    /// picked, and sit on the dash where nothing has been. Returning to problem 1
    /// lands on the part that was being written; arriving somewhere new files ink
    /// under the level actually asked for, rather than walking into a first part
    /// nobody chose.
    func selectOption(_ optionID: Int, atLevel level: Int) {
        guard selectedPath.count >= level else { return }
        let parentPath = ProblemPath(selectedPath.prefix(level))

        guard optionID != ProblemWheelOption.noneID else {
            // Unsetting a level unsets everything under it, which truncating the
            // path to the parent does on its own.
            select(parentPath, changedLevel: level)
            return
        }

        if outline.children(under: parentPath).indices.contains(optionID) {
            select(
                outline.restoringRememberedDescendants(of: parentPath + [optionID]),
                changedLevel: level
            )
        } else if let created = outline.appendChild(under: parentPath) {
            commitStructuralEdit()
            select(created, changedLevel: level)
        }
    }

    // MARK: - Expanding

    /// The address the collapsed pill shows: "1.b", or a dash while nothing is
    /// picked and new ink is going untagged.
    var collapsedLabel: String {
        guard let selectedTag else { return ProblemWheelOption.noneLabel }
        return ProblemTagFormatter.standard.text(for: selectedTag)
    }

    func expandWheel() {
        isWheelExpanded = true
    }

    func collapseWheel() {
        isWheelExpanded = false
    }

    func toggleWheel() {
        isWheelExpanded.toggle()
    }

    // MARK: - Deleting

    /// The address a delete would remove — what the confirmation is labelled
    /// with. Empty for a row that addresses nothing, which cannot be deleted.
    func deletionLabel(for optionID: Int, atLevel level: Int) -> String {
        guard let path = deletablePath(for: optionID, atLevel: level) else { return "" }
        return ProblemTagFormatter.standard.text(for: outline.tag(at: path))
    }

    func canDelete(_ optionID: Int, atLevel level: Int) -> Bool {
        deletablePath(for: optionID, atLevel: level) != nil
    }

    /// Removes a node and everything under it. Ink filed under any of them is
    /// left pointing at an id nothing answers to, which reads as untagged
    /// rather than as an error — the drawing is never touched by a delete here.
    func deleteNode(_ optionID: Int, atLevel level: Int) {
        guard let doomedPath = deletablePath(for: optionID, atLevel: level) else { return }
        let parentPath = ProblemPath(doomedPath.dropLast())
        // Held by identity, because every sibling after the removed one is about
        // to be renumbered — and it is nil if the selection was inside what went.
        let survivingNodeID = selectedNodeID

        outline.removeNode(at: doomedPath)
        commitStructuralEdit()

        if let survivingNodeID, let landed = outline.path(ofNode: survivingNodeID) {
            select(landed, changedLevel: max(landed.count - 1, 0))
        } else {
            select(parentPath, changedLevel: level)
        }
    }

    /// The path a column row addresses, or nil for the dash, the uncreated row,
    /// and any row whose level has no parent selected.
    private func deletablePath(for optionID: Int, atLevel level: Int) -> ProblemPath? {
        guard optionID != ProblemWheelOption.noneID, selectedPath.count >= level else { return nil }
        let path = ProblemPath(selectedPath.prefix(level)) + [optionID]
        return outline.contains(path) ? path : nil
    }

    // MARK: - Loading

    /// Replaces the tree when a document opens. The selection cannot survive a
    /// different document, so it starts empty and new ink goes untagged until
    /// the user points the picker somewhere.
    func restore(outline restored: ProblemOutline) {
        outline = restored
        selectedPath = []
        isOutlineVisible = false
        isRetagging = false
        collapseWheel()
        lastChangedLevel = nil
        changeTick += 1
    }

    // MARK: - Selecting

    /// Selects a node by its position in the tree — what a tap on an outline row
    /// does, and what a drop does so the wheel shows the moved node's new label.
    func select(_ path: ProblemPath) {
        guard outline.contains(path) else { return }
        select(path, changedLevel: max(path.count - 1, 0))
    }

    func selectNode(_ nodeID: UUID) {
        guard let path = outline.path(ofNode: nodeID) else { return }
        select(path)
    }

    private func select(_ path: ProblemPath, changedLevel: Int) {
        selectedPath = path
        rememberSelectionPath()
        lastChangedLevel = changedLevel
        changeTick += 1
    }

    /// Records the choice made at every level of the new selection — including
    /// the level just past its end, which the user has deliberately left on the
    /// dash. Remembering that is what stops an unset letter coming back as a
    /// part the next time the problem is picked.
    private func rememberSelectionPath() {
        for level in selectedPath.indices {
            let childPath = ProblemPath(selectedPath.prefix(level + 1))
            outline.rememberChoice(
                outline.node(at: childPath)?.id,
                under: ProblemPath(selectedPath.prefix(level))
            )
        }
        guard !selectedPath.isEmpty, selectedPath.count < ProblemLevelNotation.maximumDepth
        else { return }
        outline.rememberChoice(nil, under: selectedPath)
    }

    // MARK: - Reorganising

    /// Applies a drop from the outline's drag. The moved node stays selected so
    /// the wheel shows its new label the moment it lands.
    func moveNode(at path: ProblemPath, to target: ProblemDropTarget) {
        guard let moved = outline.node(at: path) else { return }
        outline.move(nodeAt: path, toParent: target.parentID, at: target.index)
        commitStructuralEdit()
        if let landed = outline.path(ofNode: moved.id) {
            select(landed, changedLevel: max(landed.count - 1, 0))
        }
    }

    /// The deepest level a node may be dropped at, from the spec's
    /// `3 - depth(node)`: a leaf reaches any level, a problem whose parts already
    /// have numerals cannot move down at all.
    func deepestLevel(forNodeAt path: ProblemPath) -> Int {
        ProblemOutline.deepestLevel(forSubtreeDepth: outline.subtreeDepth(at: path))
    }

    private func commitStructuralEdit() {
        onOutlineChanged?()
    }

    // MARK: - Ink styling

    /// How the canvas should paint each stroke under the current modes. Cached
    /// on everything it depends on: the renderer asks for it on every frame of a
    /// pan, and rebuilding a dictionary over a full page of ink that often would
    /// show up in the drawing.
    func inkStyling(for strokes: [Stroke], revision: Int) -> ProblemInkStyling {
        let key = StylingKey(
            revision: revision,
            selectedNodeID: selectedNodeID,
            isRetagging: isRetagging,
            isTinting: isTintingByProblem,
            outline: outline
        )
        if let cachedStyling, cachedKey == key { return cachedStyling }

        let styling = ProblemInkStyling.make(
            strokes: strokes,
            outline: outline,
            tintByProblem: isTintingByProblem,
            focusedNodeID: isRetagging ? selectedNodeID : nil,
            dimsUnfocused: isRetagging
        )
        cachedKey = key
        cachedStyling = styling
        return styling
    }

    /// Ignored by observation on purpose: a cache written during a view's read
    /// must not itself invalidate that view.
    @ObservationIgnored private var cachedKey: StylingKey?
    @ObservationIgnored private var cachedStyling: ProblemInkStyling?

    private struct StylingKey: Equatable {
        let revision: Int
        let selectedNodeID: UUID?
        let isRetagging: Bool
        let isTinting: Bool
        let outline: ProblemOutline
    }
}
