import Testing
import Foundation
@testable import Tract

@Suite("The export picker's layouts and formats")
struct ExportLayoutTests {
    @Test("Every layout offers at least one format, and each one has an exporter behind it")
    func everyOfferedPairingResolvesToAnAdapter() {
        for layout in ExportLayout.allCases {
            #expect(!layout.formats.isEmpty, "\(layout.name) would show an empty group.")
            for format in layout.formats {
                #expect(layout.adapter(for: format) != nil,
                        "\(layout.name) offers \(format.displayName) with nothing to render it.")
            }
        }
    }

    @Test("A format a layout does not offer has no exporter")
    func unofferedPairingsResolveToNil() {
        // The picker can only produce the pairings above, but a caller in code
        // can ask for anything — and a silently wrong file is worse than a throw.
        #expect(ExportLayout.problemWorksheet.adapter(for: .png) == nil)
        #expect(ExportLayout.rawCapture.adapter(for: .pdf) == nil)
        #expect(ExportLayout.wholeDrawing.adapter(for: .json) == nil)
        #expect(ExportLayout.selectedProblems.adapter(for: .json) == nil)
    }

    @Test("Chosen problems offer the three sharing formats, and only that layout is selective")
    func chosenProblemsOfferSharingFormats() {
        #expect(ExportLayout.selectedProblems.formats == [.pdf, .png, .svg])
        #expect(ExportLayout.allCases.filter(\.usesProblemSelection) == [.selectedProblems],
                "Only the chosen-problems group carries the picker's chip chooser.")
    }

    @Test("The worksheet renders as PDF only, because only the PDF renderer pages it")
    func worksheetOffersPDFAlone() {
        #expect(ExportLayout.problemWorksheet.formats == [.pdf])
    }

    @Test("The whole drawing offers the three picture formats")
    func wholeDrawingOffersPicturesOnly() {
        #expect(ExportLayout.wholeDrawing.formats == [.pdf, .svg, .png])
    }

    @Test("The two PDFs come from different layouts, so they cannot share a file name")
    func thePDFLayoutsAreNamedApart() throws {
        let drawing = try #require(ExportLayout.wholeDrawing.adapter(for: .pdf))
        let worksheet = try #require(ExportLayout.problemWorksheet.adapter(for: .pdf))

        #expect(drawing.fileExtension == worksheet.fileExtension)
        #expect(drawing.fileNameSuffix != worksheet.fileNameSuffix,
                "Two identically named PDFs in a share sheet are impossible to tell apart.")
    }

    @Test("A format's extension is the one its exporter actually writes")
    func formatExtensionsMatchTheirAdapters() throws {
        for layout in ExportLayout.allCases {
            for format in layout.formats {
                let adapter = try #require(layout.adapter(for: format))
                #expect(adapter.fileExtension == format.fileExtension,
                        "\(format.displayName) is captioned .\(format.fileExtension) but writes .\(adapter.fileExtension)")
            }
        }
    }
}
