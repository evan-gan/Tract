import Foundation

/// The file a chosen export is written as.
///
/// Separate from `ExportAdapter` on purpose: an adapter is one concrete
/// renderer, while a format is the *choice* a user makes. The same format can be
/// produced by more than one adapter — PDF is written both by the whole-drawing
/// renderer and by the worksheet one — so the picker cannot be built from
/// adapters alone.
enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case pdf
    case svg
    case png
    case json

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .pdf: "PDF"
        case .svg: "SVG"
        case .png: "PNG"
        case .json: "JSON"
        }
    }

    /// Without a leading dot. The raw value *is* the extension for every format
    /// so far; a format whose name and extension diverge should override here.
    var fileExtension: String { rawValue }

    var symbolName: String {
        switch self {
        case .pdf: "doc.richtext"
        case .svg: "scribble.variable"
        case .png: "photo"
        case .json: "curlybraces"
        }
    }

    /// What the file itself is, one line, shown under the name in the picker.
    /// Says nothing about *what is in* the file — that is the layout's job.
    var summary: String {
        switch self {
        case .pdf: "Paged for printing."
        case .svg: "Vector paths that stay sharp at any size."
        case .png: "A flat image at the drawing's own size."
        case .json: "Structured data, not a picture."
        }
    }
}

/// What an export puts on the page — the first choice the picker asks for, with
/// the formats that can carry it underneath.
///
/// This is the grouping the export sheet is built from, and the reason it is a
/// grouping at all: "the whole drawing" can be written five ways, while the
/// per-problem worksheet only exists as PDF because only the PDF renderer knows
/// how to flow it onto pages. Offering every format under every layout would
/// mean offering exports that cannot be produced.
///
/// Adding a layout is this enum plus a `Tests/Export/ExportLayoutTests` run —
/// the picker renders whatever is here, in declaration order.
enum ExportLayout: String, CaseIterable, Identifiable, Sendable {
    /// Everything on the canvas as a single picture.
    case wholeDrawing
    /// One problem per badged shape, nested to fill the paper.
    case problemWorksheet
    /// The drawing as the app recorded it, samples and all.
    case rawCapture

    var id: String { rawValue }

    var name: String {
        switch self {
        case .wholeDrawing: "Whole drawing"
        case .problemWorksheet: "Problem worksheet"
        case .rawCapture: "Raw capture"
        }
    }

    /// What lands in the file, shown under the group's title. Written as what
    /// the user gets, not as how it is produced.
    var summary: String {
        switch self {
        case .wholeDrawing:
            "The canvas exactly as you drew it, scaled to fit."
        case .problemWorksheet:
            "Every tagged problem badged with its number and nested onto sheets, "
            + "so scattered work reads as a worksheet."
        case .rawCapture:
            "Every pencil sample, tag and timing Tract recorded — for reading the "
            + "drawing outside the app."
        }
    }

    var symbolName: String {
        switch self {
        case .wholeDrawing: "rectangle.dashed"
        case .problemWorksheet: "list.number"
        case .rawCapture: "waveform.path"
        }
    }

    /// The formats this layout can be written as, in the order the picker shows
    /// them: the one most people want first.
    var formats: [ExportFormat] {
        switch self {
        case .wholeDrawing: [.pdf, .svg, .png]
        case .problemWorksheet: [.pdf]
        case .rawCapture: [.json]
        }
    }

    /// The exporter that produces this layout in the given format, or nil when
    /// the pairing is not one this layout offers.
    ///
    /// - Parameter format: One of `formats`; anything else returns nil.
    /// - Returns: A configured `ExportAdapter`, ready to run on a document.
    func adapter(for format: ExportFormat) -> (any ExportAdapter)? {
        switch (self, format) {
        case (.wholeDrawing, .pdf): return PDFExporter()
        case (.wholeDrawing, .svg): return SVGExporter()
        case (.wholeDrawing, .png): return PNGExporter()
        case (.problemWorksheet, .pdf): return PDFExporter(options: .problemSheet)
        case (.rawCapture, .json): return JSONExporter()
        default: return nil
        }
    }
}
