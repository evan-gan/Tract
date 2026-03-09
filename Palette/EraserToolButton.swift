import SwiftUI

struct EraserToolButton: View {
    @Binding var activeTool: ToolType

    var body: some View {
        ToolButton(
            tool: .eraser,
            icon: "eraser",
            label: "Eraser",
            activeTool: $activeTool
        )
    }
}
