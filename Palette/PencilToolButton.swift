import SwiftUI

struct PencilToolButton: View {
    @Binding var activeTool: ToolType

    var body: some View {
        ToolButton(
            tool: .pencil,
            icon: "pencil",
            label: "Pencil",
            activeTool: $activeTool
        )
    }
}
