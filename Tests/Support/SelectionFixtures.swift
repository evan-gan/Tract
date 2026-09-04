import CoreGraphics
import Foundation
@testable import Tract

/// Builds a canvas that already has a lasso selection on it, so selection tests
/// can start from "something is selected" instead of re-tracing a loop each time.
@MainActor
enum SelectionFixtures {
    /// The lassoed box, in canvas space. Anything drawn inside it ends up selected.
    static let boxCorners = [
        CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0),
        CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 100),
    ]

    /// A canvas holding one short line inside the lassoed box, already selected.
    ///
    /// - Parameters:
    ///   - others: further lines drawn outside the box first, so a test can check
    ///     what an action on the selection leaves alone.
    /// - Returns: the view model, with the line inside the box selected.
    static func canvasWithSelectedLine(
        alsoDrawing others: [(CGPoint, CGPoint)] = []
    ) -> CanvasViewModel {
        let viewModel = CanvasViewModel()
        drawLine(viewModel, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 60, y: 60))
        for (start, end) in others {
            drawLine(viewModel, from: start, to: end)
        }
        lassoTheBox(viewModel)
        return viewModel
    }

    static func drawLine(_ viewModel: CanvasViewModel, from start: CGPoint, to end: CGPoint) {
        viewModel.selectTool(.pen)
        viewModel.beginStroke(with: StrokeFixtures.point(at: start))
        viewModel.continueStroke(with: StrokeFixtures.point(at: end))
        viewModel.endStroke()
    }

    static func lassoTheBox(_ viewModel: CanvasViewModel) {
        viewModel.selectTool(.lasso)
        viewModel.beginStroke(with: StrokeFixtures.point(at: boxCorners[0]))
        for corner in boxCorners.dropFirst() {
            viewModel.continueStroke(with: StrokeFixtures.point(at: corner))
        }
        viewModel.endStroke()
    }
}
