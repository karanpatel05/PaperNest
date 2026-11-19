import XCTest
import PaperNestCore
import PaperNestStore

/// Presenting a document in the running app: Present from the title menu
/// opens the page being read full screen; ‹ ›, swipes and keys turn pages;
/// with the laser pointer a swipe points, and with the pen it draws, instead
/// of turning, and nothing drawn is saved; Exit closes it on the page last
/// shown. What a presentation is lives in
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

    /// Chooses the pointer in the ⋯ menu by its name: "No Pointer",
    /// "Laser Pointer" or "Pen". Its options show as menu items, whatever type
    /// XCUITest gives them.
    private func choosePointer(_ name: String, _ app: XCUIApplication, page: XCUIElement,
                               file: StaticString = #filePath, line: UInt = #line) {
        showControls(app, page: page)
        app.buttons["presentation.more"].tap()
        let option = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", name)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5), "no \(name) in the menu", file: file, line: line)
        option.tap()
    }

    /// The pen strokes on the page shown.
    private func strokesShown(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any)["presentation.sketch"].firstMatch.value as? String ?? ""
    }

    private func drawAcross(_ page: XCUIElement, at height: CGFloat) {
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: height))
            .press(forDuration: 0.05, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: height + 0.02)))
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
        choosePointer("Laser Pointer", app, page: page)
        page.swipeRight()
        expectPage(page, 3, "with the laser on, a swipe points instead of turning")
        snap(app, "laser-en")
        choosePointer("No Pointer", app, page: page)
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

    /// The pen: a drag draws on the page and turns nothing; Clear Drawing
    /// and turning the page clear it; nothing drawn is saved.
    func testThePenDrawsOnThePageAndNothingIsSaved() async throws {
        let app = try await open()
        defer { app.terminate() }
        let page = present(app, item: "Present")
        expectPage(page, 1, "starts on page 1")
        choosePointer("Pen", app, page: page)
        drawAcross(page, at: 0.4)
        drawAcross(page, at: 0.55)
        XCTAssertEqual(strokesShown(app), "2", "two drags should be two strokes")
        expectPage(page, 1, "with the pen, a drag draws instead of turning")
        snap(app, "pen-en")

        let clear = app.buttons["presentation.clear"]
        showControls(app, page: page)
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "no Clear Drawing while there is a drawing")
        clear.tap()
        XCTAssertEqual(strokesShown(app), "0", "Clear Drawing left strokes")
        XCTAssertFalse(clear.exists, "Clear Drawing with nothing to clear")

        drawAcross(page, at: 0.5)
        XCTAssertEqual(strokesShown(app), "1")
        showControls(app, page: page)
        app.buttons["presentation.next"].tap()
        expectPage(page, 2, "› still turns the page with the pen")
        XCTAssertEqual(strokesShown(app), "0", "the drawing belongs to the page it was drawn on")

        showControls(app, page: page)
        app.buttons["presentation.exit"].tap()
        XCTAssertTrue(page.waitForNonExistence(timeout: 10))
        // Nothing the pen drew reached the document.
        let store = try XCTUnwrap(store), item = try XCTUnwrap(item)
        for each in try await store.pages(of: item) {
            let ink = try await store.objects(on: each.id).filter { if case .ink = $0.payload { true } else { false } }
            XCTAssertTrue(ink.isEmpty, "the pen's drawing was saved as ink on page \(each.id)")
        }
    }

    /// Speaker notes: written from the title menu and saved; shown under the
    /// page while presenting on an iPad, page by page; an iPhone presents
    /// without them, as the sample keeps it a viewer.
    func testSpeakerNotesAreWrittenAndShownWhilePresenting() async throws {
        let app = try await open()
        defer { app.terminate() }
        let note = "Open with the revenue chart"
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Review")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        title.tap()
        let notesItem = app.buttons["Speaker Notes"]
        XCTAssertTrue(notesItem.waitForExistence(timeout: 5), "no Speaker Notes in the title menu")
        notesItem.tap()
        let editor = app.textViews["speaker-notes-editor"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10), "the notes sheet did not open")
        editor.tap()
        editor.typeText(note)
        snap(app, "notes-sheet-en")
        app.buttons["speaker-notes-done"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10), "Done did not close the sheet")
        let store = try XCTUnwrap(store), document = try XCTUnwrap(item)
        let firstPage = try await store.pages(of: document)[0].id
        var saved: String?
        for _ in 0..<40 where saved == nil {
            try await Task.sleep(for: .milliseconds(250))
            saved = try await store.speakerNote(on: firstPage)
        }
        XCTAssertEqual(saved, note, "the note was not saved")

        let page = present(app, item: "Present")
        showControls(app, page: page)
        app.buttons["presentation.more"].tap()
        let toggle = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Speaker Notes")).firstMatch
        let panel = app.descendants(matching: .any)["presentation.notes"].firstMatch
        if isPad {
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "no Speaker Notes in the presentation's menu")
            toggle.tap()
            XCTAssertTrue(panel.waitForExistence(timeout: 5), "the notes did not show")
            XCTAssertTrue(panel.label.contains(note), "page 1's note is not shown: \(panel.label)")
            snap(app, "notes-shown-en")
            showControls(app, page: page)
            app.buttons["presentation.next"].tap()
            expectPage(page, 2, "› turns to page 2")
            let none = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "No notes for this page."),
                                                 object: panel)
            XCTAssertEqual(XCTWaiter.wait(for: [none], timeout: 5), .completed, "page 2 shows: \(panel.label)")
        } else {
            XCTAssertFalse(toggle.waitForExistence(timeout: 2), "an iPhone presents without speaker notes")
            XCTAssertFalse(panel.exists)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        showControls(app, page: page)
        app.buttons["presentation.exit"].tap()
        XCTAssertTrue(page.waitForNonExistence(timeout: 10))
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
        for (language, item, exit, pen, largest) in [("fr", "Présenter", "Quitter", "Stylo", false),
                                                     ("es", "Presentar", "Salir", "Lápiz", false),
                                                     ("es", "Presentar", "Salir", "Lápiz", true),
                                                     ("fr", "Présenter", "Quitter", "Stylo", true)] {
            let app = try await open(language: language, largestText: largest)
            let page = present(app, item: item)
            showControls(app, page: page)
            let exitButton = app.buttons["presentation.exit"]
            XCTAssertEqual(exitButton.label, exit, language)
            XCTAssertTrue(exitButton.isHittable, "\(language): Exit is not reachable")
            XCTAssertTrue(app.buttons["presentation.next"].isHittable, "\(language): › is not reachable")
            XCTAssertLessThanOrEqual(exitButton.frame.maxX, app.frame.maxX, "\(language): Exit runs off the screen")
            snap(app, "controls-\(language)\(largest ? "-xxxl" : "")")
            // With a pen drawing, Clear Drawing joins Exit and ⋯ along the top: all on screen.
            choosePointer(pen, app, page: page)
            drawAcross(page, at: 0.45)
            showControls(app, page: page)
            let clear = app.buttons["presentation.clear"], more = app.buttons["presentation.more"]
            XCTAssertTrue(clear.waitForExistence(timeout: 5), "\(language): no Clear Drawing")
            for control in [exitButton, clear, more] {
                XCTAssertTrue(control.isHittable, "\(language): \(control.label) is not reachable")
                XCTAssertGreaterThanOrEqual(control.frame.minX, app.frame.minX, "\(language): \(control.label) runs off the left")
                XCTAssertLessThanOrEqual(control.frame.maxX, app.frame.maxX, "\(language): \(control.label) runs off the right")
            }
            snap(app, "pen-\(language)\(largest ? "-xxxl" : "")")
            exitButton.tap()
            XCTAssertTrue(page.waitForNonExistence(timeout: 10))
            app.terminate()
        }
    }
}
