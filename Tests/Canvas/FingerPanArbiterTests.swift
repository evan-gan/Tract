import Testing
import CoreGraphics
@testable import Tract

/// One finger pans the canvas while the rest of the hand may be resting on it,
/// so the arbiter has to tell a moving fingertip apart from a parked palm — and
/// from a second finger, which means the user is pinching instead.
@Suite("One-finger pan arbitration")
struct FingerPanArbiterTests {

    private func candidate(_ identifier: Int,
                           from start: CGPoint,
                           to current: CGPoint) -> FingerPanCandidate<Int> {
        FingerPanCandidate(identifier: identifier, startLocation: start, currentLocation: current)
    }

    // MARK: - Palm rejection by contact width

    @Test("A fingertip-sized contact is not treated as a palm")
    func fingertipWidthIsAccepted() {
        #expect(!FingerPanArbiter.isLikelyPalm(majorRadius: 12, tolerance: 0))
        #expect(!FingerPanArbiter.isLikelyPalm(majorRadius: 25, tolerance: 2))
    }

    @Test("A flattened finger or thumb is still a finger, not a palm")
    func wideFingerContactIsStillAFinger() {
        // The width test also gates the pinch, so a broad but genuine contact has
        // to survive it — losing one finger of a pinch is worse than a stray palm.
        #expect(!FingerPanArbiter.isLikelyPalm(majorRadius: 50, tolerance: 0))
    }

    @Test("A palm-wide contact is rejected")
    func palmWidthIsRejected() {
        #expect(FingerPanArbiter.isLikelyPalm(majorRadius: 90, tolerance: 5))
    }

    @Test("A noisy radius reading cannot reject a real fingertip")
    func toleranceProtectsBorderlineFingertips() {
        // Reported just over the limit, but the system admits it could be well under.
        #expect(!FingerPanArbiter.isLikelyPalm(majorRadius: 45, tolerance: 20))
    }

    // MARK: - Electing the panning finger

    @Test("Nothing moving means no pan has started yet")
    func restingContactsDoNotPan() {
        let resting = [candidate(1, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 101, y: 100))]
        guard case .undecided = FingerPanArbiter.arbitrate(among: resting) else {
            Issue.record("A contact that has barely twitched must not start a pan")
            return
        }
    }

    @Test("An empty glass is undecided rather than panning")
    func noContactsIsUndecided() {
        guard case .undecided = FingerPanArbiter.arbitrate(among: [FingerPanCandidate<Int>]()) else {
            Issue.record("No touches cannot elect a panning finger")
            return
        }
    }

    @Test("A single travelling contact takes the pan")
    func oneMovingFingerPans() {
        let moving = [candidate(1, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 160, y: 100))]
        guard case .pan(let winner) = FingerPanArbiter.arbitrate(among: moving) else {
            Issue.record("A finger dragged well past the threshold should pan")
            return
        }
        #expect(winner.identifier == 1)
    }

    @Test("A finger moving beside a resting palm still pans, and the pan follows the finger")
    func fingerWinsOverRestingPalm() {
        // The palm landed first and has not moved; the finger is dragging elsewhere.
        let contacts = [
            candidate(1, from: CGPoint(x: 500, y: 700), to: CGPoint(x: 501, y: 701)),
            candidate(2, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 260, y: 240))
        ]
        guard case .pan(let winner) = FingerPanArbiter.arbitrate(among: contacts) else {
            Issue.record("A resting palm must not stop the moving finger from panning")
            return
        }
        #expect(winner.identifier == 2)
        #expect(winner.startLocation == CGPoint(x: 200, y: 200))
    }

    @Test("Two travelling fingers are a pinch, not a one-finger pan")
    func twoMovingFingersYieldToPinch() {
        let contacts = [
            candidate(1, from: CGPoint(x: 200, y: 200), to: CGPoint(x: 140, y: 200)),
            candidate(2, from: CGPoint(x: 400, y: 200), to: CGPoint(x: 460, y: 200))
        ]
        guard case .yieldToPinch = FingerPanArbiter.arbitrate(among: contacts) else {
            Issue.record("Two moving fingers belong to the pinch recognizer")
            return
        }
    }

    @Test("Travel is measured from where the contact landed, not step to step")
    func travelIsMeasuredFromTheStartingPoint() {
        // Exactly on the threshold counts, so a slow drag is not stuck at rest.
        let onThreshold = candidate(1,
                                    from: .zero,
                                    to: CGPoint(x: FingerPanArbiter.movementThreshold, y: 0))
        #expect(onThreshold.travel == FingerPanArbiter.movementThreshold)
        guard case .pan = FingerPanArbiter.arbitrate(among: [onThreshold]) else {
            Issue.record("A contact exactly at the movement threshold should pan")
            return
        }
    }
}
