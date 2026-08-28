import XCTest

/// Exercises the one part of the dock that unit tests cannot reach: the drag
/// gesture itself. The quadrant maths is covered by `DockEdgeTests`; this
/// verifies the gesture is wired to the dock and actually re-parks it.
@MainActor
final class ToolDockDragUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        openCanvas()
    }

    func testDraggingTheDockToTheLeftEdgeMovesItOffTheBottom() {
        let dockedAtBottom = handleFrame()
        XCTAssertGreaterThan(dockedAtBottom.midY, app.frame.height / 2,
                             "The dock starts parked on the bottom edge.")

        dragHandle(to: CGVector(dx: 0.06, dy: 0.5))

        let dockedOnTheSide = handleFrame()
        XCTAssertLessThan(dockedOnTheSide.midX, dockedAtBottom.midX,
                          "The dock should have moved toward the left edge.")
        XCTAssertLessThan(dockedOnTheSide.midY, dockedAtBottom.midY,
                          "The dock should have left the bottom edge.")
        // The grip is drawn across the dock, so a vertical dock has a wide grip.
        XCTAssertGreaterThan(dockedOnTheSide.width, dockedOnTheSide.height,
                             "Parked on a side edge, the dock should have re-flowed into a column.")
    }

    func testDraggingTheDockToTheTopEdgeKeepsItHorizontal() {
        let dockedAtBottom = handleFrame()

        dragHandle(to: CGVector(dx: 0.5, dy: 0.18))

        let dockedOnTop = handleFrame()
        XCTAssertLessThan(dockedOnTop.midY, dockedAtBottom.midY / 2,
                          "The dock should have moved to the top edge.")
        XCTAssertGreaterThan(dockedOnTop.height, dockedOnTop.width,
                             "Parked on the top edge, the dock should still be a row.")
    }

    // MARK: - Helpers

    /// Re-queries every time: an XCUIElement can otherwise serve a stale frame.
    private func handleFrame() -> CGRect {
        let handle = app.otherElements["Drag to move the tool bar"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 15), "The dock's drag handle should be on screen.")
        return handle.frame
    }

    /// A slow drag with a hold: SwiftUI needs the intermediate touch events, and
    /// the hold lets the settle animation finish before the frame is read.
    private func dragHandle(to destination: CGVector) {
        app.otherElements["Drag to move the tool bar"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2,
                   thenDragTo: app.coordinate(withNormalizedOffset: destination),
                   withVelocity: .slow,
                   thenHoldForDuration: 0.6)
    }

    /// The app opens on the document list; the dock only exists on the canvas.
    private func openCanvas() {
        let newDocument = app.buttons["New document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 15))
        newDocument.tap()
    }
}
