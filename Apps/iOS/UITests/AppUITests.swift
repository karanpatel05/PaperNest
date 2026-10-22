import XCTest

/// Drives the real app in the iOS Simulator. Run with `scripts/ui-test-ios.sh`,
/// which seeds the library at `libraryPath` with a page named "Crop target".
@MainActor
final class AppUITests: XCTestCase {
    static let libraryPath = "/tmp/papernest-uitest-library"

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", Self.libraryPath, "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-libraryLayout", "grid"] + extra
        app.launch()
        return app
    }

    /// iPhone opens on the home (Scan/Import, Recent, library, folders).
    /// Tests that need the full grid go to All Documents first.
    private func showAllDocuments(_ app: XCUIApplication) {
        let row = app.staticTexts["All Documents"]
        if UIDevice.current.userInterfaceIdiom == .phone, row.waitForExistence(timeout: 15) { row.tap() }
    }

    /// "70% wide by 75% tall" → (70, 75)
    private func keptPercentages(_ value: Any?) throws -> (Double, Double) {
        let text = try XCTUnwrap(value as? String)
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        XCTAssertEqual(numbers.count, 2, "unexpected crop value: \(text)")
        return (numbers[0], numbers[1])
    }

    func testDraggingTheTopLeftCornerCropsThePageAndTheCropIsSaved() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugOpenItem", "Crop target", "-PaperNestDebugShowCrop", "YES"])
        let area = app.descendants(matching: .any)["crop-area"]
        XCTAssertTrue(area.waitForExistence(timeout: 15), "crop editor did not open")
        let start = try keptPercentages(area.value)
        XCTAssertEqual(start.0, 100)
        XCTAssertEqual(start.1, 100)

        // Grab the top-left corner and drag it 30% across and 25% down.
        let corner = area.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.01))
        let target = area.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.26))
        corner.press(forDuration: 0.3, thenDragTo: target)
        let dragged = try keptPercentages(area.value)
        XCTAssertEqual(dragged.0, 70, accuracy: 4)
        XCTAssertEqual(dragged.1, 75, accuracy: 4)

        app.buttons["crop-done"].tap()
        XCTAssertTrue(area.waitForNonExistence(timeout: 10), "crop editor did not close")

        // Reopening shows the saved crop, not the full page.
        app.buttons["Crop"].tap()
        let reopened = app.descendants(matching: .any)["crop-area"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        let saved = try keptPercentages(reopened.value)
        XCTAssertEqual(saved.0, dragged.0, accuracy: 1)
        XCTAssertEqual(saved.1, dragged.1, accuracy: 1)
    }

    /// Smoke test for iPhone sidebar navigation: back to the sidebar, into
    /// another scope and back again, then open a document. It does not
    /// reproduce the one-off "thumbnail tap selected Favorites" glitch seen on
    /// 2026-10-21 (it also passes with the old binding); see TEST_MATRIX.md.
    func testSidebarNavigationKeepsWorkingAfterGoingBack() throws {
        continueAfterFailure = false
        let app = launch([])
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("compact-width behaviour") }
        let document = app.descendants(matching: .any)["Crop target, 1 page"]
        XCTAssertTrue(document.waitForExistence(timeout: 15), "home did not open")

        app.staticTexts["Favorites"].tap()
        XCTAssertTrue(app.staticTexts["No Favorites"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["All Documents"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5), "All Documents did not reopen")

        document.tap()
        XCTAssertTrue(app.buttons["Crop"].waitForExistence(timeout: 5), "document did not open")
    }

    func testSettingsShowsTheLibraryAndExportsABackup() throws {
        continueAfterFailure = false
        let app = launch([])
        XCTAssertTrue(app.descendants(matching: .any)["Crop target, 1 page"].waitForExistence(timeout: 15))

        app.buttons["library-settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Documents"].exists)

        app.buttons["Export All Documents…"].tap()
        XCTAssertTrue(app.buttons["Save…"].waitForExistence(timeout: 20), "backup did not finish")

        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
    }

    func testLibraryLayoutSwitchStillOpensDocumentsAndEditingTools() throws {
        continueAfterFailure = false
        let app = launch([])
        showAllDocuments(app)
        let document = app.descendants(matching: .any)["Crop target, 1 page"]
        XCTAssertTrue(document.waitForExistence(timeout: 15))
        let layouts = app.segmentedControls["library-layout"]
        layouts.buttons["List"].tap()
        XCTAssertTrue(layouts.buttons["List"].isSelected)
        XCTAssertTrue(document.isHittable)
        layouts.buttons["Grid"].tap()
        XCTAssertTrue(layouts.buttons["Grid"].isSelected)
        layouts.buttons["List"].tap()
        document.tap()
        XCTAssertTrue(app.buttons["editor-crop"].waitForExistence(timeout: 5))
        app.buttons["Rotate"].tap()
        app.buttons["Rotate Right"].tap()
        app.buttons["editor-crop"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["crop-area"].waitForExistence(timeout: 5))
        app.buttons["crop-done"].tap()
        XCTAssertTrue(app.buttons["editor-export"].waitForExistence(timeout: 5))
        app.buttons["editor-export"].tap()
        XCTAssertTrue(app.staticTexts["Export"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-format-pdf"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-format-pdf"].isSelected)
    }

    /// Design pass 2: a folder made from the sidebar, filled from a
    /// document's ⋯ menu, then deleted without losing the document.
    func testAFolderMadeInTheSidebarHoldsAMovedDocument() throws {
        continueAfterFailure = false
        let app = launch([])
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("compact-width behaviour") }
        let document = app.descendants(matching: .any)["Crop target, 1 page"]
        XCTAssertTrue(document.waitForExistence(timeout: 15), "home did not open")

        app.buttons["sidebar-new-folder"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Receipts UI")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["This Folder Is Empty"].waitForExistence(timeout: 5), "new folder not shown")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["All Documents"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        app.buttons["item-more"].firstMatch.tap()
        app.buttons["Move to Folder"].tap()
        app.buttons["Receipts UI"].tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Receipts UI"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5), "document not in the folder")
        XCTAssertEqual(app.staticTexts["library-count"].label, "1 item")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Receipts UI"].press(forDuration: 1.2)
        app.buttons["Delete Folder…"].tap()
        app.buttons["Delete Folder"].tap()
        XCTAssertTrue(app.staticTexts["Receipts UI"].waitForNonExistence(timeout: 5), "folder not deleted")
        app.staticTexts["All Documents"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5), "document lost with the folder")
    }

    /// iPhone home: Recent opens a document; See All shows the full grid.
    func testHomeRecentOpensADocumentAndSeeAllShowsTheGrid() throws {
        continueAfterFailure = false
        let app = launch([])
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("compact-width behaviour") }
        let recent = app.descendants(matching: .any)["home-recent"]
        XCTAssertTrue(recent.waitForExistence(timeout: 15), "home has no Recent row")
        XCTAssertTrue(app.buttons["library-scan"].exists && app.buttons["library-import"].exists)

        recent.descendants(matching: .any)["Crop target, 1 page"].firstMatch.tap()
        XCTAssertTrue(app.buttons["editor-crop"].waitForExistence(timeout: 5), "document did not open from Recent")

        app.navigationBars.buttons.element(boundBy: 0).tap()   // back to the home
        app.buttons["home-see-all"].tap()
        XCTAssertTrue(app.segmentedControls["library-layout"].waitForExistence(timeout: 5), "See All did not show the grid")
    }

    /// Design pass 3: each tile in a Form row takes its own tap, and Copy
    /// confirms once the export is on the clipboard.
    func testExportTilesSelectOneAtATimeAndCopyConfirms() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugOpenItem", "Crop target", "-PaperNestDebugShowExport", "YES"])
        let pdf = app.buttons["export-format-pdf"], jpeg = app.buttons["export-format-jpeg"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 15), "export sheet did not open")
        XCTAssertTrue(pdf.isSelected)

        jpeg.tap()
        XCTAssertTrue(jpeg.isSelected)
        XCTAssertFalse(pdf.isSelected)
        let all = app.buttons["export-pages-all"], range = app.buttons["export-pages-range"]
        range.tap()
        XCTAssertTrue(range.isSelected)
        XCTAssertFalse(all.isSelected)
        XCTAssertTrue(jpeg.isSelected, "a pages tap changed the format")
        all.tap()

        app.swipeUp()
        let copy = app.buttons["export-destination-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(copy.isSelected)
        XCTAssertFalse(app.buttons["export-destination-save"].isSelected)
        app.buttons["export-start"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["export-copied"].waitForExistence(timeout: 20), "no copy confirmation")
    }

    /// Design pass 3: with Save chosen, Export opens the system save dialog;
    /// closing it keeps the exported file with Save and Share still offered.
    func testExportSaveOpensTheSaveDialogAndClosingItKeepsTheExport() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugOpenItem", "Crop target", "-PaperNestDebugShowExport", "YES"])
        let start = app.buttons["export-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 15), "export sheet did not open")
        app.swipeUp()   // the destination tiles are below the fold
        XCTAssertTrue(app.buttons["export-destination-save"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-destination-save"].isSelected)
        start.tap()
        XCTAssertTrue(app.staticTexts["Save as"].waitForExistence(timeout: 20), "save dialog did not open")

        // Drag the dialog down from its middle (not from its buttons).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        XCTAssertTrue(app.buttons["Save…"].waitForExistence(timeout: 10), "no fallback after closing the save dialog")
        XCTAssertTrue(app.descendants(matching: .any)["export-share"].exists)
    }

    /// Design pass 4 (iPhone): the filter strip applies a filter, and the
    /// title's menu adds and removes the document from Favorites. Leaves
    /// the page and the favorite as they were for the other tests.
    func testFilterStripAndTitleMenu() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugOpenItem", "Crop target"])
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("compact-width behaviour") }
        let filterButton = app.buttons["editor-filter"]
        XCTAssertTrue(filterButton.waitForExistence(timeout: 15), "document did not open")
        filterButton.tap()
        let original = app.buttons["filter-original"], gray = app.buttons["filter-grayscale"]
        XCTAssertTrue(gray.waitForExistence(timeout: 5), "no filter strip")
        XCTAssertTrue(original.isSelected)
        gray.tap()
        let selected = NSPredicate(format: "isSelected == true")
        wait(for: [expectation(for: selected, evaluatedWith: gray)], timeout: 5)
        XCTAssertFalse(original.isSelected)
        original.tap()
        wait(for: [expectation(for: selected, evaluatedWith: original)], timeout: 5)

        let titleButton = app.navigationBars.buttons["Crop target"]
        let title = titleButton.exists ? titleButton : app.navigationBars.staticTexts["Crop target"]
        title.tap()
        app.buttons["Add to Favorites"].tap()
        title.tap()
        XCTAssertTrue(app.buttons["Remove from Favorites"].waitForExistence(timeout: 5), "favorite not saved")
        app.buttons["Remove from Favorites"].tap()
        title.tap()
        XCTAssertTrue(app.buttons["Add to Favorites"].waitForExistence(timeout: 5))
        app.buttons["Add to Favorites"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 400)).tap()
    }
}
