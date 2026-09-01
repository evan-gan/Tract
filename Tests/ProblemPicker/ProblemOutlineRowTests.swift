import Testing
@testable import Tract

@Suite("Flattening the outline into rows with tree connectors")
struct ProblemOutlineRowTests {
    /// ```
    /// 1
    /// ├ a
    /// │ ├ I
    /// │ └ II
    /// └ b
    /// 2
    /// ```
    private func sampleOutline() -> ProblemOutline {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 1, 2])
        _ = builder.node([1, 2])
        _ = builder.node([2])
        return builder.outline
    }

    @Test("Rows come out depth first, in the order they are drawn")
    func rowsAreDepthFirst() {
        #expect(sampleOutline().rows.map(\.label) == ["1", "a", "I", "II", "b", "2"])
    }

    @Test("A row knows its level, its parent and how many children it has")
    func rowsCarryTheirPlaceInTheTree() {
        let rows = sampleOutline().rows

        #expect(rows[1].level == 1)
        #expect(rows[1].parentID == rows[0].id)
        #expect(rows[1].childCount == 2)
        #expect(rows[5].parentID == nil)
    }

    @Test("Only the last of a run of siblings ends its spine at the row's centre")
    func lastSiblingsStopTheirSpine() {
        let rows = sampleOutline().rows

        #expect(!rows[1].isLastSibling)   // a, with b to follow
        #expect(rows[4].isLastSibling)    // b
        #expect(!rows[2].isLastSibling)   // I, with II to follow
        #expect(rows[3].isLastSibling)    // II
    }

    @Test("An ancestor's column keeps its vertical only while that branch has work below")
    func ancestorColumnsTrackRemainingSiblings() {
        let rows = sampleOutline().rows

        // Numeral I sits under part a, which still has part b coming, so the
        // column belonging to problem 1 runs the full height of the row.
        #expect(rows[2].ancestorSpines == [true, true])
        // Problem 2 has no ancestors at all.
        #expect(rows[5].ancestorSpines.isEmpty)
    }
}
