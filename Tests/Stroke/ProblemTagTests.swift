import Testing
import Foundation
@testable import Tract

@Suite("Problem tag ordering")
struct ProblemTagOrderingTests {
    @Test("Levels are compared outermost first, so 2 beats 10 at the top level")
    func topLevelOrdersByOrdinal() {
        let sorted: [ProblemTag] = [[.number(10)], [.number(2)], [.number(1)]].sorted()

        #expect(sorted.map(\.components.first?.ordinal) == [1, 2, 10])
    }

    @Test("A parent sorts before its own children")
    func parentPrecedesChild() {
        let parent: ProblemTag = [.number(1)]
        let child: ProblemTag = [.number(1), .lowercaseLetter(1)]

        #expect(parent < child)
    }

    @Test("A deep child still sorts before the next problem")
    func childPrecedesNextProblem() {
        let child: ProblemTag = [.number(1), .lowercaseLetter(26), .lowercaseRoman(99)]
        let next: ProblemTag = [.number(2)]

        #expect(child < next)
    }

    @Test("Ordering reads ordinals, so notation never affects it")
    func notationDoesNotAffectOrdering() {
        // Written out these are vi and ix; sorted as text, ix would come first.
        let six: ProblemTag = [.lowercaseRoman(6)]
        let nine: ProblemTag = [.lowercaseRoman(9)]

        #expect(six < nine)
    }

    @Test("The same ordinal in different notations still has a stable order")
    func mixedNotationsAreDeterministic() {
        let letter: ProblemTag = [.lowercaseLetter(1)]
        let roman: ProblemTag = [.lowercaseRoman(1)]

        #expect((letter < roman) != (roman < letter))
    }

    @Test("Cutting a tag to a depth yields its ancestor's address")
    func prefixYieldsAncestor() {
        let tag: ProblemTag = [.number(1), .lowercaseLetter(2), .lowercaseRoman(3)]

        #expect(tag.prefix(1) == [.number(1)])
        #expect(tag.prefix(2) == [.number(1), .lowercaseLetter(2)])
        #expect(tag.prefix(9) == tag)
        #expect(tag.prefix(0).isEmpty)
    }

    @Test("Appending a level deepens the address without touching the levels above")
    func appendingDeepensTheAddress() {
        let tag = ProblemTag([.number(1)]).appending(.lowercaseLetter(2))

        #expect(tag.components == [.number(1), .lowercaseLetter(2)])
        #expect(tag.depth == 2)
    }
}

@Suite("Problem tag storage format")
struct ProblemTagCodingTests {
    @Test("A tag survives a round trip through the on-disk encoder")
    func tagRoundTrips() throws {
        let tag: ProblemTag = [.number(1), .uppercaseLetter(2), .lowercaseRoman(4)]

        let encoded = try PropertyListEncoder().encode(tag)
        let decoded = try PropertyListDecoder().decode(ProblemTag.self, from: encoded)

        #expect(decoded == tag)
    }

    @Test("A level written by a build that knows a newer notation still decodes")
    func unknownStyleSurvivesDecoding() throws {
        // The whole point of storing styleID as a string: a document from a future
        // build must load, sort and re-save rather than take the library down.
        let futureTag = ProblemTag([ProblemLabelComponent(styleID: "greekLetter", ordinal: 3)])

        let encoded = try PropertyListEncoder().encode(futureTag)
        let decoded = try PropertyListDecoder().decode(ProblemTag.self, from: encoded)

        #expect(decoded == futureTag)
        #expect(ProblemTagFormatter.standard.text(for: decoded) == "3")
    }

    @Test("A stroke saved before tagging existed still loads, untagged")
    func strokeWithoutTagKeyDecodes() throws {
        var untagged = StrokeFixtures.square(at: .zero)
        untagged.problemTag = nil

        let encoded = try PropertyListEncoder().encode(untagged)
        let decoded = try PropertyListDecoder().decode(Stroke.self, from: encoded)

        #expect(decoded.problemTag == nil)
    }
}
