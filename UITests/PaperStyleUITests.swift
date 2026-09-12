import XCTest

/// The paper picker's wiring: a popover from the dock, a pick that sticks, and a
/// choice that is still there when the document is reopened. The palette itself
/// is covered by `CanvasBackgroundStyleTests`; this is the part only a running
/// app can prove.
@MainActor
final class PaperStyleUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        openCanvas()
    }

    func testPickingAPaperMarksItAsTheCurrentSheet() {
        openPaperPicker()

        let blueprint = app.buttons["paperStyleOption-blueprint"].firstMatch
        XCTAssertTrue(blueprint.waitForExistence(timeout: 10),
                      "The picker should list every paper it offers.")
        blueprint.tap()

        XCTAssertEqual(paperButton().value as? String, "Blueprint",
                       "The dock swatch should advertise the paper that was picked.")

        openPaperPicker()
        XCTAssertTrue(app.buttons["paperStyleOption-blueprint"].firstMatch.isSelected,
                      "Reopening the picker should show the chosen paper as selected.")
    }

    /// The paper is document content, so it has to survive the round trip to disk
    /// — leaving the canvas flushes the save, and reopening reloads it.
    func testTheChosenPaperSurvivesClosingTheDocument() {
        openPaperPicker()
        app.buttons["paperStyleOption-legalPad"].firstMatch.tap()

        let back = app.buttons["Documents"].firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "The canvas should offer a way back.")
        back.tap()

        // Cards are labelled by title; a document made by this test is untitled.
        let card = app.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Untitled"))
            .element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 15),
                      "The library should show the document that was just closed.")
        card.tap()

        XCTAssertTrue(paperButton().waitForExistence(timeout: 15))
        XCTAssertEqual(paperButton().value as? String, "Legal pad",
                       "A reopened document should come back on the paper it was saved with.")
    }

    // MARK: - Helpers

    /// Re-queried every time: an XCUIElement can otherwise serve a stale value.
    private func paperButton() -> XCUIElement {
        app.buttons["paperStyleButton"].firstMatch
    }

    private func openPaperPicker() {
        let button = paperButton()
        XCTAssertTrue(button.waitForExistence(timeout: 15), "The dock should offer the paper picker.")
        button.tap()
    }

    /// The app opens on the document list; the dock only exists on the canvas.
    private func openCanvas() {
        let newDocument = app.buttons["New document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 15))
        newDocument.tap()
    }
}
