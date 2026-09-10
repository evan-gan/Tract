import Testing
import CoreGraphics
import Foundation
@testable import Tract

@Suite("Running a picked export")
struct ExportRunnerTests {
    @Test("A pick becomes a file named after the document, with the format's extension")
    func writesAFileNamedAfterTheDocument() throws {
        let directory = try TemporaryDirectory()

        let url = try ExportRunner.writeExport(
            of: document(titled: "Wave study"),
            layout: .wholeDrawing,
            format: .svg,
            into: directory.url
        )

        #expect(url.lastPathComponent == "Wave study.svg")
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test("The worksheet's file name says which of the two PDFs it is")
    func worksheetFileNameIsDistinguishable() throws {
        let directory = try TemporaryDirectory()

        let drawing = try ExportRunner.writeExport(
            of: document(titled: "Set 3"), layout: .wholeDrawing, format: .pdf, into: directory.url
        )
        let worksheet = try ExportRunner.writeExport(
            of: document(titled: "Set 3"), layout: .problemWorksheet, format: .pdf, into: directory.url
        )

        #expect(drawing.lastPathComponent == "Set 3.pdf")
        #expect(worksheet.lastPathComponent == "Set 3 problems.pdf")
    }

    @Test("A folder path is prefixed onto the name when the export asks for it")
    func folderPathReachesTheFileName() throws {
        let directory = try TemporaryDirectory()

        let url = try ExportRunner.writeExport(
            of: document(titled: "Filed away"),
            layout: .rawCapture,
            format: .json,
            folderPath: ["Homework", "Algebra"],
            into: directory.url
        )

        #expect(url.lastPathComponent == "Homework.Algebra.Filed away.json")
    }

    @Test("Every pairing the picker offers writes a file with something in it")
    func everyOfferedPairingProducesAFile() throws {
        let directory = try TemporaryDirectory()

        for layout in ExportLayout.allCases {
            for format in layout.formats {
                let url = try ExportRunner.writeExport(
                    of: document(titled: "\(layout.id)-\(format.id)"),
                    layout: layout,
                    format: format,
                    into: directory.url
                )
                let size = try Data(contentsOf: url).count
                #expect(size > 0, "\(layout.name) as \(format.displayName) wrote an empty file.")
            }
        }
    }

    @Test("Asking a layout for a format it does not offer throws rather than writing a wrong file")
    func unsupportedPairingThrows() throws {
        let directory = try TemporaryDirectory()

        #expect(throws: ExportError.self) {
            try ExportRunner.writeExport(
                of: document(titled: "Set 3"),
                layout: .problemWorksheet,
                format: .png,
                into: directory.url
            )
        }
    }

    @Test("A document with no ink reports the empty document rather than writing a blank file")
    func emptyDocumentThrows() throws {
        let directory = try TemporaryDirectory()
        let empty = SplineDocument(metadata: DocumentMetadata(title: "Blank"), strokes: [])

        #expect(throws: ExportError.self) {
            try ExportRunner.writeExport(
                of: empty, layout: .wholeDrawing, format: .png, into: directory.url
            )
        }
    }

    // MARK: - Fixtures

    private func document(titled title: String) -> SplineDocument {
        SplineDocument(
            metadata: DocumentMetadata(title: title),
            strokes: [StrokeFixtures.square(at: .zero, side: 200)]
        )
    }
}
