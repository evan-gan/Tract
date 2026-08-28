import SwiftUI

/// Root of the drawing screen. The only view that imports from multiple feature folders.
/// It composes every major UI region without containing logic of its own.
struct CanvasContainerView: View {
    /// Closes the canvas and returns to the document list.
    var onClose: () -> Void = {}

    @State private var viewModel = CanvasViewModel()
    @State private var isExportSheetPresented = false

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
                transform: viewModel.canvasTransform
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
        .sheet(isPresented: $isExportSheetPresented) {
            ExportSheetView(document: currentDocument())
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
                    transform: viewModel.canvasTransform
                )
            }
        }
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
        ZStack {
            TopBarView(
                glassNamespace: glassNamespace,
                onClose: onClose,
                onExportTapped: { isExportSheetPresented = true }
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
        .padding(.top, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { topChromeHeight = $0 }
    }

    // MARK: - Helpers

    private func currentDocument() -> SplineDocument {
        SplineDocument(
            title: "Untitled",
            strokes: viewModel.strokes,
            canvasOrigin: viewModel.canvasTransform.translation,
            canvasScale: viewModel.canvasTransform.scale
        )
    }
}

#Preview {
    CanvasContainerView()
}
