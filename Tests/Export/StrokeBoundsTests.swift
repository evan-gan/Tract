import Testing
import CoreGraphics
@testable import Tract

@Suite("Bounding the ink an export has to fit")
struct StrokeBoundsTests {
    @Test("Painted bounds stand off the centreline by half the nib")
    func paintedBoundsIncludeTheNib() {
        let stroke = StrokeFixtures.stroke(
            through: [.zero, CGPoint(x: 100, y: 100)],
            lineWidth: 10
        )

        let bounds = StrokeRasterizer.inkedBounds(of: [stroke])

        #expect(bounds == CGRect(x: -5, y: -5, width: 110, height: 110))
    }

    @Test("The widest nib in the set sets the standoff")
    func widestNibWins() {
        let strokes = [
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 100, y: 0)], lineWidth: 2),
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 0, y: 100)], lineWidth: 12)
        ]

        #expect(StrokeRasterizer.inkedBounds(of: strokes).minX == -6)
    }

    @Test("A tool that lays down no ink cannot widen the box")
    func nonDrawingStrokesDoNotPad() {
        // A lasso loop is never painted, so padding for its width would leave a
        // band of empty paper down the side of every export that had one.
        let lasso = StrokeFixtures.stroke(
            through: [.zero, CGPoint(x: 100, y: 100)],
            tool: .lasso,
            lineWidth: 40
        )
        let pen = StrokeFixtures.stroke(
            through: [.zero, CGPoint(x: 100, y: 100)],
            lineWidth: 4
        )

        #expect(StrokeRasterizer.inkedBounds(of: [lasso, pen]).minX == -2)
    }

    @Test("Nothing to bound stays null rather than becoming a box around the origin")
    func emptyInputIsNull() {
        #expect(StrokeRasterizer.inkedBounds(of: []).isNull)
    }
}
