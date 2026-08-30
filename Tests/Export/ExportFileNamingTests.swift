import Testing
@testable import Tract

@Suite("Naming an exported file")
struct ExportFileNamingTests {
    @Test("An ordinary title becomes the file name with the format's extension")
    func ordinaryTitleIsUsedAsIs() {
        #expect(ExportFileNaming.fileName(title: "Wave study", fileExtension: "pdf") == "Wave study.pdf")
    }

    @Test("A slash in the title is replaced rather than treated as a folder")
    func slashesAreReplaced() {
        // Left alone this wrote to a directory that does not exist, so the
        // export failed with a file-system error for a perfectly valid title.
        #expect(ExportFileNaming.fileName(title: "Problem 1/2", fileExtension: "pdf") == "Problem 1-2.pdf")
        #expect(ExportFileNaming.fileName(title: "a\\b:c", fileExtension: "png") == "a-b-c.png")
    }

    @Test("A title with nothing usable in it falls back to a placeholder")
    func emptyTitleFallsBack() {
        #expect(ExportFileNaming.fileName(title: "", fileExtension: "svg") == "Drawing.svg")
        #expect(ExportFileNaming.fileName(title: "   ", fileExtension: "svg") == "Drawing.svg")
        #expect(ExportFileNaming.fileName(title: "///", fileExtension: "svg") == "Drawing.svg")
    }

    @Test("Surrounding whitespace is trimmed off the name")
    func whitespaceIsTrimmed() {
        #expect(ExportFileNaming.fileName(title: "  Sketch  ", fileExtension: "pdf") == "Sketch.pdf")
    }
}
