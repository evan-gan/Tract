import SwiftUI

/// Root of the drawing screen. The only view that imports from multiple feature folders.
/// It composes every major UI region without containing logic of its own.
struct CanvasContainerView: View {
    /// Owns the open document: loading, autosaving, and the title.
    let session: DocumentEditorSession
    /// Closes the canvas and returns to the document library.
    var onClose: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase

    private var viewModel: CanvasViewModel { session.viewModel }

    /// Shared by every chrome surface so they morph into one another instead of
    /// cross-fading when panels open and close.
    @Namespace private var glassNamespace

    /// Measured so a top-parked dock can settle below the title row.
    @State private var topChromeHeight: CGFloat = 0

    var body: some View {
        ZStack {
            canvasBackground
            CanvasRenderer(
                strokes: viewModel.strokes,
                activeStroke: viewModel.activeStroke,
                transform: viewModel.canvasTransform,
                selectedStrokeIDs: viewModel.selectedStrokeIDs,
                selectionOffset: viewModel.selectionDragOffset,
                problemInk: viewModel.problemInkStyling
            )
            .ignoresSafeArea()
            CanvasView(viewModel: viewModel)
                .ignoresSafeArea()
            // Sits above the touch layer but passes every touch through, so the
            // lasso keeps tracking while its own outline is on screen.
            selectionOverlay
                .ignoresSafeArea()
            pencilHoverPreview
                .ignoresSafeArea()
            // Chrome deliberately keeps the safe area: it is what stops the
            // dock from parking under the status bar or the home indicator.
            overlayChrome
        }
        .overlay { loadFailureNotice }
        .task { await session.load() }
        // The canvas is the only writer, so every edit has to be handed to the
        // session here — nothing else is watching the view model.
        .onChange(of: viewModel.revision) { session.markEdited() }
        // Backgrounding is the last moment before the app can be killed without
        // warning, so it flushes rather than waiting out the autosave timer.
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active else { return }
            Task { await session.saveNow() }
        }
    }

    // MARK: - Sub-regions

    private var canvasBackground: some View {
        CanvasBackgroundView(transform: viewModel.canvasTransform)
            .ignoresSafeArea()
    }

    /// All floating controls. They share a single `GlassEffectContainer` because
    /// glass cannot sample other glass — separate containers would render the
    /// surfaces inconsistently and cost one backdrop layer each.
    private var overlayChrome: some View {
        GlassEffectContainer(spacing: 20) {
            ZStack {
                VStack {
                    topChromeRow
                    Spacer()
                }

                FloatingToolDock(
                    viewModel: viewModel,
                    glassNamespace: glassNamespace,
                    topReserved: topChromeHeight
                )
            }
        }
    }

    /// Lasso and selection chrome track canvas content rather than the screen,
    /// so they stay outside the glass container and never take a glass material.
    private var selectionOverlay: some View {
        ZStack {
            if !viewModel.lassoPath.isEmpty {
                LassoPathView(
                    canvasPoints: viewModel.lassoPath,
                    transform: viewModel.canvasTransform
                )
            }
            if viewModel.hasSelection {
                SelectionOutlineView(
                    selectedStrokes: viewModel.selectedStrokes,
                    transform: viewModel.canvasTransform,
                    standoff: viewModel.selectionStandoff,
                    dragOffset: viewModel.selectionDragOffset
                )
            }
            if let menuAnchor = viewModel.selectionMenuAnchor {
                SelectionActionMenuView(
                    anchor: menuAnchor + viewModel.selectionDragOffset,
                    transform: viewModel.canvasTransform,
                    actions: selectionActions
                )
            }
        }
    }

    /// What the selection's floating menu offers. Held here rather than in the
    /// menu so the menu stays a presentation of whatever actions it is handed.
    private var selectionActions: [SelectionAction] {
        [
            SelectionAction(
                title: "Delete",
                systemImage: "trash",
                isDestructive: true,
                perform: viewModel.deleteSelection
            )
        ]
    }

    /// The nib preview tracks the pencil rather than the chrome, so like the
    /// selection layer it stays out of the glass container.
    @ViewBuilder
    private var pencilHoverPreview: some View {
        if let hoverLocation = viewModel.pencilHoverLocation {
            PencilHoverDotView(
                location: hoverLocation,
                diameter: viewModel.pencilPreviewDiameter,
                color: viewModel.pencilPreviewColor
            )
        }
    }

    /// Title bar centred, zoom pill pinned trailing. Keeping both in one fixed
    /// row leaves every other edge free for the movable dock.
    private var topChromeRow: some View {
        ZStack(alignment: .top) {
            TopBarView(
                title: Binding(get: { session.title }, set: { session.title = $0 }),
                isSaving: session.hasUnsavedChanges,
                glassNamespace: glassNamespace,
                onClose: closeDocument,
                makeDocument: currentDocument,
                problems: viewModel.problems,
                // The bar only: the problem wheel hangs out of its underside
                // when open, and the dock must not slide down the screen with it.
                onBarHeightChange: { topChromeHeight = $0 + Self.topChromeInset }
            )

            HStack {
                Spacer()
                ZoomIndicatorView(
                    scale: viewModel.canvasTransform.scale,
                    onReset: viewModel.resetZoom
                )
                .glassEffectID("zoomIndicator", in: glassNamespace)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, Self.topChromeInset)
    }

    /// Space above the top chrome, and the part of `topChromeHeight` the bar
    /// itself cannot report.
    private static let topChromeInset: CGFloat = 12

    /// A document whose strokes could not be decoded is shown read-only rather
    /// than as a blank canvas — a blank canvas invites the user to draw on it and
    /// save the damage in place.
    @ViewBuilder
    private var loadFailureNotice: some View {
        if case .failed(let message) = session.loadState {
            ContentUnavailableView {
                Label("Couldn't open this document", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Back to Documents", action: onClose)
            }
            .background(.background)
        }
    }

    // MARK: - Actions

    private func closeDocument() {
        Task {
            await session.saveNow()
            onClose()
        }
    }

    // MARK: - Helpers

    /// Exports the live canvas, not the last save, so what leaves the app is what
    /// is on screen.
    private func currentDocument() -> SplineDocument {
        var metadata = session.metadata
        metadata.canvasOrigin = viewModel.canvasTransform.translation
        metadata.canvasScale = viewModel.canvasTransform.scale
        // The exporter groups by the tree, so a PDF must be laid out from the
        // outline as it stands now, not as it was at the last save.
        metadata.problemOutline = viewModel.problems.outline
        return SplineDocument(metadata: metadata, strokes: viewModel.strokes)
    }
}
