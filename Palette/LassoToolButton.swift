import SwiftUI

struct LassoToolButton: View {
    @Binding var activeTool: ToolType

    var body: some View {
        ToolButton(
            tool: .lasso,
            icon: "lasso",
            label: "Lasso",
            activeTool: $activeTool
        )
    }
}
