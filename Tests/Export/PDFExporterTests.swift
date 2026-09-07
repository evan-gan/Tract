import Testing
import CoreGraphics
import Foundation
@testable import Tract

@Suite("PDF export")
struct PDFExporterTests {
    // MARK: - Paper

    @Test("An exported page is standard US Letter paper, not the size of the ink")
    func pageUsesStandardPaperSize() throws {
        let data = try PDFExporter().export(document: document(with: [square()]), viewport: nil)
        let page = try PDFPageInspector.page(0, of: data)

        #expect(page.bounds(for: .mediaBox).size == PaperSize.usLetter.size(in: .portrait))
    }

    @Test("The chosen paper size and orientation reach the page box")
    func paperSizeAndOrientationAreHonoured() throws {
        var options = PDFExportOptions()
        options.paperSize = .a4
        options.orientation = .landscape

        let data = try PDFExporter(options: options).export(document: document(with: [square()]), viewport: nil)
        let page = try PDFPageInspector.page(0, of: data)

        #expect(page.bounds(for: .mediaBox).size == PaperSize.a4.size(in: .landscape))
    }

    // MARK: - The regression this fixes

    @Test("Ink drawn far from the canvas origin still lands on the page")
    func distantInkIsNotDrawnOffThePage() throws {
        // The old exporter made the page box start at the ink's own canvas origin,
        // then drew the ink at (0, 0) — off-page, so the PDF came out blank. On an
        // infinite canvas, ink thousands of points out is the normal case.
        let distant = square(at: CGPoint(x: 14_000, y: -9_000))
        let data = try PDFExporter().export(document: document(with: [distant]), viewport: nil)

        let coverage = try PDFPageInspector.inkCoverage(of: PDFPageInspector.page(0, of: data))

        #expect(coverage > 0)
    }

    @Test("A drawing wider than the paper is scaled down rather than cropped away")
    func oversizedDrawingIsScaledToFit() throws {
        var options = PDFExportOptions()
        options.maximumScale = 1

        let huge = square(at: .zero, side: 8_000)
        let data = try PDFExporter(options: options).export(document: document(with: [huge]), viewport: nil)

        // Scaled down by ~13x the strokes are hairlines, so the page needs a
        // finer raster than the default before they register as marks at all.
        let coverage = try PDFPageInspector.inkCoverage(
            of: PDFPageInspector.page(0, of: data),
            samplesAcross: 1_200
        )

        #expect(coverage > 0)
    }

    // MARK: - Empty documents

    @Test("A document with no strokes cannot be exported")
    func emptyDocumentThrows() {
        #expect(throws: ExportError.self) {
            try PDFExporter().export(document: document(with: []), viewport: nil)
        }
    }

    @Test("Lasso and eraser strokes alone are not something to export")
    func nonDrawingStrokesAloneThrow() {
        let lasso = StrokeFixtures.stroke(through: [.zero, CGPoint(x: 40, y: 40)], tool: .lasso)

        #expect(throws: ExportError.self) {
            try PDFExporter().export(document: document(with: [lasso]), viewport: nil)
        }
    }

    // MARK: - The worksheet

    @Test("Every problem's number is badged on the sheet, as it is written on a worksheet")
    func problemBadgesArePrinted() throws {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: .zero, node: builder.node([1, 1])),
            square(at: CGPoint(x: 900, y: 0), node: builder.node([1, 2, 4]))
        ]
        let data = try PDFExporter(options: taggedOnlySheet)
            .export(document: document(with: strokes, outline: builder.outline), viewport: nil)
        let text = try #require(PDFPageInspector.page(0, of: data).string)

        #expect(text.contains("1a"))
        #expect(text.contains("1bIV"))
    }

    @Test("Ink from problems drawn far apart is gathered onto one page")
    func distantProblemsAreGatheredTogether() throws {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: .zero, side: 120, node: builder.node([1])),
            square(at: CGPoint(x: 20_000, y: 12_000), side: 120, node: builder.node([2]))
        ]
        let data = try PDFExporter(options: taggedOnlySheet)
            .export(document: document(with: strokes, outline: builder.outline), viewport: nil)

        #expect(try PDFPageInspector.document(from: data).pageCount == 1)
        // Two whole problems plus their badges; a page that lost one would be
        // half as marked.
        #expect(try PDFPageInspector.inkCoverage(of: PDFPageInspector.page(0, of: data)) > 0.01)
    }

    @Test("More problems than one sheet holds flow onto further sheets")
    func problemsFlowOntoMorePages() throws {
        var builder = ProblemOutlineBuilder()
        let strokes = (1 ... 12).map { index in
            square(at: CGPoint(x: index * 500, y: 0), node: builder.node([index]))
        }
        let data = try PDFExporter(options: taggedOnlySheet)
            .export(document: document(with: strokes, outline: builder.outline), viewport: nil)

        #expect(try PDFPageInspector.document(from: data).pageCount > 1)
    }

    // MARK: - Untagged work

    @Test("Untagged work is still printed, under a heading that says so")
    func untaggedWorkIsPrinted() throws {
        var builder = ProblemOutlineBuilder()
        let strokes = [
            square(at: .zero, node: builder.node([1])),
            square(at: CGPoint(x: 500, y: 0))
        ]

        let data = try PDFExporter(options: .problemSheet)
            .export(document: document(with: strokes, outline: builder.outline), viewport: nil)
        let text = try #require(PDFPageInspector.page(0, of: data).string)

        #expect(text.contains("untagged"))
    }

    @Test("A document with nothing tagged is still exported")
    func nothingTaggedStillProducesASheet() throws {
        let data = try PDFExporter(options: .problemSheet)
            .export(document: document(with: [square()]), viewport: nil)

        #expect(try PDFPageInspector.document(from: data).pageCount == 1)
        #expect(try PDFPageInspector.inkCoverage(of: PDFPageInspector.page(0, of: data)) > 0)
    }

    @Test("Dropping untagged work from a sheet of nothing but untagged work is an error")
    func sheetWithNothingTaggedThrows() {
        #expect(throws: ExportError.self) {
            try PDFExporter(options: taggedOnlySheet).export(document: document(with: [square()]), viewport: nil)
        }
    }

    // MARK: - Filling the paper

    @Test("The worksheet grows small work rather than leaving the sheet empty")
    func worksheetEnlargesSmallWork() throws {
        var builder = ProblemOutlineBuilder()
        let strokes = [square(at: .zero, side: 40, node: builder.node([1]))]
        let tinyDocument = document(with: strokes, outline: builder.outline)

        var unscaledOptions = PDFExportOptions.problemSheet
        // The readability floor and the growth cap both pinned to 1: ink at its
        // canvas size, which is what "no fitting at all" looks like.
        unscaledOptions.layout = .worksheet(
            WorksheetOptions(minimumScale: 1, maximumScale: 1, growthCap: 1)
        )

        let fitted = try PDFPageInspector.inkCoverage(
            of: PDFPageInspector.page(0, of: PDFExporter(options: .problemSheet)
                .export(document: tinyDocument, viewport: nil))
        )
        let unscaled = try PDFPageInspector.inkCoverage(
            of: PDFPageInspector.page(0, of: PDFExporter(options: unscaledOptions)
                .export(document: tinyDocument, viewport: nil))
        )

        #expect(fitted > unscaled)
    }

    // MARK: - Fixtures

    /// The shipping worksheet with untagged work left off, so a test can count
    /// pages without an untagged block joining in.
    private var taggedOnlySheet: PDFExportOptions {
        var options = PDFExportOptions.problemSheet
        options.layout = .worksheet(WorksheetOptions(untaggedLabel: nil))
        return options
    }

    private func document(
        with strokes: [Stroke],
        outline: ProblemOutline = ProblemOutline()
    ) -> SplineDocument {
        SplineDocument(metadata: DocumentMetadata(problemOutline: outline), strokes: strokes)
    }

    private func square(at origin: CGPoint = .zero, side: CGFloat = 200, node: UUID? = nil) -> Stroke {
        StrokeFixtures.square(at: origin, side: side, problemNodeID: node)
    }
}
