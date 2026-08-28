import SwiftUI

/// Undo and redo, pinned to the leading end of the dock so they keep the same
/// spot no matter which edge the dock is parked on.
struct UndoRedoView: View {
    let axis: Axis
    let canUndo: Bool
    let canRedo: Bool
    let onUndo: () -> Void
    let onRedo: () -> Void

    var body: some View {
        let layout = DockLayout.stack(along: axis, spacing: 0)
        return layout {
            historyButton("Undo", icon: "arrow.uturn.backward", isEnabled: canUndo, action: onUndo)
            historyButton("Redo", icon: "arrow.uturn.forward", isEnabled: canRedo, action: onRedo)
        }
    }

    private func historyButton(_ label: String, icon: String,
                               isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: DockLayout.itemSize, height: DockLayout.itemSize)
                .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
