import SwiftUI

/// The outline flashed around a pin's source ink when a pin is tapped — the
/// same rolling-ball shape the page frames each problem with, in the app's
/// attention colour.
///
/// It tracks the canvas — it frames ink, so it pans and zooms with it — and is
/// kept in the hierarchy even when there is nothing to frame, because the
/// flash only replays on a change it was already present for.
struct PinnedSourceHighlightView: View {
    /// Traced when the pin was tapped, in stored canvas space. Empty draws nothing.
    let outlines: [PinSourceOutline]
    /// Applied as each point is projected, so the flash follows the ink if the
    /// arrangement moves while it fades.
    let placement: ProblemLayoutPlacement
    let transform: CanvasTransform
    let trigger: Int

    /// Screen points, so the flash is the same weight at every zoom — like the
    /// problem frames it borrows its shape from.
    private static let lineWidth: CGFloat = 3
    private static let fillOpacity: CGFloat = 0.08

    var body: some View {
        Canvas { context, _ in
            for outline in outlines {
                let path = screenPath(for: outline)
                // Even-odd so an enclosed hole is left unfilled, as the problem
                // frames do.
                context.fill(path, with: .color(AppTint.active.opacity(Self.fillOpacity)), style: FillStyle(eoFill: true))
                context.stroke(path, with: .color(AppTint.active), lineWidth: Self.lineWidth)
            }
        }
        .pinSourceFlash(trigger: trigger)
        .allowsHitTesting(false)
    }

    private func screenPath(for outline: PinSourceOutline) -> Path {
        let offset = placement.offset(forNode: outline.problemNodeID)
        return Path { path in
            for contour in outline.contours {
                path.addSmoothedLoop(through: contour.map { transform.toScreen($0 + offset) })
            }
        }
    }
}
