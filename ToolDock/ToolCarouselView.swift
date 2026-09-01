import SwiftUI

/// The dock's run of tools, in a fixed order so muscle memory survives a move.
/// The active tool sits inside a plain Liquid Glass pill that morphs across to
/// whichever tool is picked next — no tint, no highlight, just the material.
struct ToolCarouselView: View {
    let activeTool: ToolType
    let edge: DockEdge
    /// Ink the pen glyph's tip is filled with.
    let inkColor: Color
    let onSelect: (ToolType) -> Void

    @Namespace private var selectionNamespace

    var body: some View {
        let layout = DockLayout.stack(along: edge.axis, spacing: 2)
        // Its own container, with no spacing to bridge on: the dock's outer glass
        // lives in the app-wide container, and letting the selector share that one
        // makes the two surfaces merge and eat a hole out of the dock.
        return GlassEffectContainer(spacing: 0) {
            layout {
                ForEach(ToolType.allCases, id: \.self) { tool in
                    DockToolButton(
                        tool: tool,
                        isActive: tool == activeTool,
                        selectionNamespace: selectionNamespace,
                        inkColor: inkColor,
                        onTapped: { onSelect(tool) }
                    )
                }
            }
        }
    }
}
