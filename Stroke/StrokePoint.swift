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

    var estimatedProperties: UITouch.Properties {
        UITouch.Properties(rawValue: estimatedPropertiesMask)
    }
}
