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
        CanvasBackgroundView()
            .ignoresSafeArea()
    }

    /// All floating controls. They share a single `GlassEffectContainer` because
    /// glass cannot sample other glass — separate containers would render the
    /// surfaces inconsistently and cost one backdrop layer each.
    private var overlayChrome: some View {
        ZStack {
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

            // Selection chrome tracks canvas content, so it stays outside the
            // glass container and never takes a glass material.
            if viewModel.isSelectionMode {
                SelectionBoxView(selectedStrokes: selectedStrokes())
            }
        }
    }

    /// Title bar centred, zoom pill pinned trailing. Keeping both in one fixed
    /// row leaves every other edge free for the movable dock.
    private var topChromeRow: some View {
        ZStack {
            TopBarView(
                viewModel: viewModel,
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

    private func selectedStrokes() -> [Stroke] {
        viewModel.strokes.filter { viewModel.selectedStrokeIDs.contains($0.id) }
    }

    private func currentDocument() -> SplineDocument {
        SplineDocument(
            title: "Untitled",
            strokes: viewModel.strokes,
            canvasOrigin: viewModel.canvasTransform.translation,
            canvasScale: viewModel.canvasTransform.scale
        )
    }
}

// MARK: - Canvas background

/// Draws the warm off-white canvas with dot grid and faint large grid.
private struct CanvasBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            let backgroundColor: Color = colorScheme == .dark ? Color(hex: "#141414")! : Color(hex: "#f5f4f0")!
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(backgroundColor))
            drawDotGrid(in: &context, size: size)
        }
    }

    private func drawDotGrid(in context: inout GraphicsContext, size: CGSize) {
        let dotSpacing: CGFloat = 24
        let dotRadius: CGFloat = 1
        let dotColor: Color = colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.08)

        var x: CGFloat = dotSpacing
        while x < size.width {
            var y: CGFloat = dotSpacing
            while y < size.height {
                let dot = Path(ellipseIn: CGRect(x: x - dotRadius, y: y - dotRadius,
                                                  width: dotRadius * 2, height: dotRadius * 2))
                context.fill(dot, with: .color(dotColor))
                y += dotSpacing
            }
            x += dotSpacing
        }
    }
}

#Preview {
    CanvasContainerView()
}
