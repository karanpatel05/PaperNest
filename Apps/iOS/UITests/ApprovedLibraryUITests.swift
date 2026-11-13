import XCTest

/// Runs against disposable real stores; tests route through the redesigned controls.
@MainActor final class ApprovedLibraryUITests: XCTestCase {
    func testDocumentFavoritesFilterAndImportRemainReachable() {
        let app = launch()
        defer { app.terminate() }
        navigate("home-documents", sidebar: "All Documents", in: app)
        let favorites = app.buttons["library-filter-favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 10))
        favorites.tap()
        XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
        app.buttons["library-filter-recent"].tap()
        XCTAssertTrue(app.buttons["library-import"].waitForExistence(timeout: 5))
        app.buttons["library-import"].tap()
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["library-filter-recent"].waitForExistence(timeout: 5))
    }

    func testNotebookCoverGridCreatesAndReopensRealNotebook() {
        let app = launch()
        defer { app.terminate() }
        navigate("home-notes", sidebar: "Notes", in: app)
        XCTAssertTrue(app.buttons["notes-create-empty"].waitForExistence(timeout: 10))
        app.buttons["notes-create-empty"].tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Cover Test")
        app.buttons["notebook-create"].tap()
        XCTAssertTrue(app.navigationBars["Cover Test"].waitForExistence(timeout: 10))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["notes-create-tile"].waitForExistence(timeout: 10))
        app.buttons["notes-create-tile"].tap()
        XCTAssertTrue(app.textFields["notebook-name"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].firstMatch.tap()
        let notebook = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cover Test")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout: 5))
        notebook.tap()
        XCTAssertTrue(app.navigationBars["Cover Test"].waitForExistence(timeout: 5))
    }

    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-approved-library-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)",
                               "-notebookLibraryLayout", "grid", "-libraryLayout", "list"]
        app.launch()
        XCTAssertTrue(app.buttons["home-profile"].waitForExistence(timeout: 20))
        return app
    }

    private func navigate(_ identifier: String, sidebar title: String, in app: XCUIApplication) {
        let button = app.buttons[identifier]
        if button.exists, button.isHittable { button.tap() }
        else {
            // The phone reaches documents through its Files tab; the wide
            // sidebar lists them directly.
            let files = app.buttons["home-files"]
            if files.exists, files.isHittable { files.tap() }
            let row = app.cells.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            // Wide sidebar rows contain explicit Buttons. Address their action,
            // rather than asking the selectable cell to change its own selection.
            let destination = row.buttons[title]
            if destination.exists { destination.tap() } else { row.tap() }
        }
        let arrived = app.navigationBars[title].waitForExistence(timeout: 10)
        if !arrived {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "library-navigation-failure"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "library-navigation-failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(arrived, "The requested library destination must open before testing its controls")
    }
}
