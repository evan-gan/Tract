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

    /// `.keepAlways` matters: without it the attachment is discarded for a
    /// passing test, and the script would find an empty result bundle.
    private func attachScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
