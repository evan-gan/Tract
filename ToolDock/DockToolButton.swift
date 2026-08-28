import SwiftUI

/// One tool in the dock's carousel. The active tool tints and lifts out of the
/// dock toward the canvas, the way a pen pulled from a real tray would.
struct DockToolButton: View {
    let tool: ToolType
    let isActive: Bool
    /// Unit vector pointing away from the docked edge.
    let liftDirection: CGSize
    let onTapped: () -> Void

    private static let liftDistance: CGFloat = 5

    var body: some View {
        Button(action: onTapped) {
            Image(systemName: tool.iconName)
                .font(.system(size: 19))
                .frame(width: DockLayout.itemSize, height: DockLayout.itemSize)
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        // Hierarchical rather than `Color.secondary`: the dock's glass sets the
        // literal label colours, and only the hierarchical levels inherit them.
        // The active tint is literal, so it reads the same in both schemes.
        .foregroundStyle(isActive ? AnyShapeStyle(AppTint.active) : AnyShapeStyle(.secondary))
        .background(isActive ? AppTint.active.opacity(0.22) : Color.clear,
                    in: .rect(cornerRadius: 12))
        .offset(
            x: isActive ? liftDirection.width * Self.liftDistance : 0,
            y: isActive ? liftDirection.height * Self.liftDistance : 0
        )
        .accessibilityLabel(tool.displayName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}
