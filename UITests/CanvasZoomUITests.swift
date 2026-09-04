import XCTest

/// Pinch-to-zoom is UIKit gesture code, so the limits can only be exercised with
/// real touches. The zoom indicator is the read-out under test.
@MainActor
final class CanvasZoomUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        openCanvas()
    }

    func testTheCanvasOpensAtOneHundredPercent() {
        XCTAssertEqual(zoomPercent(), 100)
    }

    func testPinchingInStopsAtFiveHundredPercent() {
        // Repeated pinches: one synthetic pinch spreads the fingers by a bounded
        // amount, so the cap is only reached by asking for far more than it.
        pinchRepeatedly(scale: 3, velocity: 3)

        XCTAssertEqual(zoomPercent(), 400, "Zooming in should stop at the 400% cap.")
        attachScreenshot(named: "zoomedInCanvas")
    }

    func testPinchingOutStopsAtTenPercent() {
        pinchRepeatedly(scale: 0.35, velocity: -3)

        XCTAssertEqual(zoomPercent(), 10, "Zooming out should stop at the 10% floor.")
        attachScreenshot(named: "zoomedOutCanvas")
    }

    func testResettingTheZoomReturnsToOneHundredPercent() {
        pinchRepeatedly(scale: 3, velocity: 3)
        zoomIndicator().tap()
        XCTAssertEqual(zoomPercent(), 100)
    }

    // MARK: - Helpers

    private func pinchRepeatedly(scale: CGFloat, velocity: CGFloat, times: Int = 8) {
        for _ in 0 ..< times {
            app.pinch(withScale: scale, velocity: velocity)
        }
    }

    private func zoomIndicator() -> XCUIElement {
        let indicator = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Zoom"))
            .firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 15), "The zoom pill should be on screen.")
        return indicator
    }

    /// Reads the percentage back out of "Zoom 250%. Tap to reset."
    private func zoomPercent() -> Int {
        let label = zoomIndicator().label
        let digits = label.drop { !$0.isNumber }.prefix { $0.isNumber }
        guard let percent = Int(digits) else {
            XCTFail("Could not read a zoom percentage out of '\(label)'.")
            return 0
        }
        return percent
    }

    private func attachScreenshot(named name: String) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func openCanvas() {
        let newDocument = app.buttons["New document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 15))
        newDocument.tap()
    }
}
