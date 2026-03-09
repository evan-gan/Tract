import SwiftUI

struct PenToolButton: View {
    @Binding var activeTool: ToolType

    var body: some View {
        ToolButton(
            tool: .pen,
            icon: "pencil.tip",
            label: "Pen",
            activeTool: $activeTool
        )
    }
}
