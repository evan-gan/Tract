import XCTest

/// Smoke test: a single export, from a freshly launched app, reaches a share
/// sheet that actually has content in it — and the export picker offers each
/// layout's formats on the way there.
///
/// **This does not guard the empty-sheet bug it was written for.** That bug —
/// `.sheet(isPresented:)` presenting before the exported file landed in state,
/// giving a blank system-coloured rectangle with nothing in it — was reported on
/// device, and this test was checked against a deliberately reinstated copy of
/// it: it passed anyway. The simulator does not reproduce the timing. The real
/// fix is structural (`.sheet(item:)` cannot present without the file), and it
/// is the structure, not this test, that guarantees it.
///
/// Kept because a first export that reaches a populated share sheet is still
/// worth knowing about; do not read a pass here as proof the bug is gone.
@MainActor
final class ExportShareSheetUITests: XCTestCase {
    func testShareSheetAppearsOnTheFirstPDFExport() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)
        openExportPicker(in: app)

        tapExportOption("exportOption-wholeDrawing-pdf", in: app)

        XCTAssertTrue(waitForShareSheet(in: app),
                      "The share sheet should appear on the very first export, "
                      + "not only after a previous one has populated the view's state.")
    }

    /// The worksheet is its own group in the picker, offering only PDF — the
    /// grouping is the whole point of the sheet, so the wiring is worth a test.
    func testProblemWorksheetIsItsOwnGroupOfferingOnlyPDF() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)
        openExportPicker(in: app)

        XCTAssertFalse(app.buttons["exportOption-problemWorksheet-png"].firstMatch.exists,
                       "The worksheet layout only renders as a PDF, so no other "
                       + "format should be offered under it.")

        tapExportOption("exportOption-problemWorksheet-pdf", in: app)

        XCTAssertTrue(waitForShareSheet(in: app),
                      "Exporting the problem worksheet should reach the share sheet. "
                      + "The sample drawings carry no tags, so this also proves an "
                      + "all-untagged document still produces its one explanatory page.")
    }

    /// The raw-data export shares a file rather than a picture, and it is the one
    /// format whose whole point is leaving the app — so the path out is tested.
    func testRawCaptureExportsAsJSON() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)
        openExportPicker(in: app)

        tapExportOption("exportOption-rawCapture-json", in: app)

        XCTAssertTrue(waitForShareSheet(in: app),
                      "Exporting the raw data should reach the share sheet.")
    }

    /// Backing out of the picker must export nothing at all: the export runs when
    /// the sheet closes, so a cancel that still carried a pick would share a file
    /// nobody asked for.
    func testCancellingThePickerExportsNothing() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)
        openExportPicker(in: app)

        app.buttons["Cancel"].firstMatch.tap()

        XCTAssertFalse(waitForShareSheet(in: app, timeout: 5),
                       "Cancelling the export picker should not share anything.")
    }

    // MARK: - Chosen problems

    /// Ticking one problem and sharing it as a picture is the whole point of the
    /// chosen-problems group, so the path through the chips is tested end to end.
    func testChoosingOneProblemExportsItAsAPicture() throws {
        let app = launchWithSampleDocuments()
        openTaggedSampleDocument(in: app)
        openExportPicker(in: app)

        let pngOption = app.buttons["exportOption-selectedProblems-png"].firstMatch
        XCTAssertTrue(pngOption.waitForExistence(timeout: 10),
                      "A tagged document should offer its problems as a picture export.")
        XCTAssertFalse(pngOption.isEnabled,
                       "With no problem ticked there is nothing to export, so the "
                       + "formats should not be pickable.")

        let firstProblem = app.buttons["exportProblemChip-1"].firstMatch
        XCTAssertTrue(firstProblem.waitForExistence(timeout: 5),
                      "The seeded problem set is tagged 1 and 2, so both should be offered.")
        firstProblem.tap()

        XCTAssertTrue(pngOption.isEnabled, "Ticking a problem should make the formats pickable.")
        pngOption.tap()

        XCTAssertTrue(waitForShareSheet(in: app),
                      "Exporting a single chosen problem should reach the share sheet.")
    }

    /// The group has nothing to tick without tags, and an empty chooser is worse
    /// than no chooser.
    func testChosenProblemsGroupIsHiddenForAnUntaggedDocument() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)
        openExportPicker(in: app)

        XCTAssertFalse(app.buttons["exportOption-selectedProblems-png"].firstMatch.exists,
                       "A document with no tagged problems should not offer to export a choice of them.")
    }

    // MARK: - Folder path in the file name

    /// The toggle names the file after the folders holding the document, so it
    /// only means anything for a document that is actually filed somewhere.
    func testFolderPathToggleIsOfferedForAFiledDocument() throws {
        let app = launchWithSampleDocuments()
        openFiledSampleDocument(in: app)
        openExportPicker(in: app)

        let pathToggle = app.switches["exportIncludeFolderPath"].firstMatch
        XCTAssertTrue(pathToggle.waitForExistence(timeout: 10),
                      "A document inside a folder should offer the folder-path naming toggle.")
        pathToggle.tap()

        tapExportOption("exportOption-wholeDrawing-pdf", in: app)
        XCTAssertTrue(waitForShareSheet(in: app),
                      "Exporting with the folder path switched on should still reach the share sheet.")
    }

    func testFolderPathToggleIsHiddenForATopLevelDocument() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)
        openExportPicker(in: app)

        XCTAssertFalse(app.switches["exportIncludeFolderPath"].firstMatch.exists,
                       "A top-level document has no path to prefix, so the toggle should not be there.")
    }

    // MARK: - Steps

    private func launchWithSampleDocuments() -> XCUIApplication {
        let app = XCUIApplication()
        // Seeded documents already contain ink; XCUITest cannot draw, because the
        // canvas takes Apple Pencil touches only. An empty document would export
        // nothing and fail for the wrong reason.
        app.launchArguments.append("-TractSeedSampleDocuments")
        // Naming exports after their folder is a remembered preference, so a test
        // that switches it on would otherwise decide what every later test starts
        // with. `UserDefaults` reads launch arguments before stored values.
        app.launchArguments += ["-exportIncludesFolderPath", "NO"]
        // The filed document is reached through its folder card, which only the
        // grid has; the layout is remembered, so it has to be pinned.
        app.launchArguments += ["-libraryViewMode", "grid"]
        app.launch()
        return app
    }

    private func openSampleDocument(in app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wave study'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the Wave study drawing.")
        card.tap()
    }

    /// Opens "Problem set", the one seeded document whose ink carries problem
    /// tags — XCUITest can neither draw nor tag, so the chooser has nothing to
    /// offer in any other document.
    private func openTaggedSampleDocument(in app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Problem set'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the tagged problem set.")
        card.tap()
    }

    /// Opens "Filed away", the seeded document inside the "Homework" folder.
    private func openFiledSampleDocument(in app: XCUIApplication) {
        let folder = app.buttons["folderCard-Homework"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15),
                      "The seeded library should contain the Homework folder.")
        folder.tap()

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filed away'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The Homework folder should contain the filed drawing.")
        card.tap()
    }

    private func openExportPicker(in app: XCUIApplication) {
        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        XCTAssertTrue(app.buttons["exportOption-wholeDrawing-pdf"].firstMatch.waitForExistence(timeout: 10),
                      "The export picker should be on screen with its options.")
    }

    private func tapExportOption(_ identifier: String, in app: XCUIApplication) {
        let option = app.buttons[identifier].firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 10),
                      "The export picker should offer \(identifier).")
        option.tap()
    }

    /// `UIActivityViewController` exposes itself as "ActivityListView"; the Copy
    /// action is checked too because the container's identifier has moved between
    /// iOS releases, and either one on screen proves the sheet came up.
    private func waitForShareSheet(in app: XCUIApplication, timeout: TimeInterval = 20) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if app.otherElements["ActivityListView"].firstMatch.exists { return true }
            if app.buttons["Copy"].firstMatch.exists { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }
}
