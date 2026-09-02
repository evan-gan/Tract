import SwiftUI

/// The paper and the ink on it.
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
