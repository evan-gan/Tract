import SwiftUI

/// The tagging control, as a segment of the top bar.
///
/// Shut it is one value — the address new ink is filed under. Open, the three
/// drums take its place: the value *before* the selection lands on the bar's own
/// row, and only the selected value and the one after it hang below. That is
/// what keeps the control shallow — the bar row is doing the work a third row of
/// glass would otherwise have to.
struct ProblemWheelSegment: View {
    let model: ProblemTaggingModel
    /// The bar's coordinate space, so the drums can report where they are and
    /// the bar can hang its tongue from exactly that span.
    let barSpace: NamedCoordinateSpace
    let onWheelFrameChange: (CGRect) -> Void

    var body: some View {
        // Top-aligned so the chevron stays on the bar's row while the drums run
        // past it: it is the way to put the wheel away, and it must not wander
        // down into the tongue with them.
        HStack(alignment: .top, spacing: 8) {
            wheel
            disclosureChevron
                .frame(height: ProblemPickerMetrics.wheelRowHeight)
        }
    }

    // MARK: - The value, or the drums

    @ViewBuilder
    private var wheel: some View {
        if model.isWheelExpanded {
            columns
                .overlay(alignment: .leading) { caret(systemImage: "chevron.right") }
                .overlay(alignment: .trailing) { caret(systemImage: "chevron.left") }
                .measured(in: barSpace, onChange: onWheelFrameChange)
                .transition(.opacity)
        } else {
            collapsedValue
                .measured(in: barSpace, onChange: onWheelFrameChange)
                .transition(.opacity)
        }
    }

    /// The value opens the wheel as readily as the chevron does. It is the
    /// bigger target of the two and the one the eye is already on, so making it
    /// inert would be asking for the chevron to be aimed at instead.
    private var collapsedValue: some View {
        Text(model.collapsedLabel)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .frame(minWidth: ProblemPickerMetrics.collapsedMinimumWidth)
            .frame(height: ProblemPickerMetrics.wheelRowHeight)
            .contentShape(.rect)
            .onTapGesture { model.expandWheel() }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("problemPickerValue")
            .accessibilityLabel("Problem tag")
            .accessibilityValue(model.collapsedLabel)
            .accessibilityHint("Opens the problem new ink is filed under")
    }

    /// The one control that is in the bar either way, so there is always
    /// somewhere to press to put the wheel away again.
    private var disclosureChevron: some View {
        Image(systemName: "chevron.down")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(model.isWheelExpanded ? 180 : 0))
            .frame(width: 20)
            .contentShape(.rect)
            .onTapGesture { model.toggleWheel() }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("problemPickerCollapsed")
            .accessibilityLabel("Problem tag")
            .accessibilityValue(model.collapsedLabel)
            .accessibilityHint("Opens the problem new ink is filed under")
    }

    /// Marks the middle row as the one being read. Two small carets rather than
    /// a band behind it: the drums sit half on the bar and half on the tongue,
    /// and a filled row spanning that seam draws attention to the join instead
    /// of to the value.
    private func caret(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(.tertiary)
            .frame(height: ProblemPickerMetrics.wheelRowHeight)
            .offset(x: systemImage == "chevron.right" ? -7 : 7)
            .allowsHitTesting(false)
    }

    // MARK: - Open

    /// Laid out at full height — one row on the bar, two below it — because
    /// SwiftUI does not hit-test what hangs outside a view's own bounds, so
    /// anything drawn past the frame would simply stop taking taps.
    private var columns: some View {
        HStack(spacing: ProblemPickerMetrics.wheelColumnSpacing) {
            ForEach(0 ..< ProblemLevelNotation.maximumDepth, id: \.self) { level in
                ProblemWheelColumn(
                    level: level,
                    options: model.wheelOptions(atLevel: level),
                    selectedOptionID: model.selectedOptionID(atLevel: level),
                    onSelect: { optionID in model.selectOption(optionID, atLevel: level) },
                    deletionTitle: { optionID in deletionTitle(for: optionID, atLevel: level) },
                    onDelete: { optionID in model.deleteNode(optionID, atLevel: level) }
                )
            }
        }
    }

    private func deletionTitle(for optionID: Int, atLevel level: Int) -> String? {
        guard model.canDelete(optionID, atLevel: level) else { return nil }
        return model.deletionLabel(for: optionID, atLevel: level)
    }
}

private extension View {
    /// Reports this view's frame in a space of the caller's choosing.
    func measured(
        in space: NamedCoordinateSpace,
        onChange: @escaping (CGRect) -> Void
    ) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: space) } action: { onChange($0) }
    }
}
