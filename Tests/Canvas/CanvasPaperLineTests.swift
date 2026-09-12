import Testing
import CoreGraphics
@testable import Tract

/// Ruled and squared papers are drawn line by line from these numbers. They have
/// to stay on the same canvas coordinates the dots use — otherwise switching
/// paper would shift the whole page under the ink — and the heavy lines of the
/// graph paper have to stay heavy as the grid coarsens with the zoom.
@Suite("Canvas paper lines")
struct CanvasPaperLineTests {

    // MARK: - Line thickness

    @Test("A line thickens with the zoom, like a mark on the paper")
    func lineWidthTracksZoom() {
        #expect(CanvasGrid.lineWidth(atScale: 1) == CanvasGrid.canvasLineWidth)
        #expect(CanvasGrid.lineWidth(atScale: 2) == CanvasGrid.canvasLineWidth * 2)
    }

    @Test("Line thickness is clamped at both ends so it never vanishes or blots")
    func lineWidthIsClamped() {
        #expect(CanvasGrid.lineWidth(atScale: 0.01) == CanvasGrid.minimumLineWidth)
        #expect(CanvasGrid.lineWidth(atScale: 100) == CanvasGrid.maximumLineWidth)
    }

    // MARK: - Coarsening

    @Test("At normal zoom the lattice is at full density")
    func fullDensityAtNormalZoom() {
        #expect(CanvasGrid.coarseningFactor(atScale: 1) == 1)
        #expect(CanvasGrid.coarseningFactor(atScale: 0.5) == 1)
    }

    @Test("Zooming out doubles the factor in step with the spacing")
    func coarseningMatchesSpacing() {
        for scale in [0.4, 0.25, 0.1] as [CGFloat] {
            let factor = CanvasGrid.coarseningFactor(atScale: scale)
            let spacing = CanvasGrid.screenSpacing(atScale: scale)
            #expect(spacing == CanvasGrid.canvasSpacing * scale * CGFloat(factor))
        }
    }

    @Test("A zero or negative scale falls back to full density")
    func degenerateScaleIsFullDensity() {
        #expect(CanvasGrid.coarseningFactor(atScale: 0) == 1)
        #expect(CanvasGrid.coarseningFactor(atScale: -3) == 1)
    }

    // MARK: - First visible line

    @Test("The first line lands where the dot grid's first dot lands")
    func firstLineAgreesWithFirstDot() {
        let spacing: CGFloat = 24
        for translation in [0, 10, 24, 30, -6, -30] as [CGFloat] {
            let index = CanvasGrid.firstLineIndex(translation: translation, spacing: spacing)
            let position = translation + CGFloat(index) * spacing
            let dotOffset = CanvasGrid.firstDotOffset(translation: translation, spacing: spacing)
            #expect(abs(position - dotOffset) < 0.000_1)
        }
    }

    @Test("The first visible line is the first one at or after the viewport edge")
    func firstLineIsInsideTheViewport() {
        #expect(CanvasGrid.firstLineIndex(translation: 0, spacing: 24) == 0)
        // The origin is 30pt in, so the line before it — index -1 — is the first
        // one still on screen.
        #expect(CanvasGrid.firstLineIndex(translation: 30, spacing: 24) == -1)
        #expect(CanvasGrid.firstLineIndex(translation: -30, spacing: 24) == 2)
    }

    @Test("A degenerate spacing does not spin the line walk")
    func zeroSpacingIsSafe() {
        #expect(CanvasGrid.firstLineIndex(translation: 40, spacing: 0) == 0)
    }

    // MARK: - Heavy lines

    @Test("Every fourth line of the lattice is heavy")
    func heavyLinesRepeatOnTheLattice() {
        let isMajor = { (index: Int) in
            CanvasGrid.isMajorLine(visibleIndex: index, coarseningFactor: 1, majorEvery: 4)
        }
        #expect(isMajor(0))
        #expect(isMajor(4))
        #expect(isMajor(-4))
        #expect(!isMajor(1))
        #expect(!isMajor(-3))
    }

    @Test("Coarsening keeps the heavy lines on the same canvas coordinates")
    func heavyLinesSurviveCoarsening() {
        // At factor 2 every surviving line is an even lattice line, so heavy
        // lines are every other one that is still drawn.
        #expect(CanvasGrid.isMajorLine(visibleIndex: 2, coarseningFactor: 2, majorEvery: 4))
        #expect(!CanvasGrid.isMajorLine(visibleIndex: 3, coarseningFactor: 2, majorEvery: 4))
        // At factor 4 only heavy lines are left standing.
        #expect(CanvasGrid.isMajorLine(visibleIndex: 1, coarseningFactor: 4, majorEvery: 4))
    }

    @Test("Paper with no heavy lines reports none")
    func ruledPaperHasNoHeavyLines() {
        #expect(!CanvasGrid.isMajorLine(visibleIndex: 0, coarseningFactor: 1, majorEvery: 0))
        #expect(!CanvasGrid.isMajorLine(visibleIndex: 8, coarseningFactor: 1, majorEvery: -2))
    }
}
