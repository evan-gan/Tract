import UIKit

/// Renders strokes as a PDF using `UIGraphicsPDFRenderer`.
struct PDFExporter: ExportAdapter {
    let fileExtension = "pdf"
    let mimeType = "application/pdf"
    let displayName = "PDF"

    func export(document: SplineDocument, viewport: CGRect?) throws -> Data {
        let strokes = viewport.map { vp in document.strokes.filter { $0.canvasBounds.intersects(vp) } }
            ?? document.strokes
        guard !strokes.isEmpty else { throw ExportError.noStrokes }

        let bounds = viewport ?? unionBounds(of: strokes)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds)

        return renderer.pdfData { context in
            context.beginPage()
            drawStrokes(strokes, in: context.cgContext, offset: bounds.origin)
        }
    }

    private func drawStrokes(_ strokes: [Stroke], in cgContext: CGContext, offset: CGPoint) {
        for stroke in strokes {
            guard stroke.points.count >= 2 else { continue }
            let path = buildPath(for: stroke, offset: offset)
            let color = cgColor(from: stroke.style.color, opacity: stroke.style.opacity)
            cgContext.setStrokeColor(color)
            cgContext.setLineWidth(stroke.style.lineWidth)
            cgContext.setLineCap(.round)
            cgContext.setLineJoin(.round)
            cgContext.addPath(path)
            cgContext.strokePath()
        }
    }

    private func buildPath(for stroke: Stroke, offset: CGPoint) -> CGPath {
        let path = CGMutablePath()
        let points = stroke.points.map { $0.position - offset }
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

// CGPoint subtraction is defined in Utilities/CGPoint+Math.swift
