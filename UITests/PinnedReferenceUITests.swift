import XCTest

/// A pinned reference takes real touches: a drag moves it, the corner handle
/// resizes it and its × closes it.
///
/// The pin is seeded rather than made here — making one needs a lasso, and
/// XCUITest cannot produce the Apple Pencil touches the lasso takes. Making a
/// pin is covered by the unit tests in `PinSelectionTests`.
///
/// One test, not three: each method pays a full app launch.
@MainActor
final class PinnedReferenceUITests: XCTestCase {
    func testPinnedReferenceMovesResizesAndUnpins() {
        let app = XCUIApplication()
        app.launchArguments += ["-TractSeedSampleDocuments", "-TractSeedPinnedReference"]
        app.launchArguments += ["-libraryViewMode", "grid"]
        app.launch()

        let card = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Problem set'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The seeded library should contain the tagged problem set.")
        card.tap()

        let pin = app.otherElements["pinnedReference"].firstMatch
        XCTAssertTrue(pin.waitForExistence(timeout: 15),
                      "The problem set should open with its seeded pin on screen.")

        // A double tap pans the page to the pin's source; the card itself, which
        // lives in screen space, must stay exactly where it is.
        let frameBeforeDoubleTap = pin.frame
        pin.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).doubleTap()
        XCTAssertEqual(pin.frame.midX, frameBeforeDoubleTap.midX, accuracy: 1,
                       "Double-tapping a pin should pan the page, not move the pin.")
        XCTAssertEqual(pin.frame.width, frameBeforeDoubleTap.width, accuracy: 1,
                       "Double-tapping a pin should not resize it.")

        let startFrame = pin.frame
        let body = pin.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        body.press(forDuration: 0.1, thenDragTo: body.withOffset(CGVector(dx: -200, dy: -150)))
        let movedFrame = pin.frame
        XCTAssertLessThan(movedFrame.midX, startFrame.midX - 100, "Dragging the pin should move it left.")
        XCTAssertLessThan(movedFrame.midY, startFrame.midY - 75, "Dragging the pin should move it up.")
        XCTAssertEqual(movedFrame.width, startFrame.width, accuracy: 1,
                       "Dragging the pin's body should not resize it.")

        let handle = app.descendants(matching: .any)["pinnedReferenceResize"].firstMatch
        XCTAssertTrue(handle.exists, "The pin should carry a resize handle.")
        let grip = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grip.press(forDuration: 0.1, thenDragTo: grip.withOffset(CGVector(dx: 120, dy: 60)))
        let resizedFrame = pin.frame
        XCTAssertGreaterThan(resizedFrame.width, movedFrame.width + 60,
                             "Dragging the corner handle outward should enlarge the pin.")
        XCTAssertEqual(resizedFrame.minX, movedFrame.minX, accuracy: 2,
                       "Resizing from the corner should keep the opposite edge still.")

        // Flung far past the leading edge, the pin must stop against it rather
        // than slide partly out of frame. Sideways only, so its × stays clear of
        // the top bar for the tap below; every edge is covered by the unit tests.
        let flingStart = pin.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        // Dragged to the screen's very edge rather than past it: XCUITest
        // cannot aim a touch off screen. Grabbed 30% in, that still asks the
        // card to overhang by 30% of its width.
        let screenEdge = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 2, dy: flingStart.screenPoint.y))
        flingStart.press(forDuration: 0.1, thenDragTo: screenEdge)
        XCTAssertEqual(pin.frame.minX, app.windows.firstMatch.frame.minX, accuracy: 2,
                       "A pin pushed past the leading edge should stop flush against it.")

        app.buttons["pinnedReferenceUnpin"].firstMatch.tap()
        XCTAssertTrue(pin.waitForNonExistence(timeout: 5), "Tapping × should unpin the reference.")
    }
}
