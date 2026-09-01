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
        let dockedAtBottom = dockFrame()
        XCTAssertGreaterThan(dockedAtBottom.midY, app.frame.height / 2,
                             "The dock starts parked on the bottom edge.")

        dragDock(to: CGVector(dx: 0.06, dy: 0.5))

        let dockedOnTheSide = dockFrame()
        XCTAssertLessThan(dockedOnTheSide.midX, dockedAtBottom.midX,
                          "The dock should have moved toward the left edge.")
        XCTAssertLessThan(dockedOnTheSide.midY, dockedAtBottom.midY,
                          "The dock should have left the bottom edge.")
        XCTAssertGreaterThan(dockedOnTheSide.height, dockedOnTheSide.width,
                             "Parked on a side edge, the dock should have re-flowed into a column.")
    }

    func testDraggingTheDockToTheTopEdgeKeepsItHorizontal() {
        let dockedAtBottom = dockFrame()

        dragDock(to: CGVector(dx: 0.5, dy: 0.18))

        let dockedOnTop = dockFrame()
        XCTAssertLessThan(dockedOnTop.midY, dockedAtBottom.midY / 2,
                          "The dock should have moved to the top edge.")
        XCTAssertGreaterThan(dockedOnTop.width, dockedOnTop.height,
                             "Parked on the top edge, the dock should still be a row.")
    }

    /// The dock is almost entirely buttons, so a finger grabbing "the bar" nearly
    /// always lands on one. If the drag does not outrank them, the dock can only
    /// be moved from the slivers of padding between its controls.
    func testDraggingFromAToolButtonMovesTheDock() {
        let dockedAtBottom = dockFrame()

        drag(app.buttons["Pen"].firstMatch, to: CGVector(dx: 0.94, dy: 0.5))

        let dockedOnTheSide = dockFrame()
        XCTAssertGreaterThan(dockedOnTheSide.midX, dockedAtBottom.midX,
                             "Dragging from a tool button should have moved the dock right.")
        XCTAssertLessThan(dockedOnTheSide.midY, dockedAtBottom.midY,
                          "Dragging from a tool button should have moved it off the bottom.")
    }

    /// The other half of the same bargain: a drag that outranks the buttons must
    /// not swallow their taps, and must not fire one when the dock is dropped.
    func testTappingAToolButtonStillSelectsIt() {
        let eraser = app.buttons["Eraser"].firstMatch
        XCTAssertTrue(eraser.waitForExistence(timeout: 15))
        XCTAssertFalse(eraser.isSelected, "The canvas opens on the pen.")

        eraser.tap()

        XCTAssertTrue(app.buttons["Eraser"].firstMatch.isSelected,
                      "A tap on the dock should still reach the button under it.")
    }

    func testDraggingFromAColorSwatchDoesNotChangeTheInk() {
        app.buttons["Eraser"].firstMatch.tap()

        // Picking an ink implies drawing with it, so a swatch that fired here
        // would hand the tool back to the pen — which is what this detects.
        drag(colorSwatch(), to: CGVector(dx: 0.5, dy: 0.18))

        XCTAssertTrue(app.buttons["Eraser"].firstMatch.isSelected,
                      "Dropping the dock must not also trigger the swatch it started on.")
    }

    // MARK: - Helpers

    /// The rail's labels carry the colour's hex, so the swatches are found by
    /// position in the dock rather than by naming one particular colour.
    private func colorSwatch() -> XCUIElement {
        let swatches = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ink colour"))
        XCTAssertGreaterThan(swatches.count, 0, "The dock should show its quick ink colours.")
        return swatches.element(boundBy: 0)
    }

    /// Re-queries every time: an XCUIElement can otherwise serve a stale frame.
    private func dockFrame() -> CGRect {
        let dock = app.otherElements["toolDock"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 15), "The tool dock should be on screen.")
        return dock.frame
    }

    /// A slow drag with a hold: SwiftUI needs the intermediate touch events, and
    /// the hold lets the settle animation — which runs for the better part of a
    /// second — finish before the frame is read. Started from the dock's own
    /// edge padding so the touch does not land on one of its controls.
    private func dragDock(to destination: CGVector) {
        drag(app.otherElements["toolDock"].firstMatch, to: destination)
    }

    /// Drags from the centre of `origin` to a normalised point on screen.
    private func drag(_ origin: XCUIElement, to destination: CGVector) {
        XCTAssertTrue(origin.waitForExistence(timeout: 15), "The drag origin should be on screen.")
        origin
            .coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.2,
                   thenDragTo: app.coordinate(withNormalizedOffset: destination),
                   withVelocity: .slow,
                   thenHoldForDuration: 1.8)
    }

    /// The app opens on the document list; the dock only exists on the canvas.
    private func openCanvas() {
        let newDocument = app.buttons["New document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 15))
        newDocument.tap()
    }
}
