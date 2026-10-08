import CoreGraphics
import Foundation
import Testing
@testable import Tract

/// Making, moving, stacking and reloading pins, with no canvas involved.
@Suite("Pinned reference model")
@MainActor
struct PinnedReferenceModelTests {
    private let viewport = CGSize(width: 1200, height: 800)
    private let inkSize = CGSize(width: 200, height: 100)

    @Test("Pinning ink adds a pin holding exactly that ink")
    func pinAddsAReference() {
        let model = PinnedReferenceModel()
        let strokeIDs: Set<UUID> = [UUID(), UUID()]

        let pinned = model.pin(strokeIDs: strokeIDs, inkSize: inkSize, viewport: viewport)

        #expect(model.references.count == 1)
        #expect(pinned?.strokeIDs == strokeIDs)
    }

    @Test("Pinning nothing makes no pin")
    func emptyPinIsRefused() {
        let model = PinnedReferenceModel()
        #expect(model.pin(strokeIDs: [], inkSize: inkSize, viewport: viewport) == nil)
        #expect(model.references.isEmpty)
    }

    @Test("Moving a pin raises it above the others")
    func moveRaisesThePin() throws {
        let model = PinnedReferenceModel()
        let bottom = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))
        model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport)

        model.move(bottom.id, to: CGPoint(x: 10, y: 20))

        #expect(model.references.last?.id == bottom.id)
        #expect(model.references.last?.center == CGPoint(x: 10, y: 20))
    }

    @Test("Tapping a covered pin raises it above the others without moving it")
    func raiseBringsThePinToTheFront() throws {
        let model = PinnedReferenceModel()
        let bottom = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))
        model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport)

        model.raise(bottom.id)

        #expect(model.references.last == bottom)
        #expect(model.references.count == 2)
    }

    @Test("Raising the pin already on top changes nothing")
    func raiseOfTopPinIsANoOp() throws {
        let model = PinnedReferenceModel()
        model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport)
        let top = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))
        let before = model.references

        model.raise(top.id)

        #expect(model.references == before)
    }

    @Test("A new pin's arrival is held until its flight lands, then cleared")
    func arrivalIsHeldUntilFinished() throws {
        let model = PinnedReferenceModel()
        let pinned = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))
        let arrival = PinArrival(pinID: pinned.id, sourceInkCenter: CGPoint(x: 40, y: 40), canvasScale: 1)

        model.beginArrival(arrival)
        #expect(model.arrival == arrival)

        model.finishArrival(of: pinned.id)
        #expect(model.arrival == nil)
    }

    @Test("Finishing a different pin's flight leaves the current arrival alone")
    func finishingAnotherPinKeepsTheArrival() throws {
        let model = PinnedReferenceModel()
        let pinned = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))
        model.beginArrival(PinArrival(pinID: pinned.id, sourceInkCenter: .zero, canvasScale: 1))

        model.finishArrival(of: UUID())

        #expect(model.arrival?.pinID == pinned.id)
    }

    @Test("An arrival for a pin that does not exist is ignored")
    func arrivalForUnknownPinIsIgnored() {
        let model = PinnedReferenceModel()
        model.beginArrival(PinArrival(pinID: UUID(), sourceInkCenter: .zero, canvasScale: 1))
        #expect(model.arrival == nil)
    }

    @Test("Unpinning mid-flight drops the arrival")
    func unpinClearsTheArrival() throws {
        let model = PinnedReferenceModel()
        let pinned = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))
        model.beginArrival(PinArrival(pinID: pinned.id, sourceInkCenter: .zero, canvasScale: 1))

        model.unpin(pinned.id)

        #expect(model.arrival == nil)
    }

    @Test("Flashing a pin's source records which pin, and where its off-screen ink is")
    func highlightRecordsThePin() throws {
        let model = PinnedReferenceModel()
        let pinned = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))

        model.highlightSource(of: pinned.id, outlines: [], offscreenSourcePoint: CGPoint(x: -300, y: 50))

        #expect(model.sourceHighlight?.pinID == pinned.id)
        #expect(model.sourceHighlight?.offscreenSourcePoint == CGPoint(x: -300, y: 50))
    }

    @Test("Flashing the same pin twice still changes the trigger, so the fade replays")
    func repeatedHighlightReplays() throws {
        let model = PinnedReferenceModel()
        let pinned = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))

        model.highlightSource(of: pinned.id, outlines: [], offscreenSourcePoint: nil)
        let first = model.sourceHighlightSequence
        model.highlightSource(of: pinned.id, outlines: [], offscreenSourcePoint: nil)

        #expect(model.sourceHighlightSequence == first + 1)
    }

    @Test("A pin that does not exist cannot be flashed")
    func highlightOfUnknownPinIsIgnored() {
        let model = PinnedReferenceModel()
        model.highlightSource(of: UUID(), outlines: [], offscreenSourcePoint: nil)
        #expect(model.sourceHighlight == nil)
    }

    @Test("Unpinning a pin mid-flash drops the flash")
    func unpinClearsItsHighlight() throws {
        let model = PinnedReferenceModel()
        let pinned = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))
        model.highlightSource(of: pinned.id, outlines: [], offscreenSourcePoint: nil)

        model.unpin(pinned.id)

        #expect(model.sourceHighlight == nil)
    }

    @Test("Resizing a pin stores its new size and centre")
    func resizeStoresTheFrame() throws {
        let model = PinnedReferenceModel()
        let pinned = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))

        model.resize(pinned.id, longestSide: 333, center: CGPoint(x: 400, y: 400))

        #expect(model.references.first?.longestSide == 333)
        #expect(model.references.first?.center == CGPoint(x: 400, y: 400))
    }

    @Test("Unpinning removes only that pin")
    func unpinRemovesOne() throws {
        let model = PinnedReferenceModel()
        let first = try #require(model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport))
        model.pin(strokeIDs: [UUID()], inkSize: inkSize, viewport: viewport)

        model.unpin(first.id)

        #expect(model.references.count == 1)
        #expect(model.references.contains { $0.id == first.id } == false)
    }

    @Test("Reloading forgets ink that is gone, and pins left with none")
    func restorePrunesDeadInk() {
        let model = PinnedReferenceModel()
        let liveStroke = UUID()
        let partlyGone = PinnedReference(strokeIDs: [liveStroke, UUID()], center: .zero, longestSide: 200)
        let allGone = PinnedReference(strokeIDs: [UUID()], center: .zero, longestSide: 200)

        model.restore([partlyGone, allGone], keepingStrokeIDs: [liveStroke])

        #expect(model.references.count == 1)
        #expect(model.references.first?.strokeIDs == [liveStroke])
    }
}
