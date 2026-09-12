import XCTest

/// Captures the canvas as a PNG attachment so `./scripts/screenshot.sh` can pull
/// it out of the result bundle. This is how a UI change gets eyeballed without
/// opening Xcode or reaching for a device.
///
/// It carries no appearance logic of its own — the script sets the simulator's
/// light/dark appearance before launching, and the app follows system settings.
/// The assertions are only there to fail loudly if the shot would be of the
/// wrong screen; treat this as a capture tool, not a behaviour test.
@MainActor
final class CanvasSnapshotUITests: XCTestCase {
    func testCaptureCanvas() {
        let app = XCUIApplication()
        app.launch()

        let newDocument = app.buttons["New document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 15),
                      "The document list should offer a way to start a drawing.")
        newDocument.tap()

        XCTAssertTrue(app.otherElements["toolDock"].firstMatch
            .waitForExistence(timeout: 15),
                      "The canvas chrome should be on screen before the shot is taken.")

        attachScreenshot(named: "canvas")
    }

    /// Captures the document library with cards that have real previews on them.
    ///
    /// The drawings are seeded by the app on launch rather than drawn here: the
    /// canvas takes Apple Pencil touches only, and XCUITest cannot produce one.
    func testCaptureLibrary() {
        _ = launchSeededLibrary(viewMode: "grid")

        // Previews are read off disk per card; give them a beat to appear.
        Thread.sleep(forTimeInterval: 2)

        attachScreenshot(named: "library")
    }

    /// Captures the inside of a folder, which is the only place the breadcrumb
    /// appears — at the top level the navigation bar carries just the title.
    func testCaptureFolder() {
        let app = launchSeededLibrary(viewMode: "grid")

        let folder = app.buttons["folderCard-Homework"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15),
                      "The seeded library should contain the Homework folder.")
        folder.tap()

        XCTAssertTrue(app.buttons["libraryBackButton"].firstMatch.waitForExistence(timeout: 15),
                      "The breadcrumb should be on screen before the shot is taken.")
        Thread.sleep(forTimeInterval: 2)

        attachScreenshot(named: "folder")
    }

    /// Captures the library's outline with a folder open, which is the only way
    /// to see nesting — the grid shows one level at a time.
    func testCaptureLibraryList() {
        let app = launchSeededLibrary(viewMode: "list")

        let disclosure = app.buttons["folderDisclosure-Homework"].firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 15),
                      "The outline should be on screen before the shot is taken.")
        disclosure.tap()
        Thread.sleep(forTimeInterval: 2)

        attachScreenshot(named: "librarylist")
    }

    /// The layout is a remembered preference, so the shot has to say which one it
    /// wants; `UserDefaults` reads launch arguments before stored values.
    private func launchSeededLibrary(viewMode: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-TractSeedSampleDocuments")
        app.launchArguments += ["-libraryViewMode", viewMode]
        app.launchArguments += extraArguments
        app.launch()

        XCTAssertTrue(app.buttons["New document"].firstMatch.waitForExistence(timeout: 15),
                      "The library should be on screen before the shot is taken.")
        return app
    }

    /// Captures the export picker, which is the only way to see the layouts and
    /// their formats — the plain canvas shot shows just the Export button.
    ///
    /// It opens the *filed* document rather than a top-level one so the shot also
    /// shows the folder-path naming toggle, which a top-level document hides.
    func testCaptureExportPicker() {
        let app = launchSeededLibrary(viewMode: "grid")

        let folder = app.buttons["folderCard-Homework"].firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: 15),
                      "The seeded library should contain the Homework folder.")
        folder.tap()

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Filed away'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The Homework folder should contain the filed drawing.")
        card.tap()

        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        XCTAssertTrue(app.buttons["exportOption-wholeDrawing-pdf"].firstMatch.waitForExistence(timeout: 10),
                      "The picker should be on screen before the shot is taken.")
        // The options exist the instant the sheet is presented, but it is still
        // sliding up; shooting now catches it half way onto the screen.
        Thread.sleep(forTimeInterval: 2.5)

        attachScreenshot(named: "exportpicker")
    }

    /// Captures the export picker's problem chooser, with one problem ticked.
    ///
    /// It needs the seeded "Problem set" document: the chooser is built from
    /// *tagged* ink, and every other sample is untagged, which hides the group
    /// the shot is of — including in the `exportpicker` shot, which opens the
    /// filed document for the folder-path toggle.
    func testCaptureExportProblems() {
        let app = launchSeededLibrary(viewMode: "grid")

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Problem set'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the tagged problem set.")
        card.tap()

        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        let firstProblem = app.buttons["exportProblemChip-1"].firstMatch
        XCTAssertTrue(firstProblem.waitForExistence(timeout: 10),
                      "The picker should offer the document's problems as chips.")
        // The sheet is still sliding up when its chips first exist.
        Thread.sleep(forTimeInterval: 2.5)
        firstProblem.tap()
        // The card resizes as the summary line changes to name what is ticked.
        Thread.sleep(forTimeInterval: 1)

        attachScreenshot(named: "exportproblems")
    }

    /// Captures the spinner the picker shows while a pick renders.
    ///
    /// The seeded drawings render in milliseconds, which is far too fast to
    /// photograph, so the app is launched with `-TractSlowExport`: it holds each
    /// stage for a beat on the rendering thread. A real worksheet of a full
    /// canvas takes that long on its own.
    func testCaptureExportProgress() {
        let app = launchSeededLibrary(viewMode: "grid", extraArguments: ["-TractSlowExport"])

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wave study'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the Wave study drawing.")
        card.tap()

        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        let worksheetOption = app.buttons["exportOption-problemWorksheet-pdf"].firstMatch
        XCTAssertTrue(worksheetOption.waitForExistence(timeout: 10),
                      "The export picker should offer the problem worksheet as a PDF.")
        worksheetOption.tap()

        let progress = app.descendants(matching: .any)["exportProgress"].firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5),
                      "Picking a format should put progress on screen while it renders.")
        // Long enough for the sheet to finish resizing around the spinner and for
        // the run to be past "Preparing", which is the least interesting stage.
        Thread.sleep(forTimeInterval: 1.5)

        attachScreenshot(named: "exportprogress")
    }

    /// Captures the share sheet an export ends at.
    ///
    /// Worth its own shot because the sheet is system UI presented from inside
    /// the top bar's glass, and glass rewrites the appearance of everything under
    /// it — which is exactly how the sheet once came up in light mode on a dark
    /// device.
    func testCaptureShareSheet() {
        let app = launchSeededLibrary(viewMode: "grid")

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wave study'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the Wave study drawing.")
        card.tap()

        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        let pdfOption = app.buttons["exportOption-wholeDrawing-pdf"].firstMatch
        XCTAssertTrue(pdfOption.waitForExistence(timeout: 10),
                      "The export picker should offer the whole drawing as a PDF.")
        pdfOption.tap()

        // The sheet slides up and then fills in its activity rows; shooting on
        // first appearance catches an empty panel mid-animation.
        XCTAssertTrue(app.otherElements["ActivityListView"].firstMatch.waitForExistence(timeout: 20)
                      || app.buttons["Copy"].firstMatch.waitForExistence(timeout: 20),
                      "Exporting should reach the share sheet before the shot is taken.")
        Thread.sleep(forTimeInterval: 2.5)

        attachScreenshot(named: "sharesheet")
    }

    /// Captures the regions drawn around each problem's work.
    ///
    /// It opens the seeded "Problem set" document because the regions are built
    /// from *tagged* ink, and XCUITest can neither draw nor tag — every other
    /// sample document is untagged and would produce an empty shot.
    func testCaptureProblemBounds() {
        let app = launchSeededLibrary(viewMode: "grid")

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Problem set'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the tagged problem set.")
        card.tap()

        XCTAssertTrue(app.otherElements["toolDock"].firstMatch.waitForExistence(timeout: 15),
                      "The canvas chrome should be on screen before the shot is taken.")
        // The regions are traced once the document's strokes have loaded, which
        // happens a beat after the chrome appears.
        Thread.sleep(forTimeInterval: 2.5)

        attachScreenshot(named: "problembounds")
    }

    /// Captures the problem picker with a tree in it — a cold canvas has only
    /// dashes and a single uncreated row, which shows none of the drum.
    func testCaptureProblemPicker() {
        let app = XCUIApplication()
        app.launch()

        let newDocument = app.buttons["New document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 15),
                      "The document list should offer a way to start a drawing.")
        newDocument.tap()

        // The document's own load resets the picker, so picking before it lands
        // would have the tree wiped out from under the shot.
        Thread.sleep(forTimeInterval: 2)
        // The wheel is shut until the tag is tapped, and a shut wheel is not
        // what this shot is of.
        let tag = app.buttons["problemPickerValue"]
        XCTAssertTrue(tag.waitForExistence(timeout: 10),
                      "The chrome should offer the problem tag.")
        tag.tap()
        Thread.sleep(forTimeInterval: 0.8)
        buildSampleProblemTree(in: app)
        // The columns are still settling between the carets right after the last
        // pick.
        Thread.sleep(forTimeInterval: 1.5)

        attachScreenshot(named: "problempicker")
    }

    /// Builds 1, 1a, 1b, 1b.I by tapping the wheel's own rows.
    private func buildSampleProblemTree(in app: XCUIApplication) {
        func pickRow(_ value: String, inColumn level: Int) {
            let row = app.buttons["problemWheelOption-\(level)-\(value)"]
            XCTAssertTrue(row.waitForExistence(timeout: 10),
                          "Column \(level) should offer the row '\(value)'.")
            row.tap()
            Thread.sleep(forTimeInterval: 0.6)
        }

        pickRow("1", inColumn: 0)
        pickRow("a", inColumn: 1)
        pickRow("b", inColumn: 1)
        pickRow("I", inColumn: 2)
    }

    /// `.keepAlways` matters: without it the attachment is discarded for a
    /// passing test, and the script would find an empty result bundle.
    private func attachScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
