import SwiftUI

/// Blue selection rectangle + 8 resize handles, rendered above the canvas
/// when selection mode is active. Hidden entirely when no strokes are selected.
struct SelectionBoxView: View {
    let selectedStrokes: [Stroke]

    private static let handleSize: CGFloat = 10
    private static let selectionColor = Color(hex: "#3d6bff")!

    var body: some View {
        if let bounds = unionBounds() {
            selectionBox(bounds: bounds)
        }
    }

    private func selectionBox(bounds: CGRect) -> some View {
        ZStack {
            Rectangle()
                .strokeBorder(Self.selectionColor, lineWidth: 1.5)
                .frame(width: bounds.width, height: bounds.height)
                .position(x: bounds.midX, y: bounds.midY)

            ForEach(handlePositions(for: bounds), id: \.x) { point in
                handleCircle(at: point)
            }
        }
    }

    private func handleCircle(at point: CGPoint) -> some View {
        Circle()
            .fill(.white)
            .frame(width: Self.handleSize, height: Self.handleSize)
            .overlay { Circle().strokeBorder(Self.selectionColor, lineWidth: 1.5) }
            .position(point)
    }

    /// Union of all selected stroke bounding boxes in canvas space.
    private func unionBounds() -> CGRect? {
        guard !selectedStrokes.isEmpty else { return nil }
        return selectedStrokes.reduce(CGRect.null) { $0.union($1.canvasBounds) }
    }

    /// 8 handle positions: 4 corners + 4 edge midpoints.
    private func handlePositions(for bounds: CGRect) -> [CGPoint] {
        [
            CGPoint(x: bounds.minX, y: bounds.minY),
            CGPoint(x: bounds.midX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.minY),
            CGPoint(x: bounds.maxX, y: bounds.midY),
            CGPoint(x: bounds.maxX, y: bounds.maxY),
            CGPoint(x: bounds.midX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.maxY),
            CGPoint(x: bounds.minX, y: bounds.midY),
        ]
    }
}
