import SwiftUI

struct MarkerToolButton: View {
    @Binding var activeTool: ToolType

    var body: some View {
        ToolButton(
            tool: .marker,
            icon: "highlighter",
            label: "Marker",
            activeTool: $activeTool
        )
    }
}
