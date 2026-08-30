import CoreGraphics

/// A standard printing paper size, expressed in PDF points (72 per inch).
/// Points are the unit `UIGraphicsPDFRenderer` and every print pipeline work in,
/// so a page built from these needs no conversion and prints at true size.
struct PaperSize: Equatable, Hashable, Sendable, Identifiable {
    let name: String
    /// Dimensions with the short edge horizontal.
    let portraitSize: CGSize

    var id: String { name }

    static let usLetter = PaperSize(name: "US Letter", portraitSize: CGSize(width: 612, height: 792))
    static let usLegal = PaperSize(name: "US Legal", portraitSize: CGSize(width: 612, height: 1008))
    static let tabloid = PaperSize(name: "Tabloid", portraitSize: CGSize(width: 792, height: 1224))
    static let a4 = PaperSize(name: "A4", portraitSize: CGSize(width: 595.28, height: 841.89))
    static let a3 = PaperSize(name: "A3", portraitSize: CGSize(width: 841.89, height: 1190.55))
    static let a5 = PaperSize(name: "A5", portraitSize: CGSize(width: 419.53, height: 595.28))

    /// Every size the app offers, in the order a picker should list them.
    static let standardSizes: [PaperSize] = [.usLetter, .usLegal, .tabloid, .a4, .a3, .a5]

    func size(in orientation: PageOrientation) -> CGSize {
        switch orientation {
        case .portrait: portraitSize
        case .landscape: CGSize(width: portraitSize.height, height: portraitSize.width)
        }
    }
}

enum PageOrientation: String, CaseIterable, Sendable, Identifiable {
    case portrait, landscape

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        }
    }
}
