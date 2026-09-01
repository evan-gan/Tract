import SwiftUI

/// One line of the outline: its connectors, its label, how many children it has,
/// and whether it is the current selection.
///
/// The whole row is one hit target. Nothing else in the list is tappable — there
/// are no add or delete affordances here, because reordering *is* the editor.
struct ProblemOutlineRowView: View {
    let row: ProblemOutlineRow
    let isSelected: Bool
    /// Dimmed because it — or an ancestor of it — is being carried by a drag.
    let isBeingDragged: Bool
    /// 0 while nothing is pending; fills to 1 over the hold that changes the
    /// dragged node's level to this row's.
    let levelChangeProgress: CGFloat?

    var body: some View {
        HStack(spacing: 6) {
            Text(row.label)
                .font(labelFont)
                .foregroundStyle(labelStyle)
            if row.hasChildren {
                Text("\(row.childCount)")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.75)) : AnyShapeStyle(.tertiary))
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.level) * ProblemPickerMetrics.levelGutter + 6)
        .padding(.trailing, 8)
        .frame(height: ProblemPickerMetrics.rowHeight)
        .background(alignment: .leading) { connectors }
        .background(selectionFill)
        .overlay(alignment: .leading) { levelChangeBar }
        .opacity(isBeingDragged ? ProblemPickerMetrics.draggedRowOpacity : 1)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        // Keyed on the label so a UI test can name the row it means; the label
        // is the row's identity to the user too.
        .accessibilityIdentifier("problemRow-\(row.label)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// Level 0 carries the weight, level 2 recedes — the hierarchy has to be
    /// legible without reading the labels themselves.
    private var labelFont: Font {
        switch row.level {
        case 0: .system(size: 15, weight: .semibold, design: .rounded)
        case 1: .system(size: 14, weight: .regular, design: .rounded)
        default: .system(size: 13, weight: .regular, design: .rounded)
        }
    }

    private var labelStyle: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(.white) }
        return row.level >= 2 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary)
    }

    private var connectors: some View {
        ProblemTreeConnectors(
            level: row.level,
            isLastSibling: row.isLastSibling,
            hasChildren: row.hasChildren,
            ancestorColumns: ancestorColumns
        )
        .stroke(.tertiary, lineWidth: 1)
        .frame(width: CGFloat(row.level + 1) * ProblemPickerMetrics.levelGutter)
    }

    /// The column holding this row's own elbow is `level - 1`; everything left of
    /// it belongs to an ancestor, and continues only while that branch of the
    /// tree still has rows below.
    private var ancestorColumns: [Bool] {
        guard row.level > 1 else { return [] }
        return (0 ..< (row.level - 1)).map { column in
            row.ancestorSpines.indices.contains(column + 1) ? row.ancestorSpines[column + 1] : false
        }
    }

    /// Starts at the row's own label rather than at the popover's edge, so the
    /// tree lines to its left stay readable instead of being painted over.
    @ViewBuilder
    private var selectionFill: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTint.active)
                .padding(.leading, CGFloat(row.level) * ProblemPickerMetrics.levelGutter)
                .padding(.trailing, 6)
                .padding(.vertical, 1)
        }
    }

    /// The two-second hold that lets a drag change level, shown on the row being
    /// hovered rather than on the chip — it is that row's level being adopted.
    @ViewBuilder
    private var levelChangeBar: some View {
        if let levelChangeProgress {
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * levelChangeProgress, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .allowsHitTesting(false)
        }
    }
}
