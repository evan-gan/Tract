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

    @Test("A run reports its stages in order, so the picker's spinner tracks real work")
    func reportsStagesInOrder() throws {
        let directory = try TemporaryDirectory()
        var stages: [ExportStage] = []

        _ = try ExportRunner.writeExport(
            of: document(titled: "Set 3"),
            layout: .wholeDrawing,
            format: .pdf,
            into: directory.url,
            onStage: { stages.append($0) }
        )

        #expect(stages == [.preparing, .rendering, .writingFile])
    }

    @Test("A run that throws stops reporting where it failed")
    func stopsReportingAtTheFailedStage() throws {
        let directory = try TemporaryDirectory()
        var stages: [ExportStage] = []

        #expect(throws: ExportError.self) {
            try ExportRunner.writeExport(
                of: document(titled: "Set 3"),
                layout: .problemWorksheet,
                format: .png,
                into: directory.url,
                onStage: { stages.append($0) }
            )
        }

        // An unsupported pairing fails before anything is rendered, so the picker
        // must never have claimed it was rendering.
        #expect(stages == [.preparing])
    }

    // MARK: - Chosen problems

    @Test("Exporting chosen problems writes only their ink, named after them")
    func chosenProblemsAreNamedAndWrittenAlone() throws {
        let directory = try TemporaryDirectory()
        let tagged = taggedDocument(titled: "Set 3")

        let url = try ExportRunner.writeExport(
            of: tagged.document,
            layout: .selectedProblems,
            format: .png,
            selection: ProblemSelection(tags: [tagged.firstProblemTag]),
            into: directory.url
        )

        #expect(url.lastPathComponent == "Set 3 1.png")
        // The two problems are drawn far apart at the same size, so a PNG of one
        // of them is dramatically smaller than a PNG of the pair.
        let wholeDrawing = try ExportRunner.writeExport(
            of: tagged.document, layout: .wholeDrawing, format: .png, into: directory.url
        )
        let chosenSize = try Data(contentsOf: url).count
        let wholeSize = try Data(contentsOf: wholeDrawing).count
        #expect(chosenSize < wholeSize)
    }

    @Test("Choosing a problem that has lost its ink reports the empty selection")
    func emptySelectionThrows() throws {
        let directory = try TemporaryDirectory()
        let tagged = taggedDocument(titled: "Set 3")
        var withoutInk = tagged.document
        withoutInk.strokes = []

        #expect(throws: ExportError.self) {
            try ExportRunner.writeExport(
                of: withoutInk,
                layout: .selectedProblems,
                format: .png,
                selection: ProblemSelection(tags: [tagged.firstProblemTag]),
                into: directory.url
            )
        }
    }

    // MARK: - Fixtures

    /// Two problems, one square of ink each, drawn far enough apart that an
    /// export of one is visibly not an export of both.
    private func taggedDocument(titled title: String) -> (document: SplineDocument, firstProblemTag: ProblemTag) {
        var builder = ProblemOutlineBuilder()
        let first = builder.node([1])
        let second = builder.node([2])

        var metadata = DocumentMetadata(title: title)
        metadata.problemOutline = builder.outline
        let document = SplineDocument(
            metadata: metadata,
            strokes: [
                StrokeFixtures.square(at: .zero, side: 200, problemNodeID: first),
                StrokeFixtures.square(at: CGPoint(x: 1200, y: 900), side: 200, problemNodeID: second)
            ]
        )
        return (document, builder.outline.tag(at: builder.path([1])))
    }

    private func document(titled title: String) -> SplineDocument {
        SplineDocument(
            metadata: DocumentMetadata(title: title),
            strokes: [StrokeFixtures.square(at: .zero, side: 200)]
        )
    }
}
