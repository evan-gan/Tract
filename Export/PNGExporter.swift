import UIKit

/// Renders strokes as a PNG image using `UIGraphicsImageRenderer`.
struct PNGExporter: ExportAdapter {
    let fileExtension = "png"
    let mimeType = "image/png"
    let displayName = "PNG"

    func export(document: SplineDocument, viewport: CGRect?) throws -> Data {
        let strokes = StrokeRasterizer.inkStrokes(document.strokes, intersecting: viewport)
        guard !strokes.isEmpty else { throw ExportError.noStrokes }

        let bounds = viewport ?? StrokeRasterizer.inkedBounds(of: strokes)
        guard !bounds.isNull else { throw ExportError.noStrokes }

        return UIGraphicsImageRenderer(size: bounds.size).pngData { context in
            StrokeRasterizer.draw(strokes, in: context.cgContext, offset: bounds.origin)
        }
    }
}
