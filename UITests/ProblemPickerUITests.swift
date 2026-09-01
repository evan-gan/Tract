import XCTest

/// Drives the problem wheel the way a hand does: rows tapped, and a column
/// flicked.
///
/// These are here because the top chrome is where this app's touch handling has
/// gone wrong before — taps on the old segmented picker were delivered to the
/// wrong slot, and its drag swallowed its own taps. A scroll view should not
/// have either problem, and this is what says so.
@MainActor
final class ProblemPickerUITests: XCTestCase {
    private func openNewDocument() -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()

        let newDocument = app.buttons["New document"].firstMatch
        XCTAssertTrue(newDocument.waitForExistence(timeout: 15))
        newDocument.tap()
        // Opening the document restores the picker from disk, which would wipe
        // out anything picked before it lands.
        XCTAssertTrue(app.buttons["problemPickerValue"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)
        expandWheel(in: app)
        return app
    }

    /// The wheel lives shut over the page, so every test opens it first — by the
    /// value, which is the target a hand actually goes for.
    private func expandWheel(in app: XCUIApplication) {
        app.buttons["problemPickerValue"].tap()
        XCTAssertTrue(app.scrollViews["problemWheel0"].waitForExistence(timeout: 5),
                      "Tapping the tag should show the three columns.")
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Taps a row by the value written on it. `"none"` is the dash.
    private func pickRow(_ value: String, inColumn level: Int, in app: XCUIApplication) {
        let row = app.buttons["problemWheelOption-\(level)-\(value)"]
        XCTAssertTrue(row.waitForExistence(timeout: 5),
                      "Column \(level) should offer the row '\(value)'.")
        row.tap()
        // The column scrolls to the picked row; reading it back mid-animation
        // sees the old value.
        Thread.sleep(forTimeInterval: 0.6)
    }

    private func selectedValues(in app: XCUIApplication) -> [String] {
        (0 ... 2).map { app.scrollViews["problemWheel\($0)"].value as? String ?? "" }
    }

    /// Each column must act on its own level — the bug the old control had
    /// delivered a tap on the letter to the numeral beside it.
    func testPickingRowsBuildsTheTree() {
        let app = openNewDocument()

        pickRow("1", inColumn: 0, in: app)
        pickRow("a", inColumn: 1, in: app)
        pickRow("b", inColumn: 1, in: app)
        pickRow("I", inColumn: 2, in: app)

        XCTAssertEqual(selectedValues(in: app), ["1", "b", "I"])
    }

    /// The dash unsets its level and everything under it, which is the only way
    /// back to tagging a whole problem once its parts exist.
    func testTheDashUnsetsTheLevelsBelowIt() {
        let app = openNewDocument()
        pickRow("1", inColumn: 0, in: app)
        pickRow("a", inColumn: 1, in: app)
        pickRow("I", inColumn: 2, in: app)
        XCTAssertEqual(selectedValues(in: app), ["1", "a", "I"])

        pickRow("none", inColumn: 1, in: app)

        XCTAssertEqual(selectedValues(in: app), ["1", "—", "—"])
    }

    /// A long drag moves as far as it is dragged. The wheel has no momentum,
    /// but the hand is never argued with: this covers a fix for a column that
    /// snapped back to one value however far it was pulled.
    func testALongDragMovesAsFarAsItIsDragged() {
        let app = openNewDocument()
        for value in ["1", "2", "3", "4"] { pickRow(value, inColumn: 0, in: app) }
        XCTAssertEqual(selectedValues(in: app).first, "4")

        // The column is three rows tall, so a full column of travel is three
        // values back: 4 → 1.
        let column = app.scrollViews["problemWheel0"]
        column.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: column.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.5)),
                withVelocity: .slow,
                thenHoldForDuration: 0.3
            )
        Thread.sleep(forTimeInterval: 1)

        let landed = selectedValues(in: app).first ?? ""
        XCTAssertTrue(["1", "2"].contains(landed),
                      "A drag across the whole column should move several values, not one — landed on \(landed).")
    }

    /// One short drag, one value — the bug this covers needed two drags before
    /// the number moved, because the column was reporting a position it had only
    /// passed through.
    func testAShortDragMovesTheColumnStraightAway() {
        let app = openNewDocument()
        pickRow("1", inColumn: 0, in: app)
        pickRow("2", inColumn: 0, in: app)
        XCTAssertEqual(selectedValues(in: app).first, "2")

        let column = app.scrollViews["problemWheel0"]
        // Roughly one row down: the column is three rows tall.
        column.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.05,
                thenDragTo: column.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)),
                withVelocity: .slow,
                thenHoldForDuration: 0.1
            )
        Thread.sleep(forTimeInterval: 1)

        XCTAssertEqual(selectedValues(in: app).first, "1",
                       "A single short drag should have moved the column one value.")
    }

    /// The uncreated row at the end of a column is what adds to the tree, so a
    /// hard flick must not be able to ride it: each new problem would grow the
    /// column by another one, and a single throw would leave a pile of empty
    /// problems behind.
    func testFlickingCannotRunAwayCreatingProblems() {
        let app = openNewDocument()

        app.scrollViews["problemWheel0"].swipeUp(velocity: .fast)
        Thread.sleep(forTimeInterval: 1.5)

        XCTAssertFalse(app.buttons["problemWheelOption-0-3"].exists,
                       "One flick on a cold picker should not have created three problems.")
    }

    /// The tag opens the wheel — `openNewDocument` has already proved that — and
    /// going back to the page shuts it again, leaving the tag reading whatever
    /// new ink is now filed under.
    func testTappingTheTagOpensAndTheCanvasClosesIt() {
        let app = openNewDocument()
        pickRow("1", inColumn: 0, in: app)

        // Anywhere well below the chrome is paper.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        Thread.sleep(forTimeInterval: 1)

        XCTAssertFalse(app.scrollViews["problemWheel0"].exists,
                       "Going back to the page should have folded the wheel away.")
        let tag = app.buttons["problemPickerValue"]
        XCTAssertTrue(tag.exists)
        XCTAssertEqual(tag.value as? String, "1",
                       "The tag should still read what new ink is filed under.")
    }

    /// The chevron is the other way in and the only way out, so it has to work
    /// on its own — the tag is gone from the bar while the drums are up.
    func testTheChevronOpensAndShutsTheWheel() {
        let app = XCUIApplication()
        app.launch()
        app.buttons["New document"].firstMatch.tap()
        XCTAssertTrue(app.buttons["problemPickerCollapsed"].waitForExistence(timeout: 15))
        Thread.sleep(forTimeInterval: 1.5)

        app.buttons["problemPickerCollapsed"].tap()
        XCTAssertTrue(app.scrollViews["problemWheel0"].waitForExistence(timeout: 5),
                      "The chevron should open the wheel.")

        app.buttons["problemPickerCollapsed"].tap()
        Thread.sleep(forTimeInterval: 1)

        XCTAssertFalse(app.scrollViews["problemWheel0"].exists,
                       "The chevron should shut it again.")
    }

    /// Holding a value offers to delete it, named after the problem it would
    /// remove — the only way to take a problem back out of the tree.
    func testHoldingARowOffersToDeleteThatProblem() {
        let app = openNewDocument()
        pickRow("1", inColumn: 0, in: app)
        pickRow("2", inColumn: 0, in: app)
        XCTAssertEqual(selectedValues(in: app).first, "2")

        app.buttons["problemWheelOption-0-2"].press(forDuration: 1.2)
        let deleteButton = app.buttons["problemDelete-2"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5),
                      "Holding problem 2 should offer to delete it by name.")
        deleteButton.tap()
        Thread.sleep(forTimeInterval: 1.5)

        // Deleting what the picker was pointed at leaves it pointed at nothing,
        // so new ink goes untagged rather than to a problem that is gone.
        XCTAssertEqual(selectedValues(in: app).first, "—")
    }
}
