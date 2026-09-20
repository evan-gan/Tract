import SwiftUI

/// Every piece of chrome that tracks the canvas rather than the screen and
/// belongs *over* the drawing: the lasso loop, the selection outline and the
/// selection's action menu.
///
/// The problem regions are not here. They read as markings on the paper, so they
/// are drawn under the ink in `CanvasContentLayer`.
///
/// None of them can take a glass material — they sit over the paper, not over
/// the app — so they stay outside the glass container. Kept in their own view so
/// a loop being traced repaints only this layer.
struct CanvasSelectionLayer: View {
    let viewModel: CanvasViewModel

    var body: some View {
        ZStack {
            // Above the ink rather than under it like the bubbles: the box is a
            // boundary held open around a whole screen of work, and a stroke
            // running across its edge must not break the line.
            // The frame focus just jumped away from, closing while the new one
            // opens. Under it, so the problem being entered reads as on top.
            if let closingFrame = viewModel.problemLayout.closingFrame {
                ProblemFocusFrameView(
                    bubbleLoop: closingFrame.bubbleLoop,
                    placementOffset: viewModel.problemPlacement.offset(forNode: closingFrame.nodeID),
                    box: closingFrame.box,
                    progress: viewModel.problemLayout.closingFrameProgress,
                    transform: viewModel.canvasTransform,
                    tint: viewModel.focusFrameTint(forNode: closingFrame.nodeID)
                )
            }
            if let frameNodeID = viewModel.problemLayout.frameNodeID {
                ProblemFocusFrameView(
                    bubbleLoop: viewModel.problemLayout.focusBubbleLoop,
                    placementOffset: viewModel.problemPlacement.offset(forNode: frameNodeID),
                    box: viewModel.problemLayout.focusBox,
                    progress: viewModel.problemLayout.focusFrameProgress,
                    transform: viewModel.canvasTransform,
                    tint: viewModel.focusFrameTint(forNode: frameNodeID)
                )
            }
            if !viewModel.lassoPath.isEmpty {
                LassoPathView(
                    canvasPoints: viewModel.lassoPath,
                    transform: viewModel.canvasTransform
                )
            }
            if viewModel.hasSelection {
                SelectionOutlineView(
                    contours: viewModel.selectionContours,
                    transform: viewModel.canvasTransform,
                    dragOffset: viewModel.selectionDragOffset
                )
            }
            if let menuAnchor = viewModel.selectionMenuAnchor {
                SelectionActionMenuView(
                    anchor: menuAnchor + viewModel.selectionDragOffset,
                    transform: viewModel.canvasTransform,
                    actions: selectionActions
                )
            }
        }
    }

    /// What the selection's floating menu offers. Held here rather than in the
    /// menu so the menu stays a presentation of whatever actions it is handed.
    private var selectionActions: [SelectionAction] {
        var actions: [SelectionAction] = []
        // Nothing to move the ink to until the tree has a problem in it, and a
        // menu with no rows is a dead end rather than a choice.
        if !problemChoices.isEmpty {
            actions.append(
                SelectionAction(
                    title: "Reassign",
                    systemImage: "arrow.triangle.branch",
                    choices: problemChoices
                )
            )
        }
        actions.append(
            SelectionAction(
                title: "Delete",
                systemImage: "trash",
                isDestructive: true,
                perform: viewModel.deleteSelection
            )
        )
        return actions
    }

    /// Every problem in the tree, in the order the outline prints them — 1, 1.a,
    /// 1.a.i, 2 — each labelled with its full address so a part is never just
    /// "a" with nothing to say which problem it belongs to.
    private var problemChoices: [SelectionActionChoice] {
        let outline = viewModel.problems.outline
        let currentNodeID = commonProblemNodeID
        return outline.rows.map { row in
            SelectionActionChoice(
                id: row.id,
                title: ProblemTagFormatter.standard.text(for: outline.tag(at: row.path)),
                isCurrent: row.id == currentNodeID,
                perform: { viewModel.reassignSelection(toProblemNode: row.id) }
            )
        }
    }

    /// The problem the whole selection is already filed under, or nil when the
    /// selected ink is a mix of tags — in which case no row is the current one.
    private var commonProblemNodeID: UUID? {
        let nodeIDs = Set(viewModel.selectedStrokes.map(\.problemNodeID))
        return nodeIDs.count == 1 ? nodeIDs.first ?? nil : nil
    }
}
