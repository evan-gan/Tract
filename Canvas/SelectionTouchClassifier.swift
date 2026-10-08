import CoreGraphics

/// Decides whether a pencil touch on a selection is a tap or a drag, by whether
/// the nib leaves a small circle around where it landed.
///
/// The circle is the "contact patch" a tap is allowed to skid around in. Until
/// the nib leaves it the selection stays still, so a sloppy tap never nudges the
/// ink; once it leaves, the touch is a drag for good and the selection jumps
/// straight to the nib. There is no time limit, so a slow, careful drag works
/// as well as a quick flick.
struct SelectionTouchClassifier {

    enum Decision: Equatable {
        case undecided
        case tap
        case drag
    }

    /// Radius of the circle, in screen points, the nib may wander inside and
    /// still be a tap. Measured on screen so it feels the same at every zoom.
    static let tapRadius: CGFloat = 8

    private let startLocation: CGPoint
    private(set) var decision: Decision = .undecided

    /// - Parameter startLocation: Where the nib landed, in screen points.
    init(startLocation: CGPoint) {
        self.startLocation = startLocation
    }

    /// Feeds one more nib position in and returns the decision so far. Once the
    /// touch is a drag, coming back inside the circle does not undo that.
    ///
    /// - Parameter location: The nib's position, in screen points.
    /// - Returns: The decision after this sample.
    @discardableResult
    mutating func addSample(at location: CGPoint) -> Decision {
        if decision == .undecided, startLocation.distance(to: location) > Self.tapRadius {
            decision = .drag
        }
        return decision
    }

    /// The decision for a touch that is lifting: one that never left the circle
    /// is a tap.
    mutating func finish() -> Decision {
        if decision == .undecided { decision = .tap }
        return decision
    }
}
