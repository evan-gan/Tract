import SwiftUI

/// One tool in the dock's carousel. The active tool sits inside a sliding
/// glass selector rather than lifting or popping — the selector's own motion
/// between tools is what reads as "this one now".
struct DockToolButton: View {
    let tool: ToolType
    let isActive: Bool
    /// Shared across the carousel so the selector morphs from one tool to the
    /// next instead of fading out and back in.
    let selectionNamespace: Namespace.ID
    /// Current ink, shown in the pen's tip so the dock says what it will draw.
    let inkColor: Color
    let onTapped: () -> Void

    private static let selectorShape = RoundedRectangle(cornerRadius: 13, style: .continuous)

    @ViewBuilder
    var body: some View {
        // Only the active tool carries glass, and every button hands it the same
        // effect id, so switching tools morphs the one pill across the carousel
        // instead of cross-fading two of them.
        if isActive {
            button
                .glassEffect(.regular, in: Self.selectorShape)
                .glassEffectID("toolSelector", in: selectionNamespace)
        } else {
            button
        }
    }

    private var button: some View {
        Button(action: onTapped) {
            ToolIconView(tool: tool, color: iconColor, inkColor: inkColor)
                .frame(width: DockLayout.itemSize, height: DockLayout.itemSize)
                .contentShape(Self.selectorShape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tool.displayName)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    // Hierarchical rather than literal colours: the dock's glass sets the actual
    // label levels, and only the hierarchical styles inherit them, so these match
    // the undo/redo and stroke-weight buttons in both colour schemes.
    private var iconColor: AnyShapeStyle {
        isActive ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)
    }
}
