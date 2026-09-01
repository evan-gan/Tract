import Testing
import Foundation
@testable import Tract

@Suite("The problem outline's structure and labels")
struct ProblemOutlineTests {
    @Test("A node's label is its position, not anything it stores")
    func labelsComeFromPosition() {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([2, 2, 3])

        #expect(builder.outline.label(at: [1]) == "2")
        #expect(builder.outline.label(at: [1, 1]) == "b")
        #expect(builder.outline.label(at: [1, 1, 2]) == "III")
    }

    @Test("A tag is valid at any depth, so a stroke on 2 stays on 2")
    func tagsAreValidAtEveryDepth() {
        var builder = ProblemOutlineBuilder()
        let problemTwo = builder.node([2])
        var outline = builder.outline

        #expect(outline.tag(forNode: problemTwo) == ProblemTag([.number(2)]))

        outline.appendChild(under: [1])
        outline.appendChild(under: [1])

        // Parts appearing underneath must not move the stroke off the problem.
        #expect(outline.tag(forNode: problemTwo) == ProblemTag([.number(2)]))
    }

    @Test("Moving a node renames it and everything after it")
    func movingRenamesFollowingSiblings() {
        var builder = ProblemOutlineBuilder()
        let first = builder.node([1])
        let second = builder.node([2])
        let third = builder.node([3])
        var outline = builder.outline

        outline.move(nodeAt: [2], toParent: nil, at: 0)

        #expect(outline.tag(forNode: third) == ProblemTag([.number(1)]))
        #expect(outline.tag(forNode: first) == ProblemTag([.number(2)]))
        #expect(outline.tag(forNode: second) == ProblemTag([.number(3)]))
    }

    @Test("A move carries the whole subtree with it")
    func movingCarriesChildren() {
        var builder = ProblemOutlineBuilder()
        let part = builder.node([1, 1])
        _ = builder.node([2])
        var outline = builder.outline

        // Problem 1, with its one part, becomes a part of problem 2.
        outline.move(nodeAt: [0], toParent: outline.roots[1].id, at: 0)

        #expect(outline.tag(forNode: part) == ProblemTag([.number(1), .lowercaseLetter(1), .uppercaseRoman(1)]))
    }

    @Test("The tree is three levels deep and refuses a fourth")
    func depthIsCappedAtThree() {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 1, 1])
        var outline = builder.outline

        #expect(outline.canAddChild(under: [0, 0]))
        #expect(!outline.canAddChild(under: [0, 0, 0]))
        #expect(outline.appendChild(under: [0, 0, 0]) == nil)
    }

    @Test("A subtree may only sit where the levels it needs still fit")
    func placementRespectsSubtreeDepth() {
        // A leaf reaches any level; a problem with lettered parts reaches level 1;
        // one whose parts already carry numerals cannot move down at all.
        #expect(ProblemOutline.deepestLevel(forSubtreeDepth: 1) == 2)
        #expect(ProblemOutline.deepestLevel(forSubtreeDepth: 2) == 1)
        #expect(ProblemOutline.deepestLevel(forSubtreeDepth: 3) == 0)
        #expect(!ProblemOutline.canPlace(subtreeDepth: 2, atLevel: 2))
    }

    @Test("A node cannot be dropped inside its own subtree")
    func moveIntoOwnSubtreeIsRefused() {
        var builder = ProblemOutlineBuilder()
        let problem = builder.node([1])
        let part = builder.node([1, 1])
        var outline = builder.outline

        outline.move(nodeAt: [0], toParent: part, at: 0)

        // Nothing moved: the problem is still a root and still holds its part.
        #expect(outline.tag(forNode: problem) == ProblemTag([.number(1)]))
        #expect(outline.tag(forNode: part) == ProblemTag([.number(1), .lowercaseLetter(1)]))
    }

    @Test("The last-used memory follows the node, not its position")
    func rememberedChildSurvivesAReorder() {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 4])
        _ = builder.node([2])
        var outline = builder.outline
        let partD = outline.children(under: [0])[3].id
        outline.rememberChoice(partD, under: [0])

        outline.move(nodeAt: [1], toParent: nil, at: 0)

        // Problem 1 is problem 2 now, and still remembers the part being worked on.
        #expect(outline.restoringRememberedDescendants(of: [1]) == [1, 3])
    }

    @Test("A level last left on the dash is not descended into")
    func anUnsetLevelStopsTheWalk() {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 2])
        var outline = builder.outline
        outline.rememberChoice(nil, under: [0])

        #expect(outline.restoringRememberedDescendants(of: [0]) == [0])
    }

    @Test("A remembered part the tree has since lost is forgotten rather than trusted")
    func staleMemoryIsDropped() {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 3])
        var outline = builder.outline
        let partC = outline.children(under: [0])[2].id
        outline.rememberChoice(partC, under: [0])

        outline.removeNode(at: [0, 2])

        #expect(outline.rememberedChild(under: [0]) == nil)
        #expect(outline.restoringRememberedDescendants(of: [0]) == [0])
    }

    @Test("An outline round-trips through the metadata JSON it is stored in")
    func outlineSurvivesEncoding() throws {
        var builder = ProblemOutlineBuilder()
        let part = builder.node([2, 3])
        var outline = builder.outline
        outline.rememberChoice(part, under: [1])

        let encoded = try JSONEncoder().encode(DocumentMetadata(problemOutline: outline))
        let decoded = try JSONDecoder().decode(DocumentMetadata.self, from: encoded)

        #expect(decoded.problemOutline == outline)
        #expect(decoded.problemOutline?.tag(forNode: part) == ProblemTag([.number(2), .lowercaseLetter(3)]))
        // The memory is document content too: it comes back with the tree.
        #expect(decoded.problemOutline?.restoringRememberedDescendants(of: [1]) == [1, 2])
    }

    /// The memory has been added, removed and added back while this was being
    /// built, so documents exist on disk without it.
    @Test("An outline stored without the last-used memory still decodes")
    func outlineWithoutMemoryDecodes() throws {
        let stored = #"{"roots":[{"id":"\#(UUID().uuidString)","children":[]}]}"#

        let decoded = try JSONDecoder().decode(ProblemOutline.self, from: Data(stored.utf8))

        #expect(decoded.roots.count == 1)
        #expect(decoded.rememberedChild(under: []) == nil)
    }

    @Test("A document saved before tagging existed loads with no outline")
    func metadataWithoutOutlineKeyDecodes() throws {
        let legacy = #"{"schemaVersion":1,"id":"\#(UUID().uuidString)","title":"Old","createdAt":0,"modifiedAt":0,"strokeCount":0,"canvasOrigin":[0,0],"canvasScale":1}"#

        let decoded = try JSONDecoder().decode(DocumentMetadata.self, from: Data(legacy.utf8))

        #expect(decoded.problemOutline == nil)
        #expect(SplineDocument(metadata: decoded).problemOutline.isEmpty)
    }
}
