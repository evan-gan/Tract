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

    // MARK: - Steps

    private func launchWithSampleDocuments() -> XCUIApplication {
        let app = XCUIApplication()
        // Seeded documents already contain ink; XCUITest cannot draw, because the
        // canvas takes Apple Pencil touches only. An empty document would export
        // nothing and fail for the wrong reason.
        app.launchArguments.append("-TractSeedSampleDocuments")
        app.launch()
        return app
    }

    private func openSampleDocument(in app: XCUIApplication) {
        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wave study'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the Wave study drawing.")
        card.tap()
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
