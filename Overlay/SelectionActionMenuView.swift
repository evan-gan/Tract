import SwiftUI

/// One entry in the selection's floating action menu.
struct SelectionAction: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String
    /// Destructive actions are tinted so a delete cannot be mistaken for a move.
    var isDestructive: Bool = false
    let perform: () -> Void
}

/// Small floating menu offering what can be done with the current lasso
/// selection. It is anchored to a canvas point rather than to the screen, so it
/// stays with the ink it acts on while the canvas is panned or zoomed beneath it.
struct SelectionActionMenuView: View {
    /// Where the user tapped, in canvas space.
    let anchor: CGPoint
    let transform: CanvasTransform
    let actions: [SelectionAction]

    /// How far above the tap the menu floats, in screen points. Enough to clear
    /// a fingertip or the nib without drifting away from what it belongs to.
    private static let liftAboveTouch: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            menuBar
                .fixedSize()
                .modifier(ClampedPosition(bounds: proxy.size, target: targetPosition))
        }
    }

    private var menuBar: some View {
        HStack(spacing: 4) {
            ForEach(actions) { action in
                SelectionActionButton(action: action)
            }
        }
        .padding(4)
        .glassChrome(cornerRadius: 22)
        .transition(.scale(scale: 0.85).combined(with: .opacity))
    }

    private var targetPosition: CGPoint {
        let screenAnchor = transform.toScreen(anchor)
        return CGPoint(x: screenAnchor.x, y: screenAnchor.y - Self.liftAboveTouch)
    }
}

/// Positions a fixed-size view at a point, pulled back inside the container when
/// the point sits too close to an edge for the whole view to fit.
private struct ClampedPosition: ViewModifier {
    let bounds: CGSize
    let target: CGPoint

    @State private var menuSize: CGSize = .zero

    private static let margin: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { menuSize = $0 }
            .position(clamped)
    }

    /// Centres on the target, then slides the menu back inside the container by
    /// as much as it overhangs — so a selection tapped at the very top or edge of
    /// the screen still gets a menu the user can reach.
    private var clamped: CGPoint {
        let halfWidth = menuSize.width / 2
        let halfHeight = menuSize.height / 2
        let minimumX = halfWidth + Self.margin
        let maximumX = max(minimumX, bounds.width - halfWidth - Self.margin)
        let minimumY = halfHeight + Self.margin
        let maximumY = max(minimumY, bounds.height - halfHeight - Self.margin)
        return CGPoint(
            x: min(max(target.x, minimumX), maximumX),
            y: min(max(target.y, minimumY), maximumY)
        )
    }
}

/// One tappable entry in the menu. Kept separate so the menu itself stays a
/// layout, and so every action reads and reacts identically.
private struct SelectionActionButton: View {
    let action: SelectionAction

    var body: some View {
        Button(action: action.perform) {
            Label(action.title, systemImage: action.systemImage)
                .font(.subheadline.weight(.medium))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(action.isDestructive ? AnyShapeStyle(AppTint.active)
                                                      : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.title)
    }
}
