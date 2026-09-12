import SwiftUI

/// The problem chips in the export sheet: tick the problems to export, and
/// nothing else leaves the document.
///
/// A wrapping grid of chips rather than a row each, because a problem's address
/// is two or three characters and a page of work has a lot of them — rows would
/// make the fitted sheet taller than the screen to say very little. The grid is
/// a `LazyVGrid` rather than a `List` for the same reason the cards around it
/// are hand-built: a scroll view reports no height of its own, and the sheet
/// sizes itself to its contents.
struct ExportProblemChooser: View {
    let options: [ExportProblemOption]
    /// The ticked problems, by address.
    @Binding var selection: Set<ProblemTag>

    private let chipColumns = [GridItem(.adaptive(minimum: 62), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: chipColumns, alignment: .leading, spacing: 8) {
                ForEach(options) { option in
                    chip(for: option)
                }
            }

            HStack(spacing: 18) {
                Button("Select all") { selection = Set(options.map(\.tag)) }
                    .accessibilityIdentifier("exportSelectAllProblems")
                Button("Clear") { selection = [] }
                    .accessibilityIdentifier("exportClearProblems")
                    .disabled(selection.isEmpty)
            }
            .font(.footnote)
        }
        .padding(16)
    }

    private func chip(for option: ExportProblemOption) -> some View {
        let isPicked = selection.contains(option.tag)
        return Button {
            toggle(option.tag)
        } label: {
            Text(option.label)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                // Each chip fills its grid cell so the addresses line up in
                // columns instead of jittering with their own widths.
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .foregroundStyle(isPicked ? Color.white : Color.primary)
                // A *fill* colour rather than `.tertiary`, which paints a solid
                // grey slab on the card and reads as a second picked state.
                .background(
                    isPicked ? Color.accentColor : Color(.tertiarySystemFill),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exportProblemChip-\(option.label)")
        .accessibilityLabel("Problem \(option.label)")
        .accessibilityAddTraits(isPicked ? .isSelected : [])
    }

    private func toggle(_ tag: ProblemTag) {
        if selection.contains(tag) {
            selection.remove(tag)
        } else {
            selection.insert(tag)
        }
    }
}
