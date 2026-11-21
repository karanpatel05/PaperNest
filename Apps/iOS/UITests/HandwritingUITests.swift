import XCTest
import PaperNestCore
import PaperNestStore

/// Handwriting to text, end to end: the lasso selects the writing, ⋯ →
/// Convert to Text reads it on the device, the words are corrected in the
/// sheet, and Insert puts them on the page as a text box; Undo takes the
/// change back. The writing is synthetic single-stroke print
/// (`SyntheticHandwriting`), seeded through the store before launch: nobody's
/// real hand, and no Apple Pencil. Screenshots: `/tmp/pn-handwriting-shots`.
@MainActor final class HandwritingUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private static let blue = RGBAColor(red: 0.1, green: 0.15, blue: 0.55)

    private func seed(_ text: String? = nil, scribble: Bool = false) async throws -> (URL, LibraryStore, PageID, Int) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-handwriting-\(UUID().uuidString)")
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Journal", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let pageID = try await store.pages(of: item.id)[0].id
        var paths: [[CGPoint]] = []
        if let text { paths = try SyntheticHandwriting.strokes(text, origin: CGPoint(x: 120, y: 260), size: 26) }
        if scribble {
            var wobble = SyntheticHandwriting.Wobble(seed: 7)
            paths = (0..<6).map { _ in (0..<40).map { i in CGPoint(x: 200 + Double(i) * 3 + wobble.next(30), y: 300 + wobble.next(40)) } }
        }
        for (index, path) in paths.enumerated() {
            try await store.saveObject(PageObject(
                pageID: pageID, zKey: String(format: "K%03d", index),
                payload: .ink(InkStroke(tool: .pen, color: Self.blue, width: 3,
                                        points: path.map { InkPoint(x: $0.x, y: $0.y) })),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (directory, store, pageID, paths.count)
    }

    private func launch(_ directory: URL, language: String = "en", largest: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Journal",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
        if largest { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-handwriting-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Lasso → Select All → ⋯ → `convert`. A notebook opens with the lasso in
    /// hand, and its panel selects everything on the page.
    private func openConversion(_ app: XCUIApplication, convert: String, file: StaticString = #filePath, line: UInt = #line) {
        let lasso = app.buttons["studio-tool-lasso"]
        XCTAssertTrue(lasso.waitForExistence(timeout: 30), "the notebook did not open", file: file, line: line)
        lasso.tap()
        let selectAll = app.buttons["studio-lasso-select-all"]
        // Once in four iPhone runs (2026-11-20) the Lasso's panel did not open
        // on the first tap, though the Lasso showed as chosen; tapped again
        // only when the panel has not appeared.
        if !selectAll.waitForExistence(timeout: 5) { lasso.tap() }
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "the Lasso's panel did not open", file: file, line: line)
        // At the largest text size the Lasso's panel is a small scrolling
        // popover, and Select All is below what it shows.
        let panel = app.scrollViews.containing(NSPredicate(format: "identifier == %@", "studio-lasso-select-all")).firstMatch
        for _ in 0..<6 where !selectAll.isHittable && panel.exists { panel.swipeUp(velocity: .slow) }
        press(selectAll)
        let more = app.buttons["selection-more"]
        XCTAssertTrue(more.waitForExistence(timeout: 5), "no selection bar", file: file, line: line)
        press(more)
        let item = app.buttons[convert]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(convert) is not in the selection menu", file: file, line: line)
        item.tap()
    }

    /// Taps `element`, at its position when XCTest calls it covered. Used
    /// only for Select All and ⋯, which sit in small popovers at the largest
    /// text size; the Lasso itself is tapped plainly.
    private func press(_ element: XCUIElement) {
        if element.isHittable { element.tap() } else { element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    }

    private func objects(_ store: LibraryStore, _ page: PageID, until condition: ([PageObject]) -> Bool) async throws -> [PageObject] {
        var objects = try await store.objects(on: page)
        for _ in 0..<100 where !condition(objects) {
            try await Task.sleep(for: .milliseconds(100))
            objects = try await store.objects(on: page)
        }
        return objects
    }

    private func texts(_ objects: [PageObject]) -> [String] {
        objects.compactMap { if case .text(let box) = $0.payload { return box.text } else { return nil } }
    }

    private func inkCount(_ objects: [PageObject]) -> Int { objects.filter { $0.payload.kind == "ink" }.count }

    private static func letters(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: nil).lowercased().filter(\.isLetter)
    }

    /// Replaces what the sheet's editor holds with `text`: the caret to the
    /// end, the words deleted, the new ones typed.
    private func retype(_ editor: XCUIElement, _ text: String) {
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        let current = (editor.value as? String) ?? ""
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        editor.typeText(text)
    }

    func testHandwritingIsReadCorrectedInsertedAndUndone() async throws {
        let (directory, store, page, strokes) = try await seed("hello")
        let app = launch(directory)
        defer { app.terminate() }
        openConversion(app, convert: "Convert to Text")

        let editor = app.textViews["handwriting-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30), "the reading did not finish")
        XCTAssertEqual(Self.letters(editor.value as? String ?? ""), "hello", "read: \(editor.value ?? "")")
        XCTAssertTrue(app.images["handwriting-preview"].exists, "the selected ink is shown above the words")
        XCTAssertTrue(app.buttons["handwriting-keep"].isSelected, "the original ink is kept unless asked")
        XCTAssertFalse(app.buttons["handwriting-replace"].isSelected)
        if isPad {
            // Page-sized on an iPad: the ink, the words and both choices show
            // without scrolling, with Cancel and Insert Text at the foot.
            XCTAssertTrue(app.buttons["handwriting-replace"].isHittable, "Replace selection is below the sheet's foot")
        }
        snap(app, "read-en")
        retype(editor, "Hello Ana")
        app.buttons["handwriting-insert"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10), "the sheet did not close")

        let saved = try await objects(store, page) { texts($0) == ["Hello Ana"] }
        XCTAssertEqual(texts(saved), ["Hello Ana"], "the corrected words are on the page")
        XCTAssertEqual(inkCount(saved), strokes, "the handwriting is still there")
        snap(app, "inserted-en")

        let undo = app.buttons["notebook-undo"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        let undone = try await objects(store, page) { texts($0).isEmpty }
        XCTAssertTrue(texts(undone).isEmpty, "Undo took the words away")
        XCTAssertEqual(inkCount(undone), strokes)
    }

    /// French and Spanish, accented writing, and the handwriting replaced:
    /// the words take its place, and one Undo brings it back.
    func testReplacingHandwritingInFrenchAndSpanish() async throws {
        for (language, convert, word) in [("fr", "Convertir en texte", "café"), ("es", "Convertir en texto", "año")] {
            let (directory, store, page, strokes) = try await seed(word)
            let app = launch(directory, language: language)
            openConversion(app, convert: convert)
            let editor = app.textViews["handwriting-text"]
            XCTAssertTrue(editor.waitForExistence(timeout: 30), "\(language): the reading did not finish")
            let read = editor.value as? String ?? ""
            XCTAssertEqual(Self.letters(read), Self.letters(word), "\(language): read \(read)")
            print("HANDWRITING-UI \(language) wrote \(word) read \(read)")
            let replace = app.buttons["handwriting-replace"]
            for _ in 0..<3 where !replace.isHittable { app.swipeUp() }
            replace.tap()
            // The rows' values are in the app's language; the selected trait is not.
            XCTAssertTrue(replace.isSelected, "\(language): Replace selection is not chosen")
            XCTAssertFalse(app.buttons["handwriting-keep"].isSelected, "\(language): Keep original ink is still chosen")
            snap(app, "replace-\(language)")
            app.buttons["handwriting-insert"].tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 10))

            let replaced = try await objects(store, page) { inkCount($0) == 0 }
            XCTAssertEqual(inkCount(replaced), 0, "\(language): the handwriting was not replaced")
            XCTAssertEqual(texts(replaced).map(Self.letters), [Self.letters(word)])
            app.buttons["notebook-undo"].tap()
            let back = try await objects(store, page) { inkCount($0) == strokes }
            XCTAssertEqual(inkCount(back), strokes, "\(language): Undo did not bring the handwriting back")
            XCTAssertTrue(texts(back).isEmpty)
            app.terminate()
        }
    }

    /// A scribble has no words in it: the sheet says so and offers nothing to insert.
    func testAScribbleOffersNothingToInsert() async throws {
        let (directory, store, page, _) = try await seed(scribble: true)
        let before = try await store.objects(on: page)
        let app = launch(directory)
        defer { app.terminate() }
        openConversion(app, convert: "Convert to Text")
        let nothing = app.descendants(matching: .any)["handwriting-nothing"]
        XCTAssertTrue(nothing.waitForExistence(timeout: 30), "no 'nothing read' message")
        XCTAssertFalse(app.buttons["handwriting-insert"].isEnabled)
        XCTAssertTrue(app.images["handwriting-preview"].exists, "the scribble is still shown, so it can be seen why")
        snap(app, "nothing-en")
        app.buttons["handwriting-cancel"].tap()
        let after = try await store.objects(on: page)
        XCTAssertEqual(after, before)
    }

    /// At the largest text size, in French: the words, the switch and both
    /// buttons at the foot can all be reached, and Cancel leaves the page as it was.
    func testTheSheetAtTheLargestTextSize() async throws {
        let (directory, store, page, _) = try await seed("hello")
        let before = try await store.objects(on: page)
        let app = launch(directory, language: "fr", largest: true)
        defer { app.terminate() }
        if isPad {
            // At this size Document Tools no longer opens beside the page: with
            // the library's wide sidebar it left the page about 240 points and
            // a Lasso that could not be tapped (2026-11-20). Now it starts
            // closed and the tool bar has room.
            let lasso = app.buttons["studio-tool-lasso"]
            XCTAssertTrue(lasso.waitForExistence(timeout: 30))
            XCTAssertFalse(app.scrollViews["pdf-tools-list"].exists, "Document Tools opened beside the page at XXXL")
            XCTAssertTrue(lasso.isHittable, "the Lasso cannot be tapped at XXXL")
        }
        openConversion(app, convert: "Convertir en texte")
        let editor = app.textViews["handwriting-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["handwriting-insert"].isHittable, "Insérer le texte cannot be reached")
        XCTAssertTrue(app.buttons["handwriting-cancel"].isHittable, "Annuler cannot be reached")
        let insertFrame = app.buttons["handwriting-insert"].frame
        XCTAssertLessThanOrEqual(insertFrame.maxX, app.frame.maxX, "Insérer le texte runs off the right: \(insertFrame)")
        snap(app, "xxxl-fr")
        let replace = app.buttons["handwriting-replace"]
        for _ in 0..<5 where !(replace.exists && replace.isHittable) { app.swipeUp() }
        XCTAssertTrue(replace.isHittable, "Remplacer la sélection cannot be reached")
        XCTAssertTrue(app.buttons["handwriting-cancel"].isHittable, "Annuler is lost when the list is scrolled")
        snap(app, "xxxl-fr-switch")
        app.buttons["handwriting-cancel"].tap()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 10))
        let after = try await store.objects(on: page)
        XCTAssertEqual(after, before)
    }
}
