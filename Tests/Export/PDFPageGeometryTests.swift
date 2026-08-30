import Testing
import CoreGraphics
@testable import Tract

@Suite("PDF page geometry")
struct PDFPageGeometryTests {
    @Test("US Letter portrait is 8.5 x 11 inches at 72 points per inch")
    func letterPortraitDimensions() {
        #expect(PaperSize.usLetter.size(in: .portrait) == CGSize(width: 612, height: 792))
    }

    @Test("Landscape swaps the paper's two edges")
    func landscapeSwapsEdges() {
        let portrait = PaperSize.a4.size(in: .portrait)
        let landscape = PaperSize.a4.size(in: .landscape)

        #expect(landscape.width == portrait.height)
        #expect(landscape.height == portrait.width)
    }

    @Test("The page box starts at the origin so nothing is drawn off-page")
    func pageRectStartsAtOrigin() {
        // A media box with a non-zero origin is exactly the bug this fixes: the
        // ink was drawn at (0, 0), which sat outside the page.
        #expect(PDFExportOptions().pageRect.origin == .zero)
    }

    @Test("Margins inset the content area on all four sides")
    func contentRectRespectsMargins() {
        var options = PDFExportOptions()
        options.paperSize = .usLetter
        options.margin = 36

        #expect(options.contentRect == CGRect(x: 36, y: 36, width: 540, height: 720))
    }
}

@Suite("Problem table grid")
struct ProblemTableLayoutTests {
    private let contentRect = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test("A grid produces one cell per row-column pair")
    func cellCountMatchesGrid() {
        let layout = ProblemTableLayout(columns: 3, rows: 4)

        #expect(layout.cellRects(in: contentRect).count == 12)
        #expect(layout.cellsPerPage == 12)
    }

    @Test("Cells are laid out in reading order, left to right then top to bottom")
    func cellsAreInReadingOrder() {
        let layout = ProblemTableLayout(columns: 2, rows: 2, cellSpacing: 0)
        let cells = layout.cellRects(in: contentRect)

        #expect(cells[0] == CGRect(x: 0, y: 0, width: 200, height: 150))
        #expect(cells[1] == CGRect(x: 200, y: 0, width: 200, height: 150))
        #expect(cells[2] == CGRect(x: 0, y: 150, width: 200, height: 150))
    }

    @Test("Spacing is shared between cells, never added outside the content area")
    func spacingStaysInsideContentArea() {
        let layout = ProblemTableLayout(columns: 2, rows: 1, cellSpacing: 20)
        let cells = layout.cellRects(in: contentRect)

        #expect(cells[0].minX == contentRect.minX)
        #expect(cells[1].maxX == contentRect.maxX)
        #expect(cells[1].minX - cells[0].maxX == 20)
    }

    @Test("A cell's ink area sits below its label and inside its padding")
    func inkAreaClearsTheLabel() {
        let layout = ProblemTableLayout(cellSpacing: 0, labelHeight: 18, cellPadding: 8)
        let cell = CGRect(x: 0, y: 0, width: 200, height: 150)

        #expect(layout.labelRect(in: cell) == CGRect(x: 8, y: 8, width: 184, height: 18))
        #expect(layout.inkRect(in: cell) == CGRect(x: 8, y: 26, width: 184, height: 116))
    }
}

@Suite("Fitting ink into a box")
struct InkFitTransformTests {
    @Test("Ink larger than the box is scaled down to fit")
    func oversizedInkIsScaledDown() {
        let transform = InkFitTransform.centring(
            CGRect(x: 0, y: 0, width: 200, height: 100),
            in: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        #expect(transform.a == 0.5)
        #expect(transform.d == 0.5)
    }

    @Test("Ink is never enlarged past the maximum scale")
    func smallInkIsNotEnlargedByDefault() {
        let transform = InkFitTransform.centring(
            CGRect(x: 0, y: 0, width: 10, height: 10),
            in: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        #expect(transform.a == 1)
    }

    @Test("Raising the maximum scale lets small ink grow to fill the box")
    func raisedMaximumScaleEnlarges() {
        let transform = InkFitTransform.centring(
            CGRect(x: 0, y: 0, width: 10, height: 10),
            in: CGRect(x: 0, y: 0, width: 100, height: 100),
            maximumScale: 10
        )

        #expect(transform.a == 10)
    }

    @Test("Scaled ink is centred in its box")
    func inkIsCentred() {
        let transform = InkFitTransform.centring(
            CGRect(x: 0, y: 0, width: 50, height: 50),
            in: CGRect(x: 100, y: 200, width: 100, height: 100)
        )

        #expect(transform.tx == 125)
        #expect(transform.ty == 225)
    }

    @Test("A perfectly horizontal drawing still lands in the box")
    func zeroHeightInkDoesNotDivideByZero() {
        let transform = InkFitTransform.centring(
            CGRect(x: 0, y: 0, width: 200, height: 0),
            in: CGRect(x: 0, y: 0, width: 100, height: 100)
        )

        #expect(transform.a == 0.5)
        #expect(transform.a.isFinite)
    }
}
