import SwiftUI

/// Undo and redo buttons grouped together in the top bar.
struct UndoRedoView: View {
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button("Undo", systemImage: "arrow.uturn.backward", action: onUndo)
                .disabled(!canUndo)
            Button("Redo", systemImage: "arrow.uturn.forward", action: onRedo)
                .disabled(!canRedo)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}
