import Testing
import CoreGraphics
import Foundation
@testable import Tract

@Suite("Resolving where a dragged row would land")
struct ProblemDropResolverTests {
    /// 1, 1a, 1b, 2 — enough shape to have a parent to find, a level to clamp,
    /// and a last position to fall off the end of.
    private func sampleOutline() -> ProblemOutline {
        var builder = ProblemOutlineBuilder()
        _ = builder.node([1, 2])
        _ = builder.node([2])
        return builder.outline
    }

    @Test("The gap is the number of row midpoints above the pointer")
    func gapCountsMidpointsAbove() {
        let rowHeight: CGFloat = 34

        #expect(ProblemDropResolver.gapIndex(pointerY: 5, rowCount: 4, rowHeight: rowHeight) == 0)
        #expect(ProblemDropResolver.gapIndex(pointerY: 20, rowCount: 4, rowHeight: rowHeight) == 1)
        #expect(ProblemDropResolver.gapIndex(pointerY: 999, rowCount: 4, rowHeight: rowHeight) == 4)
    }

    @Test("A parent is the nearest row above the gap that is one level shallower")
    func parentIsTheNearestShallowerRowAbove() {
        let rows = sampleOutline().rows           // 1, 1a, 1b, 2
        let target = ProblemDropResolver.target(
            rows: rows,
            gapIndex: 2,                          // between 1a and 1b
            desiredLevel: 1,
            maximumLevel: 2
        )

        #expect(target.parentID == rows[0].id)
        #expect(target.level == 1)
        #expect(target.index == 1)                // after 1a
    }

    @Test("A level with no parent at this position steps up until one resolves")
    func unreachableLevelsStepUp() {
        let rows = sampleOutline().rows
        // Above every row there is nothing to be a child of, so level 2 and
        // level 1 both fail and the drop lands at the top level.
        let target = ProblemDropResolver.target(
            rows: rows,
            gapIndex: 0,
            desiredLevel: 2,
            maximumLevel: 2
        )

        #expect(target == ProblemDropTarget(level: 0, parentID: nil, index: 0))
    }

    @Test("The level is clamped to what the subtree is tall enough to occupy")
    func levelIsClampedBySubtreeDepth() {
        let rows = sampleOutline().rows
        // A two-level subtree cannot sit at level 2, so it lands at level 1.
        let target = ProblemDropResolver.target(
            rows: rows,
            gapIndex: 3,
            desiredLevel: 2,
            maximumLevel: 1
        )

        #expect(target.level == 1)
        #expect(target.parentID == rows[0].id)
    }

    @Test("The insertion index counts only the parent's children above the gap")
    func indexCountsChildrenAboveTheGap() {
        let rows = sampleOutline().rows
        let target = ProblemDropResolver.target(
            rows: rows,
            gapIndex: 3,                          // after 1b, before 2
            desiredLevel: 1,
            maximumLevel: 2
        )

        #expect(target.index == 2)
    }

    @Test("Level 0 always resolves, so the marker never points at nothing")
    func rootAlwaysResolves() {
        let rows = sampleOutline().rows
        let target = ProblemDropResolver.target(
            rows: rows,
            gapIndex: 4,
            desiredLevel: 0,
            maximumLevel: 2
        )

        #expect(target == ProblemDropTarget(level: 0, parentID: nil, index: 2))
    }

    @Test("The dragged rows stay on screen but take no part in the arithmetic")
    func draggedRowsAreExcludedFromTheGap() {
        let rows = sampleOutline().rows
        let carried: Set<UUID> = [rows[1].id]     // 1a is being dragged

        let surviving = ProblemDropResolver.survivingGap(
            in: rows,
            displayedGap: 3,                      // three rows on screen above the pointer
            excludedIDs: carried
        )

        #expect(surviving == 2)
    }

    @Test("Moving a node down its own list needs no off-by-one correction")
    func movingDownWithinOneListLandsWhereTheMarkerSaid() {
        var outline = sampleOutline()
        let rows = outline.rows
        let dragged = rows[1]                     // 1a
        let carried: Set<UUID> = [dragged.id]

        // Pointer past 1b: three rows on screen above it, two of them surviving.
        let gap = ProblemDropResolver.survivingGap(in: rows, displayedGap: 3, excludedIDs: carried)
        let target = ProblemDropResolver.target(
            rows: rows.filter { !carried.contains($0.id) },
            gapIndex: gap,
            desiredLevel: 1,
            maximumLevel: 2
        )
        outline.move(nodeAt: dragged.path, toParent: target.parentID, at: target.index)

        // 1a became 1b, and what was 1b became 1a.
        #expect(outline.tag(forNode: dragged.id) == ProblemTag([.number(1), .lowercaseLetter(2)]))
    }

    @Test("A drag carries its whole subtree, and cannot be dropped inside it")
    func aDragCarriesItsSubtree() {
        let outline = sampleOutline()
        let drag = ProblemOutlineDrag(row: outline.rows[0], in: outline, pointerY: 0)

        #expect(drag.carriedIDs.count == 3)                 // 1, 1a, 1b
        #expect(drag.maximumLevel == 1)                     // two levels tall
        #expect(!drag.carriedIDs.contains(outline.rows[3].id))
    }

    @Test("A hold is offered only for a level the drag could legally adopt")
    func levelHoldIsOfferedOnlyWhereItIsLegal() {
        let outline = sampleOutline()
        let rows = outline.rows
        // Problem 1, two levels tall: it may become a part (level 1) but never a
        // numeral, and hovering another problem offers nothing new.
        var drag = ProblemOutlineDrag(row: rows[0], in: outline, pointerY: 0)

        drag.pointerY = ProblemPickerMetrics.rowHeight * 3.5   // over problem 2
        #expect(drag.pendingLevel(displayedRows: rows) == nil)

        var leafDrag = ProblemOutlineDrag(row: rows[3], in: outline, pointerY: 0)
        leafDrag.pointerY = ProblemPickerMetrics.rowHeight * 1.5   // over 1a
        #expect(leafDrag.pendingLevel(displayedRows: rows) == 1)
    }
}
