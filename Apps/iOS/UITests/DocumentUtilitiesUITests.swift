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

    /// In view: its centre lies inside the visible panel, clear of the pinned
    /// Export / Save below it. `isHittable` alone is not enough — on the
    /// iPhone Duo it reported the Annotate header unreachable while a tap on
    /// it, made straight afterwards, landed (2026-11-14).
    static func inView(_ element: XCUIElement, _ list: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.isHittable { return true }
        let visible = list.frame.insetBy(dx: 0, dy: 6)
        return !visible.isEmpty && visible.contains(CGPoint(x: element.frame.midX, y: element.frame.midY))
    }

    /// Brings a control in the panel into reach by scrolling the panel.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let list = app.scrollViews["pdf-tools-list"]
        // Short drags, down the list and then back up: a full swipe in a
        // phone's short drawer can carry a section header straight past.
        // From the list's left margin, outside every card: a drag that starts
        // on a tile can open its menu (Rotate, Filter, Replace Page) instead
        // of scrolling, which on the iPhone Duo's drawer is where the middle
        // of the list lands.
        func nudge(_ dy: CGFloat) {
            let margin = list.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 5, dy: 0))
            // Slowly, and held at the end, so the list stops where the finger
            // does. A flick coasts on: in the iPhone Duo's 213-point drawer a
            // 140-point drag moved the list about 330 and carried a section
            // header from below the window to above it in one step.
            margin.press(forDuration: 0.05, thenDragTo: margin.withOffset(CGVector(dx: 0, dy: dy)),
                         withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        for _ in 0..<24 where !Self.inView(element, list) { nudge(-100) }
        for _ in 0..<34 where !Self.inView(element, list) { nudge(100) }
        XCTAssertTrue(Self.inView(element, list), "\(element) cannot be reached in the panel", file: file, line: line)
    }

    /// Closing the panel, and opening it again, keeps the page being read.
    /// Every page refits to the new width, so the same scroll offset shows
    /// another page; on 2026-11-20 closing the panel on page 3 of 3 left the
    /// reader on page 2, on both iPads.
    func testClosingAndOpeningThePanelKeepsThePage() async throws {
        try XCTSkipUnless(isPad, "the panel sits beside the page only on an iPad")
        let (app, _, _) = try await open()
        defer { app.terminate() }
        let toggle = app.buttons["editor-panels"], panel = app.scrollViews["pdf-tools-list"]
        let page = app.images["document-page-image"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        if !panel.exists { toggle.tap() }
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        /// The page shown stays `expected` for a while: a refit that moves
        /// the reader does so within a second.
        func expectStays(_ expected: String, _ message: String, line: UInt = #line) {
            for _ in 0..<20 {
                XCTAssertEqual(page.label, expected, message, line: line)
                if page.label != expected { return }
                usleep(100_000)
            }
        }
        for number in [3, 2] {
            let thumbnail = app.buttons["page-thumbnail-\(number)"]
            if !panel.exists { toggle.tap(); XCTAssertTrue(panel.waitForExistence(timeout: 5)) }
            XCTAssertTrue(thumbnail.waitForExistence(timeout: 5))
            thumbnail.tap()
            for _ in 0..<30 where (thumbnail.value as? String) != "Selected" { usleep(100_000) }
            let expected = "Page \(number) of 3"
            expectStays(expected, "choosing page \(number)")
            toggle.tap()
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
            expectStays(expected, "closing the panel on page \(number)")
            toggle.tap()
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            expectStays(expected, "opening the panel again on page \(number)")
        }
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
        // Option 6 sections, each folding on its own.
        for section in ["utilities-section-edit", "utilities-section-annotate", "utilities-section-insert",
                        "utilities-section-process"] {
            reveal(app.buttons[section], in: app)
        }
        let annotateHeader = app.buttons["utilities-section-annotate"]
        reveal(annotateHeader, in: app)
        annotateHeader.tap()
        XCTAssertTrue(app.buttons["editor-signature"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["editor-crop"].exists, "folding Annotate must not fold Edit PDF")
        annotateHeader.tap()
        XCTAssertTrue(app.buttons["editor-signature"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["utilities-export"].exists, "Export / Save is pinned below the sections")

        // The panel's own close button is the same switch.
        app.buttons["pdf-tools-close"].tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "Not selected")
        XCTAssertEqual(app.images["document-page-image"].label, "Page 3 of 3", "closing the panel keeps the page")

        // Deleting a page from the panel deletes a real page.
        toggle.tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let pagesHeaderAgain = app.buttons["utilities-section-pages"]
        for _ in 0..<6 where !pagesHeaderAgain.isHittable { app.scrollViews["pdf-tools-list"].swipeDown() }
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
        let percent = app.buttons["editor-zoom-percent"]
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

        percent.tap()
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

    /// Previous, "n / N", next — and it moves the real selection.
    func testThePageStepperMovesBetweenPages() async throws {
        let (app, _, _) = try await open(pages: 3)
        defer { app.terminate() }
        let counter = app.staticTexts["editor-page-counter"]
        XCTAssertTrue(counter.waitForExistence(timeout: 10))
        XCTAssertEqual(counter.label, "Page 1 of 3")
        XCTAssertFalse(app.buttons["editor-page-previous"].isEnabled, "nothing before the first page")
        app.buttons["editor-page-next"].tap()
        for _ in 0..<30 where counter.label != "Page 2 of 3" { usleep(100_000) }
        XCTAssertEqual(counter.label, "Page 2 of 3")
        XCTAssertEqual(app.images["document-page-image"].label, "Page 2 of 3", "the page shown follows")
        app.buttons["editor-page-next"].tap()
        for _ in 0..<30 where counter.label != "Page 3 of 3" { usleep(100_000) }
        XCTAssertFalse(app.buttons["editor-page-next"].isEnabled, "nothing after the last page")
        app.buttons["editor-page-previous"].tap()
        for _ in 0..<30 where counter.label != "Page 2 of 3" { usleep(100_000) }
        XCTAssertEqual(counter.label, "Page 2 of 3")
    }

    /// Process: Convert opens the real export sheet with Word chosen, Compress
    /// makes and measures a copy, Split makes one document per page.
    func testProcessToolsDoRealWork() async throws {
        let (app, store, _) = try await open(pages: 3)
        defer { app.terminate() }
        let panel = app.scrollViews["pdf-tools-list"]
        if !panel.exists { app.buttons["editor-panels"].tap() }
        XCTAssertTrue(panel.waitForExistence(timeout: 5))

        let convert = app.buttons["utilities-convert"]
        reveal(convert, in: app)
        convert.tap()
        let word = app.buttons["export-format-docx"]
        XCTAssertTrue(word.waitForExistence(timeout: 10), "the export sheet did not open")
        XCTAssertTrue(word.isSelected, "Convert opens export with Word chosen")
        snap(app, "34-convert")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(word.waitForNonExistence(timeout: 5))

        if !panel.exists { app.buttons["editor-panels"].tap() }
        let compress = app.buttons["utilities-compress"]
        reveal(compress, in: app)
        compress.tap()
        let start = app.buttons["compress-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10), "the compress sheet did not open")
        start.tap()
        let result = app.descendants(matching: .any)["compress-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 30), "compressing produced no result")
        XCTAssertTrue(app.buttons["compress-save"].exists && app.buttons["compress-share"].exists)
        snap(app, "35-compress")
        app.buttons["compress-close"].tap()
        XCTAssertTrue(start.waitForNonExistence(timeout: 5))

        let before = try await store.items(in: .all).count
        if !panel.exists { app.buttons["editor-panels"].tap() }
        let split = app.buttons["utilities-split"]
        reveal(split, in: app)
        split.tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "no confirmation after splitting")
        XCTAssertTrue(alert.staticTexts.allElementsBoundByIndex.contains { $0.label.contains("3 new documents") },
                      "the message says how many were made")
        alert.buttons.firstMatch.tap()
        let after = try await store.items(in: .all).count
        XCTAssertEqual(after, before + 3, "one new document per page; this one is kept")
    }

    /// On a phone the panel is a drawer: the handle makes it taller, and a
    /// swipe down puts it away.
    func testThePhoneDrawerGrowsAndSwipesAway() async throws {
        guard !isPad else { throw XCTSkip("iPad shows a column, not a drawer") }
        let (app, _, _) = try await open(pages: 2)
        defer { app.terminate() }
        let panel = app.scrollViews["pdf-tools-list"]
        app.buttons["editor-panels"].tap()
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let handle = app.descendants(matching: .any)["utilities-drawer-handle"].firstMatch
        XCTAssertTrue(handle.exists)
        let shortTop = handle.frame.minY
        handle.tap()
        for _ in 0..<20 where handle.frame.minY >= shortTop - 50 { usleep(100_000) }
        XCTAssertLessThan(handle.frame.minY, shortTop - 50, "tapping the handle makes the drawer taller")
        snap(app, "36-drawer-tall")
        handle.tap()
        for _ in 0..<20 where abs(handle.frame.minY - shortTop) > 4 { usleep(100_000) }
        let from = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 260)))
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "a swipe down closes the drawer")
        XCTAssertEqual(app.buttons["editor-panels"].value as? String, "Not selected")
    }

    /// A tool in the panel that opens a screen of its own actually opens it —
    /// on a phone the drawer has to step aside for the sheet.
    func testCropOpensFromDocumentTools() async throws {
        let (app, _, _) = try await open(pages: 2)
        defer { app.terminate() }
        let panel = app.scrollViews["pdf-tools-list"]
        if !panel.exists { app.buttons["editor-panels"].tap() }
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let crop = app.buttons["editor-crop"]
        reveal(crop, in: app)
        XCTAssertTrue(crop.isEnabled)
        crop.tap()
        let area = app.descendants(matching: .any)["crop-area"].firstMatch
        let opened = area.waitForExistence(timeout: 10)
        snap(app, "37-crop-from-tools")
        XCTAssertTrue(opened, "Crop in Document Tools did not open the crop screen")
    }
}
