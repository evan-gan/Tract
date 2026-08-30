import Testing
import CoreGraphics
@testable import Tract

@Suite("Grouping strokes by problem tag")
struct ProblemGroupingTests {
    @Test("Strokes sharing a tag are collected into one group")
    func sharedTagsCollectTogether() {
        let strokes = [
            square(at: .zero, tag: [.number(1)]),
            square(at: CGPoint(x: 300, y: 0), tag: [.number(1)]),
            square(at: CGPoint(x: 0, y: 300), tag: [.number(2)])
        ]

        let groups = ProblemGrouping.groups(from: strokes)

        #expect(groups.map(\.label) == ["1", "2"])
        #expect(groups[0].strokes.count == 2)
    }

    @Test("A group's bounds cover every stroke in it, however far apart they were drawn")
    func groupBoundsSpanAllItsStrokes() {
        let strokes = [
            square(at: .zero, side: 100, tag: [.number(1)]),
            square(at: CGPoint(x: 900, y: 0), side: 100, tag: [.number(1)])
        ]

        let bounds = ProblemGrouping.groups(from: strokes)[0].inkBounds

        #expect(bounds.minX == 0)
        #expect(bounds.maxX == 1000)
    }

    @Test("Groups order by ordinal, so problem 2 comes before problem 10")
    func groupsSortNumerically() {
        let strokes = [10, 2, 1].map { square(at: .zero, tag: [.number($0)]) }

        #expect(ProblemGrouping.groups(from: strokes).map(\.label) == ["1", "2", "10"])
    }

    @Test("Roman-numeral levels order by value, not alphabetically")
    func romanLevelsSortByValue() {
        // The flat-string sort this replaced put ix (9) before vi (6).
        let strokes = [9, 6, 4, 2].map {
            square(at: .zero, tag: [.number(1), .lowercaseRoman($0)])
        }

        let labels = ProblemGrouping.groups(from: strokes).map(\.label)

        #expect(labels == ["1.ii", "1.iv", "1.vi", "1.ix"])
    }

    @Test("A parent sorts before its own children, and children before the next problem")
    func parentsSortBeforeChildren() {
        let strokes: [Stroke] = [
            square(at: .zero, tag: [.number(2)]),
            square(at: .zero, tag: [.number(1), .lowercaseLetter(2)]),
            square(at: .zero, tag: [.number(1), .lowercaseLetter(1), .lowercaseRoman(2)]),
            square(at: .zero, tag: [.number(1), .lowercaseLetter(1), .lowercaseRoman(1)]),
            square(at: .zero, tag: [.number(1)])
        ]

        let labels = ProblemGrouping.groups(from: strokes).map(\.label)

        #expect(labels == ["1", "1.a.i", "1.a.ii", "1.b", "2"])
    }

    @Test("Grouping at depth 1 collects every part of a problem into one group")
    func depthCollapsesPartsIntoTheirProblem() {
        let strokes = [
            square(at: .zero, tag: [.number(1), .lowercaseLetter(1)]),
            square(at: CGPoint(x: 300, y: 0), tag: [.number(1), .lowercaseLetter(2)]),
            square(at: CGPoint(x: 600, y: 0), tag: [.number(2), .lowercaseLetter(1)])
        ]

        let groups = ProblemGrouping.groups(from: strokes, depth: 1)

        #expect(groups.map(\.label) == ["1", "2"])
        #expect(groups[0].strokes.count == 2)
    }

    @Test("Untagged strokes are dropped unless a heading is supplied")
    func untaggedStrokesAreOptional() {
        let strokes = [
            square(at: .zero, tag: [.number(1)]),
            square(at: CGPoint(x: 300, y: 0))
        ]

        #expect(ProblemGrouping.groups(from: strokes).map(\.label) == ["1"])
        #expect(
            ProblemGrouping.groups(from: strokes, untaggedLabel: "Untagged").map(\.label)
                == ["1", "Untagged"]
        )
    }

    @Test("The untagged group is always placed last")
    func untaggedGroupComesLast() {
        let strokes = [
            square(at: .zero, tag: [.number(9)]),
            square(at: CGPoint(x: 300, y: 0))
        ]

        let groups = ProblemGrouping.groups(from: strokes, untaggedLabel: "Alpha")

        #expect(groups.map(\.label) == ["9", "Alpha"])
    }

    @Test("A tag with no levels counts as untagged rather than a blank heading")
    func emptyTagIsTreatedAsUntagged() {
        let strokes = [square(at: .zero, tag: ProblemTag())]

        let groups = ProblemGrouping.groups(from: strokes, untaggedLabel: "Untagged")

        #expect(groups.map(\.label) == ["Untagged"])
    }

    @Test("Lasso and eraser strokes never form a group of their own")
    func nonDrawingToolsAreExcluded() {
        let strokes = [
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 50, y: 50)], tool: .lasso, problemTag: [.number(1)]),
            StrokeFixtures.stroke(through: [.zero, CGPoint(x: 50, y: 50)], tool: .eraser, problemTag: [.number(1)])
        ]

        #expect(ProblemGrouping.groups(from: strokes, untaggedLabel: "Untagged").isEmpty)
    }

    @Test("Strokes within a group keep their input order, which is drawing order")
    func groupPreservesDrawingOrder() {
        let earlier = square(at: .zero, tag: [.number(1)])
        let later = square(at: CGPoint(x: 200, y: 0), tag: [.number(1)])

        let grouped = ProblemGrouping.groups(from: [earlier, later])[0].strokes

        #expect(grouped.map(\.id) == [earlier.id, later.id])
    }

    @Test("A group carries the tag it was collected under")
    func groupCarriesItsTag() {
        let tag: ProblemTag = [.number(3), .lowercaseLetter(2)]

        let groups = ProblemGrouping.groups(from: [square(at: .zero, tag: tag)])

        #expect(groups[0].tag == tag)
    }

    private func square(at origin: CGPoint, side: CGFloat = 100, tag: ProblemTag? = nil) -> Stroke {
        StrokeFixtures.square(at: origin, side: side, problemTag: tag)
    }
}
