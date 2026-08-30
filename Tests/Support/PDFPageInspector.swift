import PDFKit
import UIKit

/// Reads back what a rendered PDF page actually contains.
///
/// Page count and media box alone cannot catch the failure that matters most —
/// a correctly sized page with the ink drawn off it — so these tests rasterise
/// the page and look for marks.
enum PDFPageInspector {
    static func document(from data: Data) throws -> PDFDocument {
        guard let document = PDFDocument(data: data) else {
            throw InspectionError.notAPDF(byteCount: data.count)
        }
        return document
    }

    static func page(_ index: Int, of data: Data) throws -> PDFPage {
        let document = try self.document(from: data)
        guard let page = document.page(at: index) else {
            throw InspectionError.missingPage(index: index, pageCount: document.pageCount)
        }
        return page
    }

    /// Fraction of the page's pixels that carry ink, painted over white paper so
    /// a transparent background reads as blank rather than as marks.
    /// - Returns: 0 for a blank page, rising towards 1 the more is drawn.
    static func inkCoverage(of page: PDFPage, samplesAcross: Int = 200) throws -> Double {
        let mediaBox = page.bounds(for: .mediaBox)
        let height = max(Int(Double(samplesAcross) * mediaBox.height / mediaBox.width), 1)
        let pixels = try grayscalePixels(of: page, width: samplesAcross, height: height)

        // Anti-aliased hairlines never reach full black; anything clearly off
        // white is a mark, and the white fill keeps the rest at 255.
        let inkedPixels = pixels.count { $0 < 200 }
        return Double(inkedPixels) / Double(pixels.count)
    }

    private static func grayscalePixels(of page: PDFPage, width: Int, height: Int) throws -> [UInt8] {
        // Owned explicitly rather than through a Swift Array: the CGContext keeps
        // the pointer for as long as it draws, which outlives a withUnsafeBytes body.
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: width * height)
        defer { buffer.deallocate() }

        guard let context = CGContext(
            data: buffer,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw InspectionError.rasterisationFailed("could not create a \(width)x\(height) grayscale context")
        }

        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let mediaBox = page.bounds(for: .mediaBox)
        context.scaleBy(x: CGFloat(width) / mediaBox.width, y: CGFloat(height) / mediaBox.height)
        page.draw(with: .mediaBox, to: context)

        return Array(UnsafeBufferPointer(start: buffer, count: width * height))
    }

    enum InspectionError: LocalizedError {
        case notAPDF(byteCount: Int)
        case missingPage(index: Int, pageCount: Int)
        case rasterisationFailed(String)

        var errorDescription: String? {
            switch self {
            case .notAPDF(let byteCount):
                "Exported data (\(byteCount) bytes) is not a readable PDF."
            case .missingPage(let index, let pageCount):
                "Expected a page at index \(index) but the PDF has \(pageCount)."
            case .rasterisationFailed(let detail):
                "Could not rasterise the PDF page: \(detail)."
            }
        }
    }
}
