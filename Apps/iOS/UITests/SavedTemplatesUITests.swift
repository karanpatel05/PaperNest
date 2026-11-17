import XCTest
import PaperNestCore
import PaperNestStore

/// Saving a page as a template from the Insert tool, making a page from it,
/// and deleting it, each checked by reading the library back from disk.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class SavedTemplatesUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func open(language: String = "en") async throws -> (XCUIApplication, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-templates-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Planning", pages: [
            .init(sourceSize: LibraryStore.notebookPageSize, content: .template(.lined))
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        try await store.saveObject(PageObject(pageID: page.id, zKey: "V", payload: .text(TextBox(
            frame: CGRect(x: 60, y: 60, width: 260, height: 24), text: "Weekly agenda")), modifiedAt: Date()))
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Planning", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        XCTAssertTrue(app.buttons["studio-tool-lasso"].waitForExistence(timeout: 30))
        return (app, store, item.id)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-templates-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Opens the Insert tool from the main toolbar, scrolled into reach on a phone.
    private func openInsert(_ app: XCUIApplication) {
        let button = app.buttons["studio-tool-insert"]
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        let bar = app.scrollViews["notebook-tool-bar"]
        let reach = bar.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 10, dy: 0)
        for _ in 0..<8 where button.frame.midX > reach.maxX { bar.swipeLeft() }
        button.tap()
        // The papers' row is always first; with templates saved, the panel's
        // other tools can be below the fold, where its lazy grid has not made them.
        XCTAssertTrue(app.scrollViews["insert-page-papers"].waitForExistence(timeout: 10), "the Insert panel did not open")
    }

    /// A control in the open panel, dragged into reach: the panel's grids are lazy.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews["tool-panel-scroll"]
        let window = app.windows.firstMatch
        func inPanel() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let panel = scroll.frame.insetBy(dx: 0, dy: 4)
            return panel.isEmpty || (panel.minY <= element.frame.minY && element.frame.maxY <= panel.maxY)
        }
        for _ in 0..<12 where !inPanel() {
            let frame = scroll.frame
            guard !frame.isEmpty else { break }
            let start = window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + 6, dy: frame.maxY - 30))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -min(220, frame.height * 0.6))),
                        withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        XCTAssertTrue(inPanel(), "\(element) cannot be reached in the panel", file: file, line: line)
    }

    private func eventually<T>(_ what: String, _ read: () async throws -> T, until done: (T) -> Bool) async throws -> T {
        var latest = try await read()
        for _ in 0..<40 where !done(latest) {
            try await Task.sleep(for: .milliseconds(250))
            latest = try await read()
        }
        XCTAssertTrue(done(latest), what)
        return latest
    }

    func testSaveAPageAsATemplateMakeAPageFromItAndDeleteIt() async throws {
        let (app, store, item) = try await open()
        defer { app.terminate() }

        // Save the page as a template, named in the prompt.
        openInsert(app)
        let save = app.buttons["insert-save-template"]
        reveal(save, in: app)
        save.tap()
        // A system alert: its field and buttons are found through it, not by identifier.
        let prompt = app.alerts.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), "no name prompt")
        let name = prompt.textFields.firstMatch
        snap(app, "save-prompt-en")
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20) + "Agenda page")
        prompt.buttons["Save"].tap()
        let saved = try await eventually("the template was not saved", { try await store.savedTemplates() }) { $0.count == 1 }
        XCTAssertEqual(saved.first?.name, "Agenda page")
        XCTAssertEqual(saved.first?.objects.count, 1)

        // Make a page from it.
        openInsert(app)
        let card = app.buttons.matching(identifier: "insert-template").matching(NSPredicate(format: "label == %@", "Agenda page")).firstMatch
        reveal(card, in: app)
        snap(app, "my-templates-en")
        card.tap()
        let pages = try await eventually("no page was made", { try await store.pages(of: item) }) { $0.count == 2 }
        guard pages.count == 2 else { return }
        XCTAssertEqual(pages[1].content, .template(.lined))
        let texts = try await store.objects(on: pages[1].id).compactMap { object -> String? in
            if case .text(let box) = object.payload { box.text } else { nil }
        }
        XCTAssertEqual(texts, ["Weekly agenda"], "the template's text box came with the page")

        // Delete it from its card's menu, after being asked.
        openInsert(app)
        let again = app.buttons.matching(identifier: "insert-template").matching(NSPredicate(format: "label == %@", "Agenda page")).firstMatch
        reveal(again, in: app)
        again.press(forDuration: 1.2)
        let delete = app.buttons["Delete"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 5), "no Delete in the card's menu")
        delete.tap()
        // An action sheet on a phone, a popover on a pad.
        let confirm = isPad ? app.popovers.buttons["Delete"].firstMatch : app.sheets.buttons["Delete"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "deleting was not asked first")
        snap(app, "delete-confirm-en")
        confirm.tap()
        _ = try await eventually("the template was not deleted", { try await store.savedTemplates() }) { $0.isEmpty }
        let kept = try await store.pages(of: item)
        XCTAssertEqual(kept.count, 2, "the page made from it stays")
    }

    /// The save prompt in French and Spanish.
    func testTheSavePromptInFrenchAndSpanish() async throws {
        for language in ["fr", "es"] {
            let (app, store, _) = try await open(language: language)
            defer { app.terminate() }
            openInsert(app)
            let save = app.buttons["insert-save-template"]
            reveal(save, in: app)
            save.tap()
            let prompt = app.alerts.firstMatch
            XCTAssertTrue(prompt.waitForExistence(timeout: 10), "\(language): no name prompt")
            XCTAssertTrue(prompt.textFields.firstMatch.exists, "\(language): no name field")
            let confirmSave = prompt.buttons[language == "fr" ? "Enregistrer" : "Guardar"]
            XCTAssertTrue(confirmSave.isHittable, "\(language): Save is out of reach")
            snap(app, "save-prompt-\(language)")
            confirmSave.tap()
            let saved = try await eventually("\(language): not saved", { try await store.savedTemplates() }) { $0.count == 1 }
            XCTAssertEqual(saved.first?.name, "Planning", "\(language): the prompt starts with the document's name")
            app.terminate()
        }
    }
}
