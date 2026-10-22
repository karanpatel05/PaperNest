import XCTest

/// Drives the real app in the iOS Simulator. Run with `scripts/ui-test-ios.sh`,
/// which seeds the library at `libraryPath` with a page named "Crop target".
@MainActor
final class AppUITests: XCTestCase {
    static let libraryPath = "/tmp/papernest-uitest-library"

    private func launch(_ extra: [String], libraryPath: String = AppUITests.libraryPath, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", libraryPath, "-AppleLanguages", "(\(language))", "-AppleLocale", "en_US", "-libraryLayout", "grid"] + extra
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
        let tools = app.buttons["library-tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 15))
        tools.tap()

        let merge = app.buttons["tool-merge"]
        XCTAssertTrue(merge.waitForExistence(timeout: 5))
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

    func testAFileItemShowsItsTypeAndSizeAndOffersACopy() throws {
        continueAfterFailure = false
        let app = launch([], libraryPath: "/tmp/papernest-file-items-library")
        showAllDocuments(app)
        // A text file cannot become pages, so it is kept as a file and the
        // tile shows its size where a document shows its page count.
        let cell = app.descendants(matching: .any)["Budget notes, 18 bytes"].firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 15), "the file should be in the library")
        cell.tap()

        let header = app.descendants(matching: .any)["file-details-header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5), "tapping a file should show what it is")
        // A LabeledContent row is one element labelled "<label>, <value>".
        let originalName = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "Budget notes.txt")).firstMatch
        XCTAssertTrue(originalName.waitForExistence(timeout: 5), "the details should name the original file")
        XCTAssertTrue(app.buttons["file-save-copy"].waitForExistence(timeout: 10),
                      "a copy of the file should be offered")
        app.buttons["file-details-done"].tap()
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
    }
}
