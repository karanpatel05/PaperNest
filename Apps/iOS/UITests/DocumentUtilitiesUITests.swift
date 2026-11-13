import XCTest
import PaperNestCore
import PaperNestStore

/// Document Utilities: one panel for pages and tools, one control to show it.
@MainActor final class DocumentUtilitiesUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-toolbar-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    private func open(pages: Int = 3) async throws -> (XCUIApplication, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-utilities-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Utilities", pages: (0..<pages).map { _ in
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        }, assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Utilities", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-panels"].waitForExistence(timeout: 30))
        return (app, store, item.id)
    }

    /// Brings a control in the panel into reach by scrolling the panel.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let list = app.scrollViews["pdf-tools-list"]
        for _ in 0..<10 where !(element.exists && element.isHittable) { list.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) cannot be reached in the panel", file: file, line: line)
    }

    func testOneControlShowsAndHidesPagesAndToolsTogether() async throws {
        let (app, store, item) = try await open()
        defer { app.terminate() }
        let toggle = app.buttons["editor-panels"]
        let panel = app.scrollViews["pdf-tools-list"]
        let page = app.images["document-page-image"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))

        // Exactly one control, and none of the old ones.
        XCTAssertEqual(app.buttons.matching(identifier: "editor-panels").count, 1)
        for old in ["editor-toggle-thumbnails", "editor-toggle-pdf-tools"] {
            XCTAssertEqual(app.descendants(matching: .any).matching(identifier: old).count, 0, "\(old) is still on screen")
        }

        if panel.exists {
            // Wide iPad: it opens beside the page. Closing it gives the page
            // the room back.
            XCTAssertEqual(toggle.value as? String, "Selected")
            let pageWithPanel = page.frame
            toggle.tap()
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
            XCTAssertEqual(toggle.value as? String, "Not selected")
            for _ in 0..<20 where page.frame.midX == pageWithPanel.midX { usleep(100_000) }
            XCTAssertGreaterThan(page.frame.midX, pageWithPanel.midX, "the canvas takes the space the panel gave up")
            toggle.tap()
        } else {
            XCTAssertEqual(toggle.value as? String, "Not selected")
            toggle.tap()
        }
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "Selected")
        snap(app, "30-utilities")

        // Pages: the real count, the real pages, and a tap goes to one.
        let pagesHeader = app.buttons["utilities-section-pages"]
        XCTAssertTrue(pagesHeader.label.contains("3"), "the Pages header reads \(pagesHeader.label)")
        for number in 1...3 { XCTAssertTrue(app.buttons["page-thumbnail-\(number)"].exists, "page \(number) has no thumbnail") }
        XCTAssertFalse(app.buttons["page-thumbnail-4"].exists)
        XCTAssertEqual(app.buttons["page-thumbnail-1"].value as? String, "Selected")
        app.buttons["page-thumbnail-3"].tap()
        let third = app.buttons["page-thumbnail-3"]
        for _ in 0..<30 where (third.value as? String) != "Selected" { usleep(100_000) }
        XCTAssertEqual(third.value as? String, "Selected")
        XCTAssertNotEqual(app.buttons["page-thumbnail-1"].value as? String, "Selected")

        // Tools share the panel.
        for tool in ["editor-signature", "editor-shapes", "editor-markup", "editor-crop", "editor-stamps",
                     "editor-comments", "editor-annotate", "editor-pages", "editor-delete-page"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: tool).firstMatch.exists, "\(tool) is missing")
        }

        // Each section folds on its own, and the other stays.
        pagesHeader.tap()
        XCTAssertTrue(app.buttons["page-thumbnail-1"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(pagesHeader.value as? String, "Collapsed")
        XCTAssertTrue(app.buttons["editor-signature"].exists, "folding Pages must not fold the tools")
        snap(app, "31-utilities-pages-folded")
        pagesHeader.tap()
        XCTAssertTrue(app.buttons["page-thumbnail-1"].waitForExistence(timeout: 5))
        let toolsHeader = app.buttons["utilities-section-tools"]
        reveal(toolsHeader, in: app)
        toolsHeader.tap()
        XCTAssertTrue(app.buttons["editor-signature"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["page-thumbnail-1"].exists, "folding the tools must not fold Pages")
        toolsHeader.tap()
        XCTAssertTrue(app.buttons["editor-signature"].waitForExistence(timeout: 5))

        // The panel's own close button is the same switch.
        app.buttons["pdf-tools-close"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "Not selected")
        XCTAssertEqual(app.images["document-page-image"].label, "Page 3 of 3", "closing the panel keeps the page")

        // Deleting a page from the panel deletes a real page.
        toggle.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let delete = app.buttons["editor-delete-page"]
        reveal(delete, in: app)
        delete.tap()
        for _ in 0..<40 where try await store.pages(of: item).count != 2 { try await Task.sleep(for: .milliseconds(250)) }
        let remaining = try await store.pages(of: item).count
        XCTAssertEqual(remaining, 2, "the page was removed from the library")
        XCTAssertTrue(pagesHeader.label.contains("2"), "the Pages header reads \(pagesHeader.label)")
    }

    /// The lower bar is about the view: zoom, drawing mode, display settings.
    func testTheLowerBarZoomsAndHasNoSecondLasso() async throws {
        let (app, _, _) = try await open(pages: 1)
        defer { app.terminate() }
        let percent = app.staticTexts["editor-zoom-percent"]
        XCTAssertTrue(percent.waitForExistence(timeout: 10))
        XCTAssertEqual(percent.value as? String, "100%")
        // The Lasso tool is armed when a notebook opens. It appears once, in
        // the toolbar, and not again in the lower bar.
        XCTAssertEqual(app.buttons["studio-tool-lasso"].value as? String, "Selected")
        XCTAssertEqual(app.buttons.matching(identifier: "studio-tool-lasso").count, 1)
        let drawing = app.buttons["studio-drawing-toggle"]
        XCTAssertEqual(drawing.label, "Drawing Mode")
        XCTAssertEqual(drawing.value as? String, "Selected")

        app.buttons["editor-zoom-in"].tap()
        for _ in 0..<20 where (percent.value as? String) == "100%" { usleep(100_000) }
        XCTAssertEqual(percent.value as? String, "150%")
        app.buttons["editor-zoom-out"].tap()
        for _ in 0..<20 where (percent.value as? String) != "100%" { usleep(100_000) }
        XCTAssertEqual(percent.value as? String, "100%")

        app.buttons["studio-tool-settings"].tap()
        let twoHundred = app.buttons["display-zoom-200"]
        XCTAssertTrue(twoHundred.waitForExistence(timeout: 5))
        snap(app, "32-display-settings")
        twoHundred.tap()
        XCTAssertEqual(twoHundred.value as? String, "Selected")
        app.buttons["display-fit-page"].tap()
        XCTAssertEqual(app.buttons["display-zoom-100"].value as? String, "Selected")
        app.closeToolSettings()
        XCTAssertEqual(percent.value as? String, "100%")
        snap(app, "33-lower-bar")
    }
}
