import Testing
import CoreGraphics
import Foundation
@testable import Tract

/// UIKit refines force and azimuth after a sample has been recorded, and hands
/// the refinement back as a whole touch. Taking that touch's *position* as well
/// is the bug these tests exist to prevent: the stored position is not always
/// the raw one — under the automatic problem layout ink is stored with its
/// problem's shift removed — so writing the raw point back teleports a sample
/// out of the middle of a finished stroke.
@Suite("Estimated property updates")
struct StrokeEstimatedUpdateTests {

    private func sample(
        at position: CGPoint,
        force: CGFloat,
        updateIndex: Int?
    ) -> StrokePoint {
        StrokePoint(
            position: position,
            force: force,
            azimuth: 0,
            altitude: 0,
            rollAngle: 0,
            estimatedPropertiesMask: 0,
            estimationUpdateIndex: updateIndex,
            timestamp: nil
        )
    }

    private func strokeAwaitingUpdate() -> Stroke {
        var stroke = Stroke(sessionID: UUID(), style: .default)
        stroke.appendPoint(sample(at: CGPoint(x: 10, y: 10), force: 0.1, updateIndex: nil))
        stroke.appendPoint(sample(at: CGPoint(x: 20, y: 20), force: 0.1, updateIndex: 7))
        stroke.appendPoint(sample(at: CGPoint(x: 30, y: 30), force: 0.1, updateIndex: nil))
        return stroke
    }

    @Test("A refined sample keeps the position it was stored at")
    func positionSurvivesTheUpdate() {
        var stroke = strokeAwaitingUpdate()
        // The raw touch location, a long way from where the sample was stored —
        // which is what a layout offset does to it.
        stroke.updatePoint(
            at: 7,
            with: sample(at: CGPoint(x: 4000, y: 4000), force: 0.9, updateIndex: 7)
        )

        #expect(stroke.points[1].position == CGPoint(x: 20, y: 20))
    }

    @Test("The refined force is taken")
    func forceIsUpdated() {
        var stroke = strokeAwaitingUpdate()
        stroke.updatePoint(
            at: 7,
            with: sample(at: CGPoint(x: 4000, y: 4000), force: 0.9, updateIndex: 7)
        )

        #expect(stroke.points[1].force == 0.9)
    }

    /// The eraser broad-phases on `canvasBounds`, so a sample outside it is ink
    /// the user can see and cannot rub out.
    @Test("A refined sample stays inside the stroke's own bounds")
    func boundsStillCoverEverySample() {
        var stroke = strokeAwaitingUpdate()
        stroke.updatePoint(
            at: 7,
            with: sample(at: CGPoint(x: 4000, y: 4000), force: 0.9, updateIndex: 7)
        )

        for point in stroke.points {
            // `spans`, not `contains`: the box is the union of the samples, so
            // the outermost ones sit exactly on its edges, and `CGRect.contains`
            // treats maxX and maxY as outside.
            #expect(stroke.canvasBounds.spans(CGRect(origin: point.position, size: .zero)))
        }
    }

    @Test("An update for a sample this stroke does not have changes nothing")
    func unknownUpdateIndexIsIgnored() {
        var stroke = strokeAwaitingUpdate()
        let before = stroke.points.map(\.position)
        stroke.updatePoint(
            at: 99,
            with: sample(at: CGPoint(x: 4000, y: 4000), force: 0.9, updateIndex: 99)
        )

        #expect(stroke.points.map(\.position) == before)
    }
}
