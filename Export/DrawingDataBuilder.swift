import CoreGraphics
import Foundation
import UIKit

/// Turns an open document into the published `DrawingDataExport` shape.
///
/// Kept apart from `JSONExporter` so the mapping can be tested on its values
/// rather than by parsing bytes back out of a file, and so a second serialisation
/// of the same data — NDJSON, msgpack, a debug dump — needs no second mapping.
enum DrawingDataBuilder {
    /// - Parameters:
    ///   - document: The document to describe. Its strokes are taken as they are:
    ///     nothing is filtered, because a consumer analysing input cannot ask for
    ///     the samples a rasteriser decided were not worth painting.
    ///   - viewport: If non-nil, only strokes touching this canvas-space rect are
    ///     included — the same clipping every other exporter applies.
    ///   - exportedAt: Stamped into the file. A parameter so a test can pin it.
    static func makeExport(
        from document: SplineDocument,
        viewport: CGRect? = nil,
        exportedAt: Date = .now,
        formatter: ProblemTagFormatter = .standard
    ) -> DrawingDataExport {
        let strokes = StrokeRasterizer.strokes(document.strokes, intersecting: viewport)
        let outline = document.problemOutline
        return DrawingDataExport(
            exportedAt: exportedAt,
            document: documentInfo(for: document, strokes: strokes),
            problems: problemNodes(under: [], in: outline, formatter: formatter),
            strokes: strokes.enumerated().map { index, stroke in
                exportedStroke(stroke, index: index, outline: outline, formatter: formatter)
            }
        )
    }

    // MARK: - Document

    private static func documentInfo(
        for document: SplineDocument,
        strokes: [Stroke]
    ) -> ExportedDocumentInfo {
        let metadata = document.metadata
        return ExportedDocumentInfo(
            id: metadata.id,
            title: metadata.title,
            createdAt: metadata.createdAt,
            modifiedAt: metadata.modifiedAt,
            strokeCount: strokes.count,
            canvasOrigin: ExportedPoint(metadata.canvasOrigin),
            canvasScale: metadata.canvasScale,
            // Painted bounds, so a consumer laying the drawing out on a page gets
            // the same box Tract's own PNG and PDF exports fit to.
            inkBounds: ExportedRect(StrokeRasterizer.inkedBounds(of: StrokeRasterizer.inkStrokes(strokes)))
        )
    }

    // MARK: - Problems

    /// The subtree under `parentPath`, depth first. Labels are resolved here
    /// rather than stored, exactly as they are everywhere else in the app.
    private static func problemNodes(
        under parentPath: ProblemPath,
        in outline: ProblemOutline,
        formatter: ProblemTagFormatter
    ) -> [ExportedProblemNode] {
        outline.children(under: parentPath).enumerated().map { siblingIndex, node in
            let path = parentPath + [siblingIndex]
            let tag = outline.tag(at: path)
            return ExportedProblemNode(
                id: node.id,
                label: outline.label(at: path) ?? "",
                tag: formatter.text(for: tag),
                path: path,
                components: components(of: tag, formatter: formatter),
                children: problemNodes(under: path, in: outline, formatter: formatter)
            )
        }
    }

    private static func components(
        of tag: ProblemTag,
        formatter: ProblemTagFormatter
    ) -> [ExportedTagComponent] {
        tag.components.map { component in
            ExportedTagComponent(
                styleID: component.styleID,
                ordinal: component.ordinal,
                customText: component.customText,
                text: formatter.text(for: component)
            )
        }
    }

    /// A stroke's tag as it reads today. A node id whose node has been deleted
    /// keeps the id — it is the only record of what the stroke once belonged to —
    /// and reports no address, which is how the rest of the app treats it too.
    private static func problemReference(
        for stroke: Stroke,
        outline: ProblemOutline,
        formatter: ProblemTagFormatter
    ) -> ExportedProblemReference? {
        guard let nodeID = stroke.problemNodeID else { return nil }
        guard let path = outline.path(ofNode: nodeID) else {
            return ExportedProblemReference(nodeID: nodeID, tag: nil, path: nil, components: nil)
        }
        let tag = outline.tag(at: path)
        return ExportedProblemReference(
            nodeID: nodeID,
            tag: formatter.text(for: tag),
            path: path,
            components: components(of: tag, formatter: formatter)
        )
    }

    // MARK: - Strokes

    private static func exportedStroke(
        _ stroke: Stroke,
        index: Int,
        outline: ProblemOutline,
        formatter: ProblemTagFormatter
    ) -> ExportedStroke {
        // Every sample's offset is measured from the first one that carries a
        // clock, not from the first sample outright: a stroke saved by an older
        // build has no clock at all, and one point missing it must not shift the
        // rest of the stroke's timeline.
        let strokeStartTimestamp = stroke.points.compactMap(\.timestamp).first
        return ExportedStroke(
            id: stroke.id,
            sessionID: stroke.sessionID,
            index: index,
            startTime: stroke.startTime,
            endTime: stroke.endTime,
            durationSeconds: stroke.endTime.timeIntervalSince(stroke.startTime),
            isComplete: stroke.isComplete,
            style: exportedStyle(stroke.style),
            bounds: ExportedRect(stroke.canvasBounds),
            problem: problemReference(for: stroke, outline: outline, formatter: formatter),
            pointCount: stroke.points.count,
            points: stroke.points.map { exportedPoint($0, strokeStartTimestamp: strokeStartTimestamp) }
        )
    }

    private static func exportedStyle(_ style: StrokeStyle) -> ExportedStrokeStyle {
        ExportedStrokeStyle(
            tool: style.tool.rawValue,
            color: ExportedColor(
                red: style.color.x,
                green: style.color.y,
                blue: style.color.z,
                alpha: style.color.w
            ),
            colorHex: hexString(for: style.color),
            lineWidth: style.lineWidth,
            opacity: style.opacity
        )
    }

    private static func exportedPoint(
        _ point: StrokePoint,
        strokeStartTimestamp: TimeInterval?
    ) -> ExportedStrokePoint {
        let timeOffset: TimeInterval? = if let timestamp = point.timestamp, let strokeStartTimestamp {
            timestamp - strokeStartTimestamp
        } else {
            nil
        }
        return ExportedStrokePoint(
            x: point.position.x,
            y: point.position.y,
            force: point.force,
            azimuth: point.azimuth,
            altitude: point.altitude,
            rollAngle: point.rollAngle,
            timeOffset: timeOffset,
            deviceTimestamp: point.timestamp,
            estimatedProperties: estimatedPropertyNames(point.estimatedProperties)
        )
    }

    /// Names rather than the raw bitmask: the mask is a UIKit constant a reader
    /// outside this app has no way to look up.
    static func estimatedPropertyNames(_ properties: UITouch.Properties) -> [String] {
        let namesByProperty: [(UITouch.Properties, String)] = [
            (.force, "force"),
            (.azimuth, "azimuth"),
            (.altitude, "altitude"),
            (.location, "location")
        ]
        return namesByProperty.filter { properties.contains($0.0) }.map(\.1)
    }

    private static func hexString(for color: SIMD4<Float>) -> String {
        let channel = { (value: Float) in Int((max(0, min(1, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", channel(color.x), channel(color.y), channel(color.z))
    }
}
