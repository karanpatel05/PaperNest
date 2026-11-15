import XCTest
import PaperNestCore
import PaperNestStore

/// Two-page view in the running app: a document a spread at a time on an
/// iPad, the page beside the one being read a tap away, the cover on its own
/// when asked; and on a phone, not offered at all.
@MainActor final class TwoPageViewUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-two-page-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Four portrait pages, each with its number written large.
    private func open(language: String = "en") async throws -> (XCUIApplication, [PageID]) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-two-page-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["Page one", "Page two", "Page three", "Page four"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Book.pdf")
        let item = try await store.createItem(kind: .document, name: "Book", pages: (0..<4).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset])
        let ids = try await store.pages(of: item.id).map(\.id)
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Book", "-AppleLanguages", "(\(language))"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 15))
        return (app, ids)
    }

    private func openDisplaySettings(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons["studio-tool-settings"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), file: file, line: line)
        button.tap()
        XCTAssertTrue(app.buttons["studio-settings-done"].waitForExistence(timeout: 5),
                      "Display settings did not open", file: file, line: line)
    }

    private func set(_ id: String, _ on: Bool, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = app.switches[id]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "\(id) is not in Display settings", file: file, line: line)
        if (toggle.value as? String) != (on ? "1" : "0") { toggle.flipSwitch() }
        XCTAssertEqual(toggle.value as? String, on ? "1" : "0", "\(id) did not switch", file: file, line: line)
    }

    private func goTo(_ number: Int, in app: XCUIApplication) {
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Book")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "no title to open the menu from")
        title.tap()
        let item = app.buttons["Go to Page…"]
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        let alert = app.alerts["Go to Page…"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText(String(number))
        alert.buttons["Go"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { usleep(100_000) }
        XCTAssertTrue(condition(), what, file: file, line: line)
    }

    func testAnIPadShowsTwoPagesAndTheOneBesideItIsATapAway() async throws {
        let (app, ids) = try await open()
        defer { app.terminate() }
        guard isPad else {
            // A phone has no room for two pages: the switch is not there.
            openDisplaySettings(app)
            XCTAssertFalse(app.switches["display-two-pages"].exists, "Two Pages is offered on a phone")
            app.closeToolSettings()
            return
        }
        let spread = app.descendants(matching: .any)["document-spread"].firstMatch
        XCTAssertFalse(spread.exists, "two pages before it was asked for")

        openDisplaySettings(app)
        set("display-two-pages", true, in: app)
        app.closeToolSettings()
        waitFor("pages 1 and 2 are not side by side") { spread.exists && (spread.value as? String) == "1-2" }
        let page = app.images["document-page-image"]
        XCTAssertEqual(page.label, "Page 1 of 4")
        // The page beside it is on screen, next to it and the same height.
        let beside = app.descendants(matching: .any)["notebook-preview-\(ids[1])"].firstMatch
        XCTAssertTrue(beside.waitForExistence(timeout: 5), "page 2 is not beside page 1")
        XCTAssertGreaterThan(beside.frame.minX, page.frame.maxX, "page 2 is not to the right of page 1")
        XCTAssertEqual(beside.frame.height, page.frame.height, accuracy: 2)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(beside.frame), "page 2 is not wholly on screen")
        snap(app, "spread-1-2")

        // A tap on it makes it the page being read; the spread stays.
        beside.tap()
        waitFor("tapping page 2 did not make it the page being read") { page.label == "Page 2 of 4" }
        XCTAssertEqual(spread.value as? String, "1-2")

        // Next steps a spread, from the right page of one too.
        app.buttons["editor-page-next"].tap()
        waitFor("next did not bring pages 3 and 4") { (spread.value as? String) == "3-4" && page.label == "Page 3 of 4" }
        XCTAssertFalse(app.buttons["editor-page-next"].isEnabled, "next is offered past the last spread")
        app.buttons["editor-page-previous"].tap()
        waitFor("previous did not bring pages 1 and 2") { (spread.value as? String) == "1-2" && page.label == "Page 1 of 4" }

        // Going to a page brings its spread.
        goTo(3, in: app)
        waitFor("page 3 did not bring pages 3 and 4") { (spread.value as? String) == "3-4" && page.label == "Page 3 of 4" }

        // The cover on its own: page 3 now faces page 2.
        openDisplaySettings(app)
        set("display-two-pages-cover", true, in: app)
        app.closeToolSettings()
        waitFor("with the cover alone page 3 does not face page 2") { (spread.value as? String) == "2-3" }
        goTo(1, in: app)
        waitFor("the cover is not on its own") { (spread.value as? String) == "1" }
        snap(app, "cover-alone")

        // Off again: one page.
        openDisplaySettings(app)
        set("display-two-pages", false, in: app)
        XCTAssertFalse(app.switches["display-two-pages-cover"].exists, "the cover option outlived two-page view")
        app.closeToolSettings()
        waitFor("two pages are still shown") { !spread.exists }
        XCTAssertEqual(page.label, "Page 1 of 4")
    }

    /// The switches are named, and fit, in French and Spanish.
    func testTwoPagesIsNamedInFrenchAndSpanish() async throws {
        for (language, title) in [("fr", "Deux pages"), ("es", "Dos páginas")] {
            let (app, _) = try await open(language: language)
            openDisplaySettings(app)
            let toggle = app.switches["display-two-pages"]
            if isPad {
                XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Two Pages switch in \(language)")
                // The row's label is its title and then its description.
                XCTAssertTrue(toggle.label.hasPrefix(title), "the \(language) switch is called \"\(toggle.label)\"")
                XCTAssertTrue(app.windows.firstMatch.frame.contains(toggle.frame), "the \(language) switch is off screen")
                XCTAssertGreaterThan(toggle.frame.width, 240, "the \(language) row is squeezed to \(toggle.frame.width)")
                snap(app, "settings-\(language)")
            } else {
                XCTAssertFalse(toggle.exists, "Two Pages is offered on a phone in \(language)")
            }
            app.closeToolSettings()
            app.terminate()
        }
    }
}
