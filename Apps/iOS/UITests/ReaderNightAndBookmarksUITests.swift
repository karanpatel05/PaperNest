import XCTest
import PaperNestCore
import PaperNestStore

/// The cases night mode and bookmarks were not tried in when they were built
/// (see their TEST_MATRIX entries of 2026-11-13): typing at night, a filled
/// form at night, ⌘D from a hardware keyboard, and a notebook's continuous
/// pages, at night.
@MainActor final class ReaderNightAndBookmarksUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-reader-gap-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    // MARK: - Opening a library

    private func launch(_ directory: URL, item: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", item, "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 15))
        return app
    }

    /// A one-page PDF of `data`, named `name`.
    private func openPDF(_ data: Data, name: String) async throws -> (XCUIApplication, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-reader-gaps-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "\(name).pdf")
        let item = try await store.createItem(kind: .document, name: name, pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        return (launch(directory, item: name), store, item.id)
    }

    // MARK: - Reading the screen

    /// Pixels of a region of the page on screen. `rect` is in the page's own
    /// points, from its top-left corner, on a page `pageSize` points big.
    private struct Region {
        var pixels: [(r: Int, g: Int, b: Int)] = []

        var brightest: Int { pixels.map { max($0.r, $0.g, $0.b) }.max() ?? -1 }
        func count(_ test: ((r: Int, g: Int, b: Int)) -> Bool) -> Int { pixels.filter(test).count }
        var average: (r: Int, g: Int, b: Int) {
            guard !pixels.isEmpty else { return (-1, -1, -1) }
            let n = pixels.count
            return (pixels.map(\.r).reduce(0, +) / n, pixels.map(\.g).reduce(0, +) / n, pixels.map(\.b).reduce(0, +) / n)
        }
    }

    private func region(_ app: XCUIApplication, of element: XCUIElement, rect: CGRect,
                        pageSize: CGSize = CGSize(width: 612, height: 792)) -> Region {
        let frame = element.frame
        let onScreen = CGRect(x: frame.minX + frame.width * rect.minX / pageSize.width,
                              y: frame.minY + frame.height * rect.minY / pageSize.height,
                              width: frame.width * rect.width / pageSize.width,
                              height: frame.height * rect.height / pageSize.height)
        return pixels(app, in: onScreen)
    }

    /// The pixels inside `rect`, given in screen points.
    private func pixels(_ app: XCUIApplication, in rect: CGRect) -> Region {
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return Region() }
        let scale = CGFloat(image.width) / app.frame.width
        let box = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale,
                         height: rect.height * scale).integral
        guard box.width >= 1, box.height >= 1, let patch = image.cropping(to: box) else { return Region() }
        let width = patch.width, height = patch.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(patch, in: CGRect(x: 0, y: 0, width: width, height: height))
        var result = Region()
        result.pixels.reserveCapacity(width * height)
        for index in 0..<(width * height) {
            result.pixels.append((Int(buffer[index * 4]), Int(buffer[index * 4 + 1]), Int(buffer[index * 4 + 2])))
        }
        return result
    }

    /// Waits until a patch of plain paper is dark (night) or light (day).
    private func waitForPaper(_ app: XCUIApplication, dark: Bool, at rect: CGRect,
                              pageSize: CGSize = CGSize(width: 612, height: 792),
                              file: StaticString = #filePath, line: UInt = #line) {
        let page = app.images["document-page-image"]
        let deadline = Date().addingTimeInterval(10)
        var seen = region(app, of: page, rect: rect, pageSize: pageSize).brightest
        while Date() < deadline, dark ? seen > 40 : seen < 215 {
            usleep(200_000)
            seen = region(app, of: page, rect: rect, pageSize: pageSize).brightest
        }
        XCTAssertTrue(dark ? seen <= 40 : seen >= 215,
                      "the paper's brightest pixel is \(seen), which is not \(dark ? "dark" : "light")",
                      file: file, line: line)
    }

    /// A patch of paper with nothing printed on it in any fixture here, high
    /// enough on the page to be clear of a phone's floating bottom bar — a
    /// patch lower down sampled that light bar instead of the paper.
    private static let plainPaper = CGRect(x: 380, y: 430, width: 40, height: 40)

    // MARK: - Switching night mode

    private func setNightMode(_ app: XCUIApplication, _ on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        app.buttons["studio-tool-settings"].tap()
        let night = app.switches["display-night-mode"]
        XCTAssertTrue(night.waitForExistence(timeout: 5), "Display settings has no Night Mode switch",
                      file: file, line: line)
        let scroll = app.scrollViews["display-settings-scroll"]
        let window = app.windows.firstMatch.frame
        for _ in 0..<4 where scroll.exists && !(night.isHittable && window.contains(night.frame)) { scroll.swipeUp() }
        if (night.value as? String) != (on ? "1" : "0") { night.flipSwitch() }
        XCTAssertEqual(night.value as? String, on ? "1" : "0", file: file, line: line)
        app.closeToolSettings(file: file, line: line)
    }

    private func chooseFromTitleMenu(_ app: XCUIApplication, title: String, _ name: String,
                                     file: StaticString = #filePath, line: UInt = #line) {
        let button = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no title to open the menu from", file: file, line: line)
        button.tap()
        let item = app.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(name) is not in the title menu", file: file, line: line)
        item.tap()
    }

    private func waitForPage(_ app: XCUIApplication, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let page = app.images["document-page-image"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(page.exists && page.label == label) { usleep(100_000) }
        XCTAssertEqual(page.exists ? page.label : "<absent>", label, file: file, line: line)
    }

    // MARK: - Night mode

    /// Typing at night: every letter lands, the words show light on the dark
    /// page, and what is saved is the colour chosen — not its night shade.
    func testTextTypedAtNightIsSavedInItsOwnColour() async throws {
        let (app, store, item) = try await openPDF(SyntheticDocuments.textPDF(pages: ["Statement"]), name: "Statement")
        defer { app.terminate() }
        let page = app.images["document-page-image"]
        setNightMode(app, true)
        waitForPaper(app, dark: true, at: Self.plainPaper)

        app.buttons["editor-text-box"].tap()
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)).tap()
        let editor = app.textViews["inline-text-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Night note")
        XCTAssertEqual(editor.value as? String, "Night note", "letters were lost while typing at night")
        // What is being typed is readable: there is light print inside the box.
        let typing = pixels(app, in: editor.frame)
        XCTAssertGreaterThan(typing.count { max($0.r, $0.g, $0.b) > 170 }, 30,
                             "the words being typed do not show light on the dark page")
        // The formatting bar is controls, not page, so night mode leaves it
        // alone: the swatch for black text is black. It once showed white.
        let swatch = app.buttons["inline-text-color"]
        XCTAssertTrue(swatch.exists)
        let centre = pixels(app, in: swatch.frame.insetBy(dx: swatch.frame.width * 0.4,
                                                          dy: swatch.frame.height * 0.4))
        XCTAssertLessThan(centre.brightest, 90,
                          "the colour swatch for black text is not black at night: \(centre.average)")
        snap(app, "typing-at-night")
        app.buttons["inline-text-done"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))

        // Saved in the colour chosen, which is dark: a night shade would be light.
        let pageID = try await store.pages(of: item)[0].id
        var saved: TextBox?
        for _ in 0..<40 where saved == nil {
            saved = try await store.objects(on: pageID).compactMap {
                if case .text(let box) = $0.payload { return box } else { return nil }
            }.first
            if saved == nil { try await Task.sleep(for: .milliseconds(250)) }
        }
        let box = try XCTUnwrap(saved, "the text box was not saved")
        XCTAssertEqual(box.text.trimmingCharacters(in: .whitespacesAndNewlines), "Night note")
        XCTAssertLessThan(max(box.color.red, box.color.green, box.color.blue), 0.5,
                          "the text was saved in its night shade: \(box.color)")

        // And the page still reads light on dark once the box is placed.
        waitForPaper(app, dark: true, at: Self.plainPaper)
    }

    /// A filled-in form's answers are drawn from the form, not the page's
    /// print, since 78d7e77 — after night mode was built. They must turn
    /// with the page like everything else on it.
    func testAFilledFormsAnswerShowsLightOnDarkAtNight() async throws {
        let form = SyntheticDocuments.acroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer", value: "MMMMMMMM"),
        ])
        let (app, _, _) = try await openPDF(form, name: "Form")
        defer { app.terminate() }
        let page = app.images["document-page-image"]
        // The field is at [72 600 300 630] in PDF space: 162 to 192 from the top.
        let field = CGRect(x: 72, y: 162, width: 228, height: 30)
        let paper = Self.plainPaper

        waitForPaper(app, dark: false, at: paper)
        let byDay = region(app, of: page, rect: field)
        XCTAssertGreaterThan(byDay.count { max($0.r, $0.g, $0.b) < 90 }, 25,
                             "by day there is no answer printed in the field, so this test has nothing to look at")

        setNightMode(app, true)
        waitForPaper(app, dark: true, at: paper)
        let atNight = region(app, of: page, rect: field)
        XCTAssertGreaterThan(atNight.count { min($0.r, $0.g, $0.b) > 150 }, 25,
                             "at night the answer is not light on the page")
        XCTAssertLessThan(atNight.count { max($0.r, $0.g, $0.b) < 90 }, atNight.pixels.count,
                          "the field is all dark: the answer vanished")
        snap(app, "form-at-night")
    }

    // MARK: - Bookmarks

    /// ⌘D from a hardware keyboard marks the page and unmarks it. A phone
    /// has no menu bar to carry the shortcut, so this is an iPad's.
    func testCommandDBookmarksThePageFromAHardwareKeyboard() async throws {
        try XCTSkipUnless(isPad, "a phone has no menu bar for ⌘D to live in")
        let (app, store, item) = try await openPDF(SyntheticDocuments.textPDF(pages: ["Statement"]), name: "Statement")
        defer { app.terminate() }
        let ribbon = app.descendants(matching: .any).matching(identifier: "page-bookmark-ribbon").firstMatch
        XCTAssertFalse(ribbon.exists)

        app.typeKey("d", modifierFlags: .command)

        XCTAssertTrue(ribbon.waitForExistence(timeout: 5), "⌘D did not bookmark the page")
        var saved: [Bookmark] = []
        for _ in 0..<40 where saved.isEmpty {
            saved = try await store.bookmarks(of: item)
            if saved.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
        }
        XCTAssertEqual(saved.count, 1, "⌘D showed a ribbon but saved no bookmark")
        snap(app, "command-d")

        app.typeKey("d", modifierFlags: .command)

        XCTAssertTrue(ribbon.waitForNonExistence(timeout: 5), "⌘D a second time did not remove the bookmark")
        for _ in 0..<40 where !saved.isEmpty {
            saved = try await store.bookmarks(of: item)
            if !saved.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
        }
        XCTAssertTrue(saved.isEmpty, "the bookmark is still saved after ⌘D removed its ribbon")
    }

    /// A notebook scrolls through all its pages at once. A bookmark there
    /// marks its own page, leads back to it from the list, and its ribbon
    /// still reads as red at night.
    func testANotebooksBookmarkMarksItsPageLeadsBackAndShowsAtNight() async throws {
        let directory = URL(fileURLWithPath: "/tmp/papernest-reader-gaps-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Journal", pages: (0..<3).map { _ in
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        }, assets: [])
        let app = launch(directory, item: "Journal")
        defer { app.terminate() }
        let ribbons = app.descendants(matching: .any).matching(identifier: "page-bookmark-ribbon")
        let notebookPage = CGSize(width: 600, height: 800)

        // Page 2, bookmarked from the title menu.
        chooseFromTitleMenu(app, title: "Journal", "Go to Page…")
        let alert = app.alerts["Go to Page…"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("2")
        alert.buttons["Go"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        waitForPage(app, "Page 2 of 3")
        chooseFromTitleMenu(app, title: "Journal", "Add Bookmark")
        XCTAssertTrue(ribbons.firstMatch.waitForExistence(timeout: 5), "no ribbon on the bookmarked page")
        XCTAssertEqual(ribbons.count, 1, "more than one page shows a ribbon")
        let pageFrame = app.images["document-page-image"].frame
        let ribbonFrame = ribbons.firstMatch.frame
        XCTAssertTrue(pageFrame.insetBy(dx: -8, dy: -8).contains(ribbonFrame),
                      "the ribbon \(ribbonFrame) is not on page 2 \(pageFrame)")
        var saved: [Bookmark] = []
        for _ in 0..<40 where saved.isEmpty {
            saved = try await store.bookmarks(of: item.id)
            if saved.isEmpty { try await Task.sleep(for: .milliseconds(250)) }
        }
        let pages = try await store.pages(of: item.id)
        XCTAssertEqual(saved.map(\.pageID), [pages[1].id], "the bookmark was saved against the wrong page")

        // At night the ribbon is still a red mark, lighter but red.
        setNightMode(app, true)
        waitForPaper(app, dark: true, at: Self.plainPaper, pageSize: notebookPage)
        // On a phone the page is taller than the space for it, and going to
        // it centres it, so its top edge — and the ribbon — are scrolled out
        // of sight above. Scroll back a little, dragging in the margin beside
        // the paper so no page tool takes the drag. (Zooming out was tried
        // first and moved the ribbon further off, not into view.)
        let toolbarBottom = app.buttons["editor-text-box"].frame.maxY
        let margin = app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: 5, dy: toolbarBottom + 120))
        for _ in 0..<4 where ribbons.firstMatch.frame.minY < toolbarBottom + 4 {
            margin.press(forDuration: 0.05, thenDragTo: margin.withOffset(CGVector(dx: 0, dy: 140)))
            usleep(700_000)
        }
        XCTAssertGreaterThan(ribbons.firstMatch.frame.minY, toolbarBottom,
                             "the ribbon cannot be scrolled into view")
        let mark = pixels(app, in: ribbons.firstMatch.frame.insetBy(dx: ribbons.firstMatch.frame.width * 0.3,
                                                                      dy: ribbons.firstMatch.frame.height * 0.3))
        let colour = mark.average
        XCTAssertGreaterThan(colour.r - colour.b, 40, "the ribbon is not red at night: \(colour)")
        XCTAssertGreaterThan(colour.r - colour.g, 40, "the ribbon is not red at night: \(colour)")
        snap(app, "notebook-ribbon-at-night")

        // From page 3, the list leads back to page 2.
        chooseFromTitleMenu(app, title: "Journal", "Go to Page…")
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.textFields.firstMatch.typeText("3")
        alert.buttons["Go"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        waitForPage(app, "Page 3 of 3")
        chooseFromTitleMenu(app, title: "Journal", "Bookmarks…")
        let row = app.buttons["bookmark-row-0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the list has no row for the bookmark")
        row.tap()
        waitForPage(app, "Page 2 of 3")
    }
}
