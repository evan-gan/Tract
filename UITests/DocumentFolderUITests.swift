import XCTest

/// The library's folders, driven the way a user drives them: the toolbar
/// buttons, the rename alert, the breadcrumb, and the outline's disclosure.
///
/// Every test launches with `-TractSeedSampleDocuments`, so the library always
/// starts as three top-level drawings plus a "Homework" folder holding one.
@MainActor
final class DocumentFolderUITests: XCTestCase {
    private func launchSeededLibrary() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-TractSeedSampleDocuments")
        // The layout is a remembered preference, so without pinning it here a
        // test that switches to the outline would change what every later test
        // sees. `UserDefaults` reads launch arguments before stored values.
        app.launchArguments += ["-libraryViewMode", "grid"]
        app.launch()
        XCTAssertTrue(app.buttons["New document"].firstMatch.waitForExistence(timeout: 15),
                      "The library should be on screen before the test starts.")
        return app
    }

    // MARK: - Grid

    func testSeededFolderIsShownInTheLibrary() {
        let app = launchSeededLibrary()

        XCTAssertTrue(app.buttons["folderCard-Homework"].firstMatch.waitForExistence(timeout: 15),
                      "A folder in the library should get its own card.")
    }

    func testOpeningAFolderShowsOnlyTheDocumentsInsideIt() {
        let app = launchSeededLibrary()

        app.buttons["folderCard-Homework"].firstMatch.tap()

        XCTAssertTrue(app.buttons.matching(labelBeginning: "Filed away").firstMatch.waitForExistence(timeout: 15),
                      "The document filed in the folder should be listed inside it.")
        XCTAssertFalse(app.buttons.matching(labelBeginning: "Wave study").firstMatch.exists,
                       "A top-level document should not appear inside a folder.")
    }

    func testTheNewFolderButtonAddsAFolderWithTheNameTheUserTyped() {
        let app = launchSeededLibrary()

        app.buttons["New folder"].firstMatch.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 5), "Creating a folder should ask for a name.")
        // The field arrives pre-filled with "New Folder", which has to go before
        // the typed name or the two run together.
        nameField.tap()
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        nameField.typeText("Algebra")
        app.buttons["Create"].firstMatch.tap()

        XCTAssertTrue(app.buttons["folderCard-Algebra"].firstMatch.waitForExistence(timeout: 15),
                      "The new folder should appear in the grid straight away.")
    }

    // MARK: - Breadcrumb

    func testInsideAFolderTheBreadcrumbShowsThePath() {
        let app = launchSeededLibrary()

        app.buttons["folderCard-Homework"].firstMatch.tap()

        XCTAssertTrue(app.buttons["libraryBackButton"].firstMatch.waitForExistence(timeout: 15),
                      "Inside a folder there should be a back button.")
        XCTAssertTrue(app.buttons["breadcrumb-Documents"].firstMatch.exists,
                      "The path should start at the top level.")
        XCTAssertTrue(app.buttons["breadcrumb-Homework"].firstMatch.exists,
                      "The path should end at the folder being shown.")
    }

    func testTheBackButtonReturnsToTheTopLevel() {
        let app = launchSeededLibrary()

        app.buttons["folderCard-Homework"].firstMatch.tap()
        let backButton = app.buttons["libraryBackButton"].firstMatch
        XCTAssertTrue(backButton.waitForExistence(timeout: 15))
        backButton.tap()

        XCTAssertTrue(app.buttons.matching(labelBeginning: "Wave study").firstMatch.waitForExistence(timeout: 15),
                      "Leaving a folder should show the top level again.")
    }

    func testTappingTheRootCrumbJumpsBackToTheTopLevel() {
        let app = launchSeededLibrary()

        app.buttons["folderCard-Homework"].firstMatch.tap()
        let rootCrumb = app.buttons["breadcrumb-Documents"].firstMatch
        XCTAssertTrue(rootCrumb.waitForExistence(timeout: 15))
        rootCrumb.tap()

        XCTAssertTrue(app.buttons.matching(labelBeginning: "Wave study").firstMatch.waitForExistence(timeout: 15),
                      "Tapping the first crumb should go back to the top level.")
    }

    // MARK: - Outline

    func testTheListViewExpandsAFolderInPlace() {
        let app = launchSeededLibrary()

        app.buttons["libraryViewModeToggle"].firstMatch.tap()

        let disclosure = app.buttons["folderDisclosure-Homework"].firstMatch
        XCTAssertTrue(disclosure.waitForExistence(timeout: 15),
                      "The outline should offer a way to open a folder in place.")
        XCTAssertFalse(app.buttons.matching(labelBeginning: "Filed away").firstMatch.exists,
                       "A collapsed folder should not be showing its contents.")

        disclosure.tap()

        XCTAssertTrue(app.buttons.matching(labelBeginning: "Filed away").firstMatch.waitForExistence(timeout: 15),
                      "Expanding a folder should list what is inside it without navigating.")
        XCTAssertTrue(app.buttons.matching(labelBeginning: "Wave study").firstMatch.exists,
                      "The rest of the library should stay on screen while a folder is open.")
    }

    func testTheViewModeToggleSwitchesBackToTheGrid() {
        let app = launchSeededLibrary()
        let toggle = app.buttons["libraryViewModeToggle"].firstMatch

        toggle.tap()
        XCTAssertTrue(app.buttons["folderDisclosure-Homework"].firstMatch.waitForExistence(timeout: 15),
                      "The first tap should show the outline, whose folders carry a disclosure chevron.")

        toggle.tap()
        XCTAssertTrue(app.buttons["folderCard-Homework"].firstMatch.waitForExistence(timeout: 15),
                      "The second tap should put the grid back.")
    }
}

private extension XCUIElementQuery {
    /// Document rows and cards are found by label, because their identifier is
    /// the document's UUID and their label starts with the title.
    func matching(labelBeginning prefix: String) -> XCUIElementQuery {
        matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
    }
}
