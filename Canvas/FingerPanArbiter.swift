import CoreGraphics

/// One touch being considered as the finger that is panning the canvas.
///
/// `Identifier` is whatever the caller uses to tell touches apart — the gesture
/// recognizer keys on the `UITouch` itself, tests use plain integers.
struct FingerPanCandidate<Identifier> {
    let identifier: Identifier
    let startLocation: CGPoint
    let currentLocation: CGPoint

    var travel: CGFloat { startLocation.distance(to: currentLocation) }
}

/// The result of looking at every finger currently on the glass.
enum FingerPanArbitration<Identifier> {
    /// Nothing has moved far enough yet — keep watching.
    case undecided
    /// Exactly one contact is moving: the user is panning with a finger while
    /// anything else on the glass is just resting there.
    case pan(FingerPanCandidate<Identifier>)
    /// Two or more contacts are moving, which is a pinch, not a one-finger pan.
    case yieldToPinch
}

/// Decides which touch — if any — is a finger deliberately dragging the canvas.
///
/// Palm rejection here is two-layered, and the movement test does most of the
/// work: a palm or forearm reports a far wider contact than a fingertip, but that
/// width test is kept loose so it can never swallow a real finger, and whatever
/// slips past it is caught by the fact that a resting limb does not travel while
/// the finger driving the pan does.
enum FingerPanArbiter {
    /// Contacts wider than this are a palm or a forearm rather than a fingertip.
    ///
    /// Deliberately generous. A fingertip usually reports 10–30pt, but a thumb or a
    /// flattened finger can report far more, and this test also decides which
    /// touches the *pinch* is allowed to see — refusing one finger of a real pinch
    /// is a much worse failure than letting a palm through, because the movement
    /// test below catches a palm anyway and nothing catches a lost pinch.
    static let maximumFingerRadius: CGFloat = 60

    /// How far a contact must travel before it counts as a deliberate pan. Wide
    /// enough to ignore the jitter of a hand resting on the glass, small enough
    /// that the canvas still starts moving as soon as the finger does.
    static let movementThreshold: CGFloat = 8

    /// Whether a contact is too wide to be a fingertip.
    ///
    /// - Parameters:
    ///   - majorRadius: The touch's reported contact radius, in points.
    ///   - tolerance: The system's own uncertainty about that radius. Subtracted
    ///     so a noisy reading cannot reject a genuine fingertip.
    /// - Returns: `true` when even the smallest plausible radius is palm-sized.
    static func isLikelyPalm(majorRadius: CGFloat, tolerance: CGFloat) -> Bool {
        majorRadius - tolerance > maximumFingerRadius
    }

    /// Picks the panning finger out of everything currently touching the canvas.
    ///
    /// - Parameter candidates: Every contact that passed the width test, with
    ///   where it landed and where it is now.
    /// - Returns: `.pan` with the single moving contact, `.yieldToPinch` when more
    ///   than one is moving, or `.undecided` while everything is still at rest.
    static func arbitrate<Identifier>(
        among candidates: [FingerPanCandidate<Identifier>]
    ) -> FingerPanArbitration<Identifier> {
        let moving = candidates.filter { $0.travel >= movementThreshold }
        switch moving.count {
        case 0: return .undecided
        case 1: return .pan(moving[0])
        default: return .yieldToPinch
        }
    }
}
