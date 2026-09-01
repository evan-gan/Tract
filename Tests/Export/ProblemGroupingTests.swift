import Testing
import CoreGraphics
import Foundation
@testable import Tract

@Suite("Grouping strokes by the problem they are tagged with")
struct ProblemGroupingTests {
    @Test("Strokes sharing a tag are collected into one group")
    func sharedTagsCollectTogether() {
        var builder = ProblemOutlineBuilder()
        let problemOne = builder.node([1])
        let problemTwo = builder.node([2])
        let strokes = [
            square(at: .zero, node: problemOne),
            square(at: CGPoint(x: 300, y: 0), node: problemOne),
            square(at: CGPoint(x: 0, y: 300), node: problemTwo)
        ]

        let groups = ProblemGrouping.groups(from: strokes, outline: builder.outline)

        #expect(groups.map(\.label) == ["1", "2"])
        #expect(groups[0].strokes.count == 2)
    }

    @Test("A group's bounds cover every stroke in it, however far apart they were drawn")
    func groupBoundsSpanAllItsStrokes() {
        var builder = ProblemOutlineBuilder()
        let problemOne = builder.node([1])
        let strokes = [
            square(at: .zero, side: 100, node: problemOne),
            square(at: CGPoint(x: 900, y: 0), side: 100, node: problemOne)
        ]

        let bounds = ProblemGrouping.groups(from: strokes, outline: builder.outline)[0].inkBounds

        #expect(bounds.minX == 0)
        #expect(bounds.maxX == 1000)
    }

    @Test("Groups order by position, so problem 2 comes before problem 10")
    func groupsSortNumerically() {
        var builder = ProblemOutlineBuilder()
        let strokes = [10, 2, 1].map { square(at: .zero, node: builder.node([$0])) }

        let labels = ProblemGrouping.groups(from: strokes, outline: builder.outline).map(\.label)

        #expect(labels == ["1", "2", "10"])
    }

    @Test("Roman-numeral levels order by value, not alphabetically")
    func romanLevelsSortByValue() {
        // The flat-string sort this replaced put IX (9) before VI (6).
        var builder = ProblemOutlineBuilder()
        let strokes = [9, 6, 4, 2].map { square(at: .zero, node: builder.node([1, 1, $0])) }

        let labels = ProblemGrouping.groups(from: strokes, outline: builder.outline).map(\.label)

        #expect(labels == ["1.a.II", "1.a.IV", "1.a.VI", "1.a.IX"])
    }

    @Test("A parent sorts before its own children, and children before the next problem")
    func parentsSortBeforeChildren() {
        var builder = ProblemOutlineBuilder()
        let strokes = [[2], [1, 2], [1, 1, 2], [1, 1, 1], [1]].map {
            square(at: .zero, node: builder.node($0))
        }

        let labels = ProblemGrouping.groups(from: strokes, outline: builder.outline).map(\.label)

        #expect(labels == ["1", "1.a.I", "1.a.II", "1.b", "2"])
    }

    @Test("Grouping at depth 1 collects every part of a problem into one group")
    func depthCollapsesPartsIntoTheirProblem() {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: .zero, node: builder.node([1, 1])),
            square(at: CGPoint(x: 300, y: 0), node: builder.node([1, 2])),
            square(at: CGPoint(x: 600, y: 0), node: builder.node([2, 1]))
        ]

        let groups = ProblemGrouping.groups(from: strokes, outline: builder.outline, depth: 1)

        #expect(groups.map(\.label) == ["1", "2"])
        #expect(groups[0].strokes.count == 2)
    }

    @Test("Untagged strokes are dropped unless a heading is supplied")
    func untaggedStrokesAreOptional() {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: .zero, node: builder.node([1])),
            square(at: CGPoint(x: 300, y: 0))
        ]
        let outline = builder.outline

        #expect(ProblemGrouping.groups(from: strokes, outline: outline).map(\.label) == ["1"])
        #expect(
            ProblemGrouping.groups(from: strokes, outline: outline, untaggedLabel: "Untagged")
                .map(\.label) == ["1", "Untagged"]
        )
    }

    @Test("The untagged group is always placed last")
    func untaggedGroupComesLast() {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: .zero, node: builder.node([9])),
            square(at: CGPoint(x: 300, y: 0))
        ]

        let groups = ProblemGrouping.groups(
            from: strokes,
            outline: builder.outline,
            untaggedLabel: "Alpha"
        )

        #expect(groups.map(\.label) == ["9", "Alpha"])
    }

    @Test("A stroke pointing at a deleted problem counts as untagged, not as a blank heading")
    func strokeWithMissingNodeIsUntagged() {
        let strokes = [square(at: .zero, node: UUID())]

        let groups = ProblemGrouping.groups(
            from: strokes,
            outline: ProblemOutline(),
            untaggedLabel: "Untagged"
        )

        #expect(groups.map(\.label) == ["Untagged"])
    }

    @Test("Lasso and eraser strokes never form a group of their own")
    func nonDrawingToolsAreExcluded() {
        var builder = ProblemOutlineBuilder()
        let problemOne = builder.node([1])
        let strokes = [ToolType.lasso, .eraser].map {
            StrokeFixtures.stroke(
                through: [.zero, CGPoint(x: 50, y: 50)],
                tool: $0,
                problemNodeID: problemOne
            )
        }

        let groups = ProblemGrouping.groups(
            from: strokes,
            outline: builder.outline,
            untaggedLabel: "Untagged"
        )

        #expect(groups.isEmpty)
    }

    @Test("Strokes within a group keep their input order, which is drawing order")
    func groupPreservesDrawingOrder() {
        var builder = ProblemOutlineBuilder()
        let problemOne = builder.node([1])
        let earlier = square(at: .zero, node: problemOne)
        let later = square(at: CGPoint(x: 200, y: 0), node: problemOne)

        let grouped = ProblemGrouping.groups(
            from: [earlier, later],
            outline: builder.outline
        )[0].strokes

        #expect(grouped.map(\.id) == [earlier.id, later.id])
    }

    @Test("A group carries the tag its node resolves to today")
    func groupCarriesItsTag() {
        var builder = ProblemOutlineBuilder()
        let partB = builder.node([3, 2])

        let groups = ProblemGrouping.groups(
            from: [square(at: .zero, node: partB)],
            outline: builder.outline
        )

        #expect(groups[0].tag == ProblemTag([.number(3), .lowercaseLetter(2)]))
    }

    @Test("Reordering problems relabels the ink without any stroke being touched")
    func reorderRelabelsWithoutTouchingStrokes() {
        var builder = ProblemOutlineBuilder()
        let firstProblem = builder.node([1])
        let secondProblem = builder.node([2])
        let strokes = [
            square(at: .zero, node: firstProblem),
            square(at: CGPoint(x: 300, y: 0), node: secondProblem)
        ]

        var outline = builder.outline
        outline.move(nodeAt: [1], toParent: nil, at: 0)
        let groups = ProblemGrouping.groups(from: strokes, outline: outline)

        // The ink that was problem 2 is now problem 1, and its stroke never changed.
        #expect(groups[0].strokes.map(\.id) == [strokes[1].id])
        #expect(groups[0].label == "1")
        #expect(groups[1].strokes.map(\.id) == [strokes[0].id])
    }

    private func square(at origin: CGPoint, side: CGFloat = 100, node: UUID? = nil) -> Stroke {
        StrokeFixtures.square(at: origin, side: side, problemNodeID: node)
    }
}
