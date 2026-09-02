import UIKit

/// The preview of where the pencil is about to draw, as a CoreAnimation layer.
///
/// Hover is the one piece of chrome that must not lag by even a frame: the dot is
/// claiming to *be* the nib, so anything trailing behind it reads as lag in the
/// pencil itself. A SwiftUI view cannot move until an observation invalidation, a
/// body evaluation and a layout pass have run; a layer's position can be set
/// inside the hover callback, in the same run loop turn the event arrived on.
///
/// Implicit animation is off for every property it touches — CoreAnimation's
/// default is to *animate* a position change over a quarter second, which is the
/// same lag by another route.
@MainActor
final class PencilHoverDot {
    let layer = CAShapeLayer()

    /// A hairline weight zoomed out is sub-pixel; below this the dot would vanish
    /// exactly when the user most needs to know where the nib is pointing.
    private static let minimumDiameter: CGFloat = 4
    private static let ringWidth: CGFloat = 1
    /// The fill is translucent so the ink underneath still reads; the ring keeps
    /// the dot legible over ink of its own colour, which the fill alone would
    /// disappear into.
    private static let fillAlpha: CGFloat = 0.35
    private static let ringAlpha: CGFloat = 0.9

    /// What the layer currently draws, so an unchanged frame rebuilds nothing.
    private var drawnDiameter: CGFloat = 0
    private var drawnColor: UIColor?

    init() {
        layer.lineWidth = Self.ringWidth
        layer.isHidden = true
        // The dot is a picture of the nib, never a target for it.
        layer.actions = [
            "position": NSNull(), "bounds": NSNull(), "path": NSNull(),
            "hidden": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull()
        ]
    }

    /// - Parameters:
    ///   - location: Where the nib is hovering, in the canvas view's own space.
    ///   - diameter: Size of the mark this stroke weight would leave, in screen
    ///     points — already through the zoom.
    ///   - color: The ink about to be laid down, resolved for the current traits.
    func show(at location: CGPoint, diameter: CGFloat, color: UIColor) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        resizeIfNeeded(to: max(diameter, Self.minimumDiameter))
        recolorIfNeeded(to: color)
        layer.position = location
        layer.isHidden = false
        CATransaction.commit()
    }

    func hide() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.isHidden = true
        CATransaction.commit()
    }

    private func resizeIfNeeded(to diameter: CGFloat) {
        guard diameter != drawnDiameter else { return }
        drawnDiameter = diameter
        layer.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        // The ring is drawn *inside* the dot's own diameter: a centred stroke
        // would make the preview read wider than the mark it is previewing.
        let inset = Self.ringWidth / 2
        layer.path = CGPath(
            ellipseIn: CGRect(x: 0, y: 0, width: diameter, height: diameter)
                .insetBy(dx: inset, dy: inset),
            transform: nil
        )
    }

    private func recolorIfNeeded(to color: UIColor) {
        guard color != drawnColor else { return }
        drawnColor = color
        // Scaled rather than replaced, so ink the user already made translucent
        // previews translucent too.
        let inkAlpha = color.cgColor.alpha
        layer.fillColor = color.withAlphaComponent(inkAlpha * Self.fillAlpha).cgColor
        layer.strokeColor = color.withAlphaComponent(inkAlpha * Self.ringAlpha).cgColor
    }
}
