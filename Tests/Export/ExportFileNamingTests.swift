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

    // MARK: - Folder path prefix

    @Test("A folder path is prefixed onto the name, separated by periods")
    func folderPathBecomesADottedPrefix() {
        #expect(
            ExportFileNaming.fileName(
                title: "Filed away",
                folderPath: ["Homework"],
                fileExtension: "pdf"
            ) == "Homework.Filed away.pdf"
        )
        #expect(
            ExportFileNaming.fileName(
                title: "Set 3",
                folderPath: ["Homework", "Algebra"],
                fileExtension: "png"
            ) == "Homework.Algebra.Set 3.png"
        )
    }

    @Test("A top-level document gets no prefix at all")
    func emptyPathAddsNothing() {
        #expect(ExportFileNaming.fileName(title: "Wave study", folderPath: [], fileExtension: "svg") == "Wave study.svg")
    }

    @Test("A period inside a folder name is replaced so it cannot read as nesting")
    func periodsInFolderNamesAreReplaced() {
        // "Unit 1.2" left alone would come back out of the name as two folders.
        #expect(
            ExportFileNaming.fileName(
                title: "Sketch",
                folderPath: ["Unit 1.2"],
                fileExtension: "pdf"
            ) == "Unit 1-2.Sketch.pdf"
        )
    }

    @Test("A folder name that is only separators is dropped from the prefix")
    func unusableFolderNamesAreSkipped() {
        #expect(
            ExportFileNaming.fileName(
                title: "Sketch",
                folderPath: ["...", "Homework"],
                fileExtension: "pdf"
            ) == "Homework.Sketch.pdf"
        )
    }

    @Test("Slashes in a folder name cannot turn the prefix into a real directory")
    func slashesInFolderNamesAreReplaced() {
        #expect(
            ExportFileNaming.fileName(
                title: "Sketch",
                folderPath: ["Term 1/2"],
                fileExtension: "pdf"
            ) == "Term 1-2.Sketch.pdf"
        )
    }

    @Test("A prefix still applies when the title itself is unusable")
    func placeholderTitleKeepsThePrefix() {
        #expect(
            ExportFileNaming.fileName(
                title: "   ",
                folderPath: ["Homework"],
                fileExtension: "svg"
            ) == "Homework.Drawing.svg"
        )
    }
}
