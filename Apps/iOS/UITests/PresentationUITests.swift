import XCTest
import PaperNestCore
import PaperNestStore

/// Presenting a document in the running app: Present from the title menu
/// opens the page being read full screen; ‹ ›, swipes and keys turn pages;
/// with the laser pointer on, a swipe points instead of turning; Exit
/// closes it on the page last shown. What a presentation is lives in
/// `PresentationTests`.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class PresentationUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-presentation-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// The library the app has open, for reading back what it saved.
    private var store: LibraryStore?
    private var item: ItemID?

    private func open(language: String = "en", largestText: Bool = false) async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-presentation-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        self.store = store
        let data = SyntheticDocuments.textPDF(pages: ["Quarterly review", "Spring results", "Next steps"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Review.pdf")
        item = try await store.createItem(kind: .document, name: "Review", pages: (0..<3).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset]).id
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Review",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
        if largestText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 30), "the document did not open")
        return app
    }

    /// Present, from the title menu.
    private func present(_ app: XCUIApplication, item: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "no title to open the menu from", file: file, line: line)
        title.tap()
        let menuItem = app.buttons[item]
        XCTAssertTrue(menuItem.waitForExistence(timeout: 5), "\(item) is not in the title menu", file: file, line: line)
        menuItem.tap()
        let page = app.descendants(matching: .any)["presentation.page"].firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the presentation did not open", file: file, line: line)
        return page
    }

    private func expectPage(_ page: XCUIElement, _ number: Int, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", String(number)), object: page)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 10), .completed,
                       "\(message): showing \(page.value ?? "nothing")", file: file, line: line)
    }

    /// Shows the controls if they are hidden, with a tap on the page.
    private func showControls(_ app: XCUIApplication, page: XCUIElement) {
        if !app.buttons["presentation.exit"].exists { page.tap() }
        XCTAssertTrue(app.buttons["presentation.exit"].waitForExistence(timeout: 5), "a tap did not show the controls")
    }

    private func setLaser(_ app: XCUIApplication, page: XCUIElement) {
        showControls(app, page: page)
        app.buttons["presentation.more"].tap()
        // A toggle in a menu shows as a menu item, whatever type XCUITest gives it.
        let laser = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == %@ OR label == %@", "presentation.laser", "Laser Pointer")).firstMatch
        XCTAssertTrue(laser.waitForExistence(timeout: 5), "no Laser Pointer in the menu")
        laser.tap()
    }

    func testPresentingTurnsPagesPointsAndEndsWhereItStopped() async throws {
        let app = try await open()
        defer { app.terminate() }
        let page = present(app, item: "Present")
        expectPage(page, 1, "the presentation starts on the page being read")
        XCTAssertFalse(app.buttons["presentation.exit"].exists, "the controls start hidden")
        // XCUITest still lists the document under a full-screen cover; what matters is that it cannot be reached.
        XCTAssertFalse(app.navigationBars.firstMatch.isHittable, "the document's bars are not shown")
        snap(app, "page-en")

        showControls(app, page: page)
        snap(app, "controls-en")
        XCTAssertFalse(app.buttons["presentation.previous"].isEnabled, "nothing before the first page")
        app.buttons["presentation.next"].tap()
        expectPage(page, 2, "› turns to the next page")
        page.swipeLeft()
        expectPage(page, 3, "a swipe turns the page")
        XCTAssertFalse(app.buttons["presentation.next"].isEnabled, "nothing after the last page")
        page.swipeLeft()
        expectPage(page, 3, "the last page stays")

        // The laser pointer: a swipe points, and the page stays.
        setLaser(app, page: page)
        page.swipeRight()
        expectPage(page, 3, "with the laser on, a swipe points instead of turning")
        snap(app, "laser-en")
        setLaser(app, page: page)
        page.swipeRight()
        expectPage(page, 2, "with the laser off again, a swipe turns the page")

        showControls(app, page: page)
        app.buttons["presentation.exit"].tap()
        XCTAssertTrue(page.waitForNonExistence(timeout: 10), "Exit did not close the presentation")
        let reader = app.images["document-page-image"]
        let onTwo = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Page 2 of 3"), object: reader)
        XCTAssertEqual(XCTWaiter.wait(for: [onTwo], timeout: 10), .completed,
                       "the reader is not on the page last shown: \(reader.label)")

        // Drawing still works after presenting: the presentation took the
        // keyboard from the document's canvas, and the canvas must take it back.
        // A finger draws only once finger drawing is on (Display settings).
        app.buttons["studio-tool-settings"].tap()
        let finger = app.switches["studio-finger-drawing"]
        XCTAssertTrue(finger.waitForExistence(timeout: 5), "no finger drawing switch")
        let scroll = app.scrollViews["display-settings-scroll"]
        for _ in 0..<4 where scroll.exists && !(finger.isHittable && app.windows.firstMatch.frame.contains(finger.frame)) {
            scroll.swipeUp()
        }
        if (finger.value as? String) != "1" { finger.flipSwitch() }
        XCTAssertEqual(finger.value as? String, "1")
        app.closeToolSettings()
        let drawing = app.buttons["studio-drawing-toggle"]
        XCTAssertTrue(drawing.waitForExistence(timeout: 5))
        if (drawing.value as? String) != "Selected" { drawing.tap() }
        let pen = app.buttons["studio-tool-pen"]
        XCTAssertTrue(pen.waitForExistence(timeout: 5))
        if (pen.value as? String) != "Selected" { pen.tap() }
        reader.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: reader.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        let store = try XCTUnwrap(store), item = try XCTUnwrap(item)
        var strokes = 0
        for _ in 0..<40 where strokes == 0 {
            try await Task.sleep(for: .milliseconds(250))
            let pageID = try await store.pages(of: item)[1].id
            strokes = try await store.objects(on: pageID).filter { if case .ink = $0.payload { true } else { false } }.count
        }
        XCTAssertEqual(strokes, 1, "after presenting, a stroke on the page was not saved")
    }

    /// The keyboard: the arrows and space turn pages. (Escape is handled too,
    /// but sent this way it never reached the app; not claimed.)
    func testAKeyboardTurnsPages() async throws {
        let app = try await open()
        defer { app.terminate() }
        let page = present(app, item: "Present")
        expectPage(page, 1, "starts on page 1")
        app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        expectPage(page, 2, "→ turns to the next page")
        app.typeKey(XCUIKeyboardKey.space, modifierFlags: [])
        expectPage(page, 3, "space turns to the next page")
        app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
        expectPage(page, 2, "← turns back")
    }

    /// French and Spanish, and Spanish at the largest text size: the menu
    /// item and the controls in the language, the controls on screen.
    func testPresentingInFrenchAndSpanish() async throws {
        for (language, item, exit, largest) in [("fr", "Présenter", "Quitter", false), ("es", "Presentar", "Salir", false),
                                                ("es", "Presentar", "Salir", true)] {
            let app = try await open(language: language, largestText: largest)
            let page = present(app, item: item)
            showControls(app, page: page)
            let exitButton = app.buttons["presentation.exit"]
            XCTAssertEqual(exitButton.label, exit, language)
            XCTAssertTrue(exitButton.isHittable, "\(language): Exit is not reachable")
            XCTAssertTrue(app.buttons["presentation.next"].isHittable, "\(language): › is not reachable")
            XCTAssertLessThanOrEqual(exitButton.frame.maxX, app.frame.maxX, "\(language): Exit runs off the screen")
            snap(app, "controls-\(language)\(largest ? "-xxxl" : "")")
            exitButton.tap()
            XCTAssertTrue(page.waitForNonExistence(timeout: 10))
            app.terminate()
        }
    }
}
