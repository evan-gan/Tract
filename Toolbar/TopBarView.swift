import SwiftUI

/// Document chrome at the top of the screen, on **one** piece of glass: back,
/// title, the saving dot, the problem tag, and Export.
///
/// One surface rather than three because they are one row of controls over the
/// page, and three pills reading left to right made the eye stop twice on the
/// way to a button. Selection lives on the lasso tool in the dock, undo and redo
/// on the movable dock.
///
/// Opening the problem wheel widens its segment — pushing the title and Export
/// aside — and hangs the rest of the drums out of the bar's underside on the
/// same surface. Nothing above the bar moves, and the bar keeps its height.
struct TopBarView: View {
    @Binding var title: String
    /// Drives the small "saving" dot. Saving is silent and automatic, so this
    /// is the only signal the user gets that their edit has been recorded.
    let isSaving: Bool
    let glassNamespace: Namespace.ID
    let onClose: () -> Void
    /// Handed to the export menu, which calls it only when a format is picked.
    let makeDocument: () -> SplineDocument
    /// The problem tree and the tag new ink is filed under.
    let problems: ProblemTaggingModel
    /// Height of the bar itself, reported so a dock parked at the top can settle
    /// under it. Deliberately *not* the height of the whole control: the wheel
    /// hanging open below must not shove the dock down the screen.
    var onBarHeightChange: (CGFloat) -> Void = { _ in }

    /// Where the drums sit, in the bar's own space — which is what the surface
    /// hangs its tongue from. Measured rather than assumed, because the segment
    /// moves whenever the title changes width.
    @State private var segmentFrame: CGRect = .zero

    /// The row every control in the bar is centred on. It is one wheel row tall,
    /// so the wheel's selected value lands exactly on it.
    private static let rowHeight = ProblemPickerMetrics.wheelRowHeight
    private static let verticalPadding: CGFloat = 8
    private static let horizontalPadding: CGFloat = 16
    private static var barHeight: CGFloat { rowHeight + verticalPadding * 2 }
    private static let coordinateSpace = "topBar"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            row { closeButton }
            row { separator }
            row { DocumentTitleView(title: $title) }
            row { SaveIndicatorView(isSaving: isSaving) }
            row { separator }
            wheelSegment
            row { separator }
            row {
                ExportMenu(makeDocument: makeDocument)
                    .glassEffectID("export", in: glassNamespace)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .padding(.vertical, Self.verticalPadding)
        .coordinateSpace(.named(Self.coordinateSpace))
        .glassChrome(shape: surface)
        .glassEffectID("topBar", in: glassNamespace)
        .animation(.smooth(duration: 0.28), value: problems.isWheelExpanded)
        .onAppear { onBarHeightChange(Self.barHeight) }
    }

    /// Every control but the wheel keeps to the bar's own row, so the row stays
    /// put when the wheel grows past it.
    private func row(@ViewBuilder _ content: () -> some View) -> some View {
        content().frame(height: Self.rowHeight)
    }

    /// The tongue hangs from the drums themselves, not from the whole segment:
    /// the chevron beside them stays on the bar, and a tongue reaching under it
    /// would be a lobe of glass with nothing in it.
    private var wheelSegment: some View {
        ProblemWheelSegment(
            model: problems,
            barSpace: .named(Self.coordinateSpace),
            onWheelFrameChange: { segmentFrame = $0 }
        )
    }

    /// The bar and the wheel's tongue as a single outline. The tongue's depth
    /// comes from the view's own height, so it grows with the expansion without
    /// the shape animating anything itself.
    private var surface: TopBarSurfaceShape {
        TopBarSurfaceShape(
            barHeight: Self.barHeight,
            tongue: problems.isWheelExpanded ? tongue : nil,
            barCornerRadius: 22,
            tongueCornerRadius: 18,
            jointRadius: 12
        )
    }

    private var tongue: TopBarSurfaceShape.Tongue {
        let padding = ProblemPickerMetrics.wheelPanelPadding
        return TopBarSurfaceShape.Tongue(
            minX: segmentFrame.minX - padding,
            maxX: segmentFrame.maxX + padding
        )
    }

    private var closeButton: some View {
        Button("Documents", systemImage: "chevron.backward", action: onClose)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
    }

    private var separator: some View {
        Divider().frame(height: 20)
    }
}
