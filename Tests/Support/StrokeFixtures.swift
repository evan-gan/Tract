import CoreGraphics
import Foundation
@testable import Tract

/// Builds strokes from bare coordinates so geometry tests read as the shapes
/// they describe instead of as pages of Apple Pencil telemetry.
enum StrokeFixtures {
    static func stroke(
        through positions: [CGPoint],
        tool: ToolType = .pen,
        lineWidth: CGFloat = 2
    ) -> Stroke {
        var stroke = Stroke(
            sessionID: UUID(),
            style: StrokeStyle(color: SIMD4(0, 0, 0, 1), lineWidth: lineWidth, opacity: 1, tool: tool)
        )
        for position in positions {
            stroke.appendPoint(point(at: position))
        }
        stroke.isComplete = true
        return stroke
    }

    static func point(at position: CGPoint) -> StrokePoint {
        StrokePoint(
            position: position,
            force: 1,
            azimuth: 0,
            altitude: .pi / 2,
            rollAngle: 0,
            estimatedPropertiesMask: 0,
            estimationUpdateIndex: nil
        )
    }
}
