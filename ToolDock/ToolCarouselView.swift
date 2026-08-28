import SwiftUI

/// The dock's run of tools, in a fixed order so muscle memory survives a move.
struct ToolCarouselView: View {
    let activeTool: ToolType
    let edge: DockEdge
    let onSelect: (ToolType) -> Void

    var body: some View {
        let layout = DockLayout.stack(along: edge.axis, spacing: 2)
        return layout {
            ForEach(ToolType.allCases, id: \.self) { tool in
                DockToolButton(
                    tool: tool,
                    isActive: tool == activeTool,
                    liftDirection: edge.liftDirection,
                    onTapped: { onSelect(tool) }
                )
            }
        }
    }
}
