import Testing
import CoreGraphics
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

    // MARK: - Problem table

    @Test("Each tagged problem gets its own cell, and cells flow onto more pages")
    func problemsFlowAcrossPages() throws {
        // One cell per page makes the pagination arithmetic visible: four problems
        // must produce four pages.
        let layout = ProblemTableLayout(columns: 1, rows: 1, untaggedLabel: nil)
        var options = PDFExportOptions()
        options.layout = .problemTable(layout)

        let strokes = (1 ... 4).map { index in
            square(at: CGPoint(x: index * 500, y: 0), tag: [.number(index)])
        }
        let data = try PDFExporter(options: options).export(document: document(with: strokes), viewport: nil)

        #expect(try PDFPageInspector.document(from: data).pageCount == 4)
    }

    @Test("Six problems fit one 2x3 page")
    func aFullGridFitsOnOnePage() throws {
        var options = PDFExportOptions()
        options.layout = .problemTable(ProblemTableLayout(columns: 2, rows: 3, untaggedLabel: nil))

        let strokes = (1 ... 6).map { index in
            square(at: CGPoint(x: index * 500, y: 0), tag: [.number(index)])
        }
        let data = try PDFExporter(options: options).export(document: document(with: strokes), viewport: nil)

        #expect(try PDFPageInspector.document(from: data).pageCount == 1)
    }

    @Test("Every problem's label is printed on the sheet")
    func problemLabelsArePrinted() throws {
        var options = PDFExportOptions()
        options.layout = .problemTable(ProblemTableLayout(untaggedLabel: nil))

        let strokes = [
            square(at: .zero, tag: [.number(1), .lowercaseLetter(1)]),
            square(at: CGPoint(x: 900, y: 0), tag: [.number(1), .lowercaseRoman(4)])
        ]
        let data = try PDFExporter(options: options).export(document: document(with: strokes), viewport: nil)
        let text = try #require(PDFPageInspector.page(0, of: data).string)

        #expect(text.contains("1.a"))
        #expect(text.contains("1.iv"))
    }

    @Test("Ink from problems drawn far apart is gathered onto one page")
    func distantProblemsAreGatheredTogether() throws {
        var options = PDFExportOptions()
        // Ink written small on a big canvas has to grow to fill its cell.
        options.maximumScale = 20
        options.layout = .problemTable(ProblemTableLayout(columns: 2, rows: 1, untaggedLabel: nil))

        let strokes = [
            square(at: .zero, side: 60, tag: [.number(1)]),
            square(at: CGPoint(x: 20_000, y: 12_000), side: 60, tag: [.number(2)])
        ]
        let data = try PDFExporter(options: options).export(document: document(with: strokes), viewport: nil)

        let coverage = try PDFPageInspector.inkCoverage(of: PDFPageInspector.page(0, of: data))

        // Two filled cells plus their borders; a page that lost one would be far sparser.
        #expect(coverage > 0.01)
    }

    @Test("Grouping by depth puts a problem's parts in one cell instead of several")
    func groupingDepthCollapsesParts() throws {
        var layout = ProblemTableLayout(columns: 1, rows: 1, untaggedLabel: nil)
        layout.groupingDepth = 1
        var options = PDFExportOptions()
        options.layout = .problemTable(layout)

        // Three parts of one problem: one cell at depth 1, so one page.
        let strokes = (1 ... 3).map { part in
            square(at: CGPoint(x: part * 500, y: 0), tag: [.number(1), .lowercaseLetter(part)])
        }
        let data = try PDFExporter(options: options).export(document: document(with: strokes), viewport: nil)

        #expect(try PDFPageInspector.document(from: data).pageCount == 1)
        #expect(try #require(PDFPageInspector.page(0, of: data).string).contains("1"))
    }

    @Test("Dropping untagged work from a table of nothing but untagged work is an error")
    func tableWithNothingTaggedThrows() {
        var options = PDFExportOptions()
        options.layout = .problemTable(ProblemTableLayout(untaggedLabel: nil))

        #expect(throws: ExportError.self) {
            try PDFExporter(options: options).export(document: document(with: [square()]), viewport: nil)
        }
    }

    // MARK: - Fixtures

    private func document(with strokes: [Stroke]) -> SplineDocument {
        SplineDocument(strokes: strokes)
    }

    private func square(at origin: CGPoint = .zero, side: CGFloat = 200, tag: ProblemTag? = nil) -> Stroke {
        StrokeFixtures.square(at: origin, side: side, problemTag: tag)
    }
}
