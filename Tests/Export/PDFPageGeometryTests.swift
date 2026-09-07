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

@Suite("Worksheet paper")
struct WorksheetPageGeometryTests {
    @Test("The problem sheet prints landscape at a half-inch margin")
    func problemSheetPaper() {
        let options = PDFExportOptions.problemSheet

        #expect(options.pageRect.size == CGSize(width: 792, height: 612))
        #expect(options.worksheetPage.contentRect == CGRect(x: 36, y: 36, width: 720, height: 540))
    }

    @Test("The worksheet's content box is the page inside its margins")
    func contentBoxRespectsMargins() {
        let page = WorksheetPageGeometry(size: CGSize(width: 200, height: 100), margin: 10)

        #expect(page.pageRect == CGRect(x: 0, y: 0, width: 200, height: 100))
        #expect(page.contentRect == CGRect(x: 10, y: 10, width: 180, height: 80))
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
