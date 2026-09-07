import Testing
import CoreGraphics
@testable import Tract

@Suite("Worksheet growth")
struct WorksheetRelaxerTests {
    private let page = WorksheetFixtures.letterLandscape
    private let padding: CGFloat = 8
    private let cap: CGFloat = 1.25

    @Test("A problem with room around it grows")
    func aLonelyProblemFillsItsSpace() throws {
        let nested = WorksheetNester.nest(
            [WorksheetFixtures.block(label: "1", side: 100)],
            page: page,
            padding: padding,
            scale: 0.8
        )

        let grown = WorksheetRelaxer.grown(nested, page: page, padding: padding, cap: cap)

        #expect(try #require(grown.first?.placements.first).scale == cap)
    }

    @Test("Growth never shrinks a problem and never passes the cap")
    func growthOnlyEverGoesUpToTheCap() {
        let nested = WorksheetNester.nest(
            WorksheetFixtures.numberedBlocks(6),
            page: page,
            padding: padding,
            scale: 0.9
        )

        let grown = WorksheetRelaxer.grown(nested, page: page, padding: padding, cap: cap)

        for (before, after) in zip(nested.flatMap(\.placements), grown.flatMap(\.placements)) {
            #expect(after.scale >= before.scale)
            #expect(after.scale <= cap)
            #expect(after.block.label == before.block.label)
        }
    }

    @Test("Growth never lets ink overlap ink, or cross a margin")
    func growthKeepsTheLayoutLegal() {
        let nested = WorksheetNester.nest(
            WorksheetFixtures.numberedBlocks(8),
            page: page,
            padding: padding,
            scale: 0.8
        )

        let grown = WorksheetRelaxer.grown(nested, page: page, padding: padding, cap: cap)

        for sheet in grown {
            let outlines = sheet.placements.map { $0.outline(padding: padding) }
            for first in outlines.indices {
                #expect(page.contentRect.insetBy(dx: -0.001, dy: -0.001)
                    .contains(WorksheetPolygon.bounds(of: outlines[first])))
                for second in outlines.indices where second > first {
                    #expect(!WorksheetPolygon.intersect(outlines[first], outlines[second]))
                }
            }
        }
    }

    @Test("Free space is shared out rather than eaten by whichever problem comes first")
    func growthIsSharedRoundRobin() {
        // Two problems with a gap between them and a cap far out of reach, so a
        // pass that grew one problem to its limit before starting the next would
        // leave the second at the size it arrived at.
        let narrowPage = WorksheetPageGeometry(size: CGSize(width: 400, height: 300), margin: 36)
        let sheet = WorksheetSheet(placements: [
            placement(label: "1", at: CGPoint(x: 60, y: 120)),
            placement(label: "2", at: CGPoint(x: 250, y: 120))
        ])

        let grown = WorksheetRelaxer.grown([sheet], page: narrowPage, padding: padding, cap: 5)
        let scales = grown.flatMap { $0.placements.map(\.scale) }

        #expect((scales.min() ?? 0) > 1.1)
        #expect(abs(scales[0] - scales[1]) < 0.3)
    }

    private func placement(label: String, at origin: CGPoint) -> WorksheetPlacement {
        WorksheetPlacement(
            block: WorksheetFixtures.block(label: label, side: 100),
            origin: origin,
            scale: 0.8
        )
    }

    @Test("A page packed solid at the cap has nothing left to give")
    func nothingGrowsPastWhatFits() {
        // Everything already at the cap: the pass must be a no-op rather than
        // nudging placements about for no gain.
        let nested = WorksheetNester.nest(
            WorksheetFixtures.numberedBlocks(4),
            page: page,
            padding: padding,
            scale: cap
        )

        let grown = WorksheetRelaxer.grown(nested, page: page, padding: padding, cap: cap)

        for (before, after) in zip(nested.flatMap(\.placements), grown.flatMap(\.placements)) {
            #expect(after.scale == before.scale)
            #expect(after.origin == before.origin)
        }
    }
}
