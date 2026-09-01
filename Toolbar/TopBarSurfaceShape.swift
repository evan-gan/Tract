import SwiftUI

/// The top bar's glass outline: one rounded bar, and — while the problem wheel
/// is open — a tongue hanging out of its underside, joined by a fillet on each
/// side.
///
/// Drawn as a single path on purpose. Two glass surfaces set against each other
/// are blended by the glass container itself, and that blend takes a bite out of
/// the bar where they meet: a shape that belongs to neither. One path is one
/// surface, so the join is exactly the radius asked for and nothing else.
struct TopBarSurfaceShape: Shape {
    /// Where the tongue hangs from, in the bar's own coordinates.
    struct Tongue {
        let minX: CGFloat
        let maxX: CGFloat
    }

    /// Height of the bar proper. Everything below this in `rect` is tongue,
    /// which is what lets the shape follow the expansion without animating
    /// anything of its own: the layout is already growing.
    let barHeight: CGFloat
    let tongue: Tongue?
    let barCornerRadius: CGFloat
    let tongueCornerRadius: CGFloat
    /// The concave curve where the tongue leaves the bar.
    let jointRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        guard let tongue, rect.height > barHeight + 1 else {
            return Path(
                roundedRect: CGRect(x: 0, y: 0, width: rect.width, height: min(rect.height, barHeight)),
                cornerRadius: barCornerRadius,
                style: .continuous
            )
        }
        return path(in: rect, tongue: clamped(tongue, in: rect))
    }

    /// Keeps the tongue and its fillets inside the bar's own rounded corners, so
    /// a wheel opened under a control near the edge cannot push the join off the
    /// end of the bar.
    private func clamped(_ tongue: Tongue, in rect: CGRect) -> Tongue {
        let inset = barCornerRadius + jointRadius
        let minX = min(max(tongue.minX, inset), rect.maxX - inset)
        let maxX = max(min(tongue.maxX, rect.maxX - inset), inset)
        return Tongue(minX: min(minX, maxX), maxX: max(minX, maxX))
    }

    private func path(in rect: CGRect, tongue: Tongue) -> Path {
        var path = Path()
        let bottom = rect.maxY

        path.move(to: CGPoint(x: 0, y: barCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: barCornerRadius, y: 0),
            control: .zero
        )
        path.addLine(to: CGPoint(x: rect.maxX - barCornerRadius, y: 0))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: barCornerRadius),
            control: CGPoint(x: rect.maxX, y: 0)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: barHeight - barCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - barCornerRadius, y: barHeight),
            control: CGPoint(x: rect.maxX, y: barHeight)
        )

        // Down the right-hand side of the tongue, starting with the fillet that
        // curves out of the bar rather than cutting into it.
        path.addLine(to: CGPoint(x: tongue.maxX + jointRadius, y: barHeight))
        path.addQuadCurve(
            to: CGPoint(x: tongue.maxX, y: barHeight + jointRadius),
            control: CGPoint(x: tongue.maxX, y: barHeight)
        )
        path.addLine(to: CGPoint(x: tongue.maxX, y: bottom - tongueCornerRadius))
        path.addQuadCurve(
            to: CGPoint(x: tongue.maxX - tongueCornerRadius, y: bottom),
            control: CGPoint(x: tongue.maxX, y: bottom)
        )
        path.addLine(to: CGPoint(x: tongue.minX + tongueCornerRadius, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: tongue.minX, y: bottom - tongueCornerRadius),
            control: CGPoint(x: tongue.minX, y: bottom)
        )
        path.addLine(to: CGPoint(x: tongue.minX, y: barHeight + jointRadius))
        path.addQuadCurve(
            to: CGPoint(x: tongue.minX - jointRadius, y: barHeight),
            control: CGPoint(x: tongue.minX, y: barHeight)
        )

        path.addLine(to: CGPoint(x: barCornerRadius, y: barHeight))
        path.addQuadCurve(
            to: CGPoint(x: 0, y: barHeight - barCornerRadius),
            control: CGPoint(x: 0, y: barHeight)
        )
        path.closeSubpath()
        return path
    }
}
