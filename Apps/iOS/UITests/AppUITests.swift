import XCTest
import SQLite3
import PaperNestCore
import PaperNestStore

/// Drives the real app in the iOS Simulator. Run with `scripts/ui-test-ios.sh`,
/// which seeds the library at `libraryPath` with a page named "Crop target".
@MainActor
final class AppUITests: XCTestCase {
    static let libraryPath = "/tmp/papernest-uitest-library"

    private func launch(_ extra: [String], libraryPath: String = AppUITests.libraryPath, language: String = "en", skipWelcome: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", libraryPath, "-AppleLanguages", "(\(language))", "-AppleLocale", "en_US", "-libraryLayout", "grid", "-PaperNestDebugSkipWelcome", skipWelcome ? "YES" : "NO"] + extra
        app.launch()
        return app
    }

    /// iPhone opens on the home (Scan/Import, Recent, library, folders).
    /// Tests that need the full grid go to All Documents first.
    private func showAllDocuments(_ app: XCUIApplication) {
        let seeAll = app.buttons["home-see-all"]
        if seeAll.waitForExistence(timeout: 15) {
            for _ in 0..<8 where !seeAll.isHittable { app.swipeUp() }
            seeAll.tap()
        }
    }

    /// Tools now live in Home; retain the existing workflow tests' intent.
    private func homeTools(_ app: XCUIApplication) -> XCUIElement {
        let tools = app.buttons["home-tools-all"]
        if !tools.exists {
            if app.buttons["home-tab"].isHittable { app.buttons["home-tab"].tap() }
            else if app.descendants(matching: .any)["sidebar-home"].firstMatch.isHittable { app.descendants(matching: .any)["sidebar-home"].firstMatch.tap() }
        }
        XCTAssertTrue(tools.waitForExistence(timeout: 15))
        for _ in 0..<8 where !tools.isHittable { app.swipeUp() }
        return tools
    }

    func testDashboardCanReturnToTheSameSidebarScope() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("wide sidebar") }
        let app = launch([])
        XCTAssertTrue(app.descendants(matching: .any)["sidebar-home"].firstMatch.waitForExistence(timeout: 15))
        for _ in 0..<2 {
            app.staticTexts["Favorites"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
            app.descendants(matching: .any)["sidebar-home"].firstMatch.tap()
            XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 5))
        }
        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("Crop")
        XCTAssertEqual(search.value as? String, "Crop")
        search.typeText("\n")
        XCTAssertTrue(app.segmentedControls["library-layout"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Crop target, 1 page"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testPremiumFolderActionCreatesARealFolder() throws {
        let app = launch([], libraryPath: "/tmp/papernest-premium-folder-\(UUID().uuidString)")
        XCTAssertTrue(app.buttons["home-new-folder"].waitForExistence(timeout: 15))
        app.buttons["home-new-folder"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Design folder")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["This Folder Is Empty"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Design folder"].exists)
        app.terminate()
    }

    func testPremiumLandscapeDashboard() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad landscape") }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launch([])
        XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .landscapeLeft
        for _ in 0..<20 {
            if app.frame.width > app.frame.height { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertGreaterThan(app.frame.width, app.frame.height, "Verify the app actually rotated")
        XCTAssertTrue(app.buttons["home-new-folder"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "premium-home-rotation-attempt"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    func testPremiumHomeAtLargestTextSize() throws {
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 15))
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertLessThan(app.staticTexts["PaperNest"].firstMatch.frame.height, 130,
                              "The brand must not wrap into character fragments")
            XCTAssertTrue(app.buttons["home-navigation-menu"].isHittable)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "premium-home-largest-text"
        shot.lifetime = .keepAlways
        add(shot)
        homeTools(app).tap()
            app.buttons["tool-notebook"].tap()
        XCTAssertTrue(app.textFields["notebook-name"].waitForExistence(timeout: 5))
        app.terminate()
    }

    func testPremiumDashboardActionsAndLocalizedLayout() throws {
        continueAfterFailure = false
        for language in ["en", "fr", "es"] {
            let app = launch([], language: language)
            let note = homeTools(app)
            XCTAssertTrue(note.waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["library-import"].exists)
            XCTAssertTrue(app.buttons["home-new-folder"].exists)
            XCTAssertFalse(app.buttons["home-vault"].exists)
            XCTAssertFalse(app.buttons["home-vpn"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "premium-home-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            note.tap()
            app.buttons["tool-notebook"].tap()
            XCTAssertTrue(app.textFields["notebook-name"].waitForExistence(timeout: 5))
            app.textFields["notebook-name"].tap()
            app.textFields["notebook-name"].typeText("Dashboard \(language)")
            app.buttons["notebook-create"].tap()
            XCTAssertTrue(app.scrollViews["notebook-tool-bar"].waitForExistence(timeout: 10))
            app.terminate()
            let reopened = launch([], language: language)
            XCTAssertTrue(reopened.buttons["home-see-all"].waitForExistence(timeout: 15))
            reopened.buttons["home-see-all"].tap()
            XCTAssertTrue(reopened.segmentedControls["library-layout"].waitForExistence(timeout: 5))
            let library = XCTAttachment(screenshot: reopened.screenshot())
            library.name = "premium-library-\(language)"
            library.lifetime = .keepAlways
            add(library)
            reopened.terminate()
        }
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
        XCTAssertTrue(app.buttons["library-scan"].exists)
        XCTAssertFalse(app.buttons["library-import"].exists)

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

        // The title menu's button is labelled "<name>, Actions Menu", so an
        // exact match misses it and the StaticText fallback is not always
        // present. Matching by prefix is what actually holds.
        let title = app.navigationBars.buttons
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Crop target")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "no title menu in the document toolbar")
        title.tap()
        app.buttons["Add to Favorites"].tap()
        title.tap()
        XCTAssertTrue(app.buttons["Remove from Favorites"].waitForExistence(timeout: 5), "favorite not saved")
        app.buttons["Remove from Favorites"].tap()
        title.tap()
        XCTAssertTrue(app.buttons["Add to Favorites"].waitForExistence(timeout: 5))
        app.buttons["Add to Favorites"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: 0, dy: 400)).tap()
    }

    /// Pass 7 (iPad): Markup lays the ink canvas over the page. Fingers
    /// don't draw until Draw with Finger is on (Apple Pencil only by
    /// default); a drawn stroke is saved and is still there after leaving
    /// Markup and after a relaunch. The Pencil itself needs a real device.
    func testMarkupWithFingerDrawingSavesAStroke() throws {
        continueAfterFailure = false
        var app = launch(["-PaperNestDebugOpenItem", "Crop target"])
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad: Apple Pencil markup") }
        let markup = app.descendants(matching: .any)["editor-markup"]
        XCTAssertTrue(markup.waitForExistence(timeout: 15), "no Markup button")
        markup.tap()
        let canvas = app.descendants(matching: .any)["ink-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5), "no ink canvas")
        let strokes = { canvas.value as? String }
        XCTAssertEqual(strokes(), "0 strokes")

        func drag(_ from: CGFloat, _ to: CGFloat) {
            canvas.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.55)))
        }
        drag(0.3, 0.6)
        sleep(1)
        XCTAssertEqual(strokes(), "0 strokes", "a finger drew while Apple Pencil only")

        app.descendants(matching: .any)["editor-finger-drawing"].tap()
        drag(0.3, 0.7)
        let one = NSPredicate(format: "value == %@", "1 stroke")
        let none = NSPredicate(format: "value == %@", "0 strokes")
        wait(for: [expectation(for: one, evaluatedWith: canvas)], timeout: 10)

        // Undo and redo from the tool palette: the stroke is one step in the
        // document's undo history. (A ⌘Z injected by XCUITest never reached
        // the app's undo in the Simulator; see TEST_MATRIX.)
        let undoButton = app.buttons["Undo"].firstMatch, redoButton = app.buttons["Redo"].firstMatch
        XCTAssertTrue(undoButton.waitForExistence(timeout: 5), "no Undo in the tool palette")
        undoButton.tap()
        wait(for: [expectation(for: none, evaluatedWith: canvas)], timeout: 10)
        redoButton.tap()
        wait(for: [expectation(for: one, evaluatedWith: canvas)], timeout: 10)

        // Undo works on saved ink, so it still works after a zoom reloads
        // the canvas at another scale. (The zoom buttons are hidden under
        // the palette while marking up; fingers pinch once they don't draw.)
        app.descendants(matching: .any)["editor-finger-drawing"].tap()
        let before = canvas.frame
        canvas.pinch(withScale: 1.8, velocity: 1)
        sleep(1)
        XCTAssertNotEqual(canvas.frame.size, before.size, "the pinch did not zoom")
        undoButton.tap()
        wait(for: [expectation(for: none, evaluatedWith: canvas)], timeout: 10)
        redoButton.tap()
        wait(for: [expectation(for: one, evaluatedWith: canvas)], timeout: 10)

        markup.tap()   // off
        markup.tap()   // on again: reloaded from the library
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertEqual(strokes(), "1 stroke")

        app.terminate()
        app = launch(["-PaperNestDebugOpenItem", "Crop target"])
        let markupAgain = app.descendants(matching: .any)["editor-markup"]
        XCTAssertTrue(markupAgain.waitForExistence(timeout: 15))
        markupAgain.tap()
        let canvasAgain = app.descendants(matching: .any)["ink-canvas"]
        XCTAssertTrue(canvasAgain.waitForExistence(timeout: 5))
        XCTAssertEqual(canvasAgain.value as? String, "1 stroke", "the stroke did not survive a relaunch")
    }

    func testDocumentToolsDuplicateMergeExtractAndKeepOriginals() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-file-tools-uitest-library"
        var app = launch([], libraryPath: library)
        showAllDocuments(app)
        let select = app.buttons["library-select"]
        XCTAssertTrue(select.waitForExistence(timeout: 15))
        app.buttons["item-more"].firstMatch.tap()
        app.buttons["Duplicate"].tap()
        let copy = app.descendants(matching: .any)["Crop target 2, 1 page"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 10))

        select.tap()
        app.buttons["Select All"].tap()
        app.buttons["selection-actions"].tap()
        app.buttons["Color Label"].tap()
        app.buttons["Blue"].tap()
        // The label is saved on both items, exposed separately from selection.
        let selectedOriginal = app.descendants(matching: .any)["Crop target, 1 page"].firstMatch
        wait(for: [expectation(for: NSPredicate(format: "value CONTAINS %@", "Blue"), evaluatedWith: selectedOriginal)], timeout: 5)
        app.buttons["selection-actions"].tap()
        app.buttons["Merge Documents"].tap()
        let name = app.textFields["document-tools-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String)?.count ?? 0))
        name.typeText("Combined test")
        app.buttons["document-tools-create"].tap()
        // The merged document opens. Assert the document itself: `page-thumbnail-…`
        // belongs to the compact-width page strip and doesn't exist on iPad.
        XCTAssertTrue(app.navigationBars["Combined test"].waitForExistence(timeout: 10))

        app.terminate()
        app = launch([], libraryPath: library)
        showAllDocuments(app)
        XCTAssertTrue(app.descendants(matching: .any)["Combined test, 2 pages"].firstMatch.waitForExistence(timeout: 10))
        // Newest item is first. Extract just its second page.
        app.buttons["item-more"].firstMatch.tap()
        app.buttons["Extract Pages"].tap()
        let secondPage = app.buttons["extract-page-2"]
        XCTAssertTrue(secondPage.waitForExistence(timeout: 5))
        secondPage.tap()
        app.buttons["document-tools-create"].tap()
        XCTAssertTrue(app.navigationBars["Combined test — Pages"].waitForExistence(timeout: 10))
        app.terminate()
        app = launch([], libraryPath: library)
        showAllDocuments(app)
        XCTAssertTrue(app.descendants(matching: .any)["Combined test — Pages, 1 page"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["Combined test, 2 pages"].firstMatch.exists)
        let original = app.descendants(matching: .any)["Crop target, 1 page"].firstMatch
        XCTAssertTrue(original.exists)
        XCTAssertEqual(original.value as? String, "Blue")

        // Emptying the current scope must still let the user leave selection.
        app.buttons["library-select"].tap()
        app.buttons["Select All"].tap()
        app.buttons["selection-actions"].tap()
        app.buttons["Delete"].tap()
        XCTAssertTrue(original.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["library-select"].exists)
        app.buttons["library-select"].tap()
        XCTAssertFalse(app.buttons["selection-actions"].exists)
    }


    func testDocumentToolsLocalizedSelectionOrderAndCancellation() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-file-tools-layout-library"
        var app = launch([], libraryPath: library)
        showAllDocuments(app)
        XCTAssertTrue(app.buttons["item-more"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["item-more"].firstMatch.tap()
        app.buttons["Duplicate"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Crop target 2, 1 page"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()

        for (language, all, selectAll, merge, cancel, extract) in [
            ("en", "All Documents", "Select All", "Merge Documents", "Cancel", "Extract Pages"),
            ("fr", "Tous les documents", "Tout sélectionner", "Fusionner des documents", "Annuler", "Extraire des pages"),
            ("es", "Todos los documentos", "Seleccionar todo", "Combinar documentos", "Cancelar", "Extraer páginas")
        ] {
            app = launch([], libraryPath: library, language: language)
            if UIDevice.current.userInterfaceIdiom == .phone {
                XCTAssertTrue(app.staticTexts[all].waitForExistence(timeout: 15))
                app.staticTexts[all].tap()
            }
            XCTAssertTrue(app.buttons["library-select"].waitForExistence(timeout: 10))
            app.buttons["library-select"].tap()
            app.buttons[selectAll].tap()
            sleep(1) // Let the native selection-label transition settle for the screenshot.
            let selectionShot = XCTAttachment(screenshot: app.screenshot())
            selectionShot.name = "file-tools-selection-\(language)"
            selectionShot.lifetime = .keepAlways
            add(selectionShot)
            app.buttons["selection-actions"].tap()
            app.buttons[merge].tap()
            XCTAssertTrue(app.textFields["document-tools-name"].waitForExistence(timeout: 5))
            // Reordering changes the snapshot, not the underlying library. The rows
            // are matched by their own identifiers: an iPad form sheet leaves the
            // library grid visible, so matching a name alone finds the tile behind it.
            XCTAssertEqual(app.staticTexts["merge-row-0"].label, "Crop target 2")
            XCTAssertEqual(app.staticTexts["merge-row-1"].label, "Crop target")
            app.buttons["merge-down-0"].tap()
            XCTAssertEqual(app.staticTexts["merge-row-0"].label, "Crop target")
            XCTAssertEqual(app.staticTexts["merge-row-1"].label, "Crop target 2")
            let mergeShot = XCTAttachment(screenshot: app.screenshot())
            mergeShot.name = "file-tools-merge-\(language)"
            mergeShot.lifetime = .keepAlways
            add(mergeShot)
            app.buttons[cancel].tap()
            XCTAssertTrue(app.buttons["library-select"].waitForExistence(timeout: 5))
            app.buttons["library-select"].tap()
            app.buttons["item-more"].firstMatch.tap()
            app.buttons[extract].tap()
            let create = app.buttons["document-tools-create"]
            XCTAssertTrue(create.waitForExistence(timeout: 5))
            XCTAssertFalse(create.isEnabled)
            app.buttons["extract-page-1"].tap()
            XCTAssertTrue(create.isEnabled)
            let extractShot = XCTAttachment(screenshot: app.screenshot())
            extractShot.name = "file-tools-extract-\(language)"
            extractShot.lifetime = .keepAlways
            add(extractShot)
            app.buttons[cancel].tap()
            XCTAssertTrue(app.buttons["library-select"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons.matching(identifier: "item-more").count, 2)
            app.terminate()
        }
    }

    func testDocumentToolsSplitMakesOneDocumentPerPageAndKeepsTheSource() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-file-tools-split-library"
        var app = launch([], libraryPath: library)
        showAllDocuments(app)
        let source = app.descendants(matching: .any)["Split target, 3 pages"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 15))
        app.buttons["item-more"].firstMatch.tap()
        app.buttons["Split into Pages"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Split target \u{2014} Page 1, 1 page"]
            .firstMatch.waitForExistence(timeout: 10))

        app.terminate()
        app = launch([], libraryPath: library)
        showAllDocuments(app)
        for page in 1...3 {
            XCTAssertTrue(app.descendants(matching: .any)["Split target \u{2014} Page \(page), 1 page"]
                .firstMatch.waitForExistence(timeout: 10), "page \(page) did not survive the relaunch")
        }
        XCTAssertTrue(source.exists, "splitting must keep the original")
        // The newest item is first, and a one-page document cannot be split again.
        app.buttons["item-more"].firstMatch.tap()
        let split = app.buttons["Split into Pages"]
        XCTAssertTrue(split.waitForExistence(timeout: 5))
        XCTAssertFalse(split.isEnabled)
    }

    func testDocumentToolsBulkExportMakesOneArchiveFromTheSelection() throws {
        continueAfterFailure = false
        // Exporting only reads the library, so this test shares the split
        // test's library without changing what that test finds.
        let app = launch([], libraryPath: "/tmp/papernest-file-tools-split-library")
        showAllDocuments(app)
        XCTAssertTrue(app.buttons["library-select"].waitForExistence(timeout: 15))
        app.buttons["library-select"].tap()
        app.buttons["Select All"].tap()
        app.buttons["selection-actions"].tap()
        app.buttons["Export as ZIP\u{2026}"].tap()
        let status = app.descendants(matching: .any)["bulk-export-status"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 30), "the archive never became ready")
        XCTAssertTrue(status.label.hasPrefix("Ready"), "unexpected status: \(status.label)")
        XCTAssertTrue(app.buttons["bulk-export-save"].exists)
        app.buttons["bulk-export-done"].tap()
        XCTAssertTrue(app.buttons["library-select"].waitForExistence(timeout: 5))
    }

    func testToolsScreenPicksTwoDocumentsAndMergesThem() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-tools-screen-library"
        var app = launch([], libraryPath: library)
        showAllDocuments(app)
        let tools = homeTools(app)
        XCTAssertTrue(tools.waitForExistence(timeout: 15))
        tools.tap()

        let merge = app.buttons["tool-merge"]
        XCTAssertTrue(merge.waitForExistence(timeout: 5))
        // Importing from Photos is offered here; the picker itself is the
        // system's and is not driven by this test.
        XCTAssertTrue(app.descendants(matching: .any)["tool-photos"].firstMatch.exists,
                      "the Tools screen should offer Photos")
        merge.tap()
        let continueButton = app.buttons["pick-continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        // Merging needs two documents, so one pick is not enough.
        app.buttons["pick-Tools A"].tap()
        XCTAssertFalse(continueButton.isEnabled)
        app.buttons["pick-Tools B"].tap()
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()

        let name = app.textFields["document-tools-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String)?.count ?? 0))
        name.typeText("Tools merged")
        app.buttons["document-tools-create"].tap()
        XCTAssertTrue(app.navigationBars["Tools merged"].waitForExistence(timeout: 10),
                      "the merged document should open once the Tools sheet closes")

        app.terminate()
        app = launch([], libraryPath: library)
        showAllDocuments(app)
        XCTAssertTrue(app.descendants(matching: .any)["Tools merged, 2 pages"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["Tools A, 1 page"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["Tools B, 1 page"].firstMatch.exists)
    }

    func testRecognizeTextMakesAWordOnThePageSearchable() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugOpenItem", "OCR target"], libraryPath: "/tmp/papernest-ocr-library")
        // Document-level actions live in the title menu on every platform;
        // the compact toolbar has no overflow menu.
        XCTAssertTrue(app.navigationBars["OCR target"].waitForExistence(timeout: 15), "document did not open")
        // Overflow lives in the bottom bar on iPhone and in the toolbar on
        // iPad and Mac; menu items are matched by label, as elsewhere here.
        let more = app.buttons["More"].firstMatch
        if more.waitForExistence(timeout: 5) {
            more.tap()
        } else {
            app.buttons["editor-more"].tap()
        }
        let recognize = app.buttons["Recognize Text"]
        XCTAssertTrue(recognize.waitForExistence(timeout: 5), "no Recognize Text in the overflow menu")
        recognize.tap()

        app.navigationBars.buttons.element(boundBy: 0).tap()
        showAllDocuments(app)
        let document = app.descendants(matching: .any)["OCR target, 3 pages"].firstMatch
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        // "Quarterly" is printed on page 1 and is not part of the title.
        search.typeText("Quarterly")
        XCTAssertTrue(document.waitForExistence(timeout: 30),
                      "the document should be found by a word only its page carries")
    }

    func testMissingFilePreviewCanBeClosedInEveryLanguage() throws {
        continueAfterFailure = false
        for language in ["en", "fr", "es"] {
            let app = launch([], libraryPath: "/tmp/papernest-missing-file-preview-library", language: language)
            let cell = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Budget notes")).firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 15))
            cell.tap()
            XCTAssertTrue(app.descendants(matching: .any)["file-preview-error"].firstMatch.waitForExistence(timeout: 10))
            let done = app.buttons["file-preview-done"]
            XCTAssertTrue(done.isHittable)
            XCTAssertTrue(app.buttons["file-preview-info"].isHittable)
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "file-preview-error-\(language)"
            attachment.lifetime = .keepAlways
            add(attachment)
            done.tap()
            XCTAssertTrue(cell.waitForExistence(timeout: 10), "a failed preview must be dismissible")
            app.terminate()
        }
    }

    func testAFileItemPreviewsAndShowsItsTypeSizeAndACopy() throws {
        continueAfterFailure = false
        let app = launch([], libraryPath: "/tmp/papernest-file-items-library")
        // Recent must route files to the same viewer as the full library.
        if UIDevice.current.userInterfaceIdiom == .phone {
            let recent = app.descendants(matching: .any)["Budget notes, 18 bytes"].firstMatch
            XCTAssertTrue(recent.waitForExistence(timeout: 15))
            recent.tap()
            XCTAssertTrue(app.buttons["file-preview-done"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.descendants(matching: .any)["file-preview"].firstMatch.waitForExistence(timeout: 10))
            app.buttons["file-preview-done"].tap()
        }
        showAllDocuments(app)
        // A text file cannot become pages, so it is kept as a file and the
        // tile shows its size where a document shows its page count.
        let cell = app.descendants(matching: .any)["Budget notes, 18 bytes"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 15), "the file should be in the library")

        // Tapping opens the system preview, not a row of metadata.
        cell.tap()
        let previewDone = app.buttons["file-preview-done"]
        XCTAssertTrue(previewDone.waitForExistence(timeout: 10), "tapping a file should preview it")
        let preview = app.descendants(matching: .any)["file-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "the file copy should load")
        let text = app.descendants(matching: .any).matching(NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "quarterly figures", "quarterly figures")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 15), "Quick Look should show the actual text file")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "file-preview-text"
        attachment.lifetime = .keepAlways
        add(attachment)
        // Info is a child sheet: dismissing it returns to the working preview.
        app.buttons["file-preview-info"].tap()
        XCTAssertTrue(app.buttons["file-share"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["file-save-copy"].isEnabled)
        app.buttons["file-details-done"].tap()
        XCTAssertTrue(text.waitForExistence(timeout: 10), "the preview copy should survive Info dismissal")
        previewDone.tap()
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        // What it is, where it came from and how big: still a menu away.
        app.buttons["item-more"].firstMatch.tap()
        app.buttons["Show Info"].tap()
        let header = app.descendants(matching: .any)["file-details-header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        // A LabeledContent row is one element labelled "<label>, <value>".
        let originalName = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Budget notes.txt")).firstMatch
        XCTAssertTrue(originalName.waitForExistence(timeout: 5), "the details should name the original file")
        XCTAssertTrue(app.buttons["file-save-copy"].waitForExistence(timeout: 10),
                      "a copy of the file should be offered")
        app.buttons["file-details-done"].tap()
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
    }

    func testRecognizedLinesCanBeMarkedAndKeptAfterRelaunch() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-text-markup-library"
        for (index, entry) in [("en", "Annotate Text", "highlight"), ("fr", "Annoter le texte", "underline"),
                               ("es", "Anotar texto", "strikethrough")].enumerated() {
            let (language, title, style) = entry
            var app = launch(["-PaperNestDebugOpenItem", "Markup target"], libraryPath: library, language: language)
            let page = app.descendants(matching: .any)["document-page-image"].firstMatch
            XCTAssertTrue(page.waitForExistence(timeout: 15))
            func openAnnotations(_ app: XCUIApplication) {
                let more = UIDevice.current.userInterfaceIdiom == .phone
                    ? app.buttons.matching(identifier: "editor-more").firstMatch : app.buttons["editor-more"]
                // Compact layout's overflow has a localized label; identify
                // its shared action entry through the supplied identifier.
                more.tap()
                app.buttons[title].tap()
            }
            openAnnotations(app)
            let apply = app.buttons["annotation-apply"]
            XCTAssertTrue(apply.waitForExistence(timeout: 5))
            XCTAssertFalse(apply.isEnabled)
            let recognize = app.buttons["annotation-recognize"]
            if recognize.waitForExistence(timeout: 2) { recognize.tap() }
            let line = app.buttons["annotation-line-0"]
            XCTAssertTrue(line.waitForExistence(timeout: 30), "real OCR should provide a line")
            app.buttons["annotation-style-" + style].tap()
            line.tap()
            XCTAssertTrue(apply.isEnabled)
            let choice = XCTAttachment(screenshot: app.screenshot())
            choice.name = "text-markup-picker-" + language
            choice.lifetime = .keepAlways
            add(choice)
            apply.tap()
            XCTAssertTrue(apply.waitForNonExistence(timeout: 10))
            let expected = String(index + 1)
            let count = NSPredicate(format: "value BEGINSWITH %@", expected)
            expectation(for: count, evaluatedWith: page)
            waitForExpectations(timeout: 10)
            let saved = XCTAttachment(screenshot: app.screenshot())
            saved.name = "text-markup-saved-" + language
            saved.lifetime = .keepAlways
            add(saved)
            // Cancellation never adds a mark.
            openAnnotations(app)
            XCTAssertTrue(app.buttons["annotation-line-0"].waitForExistence(timeout: 10))
            app.buttons["annotation-line-0"].tap()
            app.buttons["annotation-cancel"].tap()
            expectation(for: count, evaluatedWith: page)
            waitForExpectations(timeout: 5)
            app.terminate()
            app = launch(["-PaperNestDebugOpenItem", "Markup target"], libraryPath: library, language: language)
            let reopened = app.descendants(matching: .any)["document-page-image"].firstMatch
            XCTAssertTrue(reopened.waitForExistence(timeout: 15))
            expectation(for: count, evaluatedWith: reopened)
            waitForExpectations(timeout: 10)
            app.terminate()
        }
    }

    func testSavedMarkupSupportsColorsSelectionRemovalAndRelaunch() throws {
        continueAfterFailure = false
        for (language, annotate, manage) in [("en", "Annotate Text", "Manage Markup"),
                                             ("fr", "Annoter le texte", "Gérer les annotations"),
                                             ("es", "Anotar texto", "Gestionar anotaciones")] {
            let library = "/tmp/papernest-markup-controls-\(language)"
            var app = launch(["-PaperNestDebugOpenItem", "Markup target"], libraryPath: library, language: language)
            func open(_ title: String) {
                XCTAssertTrue(app.buttons["editor-more"].waitForExistence(timeout: 15))
                app.buttons["editor-more"].tap()
                app.buttons[title].tap()
            }
            func reveal(_ element: XCUIElement) {
                for _ in 0..<6 where !element.isHittable { app.swipeUp() }
                XCTAssertTrue(element.isHittable)
            }
            func rows() -> XCUIElementQuery {
                app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markup-row-"))
            }
            func expectColor(_ element: XCUIElement, _ hex: String) {
                expectation(for: NSPredicate(format: "value CONTAINS %@", hex), evaluatedWith: element)
                waitForExpectations(timeout: 10)
            }
            open(annotate)
            let green = app.buttons["markup-color-green"]
            XCTAssertTrue(green.waitForExistence(timeout: 10))
            reveal(green); green.tap()
            let recognize = app.buttons["annotation-recognize"]
            reveal(recognize); recognize.tap()
            let first = app.buttons["annotation-line-0"]
            XCTAssertTrue(first.waitForExistence(timeout: 30))
            reveal(first); first.tap()
            let second = app.buttons["annotation-line-1"]
            reveal(second); second.tap()
            app.buttons["annotation-apply"].tap()
            XCTAssertTrue(app.buttons["annotation-apply"].waitForNonExistence(timeout: 10))
            open(manage)
            XCTAssertTrue(rows().firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(rows().count, 2)
            expectColor(rows().element(boundBy: 0), "#00A640")
            rows().element(boundBy: 0).tap()
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "markup-manager-" + language
            attachment.lifetime = .keepAlways
            add(attachment)
            // Selecting and closing does not write.
            app.buttons["markup-done"].tap()
            open(manage)
            XCTAssertTrue(rows().firstMatch.waitForExistence(timeout: 10))
            XCTAssertEqual(rows().count, 2)
            expectColor(rows().element(boundBy: 0), "#00A640")
            rows().element(boundBy: 0).tap()
            let blue = app.buttons["markup-color-blue"]
            reveal(blue); blue.tap()
            let recolor = app.buttons["markup-recolor"]
            reveal(recolor); recolor.tap()
            expectColor(rows().element(boundBy: 0), "#1A59CC")
            expectColor(rows().element(boundBy: 1), "#00A640")
            app.buttons["markup-done"].tap()
            app.terminate()
            app = launch(["-PaperNestDebugOpenItem", "Markup target"], libraryPath: library, language: language)
            open(manage)
            XCTAssertTrue(rows().firstMatch.waitForExistence(timeout: 10))
            expectColor(rows().element(boundBy: 0), "#1A59CC")
            rows().element(boundBy: 0).tap()
            let remove = app.buttons["markup-remove"]
            reveal(remove); remove.tap()
            expectation(for: NSPredicate(format: "count == 1"), evaluatedWith: rows())
            waitForExpectations(timeout: 10)
            expectColor(rows().firstMatch, "#00A640")
            reveal(rows().firstMatch); rows().firstMatch.tap()
            reveal(remove); remove.tap()
            XCTAssertTrue(app.staticTexts["markup-empty"].waitForExistence(timeout: 10))
            app.buttons["markup-done"].tap()
            app.terminate()
            app = launch(["-PaperNestDebugOpenItem", "Markup target"], libraryPath: library, language: language)
            open(manage)
            XCTAssertTrue(app.staticTexts["markup-empty"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    func testNotebookCreationOpensAndSurvivesRelaunch() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-notebook-ui-\(UUID().uuidString)"
        var app = launch([], libraryPath: library)
        showAllDocuments(app)
        XCTAssertTrue(homeTools(app).waitForExistence(timeout: 15))
        homeTools(app).tap()
        XCTAssertTrue(app.buttons["tool-notebook"].waitForExistence(timeout: 5))
        app.buttons["tool-notebook"].tap()
        let create = app.buttons["notebook-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(create.isEnabled)
        let name = app.textFields["notebook-name"]
        name.tap()
        name.typeText("Study notebook")
        app.buttons["notebook-paper-grid"].tap()
        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(app.navigationBars["Study notebook"].waitForExistence(timeout: 10))
        app.terminate()
        app = launch([], libraryPath: library)
        showAllDocuments(app)
        XCTAssertTrue(app.descendants(matching: .any)["Study notebook, 1 page"].firstMatch.waitForExistence(timeout: 10))
    }
    func testNotebookPagesAddCancelUndoRedoAndReopenInAllLanguages() throws {
        continueAfterFailure = false
        for (language, selected, one, two) in [
            ("en", "Selected", "Page 1 of 1", "Page 2 of 2"),
            ("fr", "Sélectionné", "Page 1 sur 1", "Page 2 sur 2"),
            ("es", "Seleccionado", "Página 1 de 1", "Página 2 de 2")
        ] {
            let library = "/tmp/papernest-pages-ui-\(UUID().uuidString)"
            let title = "Notebook \(language)"
            var app = launch([], libraryPath: library, language: language)
            XCTAssertTrue(homeTools(app).waitForExistence(timeout: 15))
            homeTools(app).tap()
            XCTAssertTrue(app.buttons["tool-notebook"].waitForExistence(timeout: 5))
            app.buttons["tool-notebook"].tap()
            let name = app.textFields["notebook-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(title)
            app.buttons["notebook-paper-lined"].tap()
            app.buttons["notebook-create"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))

            func openAdd() {
                revealEditorTool(app, identifier: "editor-add-notebook-page")
                app.buttons["editor-add-notebook-page"].tap()
                XCTAssertTrue(app.buttons["add-page-create"].waitForExistence(timeout: 5))
            }
            openAdd()
            XCTAssertEqual(app.buttons["add-page-paper-lined"].value as? String, selected)
            app.buttons["add-page-cancel"].tap()
            XCTAssertTrue(app.descendants(matching: .any)[one].firstMatch.waitForExistence(timeout: 5))
            openAdd()
            app.buttons["add-page-paper-grid"].tap()
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "notebook-add-page-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["add-page-create"].tap()
            XCTAssertTrue(app.descendants(matching: .any)[two].firstMatch.waitForExistence(timeout: 10))
            revealEditorTool(app, identifier: "notebook-undo")
            let undo = app.buttons["notebook-undo"]
            XCTAssertTrue(undo.isEnabled)
            undo.tap()
            XCTAssertTrue(app.descendants(matching: .any)[one].firstMatch.waitForExistence(timeout: 10))
            revealEditorTool(app, identifier: "notebook-redo")
            let redo = app.buttons["notebook-redo"]
            XCTAssertTrue(redo.isEnabled)
            redo.tap()
            XCTAssertTrue(app.descendants(matching: .any)[two].firstMatch.waitForExistence(timeout: 10))
            app.terminate()
            app = launch(["-PaperNestDebugOpenItem", title], libraryPath: library, language: language)
            // Reopening selects the first page; the second page still exists in the strip.
            XCTAssertTrue(app.descendants(matching: .any)[two].firstMatch.waitForExistence(timeout: 15))
            app.terminate()
        }
    }
    func testPageCommentsEditCancelDeleteUndoAndReopenInAllLanguages() throws {
        continueAfterFailure = false
        for language in ["en", "fr", "es"] {
            let library = "/tmp/papernest-comments-ui-\(UUID().uuidString)"
            let title = "Comments \(language)"
            var app = launch([], libraryPath: library, language: language)
            XCTAssertTrue(homeTools(app).waitForExistence(timeout: 15))
            homeTools(app).tap()
            app.buttons["tool-notebook"].tap()
            let name = app.textFields["notebook-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(title)
            app.buttons["notebook-create"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            func openComments(_ app: XCUIApplication) {
                revealEditorTool(app, identifier: "editor-comments")
                app.buttons["editor-comments"].tap()
                XCTAssertTrue(app.buttons["comment-add"].waitForExistence(timeout: 5))
            }
            func row(_ app: XCUIApplication) -> XCUIElement {
                app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "comment-row-")).firstMatch
            }
            openComments(app)
            app.buttons["comment-add"].tap()
            let text = app.textViews["comment-text"]
            XCTAssertTrue(text.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["comment-save"].isEnabled)
            text.tap()
            text.typeText("Review this page")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "page-comment-editor-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["comment-save"].tap()
            XCTAssertTrue(row(app).waitForExistence(timeout: 5))
            row(app).tap()
            XCTAssertTrue(text.waitForExistence(timeout: 5))
            XCTAssertEqual(text.value as? String, "Review this page")
            text.tap()
            text.typeText(" cancelled")
            app.buttons["comment-cancel"].tap()
            row(app).tap()
            XCTAssertTrue(text.waitForExistence(timeout: 5))
            XCTAssertEqual(text.value as? String, "Review this page")
            text.tap()
            text.typeText(" updated")
            let savedText = try XCTUnwrap(text.value as? String).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertTrue(savedText.contains("Review this page"))
            XCTAssertTrue(savedText.contains("updated"))
            app.buttons["comment-save"].tap()
            XCTAssertTrue(row(app).waitForExistence(timeout: 5))
            row(app).tap()
            XCTAssertTrue(text.waitForExistence(timeout: 5))
            app.buttons["comment-delete"].tap()
            XCTAssertTrue(app.staticTexts["comments-empty"].waitForExistence(timeout: 5))
            app.buttons["comments-history"].tap()
            try XCTUnwrap(app.buttons.matching(identifier: "notebook-undo").allElementsBoundByIndex.first { $0.isHittable }).tap()
            XCTAssertTrue(row(app).waitForExistence(timeout: 5))
            app.buttons["comments-history"].tap()
            try XCTUnwrap(app.buttons.matching(identifier: "notebook-redo").allElementsBoundByIndex.first { $0.isHittable }).tap()
            XCTAssertTrue(app.staticTexts["comments-empty"].waitForExistence(timeout: 5))
            app.buttons["comments-history"].tap()
            try XCTUnwrap(app.buttons.matching(identifier: "notebook-undo").allElementsBoundByIndex.first { $0.isHittable }).tap()
            XCTAssertTrue(row(app).waitForExistence(timeout: 5))
            app.terminate()
            app = launch(["-PaperNestDebugOpenItem", title], libraryPath: library, language: language)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
            openComments(app)
            XCTAssertTrue(row(app).waitForExistence(timeout: 5))
            row(app).tap()
            XCTAssertTrue(app.textViews["comment-text"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.textViews["comment-text"].value as? String, savedText)
            app.terminate()
        }
    }

    func testShapesPlaceCancelUndoRedoAndReopenInAllLanguages() throws {
        continueAfterFailure = false
        for (language, selected) in [("en", "Selected"), ("fr", "Sélectionné"), ("es", "Seleccionado")] {
            let library = "/tmp/papernest-shapes-ui-\(UUID().uuidString)"
            let title = "Shapes \(language)"
            var app = launch([], libraryPath: library, language: language)
            XCTAssertTrue(homeTools(app).waitForExistence(timeout: 15))
            homeTools(app).tap()
            app.buttons["tool-notebook"].tap()
            let name = app.textFields["notebook-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(title)
            app.buttons["notebook-create"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            func openShapes() {
                revealEditorTool(app, identifier: "editor-shapes")
                app.buttons["editor-shapes"].tap()
                XCTAssertTrue(app.buttons["shape-save"].waitForExistence(timeout: 5))
            }
            func checkMarkup(empty: Bool) {
                revealEditorTool(app, identifier: "editor-manage-markup")
                app.buttons["editor-manage-markup"].tap()
                if empty {
                    XCTAssertTrue(app.staticTexts["markup-empty"].waitForExistence(timeout: 5))
                } else {
                    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markup-row-"))
                    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
                    XCTAssertEqual(rows.count, 1)
                }
                app.buttons["markup-done"].tap()
                XCTAssertTrue(app.buttons["markup-done"].waitForNonExistence(timeout: 5))
            }
            openShapes()
            app.buttons["shape-cancel"].tap()
            checkMarkup(empty: true)
            openShapes()
            for shape in ["ellipse", "line", "rectangle", "arrow"] {
                app.buttons["shape-kind-\(shape)"].tap()
                XCTAssertEqual(app.buttons["shape-kind-\(shape)"].value as? String, selected)
            }
            let preview = app.descendants(matching: .any)["shape-preview"].firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            let previousPosition = preview.value as? String
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)))
            let shot = XCTAttachment(screenshot: app.screenshot())
            XCTAssertNotEqual(preview.value as? String, previousPosition, "Dragging must place the shape instead of scrolling the form")
            shot.name = "shape-placement-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            let red = app.buttons["markup-color-red"]
            // Use the form margin next to the preview, inside the centered iPad
            // sheet as well as the phone sheet. Preview drags place the shape.
            let scrollStart = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: preview.frame.maxX + 8, dy: preview.frame.midY))
            let scrollEnd = scrollStart.withOffset(CGVector(dx: 0, dy: -220))
            for _ in 0..<5 where !red.isHittable {
                scrollStart.press(forDuration: 0.1, thenDragTo: scrollEnd)
            }
            XCTAssertTrue(red.isHittable)
            red.tap()
            XCTAssertEqual(red.value as? String, selected)
            app.buttons["shape-save"].tap()
            XCTAssertTrue(app.buttons["shape-save"].waitForNonExistence(timeout: 10))
            checkMarkup(empty: false)
            revealEditorTool(app, identifier: "notebook-undo")
            app.buttons["notebook-undo"].tap()
            checkMarkup(empty: true)
            revealEditorTool(app, identifier: "notebook-redo")
            app.buttons["notebook-redo"].tap()
            checkMarkup(empty: false)
            app.terminate()
            app = launch(["-PaperNestDebugOpenItem", title], libraryPath: library, language: language)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
            checkMarkup(empty: false)
            app.terminate()
        }
    }

    func testShapeUndoOnImportedDocument() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugOpenItem", "Markup target"], libraryPath: "/tmp/papernest-text-markup-library")
        XCTAssertTrue(app.navigationBars["Markup target"].waitForExistence(timeout: 15))
        revealEditorTool(app, identifier: "editor-shapes")
        app.buttons["editor-shapes"].tap()
        XCTAssertTrue(app.buttons["shape-save"].waitForExistence(timeout: 5))
        app.buttons["shape-save"].tap()
        XCTAssertTrue(app.buttons["shape-save"].waitForNonExistence(timeout: 10))
        revealEditorTool(app, identifier: "notebook-undo")
        let undo = app.buttons["notebook-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5), "Imported documents need accessible shape history too")
        XCTAssertTrue(undo.isEnabled)
        undo.tap()
        revealEditorTool(app, identifier: "editor-manage-markup")
        app.buttons["editor-manage-markup"].tap()
        XCTAssertTrue(app.staticTexts["markup-empty"].waitForExistence(timeout: 5))
        app.buttons["markup-done"].tap()
        revealEditorTool(app, identifier: "notebook-redo")
        app.buttons["notebook-redo"].tap()
        revealEditorTool(app, identifier: "editor-manage-markup")
        app.buttons["editor-manage-markup"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markup-row-")).firstMatch.waitForExistence(timeout: 5))
        app.terminate()
    }

    func testSymbolStampsEnglishLifecycle() throws {
        try checkSymbolStampLifecycle(language: "en", selected: "Selected")
    }

    func testSymbolStampsFrenchLifecycle() throws {
        try checkSymbolStampLifecycle(language: "fr", selected: "Sélectionné")
    }

    func testSymbolStampsSpanishLifecycle() throws {
        try checkSymbolStampLifecycle(language: "es", selected: "Seleccionado")
    }

    private func checkSymbolStampLifecycle(language: String, selected: String) throws {
        continueAfterFailure = false
        do {
            let library = "/tmp/papernest-stamps-ui-\(UUID().uuidString)"
            let title = "Stamps \(language)"
            var app = launch([], libraryPath: library, language: language)
            XCTAssertTrue(homeTools(app).waitForExistence(timeout: 15))
            homeTools(app).tap()
            app.buttons["tool-notebook"].tap()
            let name = app.textFields["notebook-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText(title)
            app.buttons["notebook-create"].tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            func openStamps() {
                revealEditorTool(app, identifier: "editor-stamps")
                app.buttons["editor-stamps"].tap()
                XCTAssertTrue(app.buttons["stamp-save"].waitForExistence(timeout: 5))
            }
            func checkMarkup(empty: Bool) {
                revealEditorTool(app, identifier: "editor-manage-markup")
                app.buttons["editor-manage-markup"].tap()
                if empty {
                    XCTAssertTrue(app.staticTexts["markup-empty"].waitForExistence(timeout: 5))
                } else {
                    let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markup-row-"))
                    XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
                    XCTAssertEqual(rows.count, 1)
                }
                app.buttons["markup-done"].tap()
                XCTAssertTrue(app.buttons["markup-done"].waitForNonExistence(timeout: 5))
            }
            // The shared sheet must still open ordinary shapes in shape mode.
            revealEditorTool(app, identifier: "editor-shapes")
            app.buttons["editor-shapes"].tap()
            XCTAssertTrue(app.buttons["shape-kind-rectangle"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.buttons["shape-kind-rectangle"].value as? String, selected)
            XCTAssertFalse(app.buttons["stamp-kind-checkmark"].exists)
            app.buttons["shape-cancel"].tap()
            openStamps()
            XCTAssertEqual(app.buttons["stamp-kind-checkmark"].value as? String, selected)
            app.buttons["stamp-cancel"].tap()
            checkMarkup(empty: true)
            openStamps()
            for shape in ["checkmark", "cross", "star"] {
                app.buttons["stamp-kind-\(shape)"].tap()
                XCTAssertEqual(app.buttons["stamp-kind-\(shape)"].value as? String, selected)
            }
            let preview = app.descendants(matching: .any)["stamp-preview"].firstMatch
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            let previousPosition = preview.value as? String
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: preview.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3)))
            let shot = XCTAttachment(screenshot: app.screenshot())
            XCTAssertNotEqual(preview.value as? String, previousPosition, "Dragging must place the shape instead of scrolling the form")
            shot.name = "stamp-placement-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            let red = app.buttons["markup-color-red"]
            // Use the form margin next to the preview, inside the centered iPad
            // sheet as well as the phone sheet. Preview drags place the shape.
            let scrollStart = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: preview.frame.maxX + 8, dy: preview.frame.midY))
            let scrollEnd = scrollStart.withOffset(CGVector(dx: 0, dy: -220))
            for _ in 0..<5 where !red.isHittable {
                scrollStart.press(forDuration: 0.1, thenDragTo: scrollEnd)
            }
            XCTAssertTrue(red.isHittable)
            red.tap()
            XCTAssertEqual(red.value as? String, selected)
            app.buttons["stamp-save"].tap()
            XCTAssertTrue(app.buttons["stamp-save"].waitForNonExistence(timeout: 10))
            checkMarkup(empty: false)
            revealEditorTool(app, identifier: "notebook-undo")
            app.buttons["notebook-undo"].tap()
            checkMarkup(empty: true)
            revealEditorTool(app, identifier: "notebook-redo")
            app.buttons["notebook-redo"].tap()
            checkMarkup(empty: false)
            app.terminate()
            app = launch(["-PaperNestDebugOpenItem", title], libraryPath: library, language: language)
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 15))
            checkMarkup(empty: false)
            app.terminate()
        }
    }


    func testLargeTextNotebookCreationFromNotes() throws {
        continueAfterFailure = false
        let app = launch(["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"],
                         libraryPath: "/tmp/papernest-notes-accessibility-\(UUID().uuidString)")
        createInlineTestNotebook(app, named: "Accessible Notes notebook")
    }

    // Verification backlog: exercise controls not covered by the preset flows.
    func testLargeTextShapeSlidersAndSystemColorPicker() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-accessibility-ui-\(UUID().uuidString)"
        let app = launch(["-PaperNestDebugShowTools", "YES",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"],
                         libraryPath: library)
        XCTAssertTrue(app.buttons["tool-notebook"].waitForExistence(timeout: 15))
        app.buttons["tool-notebook"].tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Accessibility notebook")
        let creationShot = XCTAttachment(screenshot: app.screenshot())
        creationShot.name = "large-text-notebook-before-create"
        creationShot.lifetime = .keepAlways
        add(creationShot)
        app.buttons["notebook-create"].tap()
        XCTAssertTrue(app.scrollViews["notebook-tool-bar"].waitForExistence(timeout: 10), app.debugDescription)
        if UIDevice.current.userInterfaceIdiom == .pad {
            let sidebar = app.collectionViews["Sidebar"]
            XCTAssertGreaterThanOrEqual(sidebar.frame.width, 400, "Large text needs a readable navigation column")
        }
        revealEditorTool(app, identifier: "editor-shapes")
        XCTAssertTrue(app.buttons["editor-shapes"].waitForExistence(timeout: 5))
        app.buttons["editor-shapes"].tap()
        XCTAssertTrue(app.buttons["shape-save"].waitForExistence(timeout: 5))
        func reveal(_ element: XCUIElement) {
            for _ in 0..<16 {
                // Hittable can be true below an iPad sheet's visible bounds.
                // Require the entire control inside the presented Form before tapping.
                let form = app.collectionViews.matching(
                    NSPredicate(format: "label != %@ AND label != %@", "Sidebar", "Pages")).firstMatch
                XCTAssertTrue(form.exists, "Presented shape Form must exist")
                let frame = form.frame.intersection(app.frame)
                let navigation = app.navigationBars["Shape"].frame
                let viewport = CGRect(x: max(frame.minX, navigation.minX),
                                      y: max(frame.minY, navigation.maxY),
                                      width: min(frame.maxX, navigation.maxX) - max(frame.minX, navigation.minX),
                                      height: frame.maxY - max(frame.minY, navigation.maxY))
                if element.exists && !element.frame.isEmpty && viewport.contains(element.frame) && element.isHittable {
                    return
                }
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
                    CGVector(dx: viewport.minX + 8, dy: viewport.midY + min(100, viewport.height * 0.2)))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)),
                            withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            XCTFail("Control did not become fully visible: \(element.debugDescription)")
        }
        let position = app.buttons["Position"]
        reveal(position)
        position.tap()
        let slider = app.sliders["shape-position-start-x"]
        reveal(slider)
        let before = slider.value as? String
        slider.adjust(toNormalizedSliderPosition: 0.85)
        XCTAssertNotEqual(slider.value as? String, before)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "large-text-shape-position"
        shot.lifetime = .keepAlways
        add(shot)
        let widthHeading = app.staticTexts["Line width"]
        reveal(widthHeading)
        XCTAssertTrue(widthHeading.isHittable)
        let thick = app.buttons["shape-width-4"]
        reveal(thick)
        thick.tap()
        XCTAssertEqual(thick.value as? String, "Selected")
        let styleShot = XCTAttachment(screenshot: app.screenshot())
        styleShot.name = "readable-large-text-width"
        styleShot.lifetime = .keepAlways
        add(styleShot)
        let custom = app.descendants(matching: .any)["markup-custom-color"].firstMatch
        reveal(custom)
        let previousColor = custom.value as? String
        custom.tap()
        let close = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "close")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 5), app.debugDescription)
        let color = app.otherElements["azure 77"]
        XCTAssertTrue(color.waitForExistence(timeout: 5))
        color.tap()
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "large-text-system-color-picker"
        picker.lifetime = .keepAlways
        add(picker)
        let popover = app.popovers.firstMatch
        if popover.exists {
            // iPad hides the floating picker's close control visually but
            // leaves it in AX; dismiss its popover by tapping outside it.
            app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: max(10, popover.frame.minX - 20), dy: popover.frame.midY)).tap()
            XCTAssertTrue(popover.waitForNonExistence(timeout: 5))
        } else {
            close.tap()
        }
        XCTAssertNotEqual(custom.value as? String, previousColor)
        XCTAssertTrue(app.buttons["shape-save"].isEnabled)
        app.buttons["shape-save"].tap()
        XCTAssertTrue(app.buttons["shape-save"].waitForNonExistence(timeout: 10))
        revealEditorTool(app, identifier: "editor-manage-markup")
        app.buttons["editor-manage-markup"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markup-row-")).firstMatch.waitForExistence(timeout: 5))
        app.terminate()
    }

    /// A second connection holds a real write transaction. The app must keep
    /// the draft after SQLite refuses its save, then allow retry after release.
    func testShapeSaveFailureKeepsDraftAndCanRetry() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-save-failure-ui-\(UUID().uuidString)"
        let app = launch(["-PaperNestDebugShowTools", "YES"], libraryPath: library)
        XCTAssertTrue(app.buttons["tool-notebook"].waitForExistence(timeout: 15))
        app.buttons["tool-notebook"].tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Save failure")
        app.buttons["notebook-create"].tap()
        XCTAssertTrue(app.scrollViews["notebook-tool-bar"].waitForExistence(timeout: 10))
        revealEditorTool(app, identifier: "editor-shapes")
        app.buttons["editor-shapes"].tap()
        XCTAssertTrue(app.buttons["shape-kind-ellipse"].waitForExistence(timeout: 5))
        app.buttons["shape-kind-ellipse"].tap()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(library + "/Library.sqlite", &database, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_exec(database, "ROLLBACK", nil, nil, nil); sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil), SQLITE_OK)
        app.buttons["shape-save"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 15))
        XCTAssertTrue(app.alerts.staticTexts["Couldn’t save this shape. If the page changed, close this sheet and try again."].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "shape-save-failure"
        shot.lifetime = .keepAlways
        add(shot)
        app.alerts.buttons["OK"].tap()
        XCTAssertEqual(app.buttons["shape-kind-ellipse"].value as? String, "Selected")
        XCTAssertEqual(sqlite3_exec(database, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        app.buttons["shape-save"].tap()
        XCTAssertTrue(app.buttons["shape-save"].waitForNonExistence(timeout: 10))
        revealEditorTool(app, identifier: "editor-manage-markup")
        app.buttons["editor-manage-markup"].tap()
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "markup-row-"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        app.terminate()
    }

    func testAnnotationSheetsAccessibilityAudit() throws {
        continueAfterFailure = true
        let app = launch(["-PaperNestDebugOpenItem", "Markup target"],
                         libraryPath: "/tmp/papernest-text-markup-library")
        XCTAssertTrue(app.buttons["editor-more"].waitForExistence(timeout: 15))
        for (entry, close) in [("editor-shapes", "shape-cancel"),
                               ("editor-stamps", "stamp-cancel"),
                               ("editor-comments", "comments-done"),
                               ("editor-manage-markup", "markup-done")] {
            app.buttons["editor-more"].tap()
            app.buttons[entry].tap()
            XCTAssertTrue(app.buttons[close].waitForExistence(timeout: 10))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "accessibility-audit-\(entry)"
            shot.lifetime = .keepAlways
            add(shot)
            // Automated audit is complementary to, not a substitute for,
            // navigating and listening with VoiceOver on real hardware.
            try app.performAccessibilityAudit(for: [.contrast, .textClipped, .dynamicType])
            app.buttons[close].tap()
        }
        app.terminate()
    }

    func testAnnotationStyleLayoutInAllLanguages() throws {
        continueAfterFailure = false
        for language in ["en", "fr", "es"] {
            let app = launch(["-PaperNestDebugOpenItem", "Markup target"],
                             libraryPath: "/tmp/papernest-text-markup-library", language: language)
            XCTAssertTrue(app.buttons["editor-more"].waitForExistence(timeout: 15))
            for (entry, prefix) in [("editor-shapes", "shape"), ("editor-stamps", "stamp")] {
                app.buttons["editor-more"].tap()
                app.buttons[entry].tap()
                XCTAssertTrue(app.buttons["\(prefix)-save"].waitForExistence(timeout: 5))
                let first = app.buttons[prefix == "shape" ? "shape-kind-rectangle" : "stamp-kind-checkmark"]
                let second = app.buttons[prefix == "shape" ? "shape-kind-ellipse" : "stamp-kind-cross"]
                XCTAssertTrue(first.isHittable)
                XCTAssertTrue(second.isHittable)
                XCTAssertEqual(first.frame.midY, second.frame.midY, accuracy: 2, "Normal text uses a compact chooser")
                second.tap()
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "readable-\(prefix)-\(language)"
                shot.lifetime = .keepAlways
                add(shot)
                app.buttons["\(prefix)-cancel"].tap()
            }
            revealEditorTool(app, identifier: "editor-comments")
            app.buttons["editor-comments"].tap()
            XCTAssertTrue(app.buttons["comment-add"].waitForExistence(timeout: 5))
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "readable-comments-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["comment-add"].tap()
            XCTAssertTrue(app.textViews["comment-text"].waitForExistence(timeout: 5))
            app.buttons["comment-cancel"].tap()
            app.buttons["comments-done"].tap()
            app.terminate()
        }
    }

    /// Show or hide Document Utilities through its one control. Idempotent:
    /// it looks at whether the panel is up before deciding to tap.
    private func setToolsPanel(_ shown: Bool, in app: XCUIApplication) {
        let panels = app.buttons["editor-panels"]
        XCTAssertTrue(panels.waitForExistence(timeout: 10))
        let list = app.scrollViews["pdf-tools-list"]
        if list.exists != shown { panels.tap() }
        if shown { XCTAssertTrue(list.waitForExistence(timeout: 5)) }
        else { XCTAssertTrue(list.waitForNonExistence(timeout: 5)) }
    }

    /// The control that reaches the editor's secondary tools: the merged
    /// panels popover on iPad and Mac, the overflow menu on the phone.
    private func toolsEntryPoint(_ app: XCUIApplication) -> XCUIElement {
        UIDevice.current.userInterfaceIdiom == .pad
            ? app.buttons["editor-panels"] : app.buttons["studio-more-tools"]
    }

    /// Secondary notebook tools now live in More; history remains in the palette.
    private func revealEditorTool(_ app: XCUIApplication, identifier: String) {
        if app.buttons[identifier].isHittable { return }
        let sidebar = app.scrollViews["pdf-tools-list"]
        if UIDevice.current.userInterfaceIdiom == .pad {
            if !sidebar.exists { setToolsPanel(true, in: app) }
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            for _ in 0..<10 where !app.buttons[identifier].isHittable { sidebar.swipeUp() }
            if !app.buttons[identifier].isHittable {
                for _ in 0..<10 where !app.buttons[identifier].isHittable { sidebar.swipeDown() }
            }
            return
        }
        let bar = app.scrollViews["notebook-tool-bar"]
        if bar.exists {
            let more = app.buttons["studio-more-tools"]
            for _ in 0..<10 where !more.isHittable { bar.swipeLeft() }
            XCTAssertTrue(more.isHittable)
            more.tap()
            // Native menus virtualize later rows at accessibility text sizes.
            // Scroll the presented menu, not the editor underneath it.
            let menu = app.collectionViews.containing(.button, identifier: "editor-shapes").firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            if !app.buttons[identifier].waitForExistence(timeout: 2) {
                for _ in 0..<10 where !app.buttons[identifier].exists {
                    guard menu.exists else { break }
                    menu.swipeUp()
                }
            }
        } else {
            app.buttons["editor-more"].tap()
        }
    }

    func testNotebookToolsAreSideBySide() throws {
        continueAfterFailure = false
        for language in ["en", "fr", "es"] {
            let app = launch([], libraryPath: "/tmp/papernest-note-bar-\(UUID().uuidString)", language: language)
            XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 15))
            homeTools(app).tap()
            app.buttons["tool-notebook"].tap()
            let name = app.textFields["notebook-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap()
            name.typeText("Note tools")
            app.buttons["notebook-create"].tap()
            let bar = app.scrollViews["notebook-tool-bar"]
            XCTAssertTrue(bar.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["editor-more"].exists)
            let shape = app.buttons["studio-tool-pen"]
            let stamp = app.buttons["studio-tool-highlighter"]
            XCTAssertTrue(shape.isHittable)
            XCTAssertTrue(stamp.isHittable)
            XCTAssertEqual(shape.frame.midY, stamp.frame.midY, accuracy: 2)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "notebook-tool-bar-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            revealEditorTool(app, identifier: "editor-shapes")
            app.buttons["editor-shapes"].tap()
            XCTAssertTrue(app.buttons["shape-save"].waitForExistence(timeout: 5))
            app.buttons["shape-save"].tap()
            XCTAssertTrue(app.buttons["shape-save"].waitForNonExistence(timeout: 10))
            revealEditorTool(app, identifier: "notebook-undo")
            XCTAssertTrue(app.buttons["notebook-undo"].isEnabled)
            app.buttons["notebook-undo"].tap()
            revealEditorTool(app, identifier: "notebook-redo")
            XCTAssertTrue(app.buttons["notebook-redo"].isEnabled)
            app.buttons["notebook-redo"].tap()
            revealEditorTool(app, identifier: "editor-add-notebook-page")
            app.buttons["editor-add-notebook-page"].tap()
            XCTAssertTrue(app.buttons["add-page-create"].waitForExistence(timeout: 5))
            app.buttons["add-page-cancel"].tap()
            revealEditorTool(app, identifier: "editor-comments")
            app.buttons["editor-comments"].tap()
            XCTAssertTrue(app.buttons["comment-add"].waitForExistence(timeout: 5))
            app.buttons["comments-done"].tap()
            revealEditorTool(app, identifier: "editor-delete-page")
            app.buttons["editor-delete-page"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["document-page-image"].firstMatch.waitForNonExistence(timeout: 5))
            XCTAssertTrue(bar.exists, "Empty notes must keep Add Page and Undo available")
            revealEditorTool(app, identifier: "notebook-undo")
            XCTAssertTrue(app.buttons["notebook-undo"].isEnabled)
            app.buttons["notebook-undo"].tap()
            revealEditorTool(app, identifier: "editor-add-notebook-page")
            app.buttons["editor-add-notebook-page"].tap()
            XCTAssertTrue(app.buttons["add-page-create"].waitForExistence(timeout: 5))
            app.buttons["add-page-create"].tap()
            XCTAssertTrue(app.buttons["add-page-create"].waitForNonExistence(timeout: 10))
            app.terminate()
        }
    }

    func testFirstLaunchWelcomeAndRelaunchInAllLanguages() throws {
        continueAfterFailure = false
        for language in ["en", "fr", "es"] {
            let library = "/tmp/papernest-welcome-\(UUID().uuidString)"
            let args = ["-PaperNestDebugWelcomeKey", "WelcomeTest-\(UUID().uuidString)"]
            var app = launch(args, libraryPath: library, language: language, skipWelcome: false)
            let start = app.buttons["welcome-continue"]
            XCTAssertTrue(start.waitForExistence(timeout: 15))
            XCTAssertTrue(start.isHittable)
            XCTAssertTrue(app.staticTexts["welcome-title"].exists)
            XCTAssertFalse(app.buttons["home-new-note"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "welcome-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            start.tap()
            XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 10))
            app.terminate()
            app = launch(args, libraryPath: library, language: language, skipWelcome: false)
            XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["welcome-continue"].exists)
            app.terminate()
        }
    }

    func testWelcomeLargestTextKeepsContinueReachable() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugWelcomeKey", "WelcomeLargeTest-\(UUID().uuidString)",
                          "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"],
                         libraryPath: "/tmp/papernest-welcome-large-\(UUID().uuidString)",
                         language: "fr", skipWelcome: false)
        let start = app.buttons["welcome-continue"]
        XCTAssertTrue(start.waitForExistence(timeout: 15))
        XCTAssertTrue(start.isHittable)
        let scroll = app.scrollViews["welcome-content"]
        scroll.swipeUp()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "welcome-largest-text-fr"
        shot.lifetime = .keepAlways
        add(shot)
        start.tap()
        XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 10))
        app.terminate()
    }

    func testVisibleAnnotationStyleContrast() throws {
        continueAfterFailure = true
        let app = launch(["-PaperNestDebugOpenItem", "Markup target"],
                         libraryPath: "/tmp/papernest-text-markup-library")
        XCTAssertTrue(app.buttons["editor-more"].waitForExistence(timeout: 15))
        for (entry, prefix) in [("editor-shapes", "shape"), ("editor-stamps", "stamp")] {
            app.buttons["editor-more"].tap()
            app.buttons[entry].tap()
            XCTAssertTrue(app.buttons["\(prefix)-cancel"].waitForExistence(timeout: 5))
            let form = app.collectionViews.matching(
                NSPredicate(format: "label != %@ AND label != %@", "Sidebar", "Pages")).firstMatch
            XCTAssertTrue(form.exists)
            let style = app.staticTexts["Style"]
            for _ in 0..<5 {
                let viewport = form.frame.intersection(app.frame).insetBy(dx: 8, dy: 60)
                if style.exists && viewport.contains(style.frame) && style.isHittable { break }
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(
                    CGVector(dx: form.frame.minX + 8, dy: form.frame.midY + 100))
                start.press(forDuration: 0.1,
                            thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)),
                            withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            XCTAssertTrue(style.exists)
            XCTAssertTrue(form.frame.intersection(app.frame).insetBy(dx: 8, dy: 60).contains(style.frame))
            XCTAssertTrue(style.isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "fully-visible-\(prefix)-style"
            shot.lifetime = .keepAlways
            add(shot)
            // Separate diagnostic: the initial-viewport audit remains unchanged.
            try app.performAccessibilityAudit(for: [.contrast, .textClipped])
            app.buttons["\(prefix)-cancel"].tap()
        }
        app.terminate()
    }

    func testBottomFoldersReachesCreationInEmptyLibrary() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Compact iPhone home navigation")
        }
        let app = launch([], libraryPath: "/tmp/papernest-bottom-folders-\(UUID().uuidString)")
        defer { app.terminate() }
        let folders = app.buttons["home-folders"]
        XCTAssertTrue(folders.waitForExistence(timeout: 15))
        folders.tap()
        let create = app.buttons["sidebar-new-folder"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isHittable, "Folders must reveal an actionable row")
        create.tap()
        XCTAssertTrue(app.alerts.textFields.firstMatch.waitForExistence(timeout: 5))
        app.alerts.textFields.firstMatch.typeText("Bottom menu folder")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.staticTexts["This Folder Is Empty"].waitForExistence(timeout: 5))
    }

    func testStudioHomeHasContentFiltersAndNoQuickActionCards() throws {
        continueAfterFailure = false
        let app = launch([])
        XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["home-new-note"].exists)
        XCTAssertFalse(app.buttons["home-create"].exists)
        XCTAssertFalse(app.buttons["library-import"].exists)
        XCTAssertFalse(app.buttons["home-filter-shared"].exists, "Unsupported shared collections must not appear as a working filter")
        app.buttons["home-filter-recent"].tap()
        app.buttons["home-notes"].tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        app.buttons["home-documents"].tap()
        XCTAssertTrue(app.buttons["Crop target, 1 page"].waitForExistence(timeout: 5))
        app.buttons["home-tab"].tap()
        XCTAssertTrue(app.buttons["home-filter-favorites"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "studio-home"; shot.lifetime = .keepAlways; add(shot)
    }

    func testStudioPenSavesAndReopensWithFloatingHistory() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-studio-ui-\(UUID().uuidString)"
        var app = launch([], libraryPath: library)
        XCTAssertTrue(homeTools(app).waitForExistence(timeout: 15))
        homeTools(app).tap()
        app.buttons["tool-notebook"].tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Studio test")
        app.buttons["notebook-create"].tap()
        let pen = app.buttons["studio-tool-pen"]
        XCTAssertTrue(pen.waitForExistence(timeout: 10)); pen.tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            app.buttons["studio-tool-settings"].tap()
            let finger = app.switches["studio-finger-drawing"]
            for _ in 0..<6 where !finger.isHittable {
                let form = app.scrollViews["tool-panel-scroll"]
                let frame = form.frame.intersection(app.frame)
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.maxX - 8, dy: frame.maxY - 40))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -200)))
            }
            XCTAssertTrue(finger.waitForExistence(timeout: 5))
            // SwiftUI exposes the entire labeled row as the switch; hit its control.
            finger.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            wait(for: [expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: finger)], timeout: 5)
            app.buttons["Done"].tap()
        }
        let canvas = app.descendants(matching: .any)["ink-canvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(canvas.frame.height, 200, "Toolbar must leave a usable writing canvas")
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        let undo = app.buttons["notebook-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        let savedStroke = NSPredicate(format: "value == %@", "1 stroke")
        wait(for: [expectation(for: savedStroke, evaluatedWith: canvas)], timeout: 10)
        wait(for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: undo)], timeout: 5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "studio-notebook"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
        app = launch(["-PaperNestDebugOpenItem", "Studio test"], libraryPath: library)
        XCTAssertTrue(app.buttons["studio-tool-pen"].waitForExistence(timeout: 15))
        let page = app.descendants(matching: .any)["document-page-image"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        XCTAssertEqual(page.value as? String, "1 stroke")
        if UIDevice.current.userInterfaceIdiom == .pad {
            app.descendants(matching: .any)["sidebar-home"].firstMatch.tap()
            let recent = app.buttons["Studio test, 1 page"]
            XCTAssertTrue(recent.waitForExistence(timeout: 5))
            recent.tap()
            XCTAssertTrue(app.buttons["studio-tool-pen"].waitForExistence(timeout: 5))
        }
    }

    func testStudioHomeLocalizedAndAccessible() throws {
        continueAfterFailure = false
        for language in ["en", "fr", "es"] {
            let app = launch(language == "es" ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [], language: language)
            XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 15))
            XCTAssertFalse(app.buttons["home-new-note"].exists)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "studio-home-\(language)"; shot.lifetime = .keepAlways; add(shot)
            app.buttons["home-filter-favorites"].tap()
            XCTAssertTrue(app.buttons["home-see-all"].exists)
            app.terminate()
        }
    }

    func testImportDestinationCreatesFolderAndOpensDocument() throws {
        let fixture = URL(fileURLWithPath: "/tmp/papernest-import-location-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 80)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
        }
        try XCTUnwrap(image.pngData()).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let library = "/tmp/papernest-import-location-ui-\(UUID().uuidString)"
        let app = launch(["-PaperNestDebugImportFile", fixture.path], libraryPath: library)
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["import-location-save"].waitForExistence(timeout: 15))
        app.buttons.matching(NSPredicate(format: "identifier == %@ AND label == %@", "import-location-picker", "New Folder")).firstMatch.tap()
        let name = app.textFields["import-location-new-folder"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Receipts")
        app.buttons["import-location-save"].tap()
        XCTAssertTrue(app.buttons["editor-export"].waitForExistence(timeout: 15))
    }

    func testImportDestinationLocalesAndLargeTextCancellation() throws {
        try checkImportDestinationLocales(auditTextClipping: false)
    }

    func testImportDestinationTextClippingAudit() throws {
        try checkImportDestinationLocales(auditTextClipping: true)
    }

    private func checkImportDestinationLocales(auditTextClipping: Bool) throws {
        let fixture = URL(fileURLWithPath: "/tmp/papernest-import-accessibility-\(UUID().uuidString).png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 60, height: 80)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 60, height: 80))
        }
        try XCTUnwrap(image.pngData()).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        for language in ["en", "fr", "es"] {
            var arguments = ["-PaperNestDebugImportFile", fixture.path]
            if language == "es" {
                arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            let app = launch(arguments, libraryPath: "/tmp/papernest-import-accessibility-\(UUID().uuidString)", language: language)
            defer { app.terminate() }
            let save = app.buttons["import-location-save"]
            let cancel = app.buttons["import-location-cancel"]
            XCTAssertTrue(save.waitForExistence(timeout: 15))
            XCTAssertTrue(save.isHittable)
            XCTAssertTrue(cancel.isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "import-destination-\(language)"
            shot.lifetime = .keepAlways
            add(shot)
            if auditTextClipping { try app.performAccessibilityAudit(for: [.textClipped]) }
            cancel.tap()
            XCTAssertTrue(save.waitForNonExistence(timeout: 5))
            XCTAssertFalse(app.buttons["editor-export"].exists)
        }
    }

    func testNoteImageMenuOffersCameraPhotosAndFiles() throws {
        continueAfterFailure = false
        let app = launch([], libraryPath: "/tmp/papernest-note-camera-\(UUID().uuidString)")
        defer { app.terminate() }
        XCTAssertTrue(homeTools(app).waitForExistence(timeout: 15))
        homeTools(app).tap()
        app.buttons["tool-notebook"].tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Camera note")
        app.buttons["notebook-create"].tap()
        let image = app.buttons["editor-insert-image"]
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        image.tap()
        XCTAssertTrue(app.buttons["editor-image-camera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor-image-photos"].exists)
        XCTAssertTrue(app.buttons["editor-image-files"].exists)
        #if targetEnvironment(simulator)
        XCTAssertFalse(app.buttons["editor-image-camera"].isEnabled)
        #endif
    }

}

// Sidebar destinations must use the list's native selection, including Home.
extension AppUITests {
    func testHomeSidebarSelectionFollowsNavigation() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("wide sidebar") }
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugTemporaryLibrary", UUID().uuidString])
        defer { app.terminate() }
        let home = app.cells.containing(.any, identifier: "sidebar-home").firstMatch
        XCTAssertTrue(home.waitForExistence(timeout: 15))
        XCTAssertTrue(home.isSelected, "Home must be a selected sidebar row at launch")
        let initial = XCTAttachment(screenshot: app.screenshot())
        initial.name = "home-sidebar-initial-selection"
        initial.lifetime = .keepAlways
        add(initial)
        for _ in 0..<2 {
            app.staticTexts["Favorites"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["Favorites"].waitForExistence(timeout: 5))
            XCTAssertFalse(home.isSelected)
            home.tap()
            XCTAssertTrue(app.buttons["home-filter-recent"].waitForExistence(timeout: 5))
            XCTAssertTrue(home.isSelected)
        }
        let notes = app.cells.containing(.any, identifier: "sidebar-notes").firstMatch
        notes.tap()
        XCTAssertTrue(notes.isSelected)
        XCTAssertFalse(home.isSelected)
        let notesScreenshot = XCTAttachment(screenshot: app.screenshot())
        notesScreenshot.name = "notes-sidebar-selection"
        notesScreenshot.lifetime = .keepAlways
        add(notesScreenshot)
        home.tap()
        XCTAssertTrue(home.isSelected)
        XCTAssertFalse(notes.isSelected)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "home-sidebar-native-selection"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

extension AppUITests {
    func testNotesSidebarCreatesAndReopensOnlyNotebooks() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("wide sidebar") }
        continueAfterFailure = false
        let library = "/tmp/papernest-notes-library-\(UUID().uuidString)"
        try FileManager.default.copyItem(atPath: Self.libraryPath, toPath: library)
        let app = launch([], libraryPath: library)
        defer { app.terminate() }
        let notes = app.cells.containing(.any, identifier: "sidebar-notes").firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 15))
        notes.tap()
        XCTAssertTrue(app.navigationBars["Notes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No Notebooks Yet"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Crop target, 1 page"].exists)
        XCTAssertFalse(app.buttons["library-scan"].exists)
        app.buttons["notes-create-empty"].tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Notes route test")
        app.buttons["notebook-create"].tap()
        XCTAssertTrue(app.buttons["studio-tool-pen"].waitForExistence(timeout: 15))
        let documents = app.cells.containing(.staticText, identifier: "All Documents").firstMatch
        documents.tap()
        XCTAssertTrue(app.buttons["Crop target, 1 page"].waitForExistence(timeout: 10))
        XCTAssertTrue(documents.isSelected)
        notes.tap()
        let notebook = app.buttons["Notes route test, 1 page"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Crop target, 1 page"].exists)
        XCTAssertTrue(app.buttons["notes-create"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "notes-library-ipad"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.terminate(); app.launch()
        XCTAssertTrue(notes.waitForExistence(timeout: 15)); notes.tap()
        XCTAssertTrue(notebook.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Crop target, 1 page"].exists)
        notebook.tap()
        XCTAssertTrue(app.buttons["studio-tool-pen"].waitForExistence(timeout: 10))
    }
}


extension AppUITests {
    /// Runs on physical iPad too: no host paths, fixture copying or real library.
    func testNotesPlusCreatesAndReopensNotebookOnDevice() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad") }
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugTemporaryLibrary", UUID().uuidString])
        defer { app.terminate() }
        let notes = app.cells.containing(.any, identifier: "sidebar-notes").firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        let create = app.buttons["notes-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap()
        name.typeText("Device notebook")
        app.buttons["notebook-create"].tap()
        let pen = app.buttons["studio-tool-pen"]
        XCTAssertTrue(pen.waitForExistence(timeout: 20))
        pen.tap()
        XCTAssertTrue(app.descendants(matching: .any)["ink-canvas"].waitForExistence(timeout: 10))
        app.terminate(); app.launch()
        XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        let notebook = app.buttons["Device notebook, 1 page"]
        XCTAssertTrue(notebook.waitForExistence(timeout: 10)); notebook.tap()
        XCTAssertTrue(pen.waitForExistence(timeout: 20))
        XCTAssertEqual(app.state, .runningForeground)
    }
}

extension AppUITests {
    func testCompactNotebookToolsAndPenControls() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugTemporaryLibrary", UUID().uuidString])
        defer { app.terminate() }
        if UIDevice.current.userInterfaceIdiom == .pad {
            let notes = app.cells.containing(.any, identifier: "sidebar-notes").firstMatch
            XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        } else {
            let notes = app.buttons["home-notes"]
            XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        }
        let create = app.buttons["notes-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        name.tap(); name.typeText("Tool controls")
        app.buttons["notebook-create"].tap()
        let pen = app.buttons["studio-tool-pen"]
        let eraser = app.buttons["studio-tool-eraser"]
        let highlight = app.buttons["studio-tool-highlighter"]
        XCTAssertTrue(pen.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["editor-insert-image"].exists, "Image belongs in the primary toolbar")
        XCTAssertTrue(app.buttons["editor-text-box"].exists, "Text Box belongs in the primary toolbar")
        // Owner's 2026-11-12 toolbar redesign: tools are named where they all
        // fit (iPad, Mac) and icon-only on a phone, and the order is Pen,
        // Highlighter, Eraser, Lasso. These two lines used to pin the
        // previous approved layout — icon-only everywhere, Eraser after Pen.
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(pen.staticTexts["Pen"].exists, "A phone's toolbar is icon-only")
        }
        XCTAssertLessThan(highlight.frame.minX, eraser.frame.minX, "Highlighter sits directly after Pen")
        XCTAssertFalse(app.buttons["editor-shapes"].exists, "The placement sheet for shapes stays in More")
        XCTAssertTrue(app.buttons["studio-tool-shape"].exists, "Drag-to-draw Shapes is a primary tool")
        pen.tap(); pen.tap()
        let width = app.sliders["studio-width-slider"]
        XCTAssertTrue(width.waitForExistence(timeout: 5))
        let done = app.buttons["studio-settings-done"]
        XCTAssertGreaterThan(done.frame.minY, pen.frame.maxY, "Pen settings open below the top tool")
        // On iPad they are a popover anchored to the tool. On a phone the
        // 2026-11-12 redesign makes them a bottom sheet, which is not near it.
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertLessThan(done.frame.minY, pen.frame.maxY + 140, "Settings stay near Pen, not the lower palette")
        }
        width.adjust(toNormalizedSliderPosition: 0.75)
        let afterWidth = XCTAttachment(screenshot: app.screenshot())
        afterWidth.name = "pen-settings-after-width"; afterWidth.lifetime = .keepAlways; add(afterWidth)
        let opacity = app.sliders["studio-opacity-slider"]
        let settingsForm = app.scrollViews["tool-panel-scroll"]
        XCTAssertTrue(settingsForm.exists)
        let settingsFrame = settingsForm.frame.intersection(app.frame)
        for _ in 0..<6 where !opacity.isHittable {
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: settingsFrame.maxX - 8, dy: settingsFrame.maxY - 40))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -250)))
        }
        opacity.adjust(toNormalizedSliderPosition: 0.45)
        let chosenWidth = width.value as? String
        let chosenOpacity = opacity.value as? String
        app.buttons["markup-color-blue"].tap()
        XCTAssertEqual(opacity.value as? String, chosenOpacity, "Choosing color preserves opacity")
        let settings = XCTAttachment(screenshot: app.screenshot())
        settings.name = "notebook-pen-controls"; settings.lifetime = .keepAlways; add(settings)
        app.closeToolSettings()
        eraser.tap()
        XCTAssertEqual(eraser.value as? String, "Selected")
        pen.tap(); pen.tap()
        XCTAssertTrue(width.waitForExistence(timeout: 5))
        XCTAssertEqual(width.value as? String, chosenWidth)
        app.closeToolSettings()
        app.buttons["editor-insert-image"].tap()
        XCTAssertTrue(app.buttons["editor-image-photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor-image-files"].exists)
        // Dismiss the native image menu by tapping the canvas outside it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.6)).tap()
        app.buttons["editor-text-box"].tap()
        app.images["document-page-image"].coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).tap()
        let text = app.textViews["inline-text-editor"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["inline-text-size"].exists)
        XCTAssertTrue(app.buttons["inline-text-alignment"].exists)
        text.typeText("Toolbar text")
        app.buttons["inline-text-done"].tap()
        XCTAssertTrue(text.waitForNonExistence(timeout: 10))
        revealEditorTool(app, identifier: "editor-shapes")
        let shapes = app.buttons["editor-shapes"]
        XCTAssertTrue(shapes.waitForExistence(timeout: 5)); shapes.tap()
        XCTAssertTrue(app.buttons["shape-save"].waitForExistence(timeout: 5))
    }
}

extension AppUITests {
    func testInlineTextPlacementFormattingAndReopen() throws {
        continueAfterFailure = false
        let token = UUID().uuidString
        let app = launch(["-PaperNestDebugTemporaryLibrary", token])
        defer { app.terminate() }
        if UIDevice.current.userInterfaceIdiom == .pad {
            let notes = app.cells.containing(.any, identifier: "sidebar-notes").firstMatch
            XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        } else { app.buttons["home-notes"].tap() }
        let create = app.buttons["notes-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText("Inline paper")
        app.buttons["notebook-create"].tap()
        let textTool = app.buttons["editor-text-box"]
        XCTAssertTrue(textTool.waitForExistence(timeout: 20)); textTool.tap()
        XCTAssertFalse(app.buttons["text-box-add"].exists, "Text placement must not open a modal")
        let page = app.images["document-page-image"]
        XCTAssertTrue(page.exists)
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.38)).tap()
        let editor = app.textViews["inline-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Placement focuses the caret immediately")
        editor.typeText("On paper")
        app.buttons["inline-text-bold"].tap()
        XCTAssertEqual(app.buttons["inline-text-bold"].value as? String, "Selected")
        editor.typeText(" now")
        XCTAssertEqual(editor.value as? String, "On paper now", "Formatting preserves the caret")
        app.buttons["inline-text-done"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        let mark = app.buttons["inline-text-object"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.value as? String, "On paper now")
        mark.tap()
        XCTAssertTrue(app.buttons["inline-text-bold"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["inline-text-bold"].value as? String, "Selected")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "inline-text-selected"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["inline-text-done"].tap()
        app.terminate(); app.launch()
        let recent = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'home-recent-' AND label CONTAINS 'Inline paper'")).firstMatch
        if recent.waitForExistence(timeout: 10) { recent.tap() }
        else {
            let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Inline paper'")).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        }
        XCTAssertTrue(app.buttons["inline-text-object"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(app.buttons["inline-text-object"].firstMatch.value as? String, "On paper now")
    }
}

extension AppUITests {
    func testInlineTextHandlesMoveResizeAndOutsideTapSaves() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugTemporaryLibrary", UUID().uuidString])
        defer { app.terminate() }
        createInlineTestNotebook(app, named: "Inline geometry")
        placeInlineTestText(app, text: "Move and resize")
        let mark = app.buttons["inline-text-object"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        let original = mark.frame

        mark.tap()
        let move = app.descendants(matching: .any)["inline-text-move"].firstMatch
        XCTAssertTrue(move.waitForExistence(timeout: 5))
        XCTAssertTrue(move.isHittable, "Movement belongs to the explicit handle")
        let moveStart = move.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        moveStart.press(forDuration: 0.15, thenDragTo: moveStart.withOffset(CGVector(dx: 35, dy: 30)))
        app.buttons["inline-text-done"].tap()
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate { _, _ in
            abs(mark.frame.minX - original.minX) > 12 && abs(mark.frame.minY - original.minY) > 12
        }, evaluatedWith: mark)], timeout: 10)
        let moved = mark.frame
        XCTAssertEqual(moved.width, original.width, accuracy: 3, "Moving preserves the box's width")
        XCTAssertEqual(moved.height, original.height, accuracy: 3, "Moving preserves the box's height")

        mark.tap()
        let resize = app.descendants(matching: .any)["inline-text-resize"].firstMatch
        XCTAssertTrue(resize.waitForExistence(timeout: 5))
        XCTAssertTrue(resize.isHittable, "Resizing belongs to the corner handle")
        let resizeStart = resize.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        resizeStart.press(forDuration: 0.15, thenDragTo: resizeStart.withOffset(CGVector(dx: 40, dy: 35)))
        // An outside paper tap commits and deselects without using Done.
        let page = app.images["document-page-image"]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.72)).tap()
        XCTAssertTrue(app.buttons["inline-text-done"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        wait(for: [expectation(for: NSPredicate { _, _ in
            mark.frame.width > moved.width + 15 && mark.frame.height > moved.height + 12
        }, evaluatedWith: mark)], timeout: 10)
        XCTAssertEqual(mark.frame.minX, moved.minX, accuracy: 3)
        XCTAssertEqual(mark.frame.minY, moved.minY, accuracy: 3)
        XCTAssertEqual(mark.value as? String, "Move and resize")
        let resized = mark.frame
        mark.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inline-text-move"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["inline-text-done"].tap()
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.frame.width, resized.width, accuracy: 3, "Reselecting keeps the saved frame")
        XCTAssertEqual(mark.frame.height, resized.height, accuracy: 3)
    }

    func testInlineTextContextualControlsDeletionHistoryAndMorePDFTool() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugTemporaryLibrary", UUID().uuidString])
        defer { app.terminate() }
        createInlineTestNotebook(app, named: "Inline controls")
        placeInlineTestText(app, text: "Styled paper")
        let mark = app.buttons["inline-text-object"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 10)); mark.tap()

        inlineControl(app, identifier: "inline-text-font").tap()
        let serif = app.buttons["inline-font-serif"]
        XCTAssertTrue(serif.waitForExistence(timeout: 5)); serif.tap()
        assertInlineValue(app, identifier: "inline-text-font", value: "Serif")
        inlineControl(app, identifier: "inline-text-size").tap()
        let size = app.buttons["inline-size-24"]
        XCTAssertTrue(size.waitForExistence(timeout: 5)); size.tap()
        assertInlineValue(app, identifier: "inline-text-size", value: "24")
        inlineControl(app, identifier: "inline-text-italic").tap()
        assertInlineValue(app, identifier: "inline-text-italic", value: "Selected")
        inlineControl(app, identifier: "inline-text-alignment").tap()
        let center = app.buttons["inline-align-center"]
        XCTAssertTrue(center.waitForExistence(timeout: 5)); center.tap()
        assertInlineValue(app, identifier: "inline-text-alignment", value: "Center")
        inlineControl(app, identifier: "inline-text-color").tap()
        let blue = app.buttons["markup-color-blue"]
        XCTAssertTrue(blue.waitForExistence(timeout: 5)); blue.tap()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: blue)], timeout: 5)
        dismissInlineColorPopover(app)
        app.buttons["inline-text-done"].tap()
        XCTAssertTrue(mark.waitForExistence(timeout: 10)); mark.tap()
        // Read the persisted object's controls after replacing the edit session.
        assertInlineValue(app, identifier: "inline-text-font", value: "Serif")
        assertInlineValue(app, identifier: "inline-text-size", value: "24")
        assertInlineValue(app, identifier: "inline-text-italic", value: "Selected")
        assertInlineValue(app, identifier: "inline-text-alignment", value: "Center")
        inlineControl(app, identifier: "inline-text-color").tap()
        XCTAssertTrue(blue.waitForExistence(timeout: 5))
        XCTAssertEqual(blue.value as? String, "Selected")
        dismissInlineColorPopover(app)
        inlineControl(app, identifier: "inline-text-delete").tap()
        XCTAssertTrue(app.buttons["inline-text-done"].waitForNonExistence(timeout: 10))
        XCTAssertFalse(mark.exists, "Delete removes the saved text object")

        tapInlineHistory(app, identifier: "notebook-undo")
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.value as? String, "Styled paper")
        tapInlineHistory(app, identifier: "notebook-redo")
        XCTAssertTrue(mark.waitForNonExistence(timeout: 10))
        tapInlineHistory(app, identifier: "notebook-undo")
        XCTAssertTrue(mark.waitForExistence(timeout: 10)); mark.tap()
        assertInlineValue(app, identifier: "inline-text-font", value: "Serif")
        assertInlineValue(app, identifier: "inline-text-size", value: "24")
        assertInlineValue(app, identifier: "inline-text-italic", value: "Selected")
        assertInlineValue(app, identifier: "inline-text-alignment", value: "Center")
        app.buttons["inline-text-done"].tap()
        XCTAssertTrue(mark.waitForExistence(timeout: 10))

        // Only the phone keeps an overflow button in the writing bar; iPad
        // and Mac reach the same actions inside the tools inspector.
        let textTool = app.buttons["editor-text-box"]
        if UIDevice.current.userInterfaceIdiom != .pad {
            let bar = app.scrollViews["notebook-tool-bar"]
            let more = app.buttons["studio-more-tools"]
            for _ in 0..<5 where !more.isHittable { bar.swipeLeft() }
            XCTAssertTrue(more.isHittable)
            XCTAssertTrue(textTool.isHittable)
            XCTAssertGreaterThan(more.frame.minX, textTool.frame.minX)
            XCTAssertLessThanOrEqual(more.frame.minX - textTool.frame.maxX, 20, "More stays directly next to Text Box")
            XCTAssertEqual(more.frame.midY, textTool.frame.midY, accuracy: 3)
        } else {
            XCTAssertTrue(textTool.isHittable)
        }
        revealEditorTool(app, identifier: "editor-crop")
        let crop = app.buttons["editor-crop"]
        XCTAssertTrue(crop.waitForExistence(timeout: 5)); crop.tap()
        XCTAssertTrue(app.descendants(matching: .any)["crop-area"].firstMatch.waitForExistence(timeout: 10),
                      "More opens the existing PDF crop action")
        XCTAssertTrue(app.buttons["crop-done"].exists)
    }

    private func createInlineTestNotebook(_ app: XCUIApplication, named title: String) {
        if UIDevice.current.userInterfaceIdiom == .pad {
            let notes = app.cells.containing(.any, identifier: "sidebar-notes").firstMatch
            XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        } else {
            let navigation = app.buttons["home-navigation-menu"]
            if navigation.waitForExistence(timeout: 3) { navigation.tap() }
            let notes = app.buttons["home-notes"]
            XCTAssertTrue(notes.waitForExistence(timeout: 20)); notes.tap()
        }
        let create = app.buttons["notes-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let name = app.textFields["notebook-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10)); name.tap(); name.typeText(title)
        app.buttons["notebook-create"].tap()
        XCTAssertTrue(app.buttons["editor-text-box"].waitForExistence(timeout: 20))
    }

    private func placeInlineTestText(_ app: XCUIApplication, text: String) {
        app.buttons["editor-text-box"].tap()
        let page = app.images["document-page-image"]
        XCTAssertTrue(page.waitForExistence(timeout: 5))
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.32)).tap()
        let editor = app.textViews["inline-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText(text)
        XCTAssertTrue(app.buttons["inline-text-done"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["inline-text-done"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["inline-text-object"].firstMatch.waitForExistence(timeout: 10))
    }

    private func inlineControl(_ app: XCUIApplication, identifier: String) -> XCUIElement {
        let button = app.buttons[identifier]
        let toolbar = app.descendants(matching: .any)["inline-text-toolbar"].firstMatch
        XCTAssertTrue(toolbar.waitForExistence(timeout: 5))
        // Measure the visible scroll viewport: the pinned Done button occupies
        // the trailing part of the toolbar. Even Bold may start offscreen when
        // the keyboard narrows the paper, so control names cannot pick direction.
        var viewport = CGRect.zero
        for _ in 0..<10 {
            if button.isHittable { break }
            let frame = toolbar.frame.intersection(app.frame)
            let done = app.buttons["inline-text-done"].frame
            viewport = CGRect(x: frame.minX + 4, y: done.midY - 16,
                              width: max(1, min(frame.maxX, done.minX) - frame.minX - 8), height: 32)
            let inset = min(CGFloat(12), viewport.width * 0.15)
            let left = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.minX + inset, dy: viewport.midY))
            let right = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.maxX - inset, dy: viewport.midY))
            let target = button.frame
            if target.minX < viewport.minX || target.midX < viewport.midX {
                left.press(forDuration: 0.1, thenDragTo: right)
            } else {
                right.press(forDuration: 0.1, thenDragTo: left)
            }
        }
        if !button.exists || !button.isHittable {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "inline-control-unreachable-\(identifier)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        XCTAssertTrue(button.isHittable, "Contextual control must be reachable: \(identifier), target: \(button.frame), viewport: \(viewport)")
        return button
    }

    private func assertInlineValue(_ app: XCUIApplication, identifier: String, value: String) {
        let control = inlineControl(app, identifier: identifier)
        wait(for: [expectation(for: NSPredicate(format: "value == %@", value), evaluatedWith: control)], timeout: 5)
    }

    private func dismissInlineColorPopover(_ app: XCUIApplication) {
        // Native popover backdrop consumes this tap; the edit session remains.
        app.images["document-page-image"].coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.78)).tap()
        XCTAssertTrue(app.buttons["markup-color-blue"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["inline-text-done"].exists)
    }

    private func tapInlineHistory(_ app: XCUIApplication, identifier: String) {
        revealEditorTool(app, identifier: identifier)
        let action = app.buttons[identifier]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        wait(for: [expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: action)], timeout: 10)
        action.tap()
    }
}

extension AppUITests {
    func testInlineTextCompactFrenchAndSpanishLargeType() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("compact iPhone layout") }
        continueAfterFailure = false
        for language in ["fr", "es"] {
            var arguments = ["-PaperNestDebugTemporaryLibrary", UUID().uuidString]
            if language == "es" {
                arguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
            }
            let app = launch(arguments, language: language)
            defer { app.terminate() }
            createInlineTestNotebook(app, named: "Inline \(language)")
            let textTool = app.buttons["editor-text-box"]
            let mainTools = app.scrollViews["notebook-tool-bar"]
            for _ in 0..<5 where !textTool.isHittable { mainTools.swipeLeft() }
            XCTAssertTrue(textTool.isHittable); textTool.tap()
            let page = app.images["document-page-image"]
            XCTAssertTrue(page.waitForExistence(timeout: 5))
            let paperWidth = page.frame.width
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.35)).tap()
            let editor = app.textViews["inline-text-editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Placement immediately focuses the native editor")
            XCTAssertEqual(page.frame.width, paperWidth, accuracy: 2, "Opening the keyboard must not shrink the paper")
            let phrase = language == "fr" ? "Écriture sur la page" : "Texto en la página"
            editor.typeText(phrase)
            XCTAssertEqual(editor.value as? String, phrase)
            XCTAssertTrue(inlineControl(app, identifier: "inline-text-font").isHittable)
            inlineControl(app, identifier: "inline-text-bold").tap()
            XCTAssertEqual(editor.value as? String, phrase)
            XCTAssertTrue(app.keyboards.firstMatch.exists, "Formatting keeps the keyboard and caret active")
            let done = app.buttons["inline-text-done"]
            XCTAssertTrue(done.isHittable, "Done stays visible at large text sizes")
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "inline-text-keyboard-\(language)\(language == "es" ? "-XXXL" : "")"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            done.tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
            let mark = app.buttons["inline-text-object"].firstMatch
            XCTAssertTrue(mark.waitForExistence(timeout: 10))
            XCTAssertEqual(mark.value as? String, phrase)
            app.terminate()
        }
    }
}

extension AppUITests {
    func testPDFFormFilledCopyReopensWithFields() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-pdf-workspace-ui"
        let app = launch(["-PaperNestDebugOpenItem", "Interactive Form"], libraryPath: library)
        defer { app.terminate() }
        XCTAssertTrue(toolsEntryPoint(app).waitForExistence(timeout: 20))
        revealEditorTool(app, identifier: "editor-fill-form")
        app.buttons["editor-fill-form"].tap()
        let customer = app.textFields["form-field-customer"]
        XCTAssertTrue(customer.waitForExistence(timeout: 15)); customer.tap(); customer.typeText("PaperNest Test")
        let approved = app.switches["form-field-approved"]
        XCTAssertTrue(approved.exists)
        approved.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        XCTAssertEqual(approved.value as? String, "1", "Checkbox changes before saving")
        let copyName = "Filled " + UUID().uuidString.prefix(8)
        let name = app.textFields["form-copy-name"]
        name.tap(); name.press(forDuration: 1)
        name.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String)?.count ?? 0))
        name.typeText(copyName)
        XCTAssertTrue(app.descendants(matching: .any)["form-unsupported-reference"].firstMatch.exists)
        app.buttons["form-save-copy"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["form-saved"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["form-close"].tap()
        app.terminate()
        app.launchArguments = ["-PaperNestLibraryPath", library, "-PaperNestDebugOpenItem", copyName,
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(toolsEntryPoint(app).waitForExistence(timeout: 20))
        revealEditorTool(app, identifier: "editor-fill-form")
        app.buttons["editor-fill-form"].tap()
        XCTAssertTrue(customer.waitForExistence(timeout: 15))
        XCTAssertEqual(customer.value as? String, "PaperNest Test")
        XCTAssertEqual(approved.value as? String, "1")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "pdf-form-filled-copy"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testSavedSignaturePlacesAndSurvivesReopen() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugTemporaryLibrary", UUID().uuidString])
        defer { app.terminate() }
        createInlineTestNotebook(app, named: "Signature notebook")
        revealEditorTool(app, identifier: "editor-signature")
        app.buttons["editor-signature"].tap()
        let name = app.textFields["signature-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        let canvas = app.descendants(matching: .any)["signature-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 10))
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.65))
        let end = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.25))
        start.press(forDuration: 0.1, thenDragTo: end)
        let save = app.buttons["signature-save"]
        XCTAssertFalse(save.isEnabled, "An unnamed signature explains why Save is unavailable")
        let nameHint = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "signature-name-required", "Enter a name to save your signature.")).firstMatch
        XCTAssertTrue(nameHint.waitForExistence(timeout: 5), app.debugDescription)
        name.tap(); name.typeText("Test signature")
        XCTAssertTrue(save.isEnabled, "Naming visible ink enables Save without dismissing the keyboard first")
        save.tap()
        XCTAssertTrue(app.descendants(matching: .any)["signature-preview"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["signature-place"].tap()
        XCTAssertTrue(app.buttons["signature-place"].waitForNonExistence(timeout: 15))
        XCTAssertEqual(app.images["document-page-image"].value as? String, "1 stroke")
        tapInlineHistory(app, identifier: "notebook-undo")
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "0 strokes"), evaluatedWith: app.images["document-page-image"])], timeout: 10)
        tapInlineHistory(app, identifier: "notebook-redo")
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "1 stroke"), evaluatedWith: app.images["document-page-image"])], timeout: 10)
        app.terminate(); app.launch()
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Signature notebook'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15)); row.tap()
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.images["document-page-image"].value as? String, "1 stroke")
        revealEditorTool(app, identifier: "editor-signature")
        app.buttons["editor-signature"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'signature-select-'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.label.contains("Test signature"))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "saved-signature-preview"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}

extension AppUITests {
    func testDocumentPagesDuplicateReorderDeleteAndExtract() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugTemporaryLibrary", UUID().uuidString])
        defer { app.terminate() }
        createInlineTestNotebook(app, named: "Page tools")
        placeInlineTestText(app, text: "Keep this editable")
        revealEditorTool(app, identifier: "editor-pages")
        app.buttons["editor-pages"].tap()
        let duplicate = app.buttons["pages-duplicate"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 10)); duplicate.tap()
        let second = app.buttons["pages-select-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertEqual(second.value as? String, "Selected")
        app.buttons["pages-more-2"].tap()
        app.buttons["pages-move-up"].tap()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: app.buttons["pages-select-1"])], timeout: 10)
        app.buttons["pages-rotate-right"].tap()
        app.buttons["pages-done"].tap()
        let mark = app.buttons["inline-text-object"].firstMatch
        XCTAssertTrue(mark.waitForExistence(timeout: 10))
        XCTAssertEqual(mark.value as? String, "Keep this editable")
        revealEditorTool(app, identifier: "editor-pages")
        app.buttons["editor-pages"].tap()
        let remove = app.buttons["pages-delete"]
        let actions = app.scrollViews["pages-actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 10))
        actions.swipeLeft()
        actions.swipeLeft()
        XCTAssertTrue(remove.isHittable); remove.tap()
        XCTAssertTrue(second.waitForNonExistence(timeout: 10))
        try XCTUnwrap(app.buttons.matching(identifier: "notebook-undo").allElementsBoundByIndex.first(where: \.isHittable)).tap()
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        let extract = app.buttons["pages-extract"]
        XCTAssertTrue(extract.isHittable); extract.tap()
        XCTAssertTrue(app.textFields["document-tools-name"].waitForExistence(timeout: 10))
        app.buttons["extract-page-1"].tap()
        app.buttons["document-tools-create"].tap()
        XCTAssertTrue(app.textFields["document-tools-name"].waitForNonExistence(timeout: 15))
        XCTAssertTrue(app.buttons["pages-select-1"].exists, "Extraction leaves source pages intact")
    }
}

extension AppUITests {
    /// A real competing SQLite edit must not trap navigation or overwrite the
    /// other window. Recovery creates a second durable text object on request.
    func testInlineTextConflictCanSaveAsNewBoxAndReopen() throws {
        continueAfterFailure = false
        let library = "/tmp/papernest-inline-conflict-ui-\(UUID().uuidString)"
        let app = launch([], libraryPath: library)
        defer { app.terminate() }
        createInlineTestNotebook(app, named: "Conflict recovery")
        placeInlineTestText(app, text: "Original conflict text")
        app.buttons["inline-text-object"].firstMatch.tap()
        var database: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(library + "/Library.sqlite", &database, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "UPDATE page_objects SET payload_json = replace(payload_json, 'Original conflict text', 'Other window text'), modified_at = modified_at + 1 WHERE kind = 'text'", nil, nil, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_changes(database), 1)
        let selected = app.descendants(matching: .any)["inline-text-selected"].firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 5)); selected.tap()
        let editor = app.textViews["inline-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.typeText(" retained")
        let retained = try XCTUnwrap(editor.value as? String)
        app.buttons["inline-text-done"].tap()
        let recovery = app.buttons["inline-text-recovery"]
        XCTAssertTrue(recovery.waitForExistence(timeout: 10))
        XCTAssertEqual(editor.value as? String, retained)
        XCTAssertGreaterThanOrEqual(recovery.frame.minY, app.scrollViews["notebook-tool-bar"].frame.maxY,
                                    "Recovery controls must stay below the main toolbar")
        recovery.tap()
        let save = app.buttons["inline-text-save-as-new"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); save.tap()
        XCTAssertTrue(recovery.waitForNonExistence(timeout: 10))
        let boxes = app.buttons.matching(identifier: "inline-text-object")
        wait(for: [expectation(for: NSPredicate(format: "count == 2"), evaluatedWith: boxes)], timeout: 10)
        XCTAssertEqual(Set(boxes.allElementsBoundByIndex.compactMap { $0.value as? String }), Set([retained, "Other window text"]))
        app.terminate()
        app.launchArguments += ["-PaperNestDebugOpenItem", "Conflict recovery"]
        app.launch()
        XCTAssertTrue(boxes.firstMatch.waitForExistence(timeout: 20))
        XCTAssertEqual(Set(boxes.allElementsBoundByIndex.compactMap { $0.value as? String }), Set([retained, "Other window text"]))
    }
}

extension AppUITests {
    func testMixedLassoDefaultsToSelectionAndMovesAllObjectKinds() async throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: "/tmp/papernest-mixed-lasso-ui-\(UUID().uuidString)")
        let store = try LibraryStore(directory: root)
        let item = try await store.createItem(kind: .notebook, name: "Mixed lasso", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let pages = try await store.pages(of: item.id)
        let page = try XCTUnwrap(pages.first)
        let ink = PageObject(pageID: page.id, zKey: "a", payload: .ink(InkStroke(tool: .pen, color: .black, width: 4,
            points: [.init(x: 100, y: 130), .init(x: 180, y: 150)])), modifiedAt: Date())
        let text = PageObject(pageID: page.id, zKey: "b", payload: .text(TextBox(frame: CGRect(x: 210, y: 120, width: 240, height: 90),
            text: "Hi", fontSize: 22)), modifiedAt: Date())
        _ = try await store.applyObjectChanges(on: page.id, saving: [ink, text], deleting: [])
        let staged = try store.assets.store(SyntheticDocuments.image(width: 100, height: 100, type: .png), kind: .png, originalFilename: nil)
        _ = try await store.placeImage(staged, on: page.id, frame: CGRect(x: 130, y: 270, width: 120, height: 100))
        let before = try await store.objects(on: page.id)
        let app = launch(["-PaperNestDebugOpenItem", "Mixed lasso"], libraryPath: root.path)
        defer { app.terminate() }
        let lasso = app.buttons["studio-tool-lasso"]
        XCTAssertTrue(lasso.waitForExistence(timeout: 20))
        XCTAssertEqual(lasso.value as? String, "Selected", "Notebooks open in selection mode")
        lasso.tap()
        XCTAssertTrue(app.buttons["studio-lasso-rectangle"].waitForExistence(timeout: 5))
        app.buttons["studio-lasso-rectangle"].tap()
        app.closeToolSettings()
        let canvas = app.descendants(matching: .any)["page-selection-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        // Enclose the visible text, leaving most of its 240 × 90 frame outside.
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 200.0 / 600, dy: 110.0 / 800))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 260.0 / 600, dy: 160.0 / 800)))
        await assertMixedSelection(canvas, count: 1)
        app.buttons["selection-clear"].tap()
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.10))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.60, dy: 0.52)))
        await assertMixedSelection(canvas, count: 3)
        let selected = XCTAttachment(screenshot: app.screenshot())
        selected.name = "mixed-lasso-selected"; selected.lifetime = .keepAlways; add(selected)
        let start = canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.30))
        start.press(forDuration: 0.15, thenDragTo: start.withOffset(CGVector(dx: 30, dy: 25)))
        // Wait for the actual durable group move, not merely its drag preview.
        var moved = before
        for _ in 0..<100 {
            moved = try await store.objects(on: page.id)
            if moved != before { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertNotEqual(moved, before)
        XCTAssertEqual(moved.count, 3)
        let delta = anchor(moved[0]) - anchor(before[0])
        XCTAssertGreaterThan(hypot(delta.x, delta.y), 10)
        for (old, new) in zip(before, moved) {
            let change = anchor(new) - anchor(old)
            XCTAssertEqual(change.x, delta.x, accuracy: 0.01)
            XCTAssertEqual(change.y, delta.y, accuracy: 0.01)
            XCTAssertEqual(old.id, new.id)
        }
        app.buttons["notebook-undo"].tap()
        for _ in 0..<100 {
            if try await store.objects(on: page.id) == before { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let undone = try await store.objects(on: page.id)
        XCTAssertEqual(undone, before)
        app.buttons["notebook-redo"].tap()
        for _ in 0..<100 {
            if try await store.objects(on: page.id) == moved { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let redone = try await store.objects(on: page.id)
        XCTAssertEqual(redone, moved)
        app.buttons["selection-clear"].tap()
        await assertMixedSelection(canvas, count: 0)
        lasso.tap(); app.buttons["studio-lasso-select-all"].tap()
        await assertMixedSelection(canvas, count: 3)
        app.terminate(); app.launch()
        XCTAssertTrue(lasso.waitForExistence(timeout: 20))
        XCTAssertEqual(lasso.value as? String, "Selected")
        let reopened = try await store.objects(on: page.id)
        XCTAssertEqual(reopened, moved)
    }

    private func assertMixedSelection(_ canvas: XCUIElement, count: Int) async {
        for _ in 0..<50 {
            if canvas.value as? String == "\(count) selected" { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(canvas.value as? String, "\(count) selected")
    }

    private func anchor(_ object: PageObject) -> CGPoint {
        switch object.payload {
        case .ink(let ink): return CGPoint(x: ink.points[0].x, y: ink.points[0].y)
        case .text(let box): return box.frame.origin
        case .image(let image): return image.frame.origin
        case .comment: return .zero
        }
    }
}

private func - (lhs: CGPoint, rhs: CGPoint) -> CGPoint { CGPoint(x: lhs.x - rhs.x, y: lhs.y - rhs.y) }

extension AppUITests {
    func testRoundEraserSizesPartialEraseUndoAndReopen() async throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: "/tmp/papernest-eraser-ui-\(UUID())")
        let store = try LibraryStore(directory: root)
        let item = try await store.createItem(kind: .notebook, name: "Round eraser", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let pages = try await store.pages(of: item.id)
        let page = try XCTUnwrap(pages.first)
        let ink = PageObject(pageID: page.id, zKey: "a", payload: .ink(InkStroke(tool: .pen, color: .black, width: 4,
            points: [.init(x: 100, y: 400), .init(x: 500, y: 400)])), modifiedAt: Date())
        let text = PageObject(pageID: page.id, zKey: "b", payload: .text(TextBox(
            frame: CGRect(x: 100, y: 500, width: 250, height: 80), text: "Keep this text")), modifiedAt: Date())
        _ = try await store.applyObjectChanges(on: page.id, saving: [ink, text], deleting: [])
        let before = try await store.objects(on: page.id)
        let app = launch(["-PaperNestDebugOpenItem", "Round eraser"], libraryPath: root.path)
        defer { app.terminate() }
        let eraser = app.buttons["studio-tool-eraser"]
        XCTAssertTrue(eraser.waitForExistence(timeout: 20)); eraser.tap(); eraser.tap()
        let slider = app.sliders["studio-eraser-size"]
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["studio-settings-done"].frame.minY, eraser.frame.maxY)
        app.buttons["studio-eraser-size-8"].tap()
        XCTAssertEqual(app.buttons["studio-eraser-size-8"].value as? String, "Selected")
        app.buttons["studio-eraser-size-64"].tap()
        XCTAssertEqual(app.buttons["studio-eraser-size-64"].value as? String, "Selected")
        app.buttons["studio-eraser-size-36"].tap()
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "round-eraser-controls"; shot.lifetime = .keepAlways; add(shot)
        let form = app.scrollViews["tool-panel-scroll"]
        let finger = app.switches["studio-finger-drawing"]
        for _ in 0..<8 where !finger.isHittable { form.swipeUp() }
        XCTAssertTrue(finger.isHittable)
        if finger.value as? String != "1" {
            finger.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        await fulfillment(of: [expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: finger)], timeout: 5)
        app.closeToolSettings()
        let canvas = app.descendants(matching: .any)["ink-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)))
        var erased = before
        for _ in 0..<100 {
            erased = try await store.objects(on: page.id)
            if erased != before { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let resultShot = XCTAttachment(screenshot: app.screenshot())
        resultShot.name = "round-eraser-result"; resultShot.lifetime = .keepAlways; add(resultShot)
        let pieces = erased.compactMap { object -> InkStroke? in
            if case .ink(let stroke) = object.payload { return stroke }; return nil
        }
        XCTAssertEqual(pieces.count, 2, "Round eraser splits the line instead of deleting it")
        XCTAssertTrue(pieces.allSatisfy { stroke in
            let xs = stroke.points.map(\.x)
            return (xs.max() ?? 600) < 300 || (xs.min() ?? 0) > 300
        })
        XCTAssertEqual(erased.first { $0.id == text.id }, text)
        app.buttons["notebook-undo"].tap()
        for _ in 0..<100 {
            if try await store.objects(on: page.id) == before { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let undone = try await store.objects(on: page.id); XCTAssertEqual(undone, before)
        app.buttons["notebook-redo"].tap()
        for _ in 0..<100 {
            if try await store.objects(on: page.id) == erased { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let redone = try await store.objects(on: page.id); XCTAssertEqual(redone, erased)
        app.terminate(); app.launch()
        XCTAssertTrue(eraser.waitForExistence(timeout: 20))
        let reopened = try await store.objects(on: page.id); XCTAssertEqual(reopened, erased)
    }
}


extension AppUITests {
    func testPDFToolsSidebarAndPhoneMenuRouting() throws {
        continueAfterFailure = false
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        for language in ["en", "fr", "es"] {
            let app = launch([], libraryPath: "/tmp/papernest-pdf-sidebar-\(UUID().uuidString)", language: language)
            homeTools(app).tap()
            app.buttons["tool-notebook"].tap()
            let name = app.textFields["notebook-name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            name.tap(); name.typeText("PDF tools")
            app.buttons["notebook-create"].tap()
            let more = toolsEntryPoint(app)
            XCTAssertTrue(more.waitForExistence(timeout: 15))
            let panel = app.scrollViews["pdf-tools-list"]
            if isPad {
                XCTAssertTrue(panel.waitForExistence(timeout: 5), "iPad PDF tools are visible by default")
            } else {
                XCTAssertFalse(panel.exists)
            }
            revealEditorTool(app, identifier: "editor-signature")
            XCTAssertEqual(panel.exists, isPad)
            if isPad {
                let shot = XCTAttachment(screenshot: app.screenshot())
                shot.name = "pdf-tools-sidebar-\(language)"; shot.lifetime = .keepAlways; add(shot)
                // Close from both the panel and its persistent toolbar button.
                app.buttons["pdf-tools-close"].tap()
                XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
                // Reopening and closing now go through the merged popover
                // rather than a toolbar button that toggled on its own.
                setToolsPanel(true, in: app); XCTAssertTrue(panel.waitForExistence(timeout: 5))
                setToolsPanel(false, in: app); XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
                revealEditorTool(app, identifier: "editor-signature")
            }
            app.buttons["editor-signature"].tap()
            XCTAssertTrue(app.buttons["signature-cancel"].waitForExistence(timeout: 5))
            app.buttons["signature-cancel"].tap()
            revealEditorTool(app, identifier: "editor-pages")
            app.buttons["editor-pages"].tap()
            XCTAssertTrue(app.buttons["pages-done"].waitForExistence(timeout: 5))
            app.buttons["pages-done"].tap()
            revealEditorTool(app, identifier: "editor-shapes")
            app.buttons["editor-shapes"].tap()
            XCTAssertTrue(app.buttons["shape-save"].waitForExistence(timeout: 5))
            app.buttons["shape-save"].tap()
            XCTAssertTrue(app.buttons["shape-save"].waitForNonExistence(timeout: 10))
            XCTAssertTrue(app.buttons["notebook-undo"].isEnabled)
            app.buttons["notebook-undo"].tap()
            if isPad {
                app.buttons["pdf-tools-close"].tap()
                XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
            }
            XCTAssertTrue(app.buttons["studio-tool-pen"].isHittable)
            app.terminate()
        }
    }
}
