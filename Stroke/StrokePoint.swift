import UIKit

/// A single sample captured from Apple Pencil during a stroke.
/// `estimatedPropertiesMask` tracks which fields (force, azimuth) arrived as
/// estimates — UIKit refines them later via `touchesEstimatedPropertiesUpdated`.
struct StrokePoint: Codable, Sendable {
    let position: CGPoint
    let force: CGFloat
    let azimuth: CGFloat       // Radians — pencil rotation around vertical axis
    let altitude: CGFloat      // Radians — 0 = flat on screen, π/2 = perpendicular
    let rollAngle: CGFloat     // Apple Pencil Pro barrel roll; 0.0 for other pencils

    /// Raw value of `UITouch.Properties` — stored as Int because the OptionSet
    /// itself doesn't conform to Codable.
    let estimatedPropertiesMask: Int

    /// Matches this point to the incoming `touchesEstimatedPropertiesUpdated` call
    /// so we can patch estimated force/azimuth with their final values.
    var estimationUpdateIndex: Int?

    /// When UIKit says this sample happened, in `UITouch.timestamp`'s own base —
    /// seconds since the device booted, *not* wall clock. Only differences within
    /// one drawing session mean anything, which is exactly what the export turns
    /// it into: how long after the stroke started this sample landed.
    ///
    /// Kept because the stroke's start/end alone cannot say how fast the pen was
    /// moving at any point, and speed is most of what separates one handwritten
    /// shape from another.
    ///
    /// Optional so documents written before it existed — and the fixtures that
    /// build strokes out of bare coordinates — still decode.
    var timestamp: TimeInterval?

    /// A copy of this sample at a new position. Every other field — the full
    /// pencil telemetry — is deliberately carried over: moving a mark across the
    /// canvas does not change how it was drawn.
    func moved(by offset: CGPoint) -> StrokePoint {
        StrokePoint(
            position: position + offset,
            force: force,
            azimuth: azimuth,
            altitude: altitude,
            rollAngle: rollAngle,
            estimatedPropertiesMask: estimatedPropertiesMask,
            estimationUpdateIndex: estimationUpdateIndex,
            timestamp: timestamp
        )
    }

    var estimatedProperties: UITouch.Properties {
        UITouch.Properties(rawValue: estimatedPropertiesMask)
    }
}
