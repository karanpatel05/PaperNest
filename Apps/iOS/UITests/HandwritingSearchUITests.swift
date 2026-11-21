import XCTest
import PaperNestCore
import PaperNestStore

/// Handwriting search, end to end: words written in a notebook (synthetic
/// single-stroke print, `SyntheticHandwriting`, nobody's real hand) are read
/// by the app's background pass a few seconds after launch, and a search for
/// one finds the page, labelled as handwriting. The library is watched from
/// here, so the test waits for the reading rather than for a fixed time.
@MainActor final class HandwritingSearchUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func seed(_ writing: String) async throws -> (URL, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-handwriting-search-\(UUID().uuidString)")
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Journal", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let pageID = try await store.pages(of: item.id)[0].id
        for (index, path) in try SyntheticHandwriting.strokes(writing, origin: CGPoint(x: 100, y: 240), size: 24).enumerated() {
            try await store.saveObject(PageObject(
                pageID: pageID, zKey: String(format: "K%03d", index),
                payload: .ink(InkStroke(tool: .pen, color: .black, width: 2.6,
                                        points: path.map { InkPoint(x: $0.x, y: $0.y) })),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return (directory, store, item.id)
    }

    private func launch(_ directory: URL, language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        return app
    }

    /// Waits for the app's background pass to make `word` findable: it starts
    /// once nothing has changed for a few seconds, then reads the page.
    private func waitUntilFindable(_ word: String, in store: LibraryStore, file: StaticString = #filePath,
                                   line: UInt = #line) async throws {
        for _ in 0..<120 {
            if !(try await store.search(word)).isEmpty { return }
            try await Task.sleep(for: .milliseconds(500))
        }
        XCTFail("the app never made “\(word)” findable", file: file, line: line)
    }

    private func search(_ word: String, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        // On a phone, Home's own search field: the All Documents field never
        // took the keyboard there in this run or in the app-wide one
        // (`testRecognizeTextMakesAWordOnThePageSearchable`, 2026-11-19).
        // Return submits it, and the results open in All Documents.
        let home = app.textFields["home-search"]
        if !isPad, home.waitForExistence(timeout: 15) {
            home.tap()
            home.typeText(word + "\n")
            return
        }
        let seeAll = app.buttons["home-see-all"]
        if seeAll.waitForExistence(timeout: 15) {
            for _ in 0..<8 where !seeAll.isHittable { app.swipeUp() }
            seeAll.tap()
        }
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10), "no search field", file: file, line: line)
        // The field sometimes takes a second tap to take the keyboard.
        for _ in 0..<3 where (field.value(forKey: "hasKeyboardFocus") as? Bool) != true {
            field.tap()
            _ = app.keyboards.firstMatch.waitForExistence(timeout: 2)
        }
        field.typeText(word)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-handwriting-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testAWordWrittenByHandIsFoundAsHandwriting() async throws {
        for (language, label) in [("en", "Handwriting"), ("fr", "Écriture manuscrite")] {
            let (directory, store, item) = try await seed("plan lunch")
            let before = try await store.search("lunch")
            XCTAssertTrue(before.isEmpty, "\(language): findable before the app read it")
            let app = launch(directory, language: language)
            try await waitUntilFindable("lunch", in: store)
            let found = try await store.search("lunch")
            XCTAssertEqual(found, [item])

            search("lunch", in: app)
            let hit = app.buttons["search-hit-0"]
            XCTAssertTrue(hit.waitForExistence(timeout: 15), "\(language): no page hit for a handwritten word")
            XCTAssertTrue(hit.label.contains(label), "\(language): the hit does not say it is handwriting: \(hit.label)")
            XCTAssertTrue(hit.label.contains("Journal"), "\(language): \(hit.label)")
            XCTAssertEqual(hit.value as? String, "1", "\(language): the hit is for page 1")
            snap(app, "search-\(language)")

            hit.tap()
            XCTAssertTrue(app.buttons["studio-tool-lasso"].waitForExistence(timeout: 20), "\(language): the hit did not open the notebook")
            app.terminate()
        }
    }
}
