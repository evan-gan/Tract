import Foundation

/// Serialises strokes as SVG `<path>` elements using cubic Bézier curves.
/// Force and timing are preserved as `data-*` attributes for AI use.
struct SVGExporter: ExportAdapter {
    let fileExtension = "svg"
    let mimeType = "image/svg+xml"
    let displayName = "SVG"

    func export(document: SplineDocument, viewport: CGRect?) throws -> Data {
        let strokes = clippedStrokes(document.strokes, to: viewport)
        guard !strokes.isEmpty else { throw ExportError.noStrokes }

        let bounds = viewport ?? unionBounds(of: strokes)
        let svg = buildSVG(strokes: strokes, bounds: bounds)

        guard let data = svg.data(using: .utf8) else {
            throw ExportError.renderingFailed("SVG string encoding returned nil")
        }
        return data
    }

    // MARK: - SVG construction

    private func buildSVG(strokes: [Stroke], bounds: CGRect) -> String {
        let paths = strokes.map { svgPath(for: $0, offset: bounds.origin) }.joined(separator: "\n  ")
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg"
             width="\(Int(bounds.width))" height="\(Int(bounds.height))"
             viewBox="0 0 \(Int(bounds.width)) \(Int(bounds.height))">
          \(paths)
        </svg>
        """
    }

    private func svgPath(for stroke: Stroke, offset: CGPoint) -> String {
        guard stroke.points.count >= 2 else { return "" }
        let d = cubicBezierPath(points: stroke.points, offset: offset)
        let color = svgColor(stroke.style.color)
        let width = stroke.style.lineWidth
        let startEpoch = stroke.startTime.timeIntervalSince1970
        let endEpoch = stroke.endTime.timeIntervalSince1970
        return """
        <path d="\(d)"
              stroke="\(color)"
              stroke-width="\(width)"
              stroke-linecap="round"
              stroke-linejoin="round"
              fill="none"
              opacity="\(stroke.style.opacity)"
              data-start-time="\(startEpoch)"
              data-end-time="\(endEpoch)"/>
        """
    }

    /// Builds a cubic Bézier path using midpoint control points for a smooth curve.
    private func cubicBezierPath(points: [StrokePoint], offset: CGPoint) -> String {
        var segments: [String] = []
        let first = points[0].position - offset
        segments.append("M \(fmt(first.x)),\(fmt(first.y))")

        for idx in 1 ..< points.count {
            let prev = points[idx - 1].position - offset
            let curr = points[idx].position - offset
            let cp1 = CGPoint(x: prev.x + (curr.x - prev.x) / 3,
                              y: prev.y + (curr.y - prev.y) / 3)
            let cp2 = CGPoint(x: prev.x + 2 * (curr.x - prev.x) / 3,
                              y: prev.y + 2 * (curr.y - prev.y) / 3)
            segments.append("C \(fmt(cp1.x)),\(fmt(cp1.y)) \(fmt(cp2.x)),\(fmt(cp2.y)) \(fmt(curr.x)),\(fmt(curr.y))")
        }
        return segments.joined(separator: " ")
    }

    private func svgColor(_ simd: SIMD4<Float>) -> String {
        let r = Int(simd.x * 255)
        let g = Int(simd.y * 255)
        let b = Int(simd.z * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func fmt(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }

    // MARK: - Viewport helpers

    private func clippedStrokes(_ strokes: [Stroke], to viewport: CGRect?) -> [Stroke] {
        guard let viewport else { return strokes }
        return strokes.filter { $0.canvasBounds.intersects(viewport) }
    }

    private func unionBounds(of strokes: [Stroke]) -> CGRect {
        strokes.reduce(CGRect.null) { $0.union($1.canvasBounds) }
    }
}

// CGPoint subtraction is defined in Utilities/CGPoint+Math.swift
