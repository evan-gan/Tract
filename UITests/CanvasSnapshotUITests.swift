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

        XCTAssertTrue(app.otherElements["Drag to move the tool bar"].firstMatch
            .waitForExistence(timeout: 15),
                      "The canvas chrome should be on screen before the shot is taken.")

        attachScreenshot(named: "canvas")
    }

    /// Captures the document library with cards that have real previews on them.
    ///
    /// The drawings are seeded by the app on launch rather than drawn here: the
    /// canvas takes Apple Pencil touches only, and XCUITest cannot produce one.
    func testCaptureLibrary() {
        let app = XCUIApplication()
        app.launchArguments.append("-TractSeedSampleDocuments")
        app.launch()

        XCTAssertTrue(app.buttons["New document"].firstMatch.waitForExistence(timeout: 15),
                      "The library should be on screen before the shot is taken.")
        // Previews are read off disk per card; give them a beat to appear.
        Thread.sleep(forTimeInterval: 2)

        attachScreenshot(named: "library")
    }

    /// Captures the Export control expanded, which is the only way to see the
    /// format options — the plain canvas shot shows just the collapsed button.
    func testCaptureExportMenu() {
        let app = XCUIApplication()
        app.launchArguments.append("-TractSeedSampleDocuments")
        app.launch()

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Wave study'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the Wave study drawing.")
        card.tap()

        let exportButton = app.buttons["Export"].firstMatch
        XCTAssertTrue(exportButton.waitForExistence(timeout: 15),
                      "The canvas should offer an Export button.")
        exportButton.tap()

        XCTAssertTrue(app.buttons["Export as PDF"].firstMatch.waitForExistence(timeout: 10),
                      "The control should have expanded before the shot is taken.")
        // The formats exist the instant the state flips, but the glass is still
        // widening; shooting now catches a half-morphed pill.
        Thread.sleep(forTimeInterval: 1.5)

        attachScreenshot(named: "exportmenu")
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
