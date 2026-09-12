import SwiftUI

/// Switches the page between the order it was written in and a grid of
/// problems — one row per problem, its parts across the row.
///
/// It sits inside the top bar's own pill, beside the problem tag, because it is
/// problem chrome: what it rearranges is exactly what the wheel addresses. It
/// carries no glass of its own — glass cannot sample glass, and the bar is
/// already a single surface.
struct ProblemLayoutToggleButton: View {
    let layout: ProblemLayoutModel
    /// Routed through the canvas rather than called on the model directly, so
    /// the selection is dropped with it: a traced selection frame describes ink
    /// at positions the arrangement is about to move.
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: layout.isEnabled ? "rectangle.3.group.fill" : "rectangle.3.group")
                .symbolRenderingMode(.hierarchical)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .foregroundStyle(layout.isEnabled ? AnyShapeStyle(AppTint.active) : AnyShapeStyle(.secondary))
        .accessibilityIdentifier("problemLayoutToggle")
        .accessibilityLabel("Arrange problems")
        .accessibilityAddTraits(layout.isEnabled ? [.isSelected] : [])
    }
}
