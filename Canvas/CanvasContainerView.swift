import SwiftUI

/// Root of the drawing screen. The only view that imports from multiple feature folders.
/// It composes every major UI region without containing logic of its own.
struct CanvasContainerView: View {
    @State private var viewModel = CanvasViewModel()
    @State private var isExportSheetPresented = false

    var body: some View {
        ZStack {
            canvasBackground
            CanvasRenderer(
                strokes: viewModel.strokes,
                activeStroke: viewModel.activeStroke,
                transform: viewModel.canvasTransform
            )
            CanvasView(viewModel: viewModel)
            overlayChrome
        }
        .ignoresSafeArea()
        .sheet(isPresented: $isExportSheetPresented) {
            ExportSheetView(document: currentDocument())
        }
    }

    // MARK: - Sub-regions

    private var canvasBackground: some View {
        CanvasBackgroundView()
            .ignoresSafeArea()
    }

    private var overlayChrome: some View {
        ZStack {
            VStack {
                TopBarView(
                    viewModel: viewModel,
                    onExportTapped: { isExportSheetPresented = true }
                )
                .padding(.top, 12)
                Spacer()
            }

            HStack {
                PaletteView(viewModel: viewModel)
                    .padding(.leading, 12)
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    ZoomIndicatorView(
                        scale: viewModel.canvasTransform.scale,
                        onReset: viewModel.resetZoom
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
                }
            }

            if viewModel.isSelectionMode {
                SelectionBoxView(selectedStrokes: selectedStrokes())
            }
        }
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
