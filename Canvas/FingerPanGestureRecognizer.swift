#if canImport(UIKit)
import UIKit
#else
#error("This file requires UIKit and is designed for iOS/iPadOS only")
#endif

/// Recognizes one finger dragging the canvas, while a palm rests on it.
///
/// `UIPanGestureRecognizer` cannot do this: it tracks whatever touches it is
/// given, so a resting palm either counts towards the touch limits or drags the
/// canvas by itself. This recognizer instead watches every contact and hands the
/// pan to the one that is actually moving — see `FingerPanArbiter` for the rules.
///
/// It deliberately gives up as soon as a second finger takes part, so pinch to
/// zoom keeps working exactly as before.
final class FingerPanGestureRecognizer: UIGestureRecognizer {
    /// Where the panning finger first landed, in view coordinates. Read by the
    /// view's `gestureRecognizerShouldBegin` to decide whether this touch belongs
    /// to the canvas or to something sitting on it, like a selection.
    private(set) var initialLocation: CGPoint = .zero

    /// Every contact still in the running, keyed by touch so ended touches can be
    /// removed without searching. Palm-sized contacts never make it in here.
    private var candidateStartLocations: [ObjectIdentifier: CGPoint] = [:]
    private var candidateTouches: [ObjectIdentifier: UITouch] = [:]

    /// The touch that won arbitration and is now moving the canvas.
    private var panningTouch: UITouch?

    /// Whether the recognizer can still change state. Once it has failed, ended or
    /// been cancelled — including when the view's `shouldBegin` gate refuses the
    /// pan — any further transition is illegal and UIKit will trap on it.
    private var isLive: Bool {
        state == .possible || state == .began || state == .changed
    }

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        // Palms and fingers both arrive as direct touches; pencil input belongs to
        // drawing and must never pan.
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }

    // MARK: - Touch tracking

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in touches {
            guard !isLikelyPalm(touch) else {
                ignore(touch, for: event)
                continue
            }
            // A fingertip arriving mid-pan means a pinch is starting. Bow out so
            // the pinch recognizer owns both touches instead of fighting for one.
            if panningTouch != nil {
                if isLive { state = .ended }
                return
            }
            let location = touch.location(in: view)
            candidateStartLocations[ObjectIdentifier(touch)] = location
            candidateTouches[ObjectIdentifier(touch)] = touch
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        // A contact can start fingertip-sized and spread as the hand settles, so
        // the width test is re-run on every update rather than only at touch down.
        for touch in touches where isLikelyPalm(touch) {
            dropCandidate(touch, for: event)
        }
        guard isLive else { return }

        if let panningTouch {
            if touches.contains(panningTouch) { state = .changed }
            return
        }
        electPanningTouchIfReady(for: event)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, endingWith: .ended)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, endingWith: .cancelled)
    }

    override func reset() {
        super.reset()
        candidateStartLocations.removeAll()
        candidateTouches.removeAll()
        panningTouch = nil
    }

    // MARK: - Arbitration

    /// Begins the pan once exactly one contact has travelled far enough, or fails
    /// outright when several have — that is a pinch, not a one-finger pan.
    private func electPanningTouchIfReady(for event: UIEvent) {
        let candidates = candidateTouches.values.compactMap { touch -> FingerPanCandidate<UITouch>? in
            guard let start = candidateStartLocations[ObjectIdentifier(touch)] else { return nil }
            return FingerPanCandidate(identifier: touch,
                                      startLocation: start,
                                      currentLocation: touch.location(in: view))
        }

        switch FingerPanArbiter.arbitrate(among: candidates) {
        case .undecided:
            return
        case .yieldToPinch:
            state = .failed
        case .pan(let winner):
            panningTouch = winner.identifier
            initialLocation = winner.startLocation
            // Everything else on the glass is resting, not panning. Ignoring those
            // touches keeps `location(in:)` reporting the moving finger alone.
            for touch in candidateTouches.values where touch !== winner.identifier {
                ignore(touch, for: event)
            }
            // Setting .began runs the view's shouldBegin gate, which can refuse.
            state = .began
        }
    }

    private func finish(_ touches: Set<UITouch>, endingWith terminalState: UIGestureRecognizer.State) {
        for touch in touches {
            candidateStartLocations.removeValue(forKey: ObjectIdentifier(touch))
            candidateTouches.removeValue(forKey: ObjectIdentifier(touch))
        }
        guard let panningTouch else {
            // No pan ever started and nothing is left to start one.
            if candidateTouches.isEmpty && state == .possible { state = .failed }
            return
        }
        if touches.contains(panningTouch) && isLive { state = terminalState }
    }

    private func dropCandidate(_ touch: UITouch, for event: UIEvent) {
        candidateStartLocations.removeValue(forKey: ObjectIdentifier(touch))
        candidateTouches.removeValue(forKey: ObjectIdentifier(touch))
        ignore(touch, for: event)
        // A contact that spread into a palm mid-pan was never a finger, so the
        // pan it was driving is cancelled rather than quietly frozen.
        if touch === panningTouch {
            panningTouch = nil
            if isLive { state = .cancelled }
        }
    }

    private func isLikelyPalm(_ touch: UITouch) -> Bool {
        FingerPanArbiter.isLikelyPalm(majorRadius: touch.majorRadius,
                                      tolerance: touch.majorRadiusTolerance)
    }
}
