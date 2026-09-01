import SwiftUI

/// One drum of the problem picker: a vertical list of values that snaps to the
/// one sitting on the bar's own row, with the values after it fading away
/// beneath.
///
/// The selected value sits in the **middle** of the column, with the value
/// before it and the value after it either side — the point of a drum is that
/// its neighbours are readable. The row above the selection is the one that
/// lands on the bar itself, so the control still only opens two rows deep.
///
/// It is a `ScrollView` rather than anything hand-rolled on gestures, and that
/// is the point. A scroll view is UIKit's own touch handling, so a finger and an
/// Apple Pencil both drive it with the same physics for free — where the
/// picker's previous hand-written drag had to decide, itself, what every touch
/// on the top chrome meant.
struct ProblemWheelColumn: View {
    /// 0, 1 or 2 — numbers, letters, numerals. Carried for the accessibility
    /// identifier, whose value has to be stable while the labels move.
    let level: Int
    let options: [ProblemWheelOption]
    /// The row the model says this column is parked on.
    let selectedOptionID: Int
    let onSelect: (Int) -> Void
    /// The address a row would delete ("1.b"), or nil for a row that addresses
    /// nothing yet — the dash and the uncreated row have nothing to remove.
    let deletionTitle: (Int) -> String?
    let onDelete: (Int) -> Void

    /// The row a long press has opened the delete confirmation on.
    @State private var rowBeingDeleted: ProblemWheelOption?
    /// The content offset seen on the last frame. Read at the end of a gesture
    /// as the place the hand left the drum, before deceleration is added on.
    @State private var liveOffset: CGFloat = 0
    /// The drag in flight, if a hand is driving the column. Scroll targets are
    /// also resolved during ordinary layout and while the column animates itself
    /// to a row the model chose — landings from those must not be reported back
    /// as choices, or a column mid-animation re-selects whatever row it passes.
    @State private var dragStartOffset: CGFloat?

    var body: some View {
        ScrollViewReader { scroller in
            column
                .onChange(of: selectedOptionID) { scroll(scroller, animated: true) }
                // The rows themselves change when a level above moves, which can
                // leave the column parked on a row that no longer exists.
                .onChange(of: options) { scroll(scroller, animated: false) }
                .onAppear { scroll(scroller, animated: false) }
        }
    }

    /// The drum itself. Deliberately *not* driven by `scrollPosition(id:)`: a
    /// bound position fights a short drag — it pins the column back to the row
    /// it already holds, so the first small turn of the wheel does nothing and
    /// the value only moves on the second. The landing comes from the scroll
    /// behaviour instead, which is the one place that knows where the gesture
    /// is going to stop.
    private var column: some View {
        ScrollView(.vertical) {
            LazyVStack(spacing: 0) {
                ForEach(options) { option in
                    row(for: option)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(ProblemWheelScrollBehavior(
            rowHeight: ProblemPickerMetrics.wheelRowHeight,
            rowCount: options.count,
            drag: dragStartOffset.map {
                ProblemWheelScrollBehavior.Drag(startOffset: $0, offsetAtLift: liveOffset)
            },
            onLanding: commit(rowIndex:)
        ))
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            // Put into the same space the scroll *target* is measured in: the
            // content offset counts from inside the top margin, and that margin
            // is half a column tall — enough that mixing the two spaces sent
            // every drag a row and a half wide of where it belonged.
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, offset in
            liveOffset = offset
        }
        .scrollIndicators(.hidden)
        // Lets the first and last rows reach the middle of the column.
        .contentMargins(.vertical, edgeInset, for: .scrollContent)
        .frame(width: ProblemPickerMetrics.wheelColumnWidth, height: ProblemPickerMetrics.wheelHeight)
        .mask(edgeFade)
        .sensoryFeedback(.selection, trigger: selectedOptionID)
        .onScrollPhaseChange { previousPhase, phase in
            if previousPhase == .idle, phase == .tracking || phase == .interacting {
                dragStartOffset = liveOffset
            }
            if phase == .idle || phase == .animating { dragStartOffset = nil }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("problemWheel\(level)")
        .accessibilityLabel(Self.accessibilityLabels[level] ?? "Problem level \(level + 1)")
        .accessibilityValue(selectedLabel)
    }

    // MARK: - Rows

    /// Deliberately not a `Button`: a button's own tap and a long press on the
    /// same row fight over the touch, and a long press that both deletes *and*
    /// selects is the last thing this control should do.
    private func row(for option: ProblemWheelOption) -> some View {
        Text(option.label)
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(textStyle(for: option))
            .frame(
                width: ProblemPickerMetrics.wheelColumnWidth,
                height: ProblemPickerMetrics.wheelRowHeight
            )
            .contentShape(.rect)
            .id(option.id)
            .onTapGesture { onSelect(option.id) }
            // Simultaneous, and cancelled by movement: a long press that
            // *competes* for the touch eats the first drag on the column, which
            // is the difference between a wheel that turns and one that needs
            // two swipes to move a value.
            .simultaneousGesture(
                LongPressGesture(
                    minimumDuration: ProblemPickerMetrics.deleteHoldSeconds,
                    maximumDistance: ProblemPickerMetrics.deleteHoldMovement
                )
                .onEnded { _ in
                    guard deletionTitle(option.id) != nil else { return }
                    rowBeingDeleted = option
                }
            )
            .popover(item: deletionBinding(for: option), arrowEdge: .leading) { row in
                ProblemDeleteConfirmationView(
                    title: deletionTitle(row.id) ?? "",
                    onDelete: {
                        rowBeingDeleted = nil
                        onDelete(row.id)
                    }
                )
            }
            .scrollTransition(.interactive, axis: .vertical) { row, phase in
                row
                    .opacity(1 - abs(phase.value) * 0.45)
                    .scaleEffect(1 - abs(phase.value) * 0.14)
            }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(option.label)
            .accessibilityIdentifier("problemWheelOption-\(level)-\(identifierSuffix(for: option))")
            .accessibilityHint(rowHint(for: option))
    }

    /// One popover, on the row it belongs to. The state is shared by every row
    /// in the column, so each has to filter it down to itself or all three would
    /// try to present at once.
    private func deletionBinding(for option: ProblemWheelOption) -> Binding<ProblemWheelOption?> {
        Binding(
            get: { rowBeingDeleted?.id == option.id ? rowBeingDeleted : nil },
            set: { rowBeingDeleted = $0 }
        )
    }

    /// A value that does not exist yet is drawn faintly, so the row that *makes*
    /// a problem never looks like one the user already wrote.
    private func textStyle(for option: ProblemWheelOption) -> AnyShapeStyle {
        option.isUncreated || option.id == ProblemWheelOption.noneID
            ? AnyShapeStyle(.tertiary)
            : AnyShapeStyle(.primary)
    }

    private func identifierSuffix(for option: ProblemWheelOption) -> String {
        option.id == ProblemWheelOption.noneID ? "none" : option.label
    }

    private func rowHint(for option: ProblemWheelOption) -> String {
        if option.isUncreated { return "Not created yet — picking it adds it" }
        if deletionTitle(option.id) != nil { return "Hold to delete" }
        return ""
    }

    // MARK: - Scroll position

    /// Points the model at the row the scroll has decided to rest on — only for
    /// a scroll a hand is driving. See `dragStartOffset`.
    private func commit(rowIndex: Int) {
        guard dragStartOffset != nil,
              let option = options[safe: rowIndex],
              option.id != selectedOptionID
        else { return }
        onSelect(option.id)
    }

    /// Brings the selected row back between the carets — after a tap on a row
    /// off centre, or after a level above this one moved.
    private func scroll(_ scroller: ScrollViewProxy, animated: Bool) {
        withAnimation(animated ? .easeOut(duration: 0.2) : nil) {
            scroller.scrollTo(selectedOptionID, anchor: .center)
        }
    }

    // MARK: - Appearance

    private var edgeInset: CGFloat {
        (ProblemPickerMetrics.wheelHeight - ProblemPickerMetrics.wheelRowHeight) / 2
    }

    /// The neighbours recede rather than being cut off, which is what makes a
    /// flat list read as a drum — and keeps the selected row the one the eye
    /// lands on without a slab of colour behind it.
    private var edgeFade: some View {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0.35), location: 0),
                .init(color: .black, location: 0.3),
                .init(color: .black, location: 0.7),
                .init(color: .black.opacity(0.35), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var selectedLabel: String {
        options.first { $0.id == selectedOptionID }?.label ?? ProblemWheelOption.noneLabel
    }

    private static let accessibilityLabels: [Int: String] = [
        0: "Problem",
        1: "Part",
        2: "Sub-part"
    ]
}
