import CoreGraphics
import Foundation
@testable import Tract

/// Builds strokes from bare coordinates so geometry tests read as the shapes
/// they describe instead of as pages of Apple Pencil telemetry.
enum StrokeFixtures {
    static func stroke(
        through positions: [CGPoint],
        tool: ToolType = .pen,
        lineWidth: CGFloat = 2,
        problemNodeID: UUID? = nil
    ) -> Stroke {
        var stroke = Stroke(
            sessionID: UUID(),
            style: StrokeStyle(color: SIMD4(0, 0, 0, 1), lineWidth: lineWidth, opacity: 1, tool: tool),
            problemNodeID: problemNodeID
        )
        for position in positions {
            stroke.appendPoint(point(at: position))
        }
        stroke.isComplete = true
        return stroke
    }

    /// A closed square of ink `side` points wide with its top-left at `origin`.
    /// Export tests use it because it covers area on the page, so a rasterised
    /// check can tell "drawn" from "drawn off the page".
    static func square(at origin: CGPoint, side: CGFloat = 100, problemNodeID: UUID? = nil) -> Stroke {
        stroke(
            through: [
                origin,
                CGPoint(x: origin.x + side, y: origin.y),
                CGPoint(x: origin.x + side, y: origin.y + side),
                CGPoint(x: origin.x, y: origin.y + side),
                origin
            ],
            lineWidth: 4,
            problemNodeID: problemNodeID
        )
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
