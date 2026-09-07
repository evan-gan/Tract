import CoreGraphics
import Foundation
import Testing
@testable import Tract

@Suite("Exporting a drawing as raw JSON data")
struct JSONExporterTests {
    @Test("The file is valid JSON that names its own format and version")
    func fileIdentifiesItself() throws {
        // A consumer that has only the bytes has to be able to tell what it is
        // holding, and whether this build's schema is one it understands.
        let data = try JSONExporter().export(document: document(with: [StrokeFixtures.square(at: .zero)]),
                                             viewport: nil)

        let parsed = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(parsed["format"] as? String == DrawingDataExport.formatIdentifier)
        #expect(parsed["formatVersion"] as? Int == DrawingDataExport.currentFormatVersion)
    }

    @Test("The written file decodes back into the published schema")
    func outputDecodesAsTheSchema() throws {
        var builder = ProblemOutlineBuilder()
        let partB = builder.node([1, 2])
        let source = document(
            with: [StrokeFixtures.square(at: .zero, problemNodeID: partB)],
            outline: builder.outline
        )

        let decoded = try decodeExport(of: source)

        #expect(decoded.document.title == "Wave study")
        #expect(decoded.strokes.count == 1)
        #expect(decoded.strokes[0].points.count == 5)
        #expect(decoded.strokes[0].problem?.tag == "1.b")
        #expect(decoded.problems.count == 1)
    }

    @Test("Dates are written as ISO 8601 so another language can read them")
    func datesAreISO8601() throws {
        let data = try JSONExporter().export(document: document(with: [StrokeFixtures.square(at: .zero)]),
                                             viewport: nil)

        let text = try #require(String(data: data, encoding: .utf8))
        // A bare epoch number would be ambiguous about its unit and its zero.
        #expect(text.contains("\"exportedAt\":\"") )
        #expect(text.range(of: #""startTime":"\d{4}-\d{2}-\d{2}T"#, options: .regularExpression) != nil)
    }

    @Test("A document with no strokes fails with a message rather than writing an empty file")
    func emptyDocumentThrows() {
        #expect(throws: ExportError.self) {
            try JSONExporter().export(document: document(with: []), viewport: nil)
        }
    }

    @Test("Non-drawing samples are kept, unlike in the rasterised formats")
    func everySampleIsKept() throws {
        // A one-sample tap paints nothing, so PNG and PDF drop it. Input data is
        // the opposite case: a consumer studying what the pen did needs the taps.
        let tap = StrokeFixtures.stroke(through: [CGPoint(x: 5, y: 5)])

        let decoded = try decodeExport(of: document(with: [tap]))

        #expect(decoded.strokes.count == 1)
        #expect(decoded.strokes[0].pointCount == 1)
    }

    @Test("Two exports of the same drawing differ only in when they were taken")
    func outputIsStableAcrossExports() throws {
        let source = document(with: [StrokeFixtures.square(at: .zero)])
        let exporter = JSONExporter()

        let first = try exporter.export(document: source, viewport: nil)
        let second = try exporter.export(document: source, viewport: nil)

        #expect(try stripExportStamp(from: first) == stripExportStamp(from: second))
    }

    // MARK: - Helpers

    private func document(with strokes: [Stroke], outline: ProblemOutline? = nil) -> SplineDocument {
        SplineDocument(
            metadata: DocumentMetadata(title: "Wave study", problemOutline: outline),
            strokes: strokes
        )
    }

    private func decodeExport(of source: SplineDocument) throws -> DrawingDataExport {
        let data = try JSONExporter().export(document: source, viewport: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(DrawingDataExport.self, from: data)
    }

    /// Everything but the export's own timestamp, which is the one field that is
    /// expected to move between two exports of an unchanged drawing.
    private func stripExportStamp(from data: Data) throws -> String {
        let text = try #require(String(data: data, encoding: .utf8))
        return text.replacingOccurrences(
            of: #""exportedAt":"[^"]+""#,
            with: "",
            options: .regularExpression
        )
    }
}
