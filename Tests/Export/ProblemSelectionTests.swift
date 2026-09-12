import Testing
import CoreGraphics
import Foundation
@testable import Tract

@Suite("Limiting an export to chosen problems")
struct ProblemSelectionTests {
    @Test("Only problems with ink under them are offered, in reading order")
    func offersTaggedProblemsInOrder() {
        let sample = taggedDocument()

        let labels = ExportProblemOption.options(in: sample.document).map(\.label)

        // Problem 2 exists in the tree but holds no ink of its own — all of its
        // work sits in 2a, which is offered in its place.
        #expect(labels == ["1", "1a", "2a"])
    }

    @Test("A document with no tagged ink offers nothing to choose")
    func untaggedDocumentOffersNoProblems() {
        let untagged = SplineDocument(
            metadata: DocumentMetadata(title: "Sketch"),
            strokes: [StrokeFixtures.square(at: .zero, side: 60)]
        )

        #expect(ExportProblemOption.options(in: untagged).isEmpty)
    }

    @Test("Applying a selection keeps only the chosen problems' strokes")
    func keepsOnlyTheChosenProblems() {
        let sample = taggedDocument()
        let selection = ProblemSelection(tags: [sample.tag(forLabel: "1a")])

        let limited = selection.applied(to: sample.document)

        #expect(limited.strokes.map(\.problemNodeID) == [sample.nodeID(forLabel: "1a")])
    }

    @Test("Choosing a problem does not drag its parts along with it")
    func doesNotIncludeDescendants() {
        let sample = taggedDocument()
        let selection = ProblemSelection(tags: [sample.tag(forLabel: "1")])

        let limited = selection.applied(to: sample.document)

        // 1 and 1a are separate chips, so ticking 1 must mean 1 alone.
        #expect(limited.strokes.map(\.problemNodeID) == [sample.nodeID(forLabel: "1")])
    }

    @Test("Untagged ink is never part of a selection")
    func dropsUntaggedInk() {
        let sample = taggedDocument()
        let everyProblem = ProblemSelection(
            tags: Set(ExportProblemOption.options(in: sample.document).map(\.tag))
        )

        let limited = everyProblem.applied(to: sample.document)

        #expect(limited.strokes.count == 3)
        #expect(limited.strokes.allSatisfy { $0.problemNodeID != nil })
    }

    @Test("An empty selection means no limit at all, so the document comes back whole")
    func emptySelectionExportsEverything() {
        let sample = taggedDocument()

        let limited = ProblemSelection.everything.applied(to: sample.document)

        #expect(limited.strokes.count == sample.document.strokes.count)
    }

    // MARK: - File naming

    @Test("One chosen problem names the file after it")
    func singleProblemNamesTheFile() {
        let sample = taggedDocument()
        let selection = ProblemSelection(tags: [sample.tag(forLabel: "1a")])

        #expect(selection.fileNameSuffix() == " 1a")
    }

    @Test("A few chosen problems are all named, in order")
    func severalProblemsAreAllNamed() {
        let sample = taggedDocument()
        let selection = ProblemSelection(tags: [
            sample.tag(forLabel: "2a"), sample.tag(forLabel: "1")
        ])

        #expect(selection.fileNameSuffix() == " 1-2a")
    }

    @Test("Past a handful the file is named by count, not by a list longer than the title")
    func manyProblemsAreNamedByCount() {
        var builder = ProblemOutlineBuilder()
        let tags = (1 ... 4).map { problem -> ProblemTag in
            _ = builder.node([problem])
            return builder.outline.tag(at: builder.path([problem]))
        }

        #expect(ProblemSelection(tags: Set(tags)).fileNameSuffix() == " 4 problems")
    }

    @Test("No selection leaves the name alone, so other layouts keep their own suffix")
    func noSelectionHasNoSuffix() {
        #expect(ProblemSelection.everything.fileNameSuffix() == nil)
    }

    // MARK: - Fixtures

    /// A document tagged 1, 1a and 2a, with a patch of untagged ink — one stroke
    /// each, so a filtered result can be checked by identity.
    private func taggedDocument() -> TaggedDocumentFixture {
        var builder = ProblemOutlineBuilder()
        let addresses: [(label: String, address: [Int])] = [
            ("1", [1]), ("1a", [1, 1]), ("2a", [2, 1])
        ]
        var nodeIDsByLabel: [String: UUID] = [:]
        var strokes: [Stroke] = []

        for (offset, entry) in addresses.enumerated() {
            let nodeID = builder.node(entry.address)
            nodeIDsByLabel[entry.label] = nodeID
            strokes.append(StrokeFixtures.square(
                at: CGPoint(x: CGFloat(offset) * 300, y: 0), side: 120, problemNodeID: nodeID
            ))
        }
        strokes.append(StrokeFixtures.square(at: CGPoint(x: 900, y: 0), side: 120))

        var metadata = DocumentMetadata(title: "Set 3")
        metadata.problemOutline = builder.outline
        return TaggedDocumentFixture(
            document: SplineDocument(metadata: metadata, strokes: strokes),
            outline: builder.outline,
            addressesByLabel: Dictionary(uniqueKeysWithValues: addresses.map { ($0.label, $0.address) }),
            nodeIDsByLabel: nodeIDsByLabel
        )
    }

    private struct TaggedDocumentFixture {
        let document: SplineDocument
        let outline: ProblemOutline
        let addressesByLabel: [String: [Int]]
        let nodeIDsByLabel: [String: UUID]

        func tag(forLabel label: String) -> ProblemTag {
            outline.tag(at: addressesByLabel[label]!.map { $0 - 1 })
        }

        func nodeID(forLabel label: String) -> UUID {
            nodeIDsByLabel[label]!
        }
    }
}
