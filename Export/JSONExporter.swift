import Foundation

/// Writes everything Tract recorded about a drawing as JSON: every pencil sample
/// with its force, tilt, roll and timing, every stroke's colour, width, tool and
/// problem tag, and the problem tree those tags resolve against.
///
/// The other exporters all answer "what does this drawing look like" — they
/// rasterise, fit to a page, drop the eraser's paths and the taps too short to
/// paint. This one answers "what happened", and so throws nothing away: it is
/// the format for taking a real drawing out of the app and into a faster
/// environment to prototype layout or handwriting recognition against.
///
/// The shape it writes is `DrawingDataExport`, which is a versioned contract —
/// see that file before changing a field name.
struct JSONExporter: ExportAdapter {
    let fileExtension = "json"
    let mimeType = "application/json"
    /// Named for the file it produces rather than for what is in it, because it
    /// sits beside PDF and PNG in the export control and reads as one of a list.
    let displayName = "JSON"

    /// Renders problem tags as "1.b" rather than the worksheet's "1b": a
    /// consumer splitting an address back into levels should not have to know
    /// where one notation ends and the next begins.
    var tagFormatter: ProblemTagFormatter = .standard

    func export(document: SplineDocument, viewport: CGRect?) throws -> Data {
        let export = DrawingDataBuilder.makeExport(
            from: document,
            viewport: viewport,
            formatter: tagFormatter
        )
        guard !export.strokes.isEmpty else { throw ExportError.noStrokes }

        do {
            return try Self.encoder.encode(export)
        } catch {
            throw ExportError.renderingFailed("JSON encoding failed: \(error.localizedDescription)")
        }
    }

    /// Not pretty-printed: a page of handwriting is tens of thousands of samples,
    /// and indenting every one of them roughly doubles a file that is going to be
    /// read by a program anyway. `jq .` renders it for a human in one command.
    ///
    /// Keys are sorted so two exports of the same drawing differ only where the
    /// drawing does — everything but the `exportedAt` stamp lines up — which is
    /// what makes two of these worth diffing.
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}
