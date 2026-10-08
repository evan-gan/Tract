import Testing
import CoreGraphics
@testable import Tract

/// A pencil touch on a selection is a drag once the nib leaves the small circle
/// around where it landed, and a tap if it never does.
@Suite("Selection touch: tap or drag by tap circle")
struct SelectionTouchClassifierTests {

    private let origin = CGPoint(x: 100, y: 100)
    private let radius = SelectionTouchClassifier.tapRadius

    private func classifier() -> SelectionTouchClassifier {
        SelectionTouchClassifier(startLocation: origin)
    }

    @Test("A nib that lands and lifts without moving is a tap")
    func stationaryTouchIsATap() {
        var touch = classifier()
        touch.addSample(at: origin)
        #expect(touch.decision == .undecided)
        #expect(touch.finish() == .tap)
    }

    @Test("Skidding around inside the circle is still a tap")
    func wanderingInsideCircleIsATap() {
        var touch = classifier()
        touch.addSample(at: CGPoint(x: origin.x + radius - 1, y: origin.y))
        touch.addSample(at: CGPoint(x: origin.x, y: origin.y - radius + 1))
        #expect(touch.finish() == .tap)
    }

    @Test("Leaving the circle makes the touch a drag")
    func leavingCircleIsADrag() {
        var touch = classifier()
        touch.addSample(at: CGPoint(x: origin.x + radius + 1, y: origin.y))
        #expect(touch.decision == .drag)
    }

    @Test("A slow creep out of the circle is a drag, however many samples it takes")
    func slowCreepIsADrag() {
        var touch = classifier()
        for step in 1...100 {
            touch.addSample(at: CGPoint(x: origin.x + CGFloat(step) * 0.2, y: origin.y))
        }
        #expect(touch.finish() == .drag)
    }

    @Test("Coming back inside the circle does not turn a drag into a tap")
    func dragDecisionIsFinal() {
        var touch = classifier()
        touch.addSample(at: CGPoint(x: origin.x + radius * 3, y: origin.y))
        touch.addSample(at: origin)
        #expect(touch.finish() == .drag)
    }
}
