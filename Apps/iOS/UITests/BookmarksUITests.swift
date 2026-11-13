import XCTest
import PaperNestCore
import PaperNestStore

/// The reader's bookmarks: mark the page being read, see the list, go to
/// one, rename one, remove one.
@MainActor final class BookmarksUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-bookmark-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// A three-page digital PDF.
    private func openReport(language: String = "en") async throws -> (XCUIApplication, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-bookmarks-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["Quarterly budget review", "Nothing on this one", "Final budget"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Report.pdf")
        let item = try await store.createItem(kind: .document, name: "Report", pages: (0..<3).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Report", "-AppleLanguages", "(\(language))"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        // The page as well as the toolbar, before the title menu is opened:
        // a tap on the title while the document was still loading once left
        // no menu up (found by the print test).
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 15))
        return (app, store, item.id)
    }

    private func waitForPage(_ app: XCUIApplication, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let page = app.images["document-page-image"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(page.exists && page.label == label) { usleep(100_000) }
        XCTAssertEqual(page.exists ? page.label : "<absent>", label, file: file, line: line)
    }

    /// Chooses an entry from the document's title menu.
    private func chooseFromTitleMenu(_ app: XCUIApplication, _ name: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Report")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "no title to open the menu from", file: file, line: line)
        title.tap()
        let item = app.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(name) is not in the title menu", file: file, line: line)
        item.tap()
    }

    private func goToPage(_ app: XCUIApplication, _ number: Int) {
        chooseFromTitleMenu(app, "Go to Page…")
        let alert = app.alerts["Go to Page…"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("\(number)")
        alert.buttons["Go"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        waitForPage(app, "Page \(number) of 3")
    }

    /// Waits for the library on disk to hold these bookmark names, in order.
    private func waitForSaved(_ store: LibraryStore, _ item: ItemID, _ expected: [String],
                              file: StaticString = #filePath, line: UInt = #line) async throws -> [Bookmark] {
        var saved: [Bookmark] = []
        for _ in 0..<40 {
            saved = try await store.bookmarks(of: item)
            if saved.map(\.name) == expected { return saved }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTFail("the library holds \(saved.map(\.name)), not \(expected)", file: file, line: line)
        return saved
    }

    func testMarkListJumpRenameAndRemove() async throws {
        let (app, store, item) = try await openReport()
        defer { app.terminate() }
        let pages = try await store.pages(of: item)
        waitForPage(app, "Page 1 of 3")
        let ribbon = app.descendants(matching: .any).matching(identifier: "page-bookmark-ribbon").firstMatch
        XCTAssertFalse(ribbon.exists)

        // With nothing marked, the list says so and says what to do.
        chooseFromTitleMenu(app, "Bookmarks…")
        let empty = app.descendants(matching: .any).matching(identifier: "bookmarks-empty").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "an empty list does not say it is empty")
        snap(app, "empty")
        app.buttons["bookmarks-done"].tap()
        XCTAssertTrue(empty.waitForNonExistence(timeout: 5))

        // Mark page 1 from the title menu: the page shows its ribbon, and the library has it.
        chooseFromTitleMenu(app, "Add Bookmark")
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5), "the marked page shows no ribbon")
        var saved = try await waitForSaved(store, item, [""])
        XCTAssertEqual(saved.map(\.pageID), [pages[0].id])

        // Mark page 3 too. Page 2, in between, is not marked and shows no ribbon.
        goToPage(app, 3)
        XCTAssertFalse(ribbon.exists, "an unmarked page shows a ribbon")
        chooseFromTitleMenu(app, "Add Bookmark")
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5))
        saved = try await waitForSaved(store, item, ["", ""])
        XCTAssertEqual(saved.map(\.pageID), [pages[0].id, pages[2].id])
        goToPage(app, 2)
        XCTAssertFalse(ribbon.exists)

        // The list has both, in page order, each called by its page.
        chooseFromTitleMenu(app, "Bookmarks…")
        let first = app.buttons["bookmark-row-0"]
        let second = app.buttons["bookmark-row-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "Page 1")
        XCTAssertEqual(second.label, "Page 3")
        XCTAssertFalse(app.buttons["bookmark-row-2"].exists)
        snap(app, "list")

        // Rename the second.
        app.buttons["bookmark-row-menu-1"].tap()
        let rename = app.buttons["Rename…"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let alert = app.alerts["Rename Bookmark"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("Totals")
        alert.buttons["OK"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        _ = try await waitForSaved(store, item, ["", "Totals"])
        XCTAssertEqual(second.label, "Totals")
        XCTAssertEqual(second.value as? String, "Page 3", "a named bookmark no longer says which page it is on")
        snap(app, "renamed")

        // Go to it: the list closes and the reader is on page 3.
        second.tap()
        XCTAssertTrue(second.waitForNonExistence(timeout: 5), "the list stayed up after choosing a bookmark")
        waitForPage(app, "Page 3 of 3")
        XCTAssertTrue(ribbon.waitForExistence(timeout: 5))
        snap(app, "ribbon")

        // The title menu now offers to take the mark off this page; taking
        // it off removes the ribbon and the row.
        chooseFromTitleMenu(app, "Remove Bookmark")
        XCTAssertTrue(ribbon.waitForNonExistence(timeout: 5))
        saved = try await waitForSaved(store, item, [""])
        XCTAssertEqual(saved.map(\.pageID), [pages[0].id])

        // Remove the last one from the list itself.
        chooseFromTitleMenu(app, "Bookmarks…")
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(second.exists)
        app.buttons["bookmark-row-menu-0"].tap()
        let remove = app.buttons["Remove Bookmark"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "removing the last bookmark did not empty the list")
        _ = try await waitForSaved(store, item, [])

        // And the page being read can be marked from inside the list.
        let toggle = app.buttons["bookmarks-toggle-current"]
        XCTAssertEqual(toggle.label, "Add Bookmark")
        toggle.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertEqual(first.label, "Page 3")
        XCTAssertEqual(toggle.label, "Remove Bookmark")
        saved = try await waitForSaved(store, item, [""])
        XCTAssertEqual(saved.map(\.pageID), [pages[2].id])
        app.buttons["bookmarks-done"].tap()

        // Marking pages edited nothing.
        let after = try await store.pages(of: item)
        XCTAssertEqual(after.map(\.revision), pages.map(\.revision))
    }

    /// A bookmark is kept in the library, not in the window: it is there
    /// after the app has been closed and opened again.
    func testABookmarkIsStillThereAfterRelaunch() async throws {
        let (app, store, item) = try await openReport()
        waitForPage(app, "Page 1 of 3")
        chooseFromTitleMenu(app, "Add Bookmark")
        _ = try await waitForSaved(store, item, [""])
        app.terminate()

        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        waitForPage(app, "Page 1 of 3")
        let ribbon = app.descendants(matching: .any).matching(identifier: "page-bookmark-ribbon").firstMatch
        XCTAssertTrue(ribbon.waitForExistence(timeout: 10), "the bookmark did not survive a relaunch")
        chooseFromTitleMenu(app, "Bookmarks…")
        XCTAssertTrue(app.buttons["bookmark-row-0"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["bookmark-row-0"].label, "Page 1")
        app.terminate()
    }

    func testBookmarksAreNamedAndFitInFrenchAndSpanish() async throws {
        for (language, add, list, title, emptyTitle) in [
            ("fr", "Ajouter un signet", "Signets…", "Signets", "Aucun signet"),
            ("es", "Añadir marcador", "Marcadores…", "Marcadores", "Sin marcadores"),
        ] {
            let (app, _, _) = try await openReport(language: language)
            let menuTitle = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Report")).firstMatch
            XCTAssertTrue(menuTitle.waitForExistence(timeout: 5))
            menuTitle.tap()
            XCTAssertTrue(app.buttons[add].waitForExistence(timeout: 5), "\(add) is not in the \(language) title menu")
            let listItem = app.buttons[list]
            XCTAssertTrue(listItem.exists, "\(list) is not in the \(language) title menu")
            snap(app, "menu-\(language)")
            listItem.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            let empty = app.descendants(matching: .any).matching(identifier: "bookmarks-empty").firstMatch
            XCTAssertTrue(empty.waitForExistence(timeout: 5))
            XCTAssertTrue(empty.label.contains(emptyTitle), "the empty list says \(empty.label)")
            let window = app.windows.firstMatch.frame
            XCTAssertTrue(window.contains(empty.frame), "the \(language) empty message runs off the screen")
            // Mark the page from the list, and see the row arrive.
            app.buttons["bookmarks-toggle-current"].tap()
            XCTAssertTrue(app.buttons["bookmark-row-0"].waitForExistence(timeout: 5))
            snap(app, "list-\(language)")
            app.terminate()
        }
    }
}
