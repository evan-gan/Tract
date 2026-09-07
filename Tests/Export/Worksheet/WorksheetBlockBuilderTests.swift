import Testing
import CoreGraphics
import Foundation
@testable import Tract

@Suite("Worksheet blocks")
struct WorksheetBlockBuilderTests {
    @Test("One block per problem, labelled the way the problem is written")
    func oneBlockPerProblem() {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: .zero, node: builder.node([1, 1])),
            square(at: CGPoint(x: 400, y: 0), node: builder.node([1, 2])),
            square(at: CGPoint(x: 800, y: 0), node: builder.node([2]))
        ]

        let blocks = blocks(for: strokes, outline: builder.outline)

        #expect(blocks.map(\.label) == ["1a", "1b", "2"])
    }

    @Test("Reading order runs 1a, 1b, 2 … and keeps 10 after 9")
    func readingOrderFollowsThePath() {
        // Sorting on the problem's position rather than on its printed tag is
        // what keeps "10" after "9" instead of straight after "1".
        var builder = ProblemOutlineBuilder()
        let strokes = (1 ... 10).reversed().map { index in
            square(at: CGPoint(x: index * 400, y: 0), node: builder.node([index]))
        }

        let blocks = blocks(for: strokes, outline: builder.outline)

        #expect(blocks.map(\.label) == (1 ... 10).map(String.init))
    }

    @Test("Untagged work goes in one block, last, and can be left out entirely")
    func untaggedWorkComesLast() {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: CGPoint(x: 400, y: 0)),
            square(at: .zero, node: builder.node([1]))
        ]

        let withUntagged = blocks(for: strokes, outline: builder.outline)
        let taggedOnly = blocks(
            for: strokes,
            outline: builder.outline,
            options: WorksheetOptions(untaggedLabel: nil)
        )

        #expect(withUntagged.map(\.label) == ["1", "untagged"])
        #expect(taggedOnly.map(\.label) == ["1"])
    }

    @Test("A stroke tagged against a deleted problem reads as untagged")
    func strokesWithDeletedProblemsAreUntagged() {
        let strokes = [square(at: .zero, node: UUID())]

        #expect(blocks(for: strokes, outline: ProblemOutline()).map(\.label) == ["untagged"])
    }

    @Test("The block's box is the painted ink, nib included, not the bare centrelines")
    func boundsIncludeTheNib() {
        // Fitting to the centreline shaves half a nib off the outermost mark —
        // a flat edge down the side of the drawing, worse the more it is scaled.
        var builder = ProblemOutlineBuilder()
        let strokes = [
            StrokeFixtures.square(at: .zero, side: 100, problemNodeID: builder.node([1]))
        ]

        let block = blocks(for: strokes, outline: builder.outline)[0]

        // StrokeFixtures.square draws at a 4pt line width.
        #expect(block.bounds == CGRect(x: -2, y: -2, width: 104, height: 104))
    }

    @Test("Samples are thinned once, up front, and the hull is built from what is left")
    func strokesAreSimplified() {
        var builder = ProblemOutlineBuilder()
        let dense = StrokeFixtures.stroke(
            through: (0 ... 200).map { CGPoint(x: CGFloat($0), y: 0) },
            problemNodeID: builder.node([1])
        )

        let block = blocks(for: [dense], outline: builder.outline)[0]

        #expect(block.strokes[0].points.count == 2)
        #expect(block.strokes[0].points.first == CGPoint(x: 0, y: 0))
        #expect(block.strokes[0].points.last == CGPoint(x: 200, y: 0))
    }

    @Test("Colour keys off the top-level problem, so every part of problem 1 matches")
    func groupIndexIsTheTopLevelProblem() {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: .zero, node: builder.node([1, 1])),
            square(at: CGPoint(x: 400, y: 0), node: builder.node([3])),
            square(at: CGPoint(x: 800, y: 0))
        ]

        let blocks = blocks(for: strokes, outline: builder.outline)

        #expect(blocks.map(\.groupIndex) == [0, 2, nil])
    }

    // MARK: - Fixtures

    private func blocks(
        for strokes: [Stroke],
        outline: ProblemOutline,
        options: WorksheetOptions = WorksheetOptions()
    ) -> [WorksheetBlock] {
        WorksheetBlockBuilder.blocks(
            from: SplineDocument(metadata: DocumentMetadata(problemOutline: outline), strokes: strokes),
            viewport: nil,
            options: options
        )
    }

    private func square(at origin: CGPoint, node: UUID? = nil) -> Stroke {
        StrokeFixtures.square(at: origin, side: 200, problemNodeID: node)
    }
}
