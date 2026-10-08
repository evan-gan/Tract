import CoreGraphics
import Foundation
import Testing
@testable import Tract

/// Pinning a lasso selection from the canvas: what gets pinned, what happens
/// to the selection, and how the pin follows the ink through erase and undo.
@Suite("Pinning a selection")
@MainActor
struct PinSelectionTests {
    @Test("Pinning a selection pins exactly the selected ink")
    func pinHoldsTheSelectedInk() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine(
            alsoDrawing: [(CGPoint(x: 300, y: 300), CGPoint(x: 400, y: 400))]
        )
        let selectedIDs = viewModel.selectedStrokeIDs

        viewModel.pinSelection()

        #expect(viewModel.pins.references.count == 1)
        #expect(viewModel.pins.references.first?.strokeIDs == selectedIDs)
    }

    @Test("Pinning drops the selection, since the pin now frames that ink")
    func pinClearsTheSelection() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.handleCanvasTap(at: CGPoint(x: 40, y: 40))

        viewModel.pinSelection()

        #expect(viewModel.hasSelection == false)
        #expect(viewModel.isSelectionMenuVisible == false)
    }

    @Test("Pinning starts the card's flight from the lassoed ink, at the canvas zoom")
    func pinStartsAnArrivalFromTheInk() throws {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.noteViewportSize(CGSize(width: 1200, height: 800))
        // The line runs 20...60 on both axes; at 2× and shifted 100pt right it
        // is drawn centred at (180, 80) on screen.
        viewModel.canvasTransform.scale = 2
        viewModel.canvasTransform.translation = CGPoint(x: 100, y: 0)

        viewModel.pinSelection()

        let pinned = try #require(viewModel.pins.references.first)
        let arrival = try #require(viewModel.pins.arrival)
        #expect(arrival.pinID == pinned.id)
        #expect(arrival.canvasScale == 2)
        #expect(abs(arrival.sourceInkCenter.x - 180) < 0.001)
        #expect(abs(arrival.sourceInkCenter.y - 80) < 0.001)
    }

    @Test("A reopened document's pins appear in place rather than flying in")
    func restoredPinsDoNotArrive() {
        let viewModel = CanvasViewModel()
        let stroke = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 10)])

        viewModel.restore(
            strokes: [stroke],
            outline: ProblemOutline(),
            origin: .zero,
            scale: 1,
            pinnedReferences: [PinnedReference(strokeIDs: [stroke.id], center: .zero, longestSide: 200)]
        )

        #expect(viewModel.pins.arrival == nil)
    }

    // MARK: - Tapping a pin

    /// Two pins of the same line on a measured 1200×800 screen; the second is on top.
    private func canvasWithTwoPins() throws -> (CanvasViewModel, bottom: PinnedReference, top: PinnedReference) {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.noteViewportSize(CGSize(width: 1200, height: 800))
        viewModel.pinSelection()
        SelectionFixtures.lassoTheBox(viewModel)
        viewModel.pinSelection()
        let pins = viewModel.pins.references
        return (viewModel, try #require(pins.first), try #require(pins.last))
    }

    @Test("Tapping a covered pin raises it and flashes its source too")
    func tapOnCoveredPinRaisesAndFlashes() throws {
        let (viewModel, bottom, _) = try canvasWithTwoPins()

        viewModel.handlePinTap(bottom.id)

        #expect(viewModel.pins.references.last?.id == bottom.id)
        #expect(viewModel.pins.sourceHighlight?.pinID == bottom.id)
    }

    @Test("Tapping the top pin flashes its source, with no arrow when the ink is on screen")
    func tapOnTopPinFlashesItsSource() throws {
        let (viewModel, _, top) = try canvasWithTwoPins()

        viewModel.handlePinTap(top.id)

        #expect(viewModel.pins.sourceHighlight?.pinID == top.id)
        #expect(viewModel.pins.sourceHighlight?.offscreenSourcePoint == nil)
        #expect(viewModel.pins.sourceHighlight?.outlines.count == 1)
    }

    @Test("Tapping the top pin when its ink is panned off screen points the arrow at it")
    func tapWithSourceOffScreenGivesTheArrowATarget() throws {
        let (viewModel, _, top) = try canvasWithTwoPins()
        // The line is drawn at 20...60; this pushes it 5000pt to the left of the screen.
        viewModel.canvasTransform.translation = CGPoint(x: -5000, y: 0)

        viewModel.handlePinTap(top.id)

        let target = try #require(viewModel.pins.sourceHighlight?.offscreenSourcePoint)
        #expect(target.x < 0)
    }

    @Test("Double-tapping a pin glides rather than jumps: the page has not moved yet when it returns")
    func doubleTapStartsAGlide() throws {
        let (viewModel, _, top) = try canvasWithTwoPins()
        viewModel.canvasTransform.translation = CGPoint(x: -5000, y: 2000)

        viewModel.panToPinSource(top.id)

        #expect(viewModel.isGlidingCanvas)
        #expect(viewModel.canvasTransform.translation == CGPoint(x: -5000, y: 2000))
        viewModel.stopCanvasGlide()
    }

    @Test("The glide lands with the pin's ink centred at the same zoom, then flashes it with no arrow")
    func doubleTapGlideLandsOnTheSource() async throws {
        let (viewModel, _, top) = try canvasWithTwoPins()
        viewModel.canvasTransform.scale = 1.5
        viewModel.canvasTransform.translation = CGPoint(x: -5000, y: 2000)
        // The taps that make up a double tap arrive as single taps first.
        viewModel.handlePinTap(top.id)
        #expect(viewModel.pins.sourceHighlight?.offscreenSourcePoint != nil)
        let sequenceBeforeGlide = viewModel.pins.sourceHighlightSequence

        viewModel.panToPinSource(top.id)
        try await Task.sleep(for: .seconds(CanvasViewModel.pinSourceGlideDuration + 0.4))

        // The line runs 20...60, so its centre is (40, 40); the screen is 1200×800.
        let landed = viewModel.canvasTransform.toScreen(CGPoint(x: 40, y: 40))
        #expect(abs(landed.x - 600) < 0.001)
        #expect(abs(landed.y - 400) < 0.001)
        #expect(viewModel.canvasTransform.scale == 1.5)
        #expect(viewModel.isGlidingCanvas == false)
        #expect(viewModel.pins.sourceHighlightSequence > sequenceBeforeGlide)
        #expect(viewModel.pins.sourceHighlight?.offscreenSourcePoint == nil)
    }

    @Test("A finger on the canvas mid-glide stops it where it is, with no arrival flash")
    func stoppingTheGlideCancelsTheArrival() async throws {
        let (viewModel, _, top) = try canvasWithTwoPins()
        viewModel.canvasTransform.translation = CGPoint(x: -5000, y: 0)
        let sequence = viewModel.pins.sourceHighlightSequence

        viewModel.panToPinSource(top.id)
        viewModel.stopCanvasGlide()
        try await Task.sleep(for: .seconds(CanvasViewModel.pinSourceGlideDuration + 0.4))

        #expect(viewModel.canvasTransform.translation == CGPoint(x: -5000, y: 0))
        #expect(viewModel.pins.sourceHighlightSequence == sequence)
    }

    @Test("Panning a flashed pin's ink into view by hand retires its arrow, without replaying the flash")
    func manualPanIntoViewDropsTheArrow() throws {
        let (viewModel, _, top) = try canvasWithTwoPins()
        viewModel.canvasTransform.translation = CGPoint(x: -5000, y: 0)
        viewModel.handlePinTap(top.id)
        let sequence = viewModel.pins.sourceHighlightSequence

        viewModel.canvasTransform.translation = .zero

        #expect(viewModel.pins.sourceHighlight?.offscreenSourcePoint == nil)
        #expect(viewModel.pins.sourceHighlightSequence == sequence)
    }

    @Test("Panning that leaves the ink off screen keeps the arrow pointing")
    func panStillOffScreenKeepsTheArrow() throws {
        let (viewModel, _, top) = try canvasWithTwoPins()
        viewModel.canvasTransform.translation = CGPoint(x: -5000, y: 0)
        viewModel.handlePinTap(top.id)

        viewModel.canvasTransform.translation = CGPoint(x: -4000, y: 0)

        #expect(viewModel.pins.sourceHighlight?.offscreenSourcePoint != nil)
    }

    @Test("Double-tapping a pin is a pan, not an edit")
    func doubleTapIsNotAnEdit() throws {
        let (viewModel, _, top) = try canvasWithTwoPins()
        let revision = viewModel.revision

        viewModel.panToPinSource(top.id)

        #expect(viewModel.revision == revision)
        #expect(viewModel.pins.references.last?.id == top.id)
    }

    @Test("Flashing a source changes nothing about the ink or the undo stack")
    func flashIsNotAnEdit() throws {
        let (viewModel, _, top) = try canvasWithTwoPins()
        let strokeIDs = viewModel.strokes.map(\.id)
        let revision = viewModel.revision
        let undoWasAvailable = viewModel.canUndo

        viewModel.handlePinTap(top.id)

        #expect(viewModel.strokes.map(\.id) == strokeIDs)
        #expect(viewModel.revision == revision)
        #expect(viewModel.canUndo == undoWasAvailable)
    }

    @Test("Pinning is not an ink edit: it leaves the undo stack alone")
    func pinIsNotUndoable() {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        let undoWasAvailable = viewModel.canUndo
        let revision = viewModel.revision

        viewModel.pinSelection()

        #expect(viewModel.canUndo == undoWasAvailable)
        #expect(viewModel.revision == revision)
    }

    @Test("Panning and zooming the canvas leaves a pin where it is on screen")
    func pinIgnoresCanvasNavigation() throws {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.noteViewportSize(CGSize(width: 1200, height: 800))
        viewModel.pinSelection()
        let before = try #require(viewModel.pins.references.first)

        viewModel.canvasTransform.translation = CGPoint(x: -500, y: 250)
        viewModel.canvasTransform.scale = 2.5

        #expect(viewModel.pins.references.first == before)
    }

    @Test("A pin starts a quarter of the screen across and below the top bar")
    func pinStartsAtAQuarterOfTheScreen() throws {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.noteViewportSize(CGSize(width: 1200, height: 800))

        viewModel.pinSelection()

        let pinned = try #require(viewModel.pins.references.first)
        #expect(pinned.longestSide == 300)
        #expect(pinned.center.y > PinnedReferenceGeometry.initialTopInset)
    }

    @Test("Erasing pinned ink empties the pin, and undo brings it back")
    func pinFollowsEraseAndUndo() throws {
        let viewModel = SelectionFixtures.canvasWithSelectedLine()
        viewModel.pinSelection()
        let pinned = try #require(viewModel.pins.references.first)

        SelectionFixtures.lassoTheBox(viewModel)
        viewModel.deleteSelection()
        #expect(viewModel.pinnedInk(for: pinned).isEmpty)

        viewModel.undo()
        #expect(viewModel.pinnedInk(for: pinned).count == 1)
    }

    @Test("Reopening a document drops pins whose ink is gone")
    func restorePrunesPins() {
        let viewModel = CanvasViewModel()
        let survivor = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 10, y: 10)])
        let orphan = PinnedReference(strokeIDs: [UUID()], center: .zero, longestSide: 200)
        let kept = PinnedReference(strokeIDs: [survivor.id], center: .zero, longestSide: 200)

        viewModel.restore(
            strokes: [survivor],
            outline: ProblemOutline(),
            origin: .zero,
            scale: 1,
            pinnedReferences: [orphan, kept]
        )

        #expect(viewModel.pins.references == [kept])
    }
}
