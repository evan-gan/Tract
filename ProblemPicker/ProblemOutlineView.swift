import SwiftUI

/// The outline popover: the whole tree, and the only place it can be
/// reorganised. There are no add or delete controls in here — a row is tapped
/// to select it and dragged to move it, and that is the entire list.
struct ProblemOutlineView: View {
    let model: ProblemTaggingModel

    @State private var drag: ProblemOutlineDrag?
    /// Fills over the hold that changes a drag's level. Driven by an animation
    /// rather than a ticking clock so the bar cannot fall behind the timer that
    /// actually applies the change.
    @State private var levelChangeProgress: CGFloat = 0
    @State private var lastDropTime: Date?

    private static let listSpace = "problemOutlineList"

    private var rows: [ProblemOutlineRow] { model.outline.rows }

    var body: some View {
        Group {
            if rows.isEmpty {
                emptyNotice
            } else {
                list
            }
        }
        .frame(width: ProblemPickerMetrics.outlineWidth)
        .frame(maxHeight: ProblemPickerMetrics.outlineMaxHeight)
    }

    private var emptyNotice: some View {
        Text("Tap the number to start problem 1.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(20)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row).id(row.id)
                    }
                }
                // The drag lives on the list, not on the rows: a gesture sharing
                // a view with a tap makes the tap unreliable, and the row a
                // press started on is just its y over the uniform row height.
                .simultaneousGesture(dragGesture)
                .coordinateSpace(.named(Self.listSpace))
                .overlay(alignment: .topLeading) { insertionLine }
                .overlay(alignment: .topLeading) { dragChip }
                .background { levelChangeHold }
            }
            .scrollDisabled(drag != nil)
            .padding(.vertical, 8)
            // Opening onto the part of the tree the user is working in matters
            // more than the top of the list — a long outline otherwise opens
            // nowhere near the selection.
            .onAppear { proxy.scrollTo(model.selectedNodeID, anchor: .center) }
        }
    }

    /// A button rather than a tap gesture: a tap gesture sharing this list with
    /// the drag below never fired reliably.
    private func rowView(_ row: ProblemOutlineRow) -> some View {
        Button {
            selectRow(row)
        } label: {
            ProblemOutlineRowView(
                row: row,
                isSelected: row.id == model.selectedNodeID,
                isBeingDragged: drag?.carriedIDs.contains(row.id) ?? false,
                levelChangeProgress: pendingLevelRowID == row.id ? levelChangeProgress : nil
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Dragging

    /// A brief press before the drag takes over. Without it the gesture would
    /// win every touch that starts on a row and the list could never be
    /// scrolled; a scroll flick moves long before the press completes, so it
    /// still reaches the scroll view untouched.
    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.18, maximumDistance: ProblemPickerMetrics.dragThreshold)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.listSpace)))
            .onChanged { value in
                guard case .second(true, let dragValue?) = value else { return }
                updateDrag(startingAt: dragValue.startLocation.y, pointerY: dragValue.location.y)
            }
            .onEnded { _ in commitDrag() }
    }

    /// Picks up whichever row the press began over, then follows the pointer.
    private func updateDrag(startingAt startY: CGFloat, pointerY: CGFloat) {
        guard drag == nil else {
            drag?.pointerY = pointerY
            return
        }
        let index = Int(startY / ProblemPickerMetrics.rowHeight)
        guard rows.indices.contains(index) else { return }
        drag = ProblemOutlineDrag(row: rows[index], in: model.outline, pointerY: pointerY)
    }

    private func commitDrag() {
        defer { drag = nil }
        guard let drag else { return }
        model.moveNode(at: drag.path, to: drag.target(displayedRows: rows))
        lastDropTime = .now
    }

    /// A drop and a row tap end the same touch, and the button under the finger
    /// fires on release either way. The moved node is already selected by then,
    /// so a tap arriving on the heels of a drop would undo that choice.
    private func selectRow(_ row: ProblemOutlineRow) {
        if let lastDropTime, Date.now.timeIntervalSince(lastDropTime) < 0.4 { return }
        model.select(row.path)
    }

    // MARK: - Drop feedback

    /// Indented to the level the node would land at, so the line itself says how
    /// deep the drop is rather than only where it is.
    @ViewBuilder
    private var insertionLine: some View {
        if let drag {
            let target = drag.target(displayedRows: rows)
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.accentColor)
                .frame(height: 2)
                .padding(.leading, CGFloat(target.level) * ProblemPickerMetrics.levelGutter + 6)
                .offset(y: CGFloat(drag.displayedGap(rowCount: rows.count)) * ProblemPickerMetrics.rowHeight - 1)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var dragChip: some View {
        if let drag {
            HStack(spacing: 4) {
                Text(drag.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                if drag.childCount > 0 {
                    Text("+\(drag.childCount)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .opacity(0.75)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // Solid rather than glass: this floats *inside* the popover's own
            // glass, and glass over glass has nothing left to sample.
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(AppTint.active))
            .offset(x: 26, y: drag.pointerY - ProblemPickerMetrics.rowHeight / 2)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Changing level mid-drag

    private var pendingLevelRowID: UUID? {
        guard drag?.pendingLevel(displayedRows: rows) != nil else { return nil }
        return drag?.hoveredRow(displayedRows: rows)?.id
    }

    /// Restarts whenever the hovered row or the pending level changes, which is
    /// exactly the reset rule the hold needs: sliding onto a different row starts
    /// the two seconds again rather than inheriting someone else's progress.
    private var levelChangeHoldKey: String {
        "\(pendingLevelRowID?.uuidString ?? "none")-\(drag?.pendingLevel(displayedRows: rows) ?? -1)"
    }

    private var levelChangeHold: some View {
        Color.clear.task(id: levelChangeHoldKey) { await runLevelChangeHold() }
    }

    private func runLevelChangeHold() async {
        levelChangeProgress = 0
        guard let pending = drag?.pendingLevel(displayedRows: rows) else { return }
        withAnimation(.linear(duration: ProblemPickerMetrics.levelChangeHoldSeconds)) {
            levelChangeProgress = 1
        }
        try? await Task.sleep(for: ProblemPickerMetrics.levelChangeHold)
        guard !Task.isCancelled else { return }
        // Adopted for the rest of the drag, so the user can now slide freely and
        // only the position changes.
        drag?.level = pending
        levelChangeProgress = 0
    }
}
