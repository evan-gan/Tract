import UIKit

/// Renders strokes as a PNG image using `UIGraphicsImageRenderer`.
struct PNGExporter: ExportAdapter {
    let fileExtension = "png"
    let mimeType = "image/png"
    let displayName = "PNG"

    func export(document: SplineDocument, viewport: CGRect?) throws -> Data {
        let strokes = viewport.map { vp in document.strokes.filter { $0.canvasBounds.intersects(vp) } }
            ?? document.strokes
        guard !strokes.isEmpty else { throw ExportError.noStrokes }

        let bounds = viewport ?? unionBounds(of: strokes)
        let renderer = UIGraphicsImageRenderer(size: bounds.size)

        return renderer.pngData { context in
            context.cgContext.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            drawStrokes(strokes, in: context.cgContext)
        }
    }

    private func drawStrokes(_ strokes: [Stroke], in cgContext: CGContext) {
        for stroke in strokes {
            guard stroke.points.count >= 2 else { continue }
            let path = buildPath(for: stroke)
            let color = cgColor(from: stroke.style.color, opacity: stroke.style.opacity)
            cgContext.setStrokeColor(color)
            cgContext.setLineWidth(stroke.style.lineWidth)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            cgContext.addPath(path)
            cgContext.strokePath()
        }
    }

    private func buildPath(for stroke: Stroke) -> CGPath {
        let path = CGMutablePath()
        let points = stroke.points.map(\.position)
        path.move(to: points[0])
        for idx in 1 ..< points.count {
            path.addLine(to: points[idx])
        }
        return path
    }

    private func cgColor(from simd: SIMD4<Float>, opacity: CGFloat) -> CGColor {
        CGColor(
            red: CGFloat(simd.x),
            green: CGFloat(simd.y),
            blue: CGFloat(simd.z),
            alpha: CGFloat(simd.w) * opacity
        )
    }

    private func unionBounds(of strokes: [Stroke]) -> CGRect {
        strokes.reduce(CGRect.null) { $0.union($1.canvasBounds) }
    }
}
