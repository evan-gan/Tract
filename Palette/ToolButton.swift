import SwiftUI

/// Shared base for all palette tool buttons.
/// Active tool gets a filled dark pill; inactive tools are transparent.
struct ToolButton: View {
    let tool: ToolType
    let icon: String
    let label: String
    @Binding var activeTool: ToolType

    private var isActive: Bool { activeTool == tool }

    var body: some View {
        Button(label, systemImage: icon, action: selectTool)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 40, height: 40)
            .background(isActive ? Color.primary.opacity(0.12) : Color.clear)
            .clipShape(.rect(cornerRadius: 10))
            .foregroundStyle(isActive ? .primary : .secondary)
            .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func selectTool() {
        activeTool = tool
    }
}
