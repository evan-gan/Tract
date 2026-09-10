import SwiftUI

/// The paper, the problems marked out on it, and the ink.
///
/// It exists to own the reads that change fastest — the transform under a pan,
/// the stroke under the pencil — so that they invalidate this view alone.
/// Reading them in the container instead would re-evaluate every piece of
/// chrome, glass included, on every frame of a gesture.
struct CanvasContentLayer: View {
    let viewModel: CanvasViewModel

    var body: some View {
        ZStack {
            CanvasBackgroundView(transform: viewModel.canvasTransform)
            // Above the paper and *under* the ink: the region is a marking on
            // the page, so nothing it is drawn over — the handwriting it frames
            // least of all — may be tinted or crossed by it.
            ProblemBoundsView(
                regions: viewModel.problemRegions,
                selectedNodeID: viewModel.problems.selectedNodeID,
                transform: viewModel.canvasTransform
            )
            CanvasRenderer(
                strokes: viewModel.strokes,
                activeStroke: viewModel.activeStroke,
                transform: viewModel.canvasTransform,
                selectedStrokeIDs: viewModel.selectedStrokeIDs,
                selectionOffset: viewModel.selectionDragOffset,
                problemInk: viewModel.problemInkStyling
            )
        }
    }
}
