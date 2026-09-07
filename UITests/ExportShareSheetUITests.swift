import XCTest

/// Smoke test: a single export, from a freshly launched app, reaches a share
/// sheet that actually has content in it.
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

        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        let pdfOption = app.buttons["Export as PDF"].firstMatch
        XCTAssertTrue(pdfOption.waitForExistence(timeout: 10),
                      "The expanded control should offer PDF as a format.")
        pdfOption.tap()

        XCTAssertTrue(waitForShareSheet(in: app),
                      "The share sheet should appear on the very first export, "
                      + "not only after a previous one has populated the view's state.")
    }

    /// The problem sheet is a second PDF behind the same control, and the two are
    /// told apart only by their button labels — so the wiring is worth a test.
    func testProblemSheetIsOfferedAsItsOwnFormat() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)

        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        let problemsOption = app.buttons["Export as Problems"].firstMatch
        XCTAssertTrue(problemsOption.waitForExistence(timeout: 10),
                      "The expanded control should offer the per-problem sheet alongside PDF.")
        problemsOption.tap()

        XCTAssertTrue(waitForShareSheet(in: app),
                      "Exporting the problem sheet should reach the share sheet. "
                      + "The sample drawings carry no tags, so this also proves an "
                      + "all-untagged document still produces its one explanatory page.")
    }

    /// The raw-data export shares a file rather than a picture, and it is the one
    /// format whose whole point is leaving the app — so the path out is tested.
    func testJSONDataExportIsOfferedAsItsOwnFormat() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)

        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        let jsonOption = app.buttons["Export as JSON"].firstMatch
        XCTAssertTrue(jsonOption.waitForExistence(timeout: 10),
                      "The expanded control should offer the raw JSON data export.")
        jsonOption.tap()

        XCTAssertTrue(waitForShareSheet(in: app),
                      "Exporting the raw data should reach the share sheet.")
    }

    // MARK: - Folder path in the file name

    /// The toggle names the file after the folders holding the document, so it
    /// only means anything for a document that is actually filed somewhere.
    func testFolderPathToggleIsOfferedForAFiledDocument() throws {
        let app = launchWithSampleDocuments()
        openFiledSampleDocument(in: app)

        expandExportControl(in: app)

        let pathToggle = app.buttons["exportIncludeFolderPath"].firstMatch
        XCTAssertTrue(pathToggle.waitForExistence(timeout: 10),
                      "A document inside a folder should offer the folder-path naming toggle.")
        pathToggle.tap()

        app.buttons["Export as PDF"].firstMatch.tap()
        XCTAssertTrue(waitForShareSheet(in: app),
                      "Exporting with the folder path switched on should still reach the share sheet.")
    }

    func testFolderPathToggleIsHiddenForATopLevelDocument() throws {
        let app = launchWithSampleDocuments()
        openSampleDocument(in: app)

        expandExportControl(in: app)

        XCTAssertFalse(app.buttons["exportIncludeFolderPath"].firstMatch.exists,
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

    private func expandExportControl(in app: XCUIApplication) {
        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        XCTAssertTrue(app.buttons["Export as PDF"].firstMatch.waitForExistence(timeout: 10),
                      "The control should expand into its format options.")
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
