import XCTest
import PaperNestCore
import PaperNestStore

/// Search results that say where the match is.
///
/// A three-page scan whose recognized text has "invoice" on page 2 only.
/// Searching from Home lists the document, and under it the page that
/// matched, with the words around the match; tapping that opens the document
/// at page 2, not page 1.
///
/// Every page is seeded with recognized text, under the app's own engine
/// version, so automatic recognition at launch reads none of them again.
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class SearchHitsUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    /// `TextRecognizer.engineVersion`.
    private let engineVersion = "vision.accurate.1"

    private func seed() async throws -> URL {
        let directory = URL(fileURLWithPath: "/tmp/papernest-search-hits-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let png = SyntheticDocuments.image(width: 1200, height: 1600, type: .png)
        let asset = try store.assets.store(png, kind: .png, originalFilename: "Statements.png")
        let item = try await store.createItem(kind: .document, name: "Statements", pages: (0..<3).map { _ in
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(asset.id))
        }, assets: [asset])
        let texts = ["Cover sheet for the quarter", "Invoice total 42 due in October", "Terms and conditions"]
        for (page, text) in zip(try await store.pages(of: item.id), texts) {
            try await store.saveRecognition(PageRecognition(
                pageID: page.id, sourceRevision: page.revision, engineVersion: engineVersion, status: .completed,
                languages: ["en-US"], lines: [RecognizedLine(text: text, box: .exact(x: 0.1, y: 0.3, width: 0.7, height: 0.04),
                                                             confidence: 1)]))
        }
        return directory
    }

    private func launch(_ directory: URL, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        return app
    }

    /// Searches from Home and waits for the first page hit.
    private func search(_ app: XCUIApplication, _ text: String,
                        file: StaticString = #filePath, line: UInt = #line) -> XCUIElement? {
        let field = app.textFields["home-search"]
        guard field.waitForExistence(timeout: 30) else {
            XCTFail("Home did not open", file: file, line: line); return nil
        }
        field.tap()
        field.typeText("\(text)\n")
        let hit = app.buttons["search-hit-0"]
        let list = app.scrollViews["library-collection"]
        // The hits are under the documents; bring them into view.
        for _ in 0..<5 where !(hit.exists && hit.isHittable) && list.exists { list.swipeUp() }
        guard hit.waitForExistence(timeout: 15) else {
            XCTFail("no page hit for \(text)", file: file, line: line); return nil
        }
        return hit
    }

    private func waitForPage(_ app: XCUIApplication, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let page = app.images["document-page-image"]
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, !(page.exists && page.label == label) { usleep(200_000) }
        XCTAssertEqual(page.exists ? page.label : "<absent>", label, file: file, line: line)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let folder = URL(fileURLWithPath: "/tmp/pn-search-hits-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testAHitNamesThePageAndOpensTheDocumentThere() async throws {
        let directory = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard let hit = search(app, "invoice") else { return }

        XCTAssertEqual(hit.value as? String, "2", "the hit is for page 2")
        XCTAssertTrue(hit.label.contains("Statements"), hit.label)
        XCTAssertTrue(hit.label.contains("Page 2"), hit.label)
        XCTAssertTrue(hit.label.contains("Invoice total 42"), "the words around the match: \(hit.label)")
        XCTAssertTrue(hit.label.contains("Recognized text"), hit.label)
        XCTAssertFalse(app.buttons["search-hit-1"].exists, "only page 2 has the word")
        snap(app, "hits-en")

        hit.tap()
        waitForPage(app, "Page 2 of 3")
    }

    /// The document is already open — its tab is kept after going back, with
    /// its page 1 showing — and the hit still takes it to page 2.
    func testAHitTakesAnAlreadyOpenDocumentToThePage() async throws {
        let directory = try await seed()
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Statements", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        waitForPage(app, "Page 1 of 3")
        let back = app.buttons["editor-back"]
        guard back.waitForExistence(timeout: 10) else { return XCTFail("no way back from the document") }
        back.tap()
        if isPad {
            app.cells.containing(.any, identifier: "sidebar-home").firstMatch.tap()
        } else if app.buttons["home-tab"].waitForExistence(timeout: 5) {
            app.buttons["home-tab"].tap()
        }
        guard let hit = search(app, "invoice") else { return }
        XCTAssertEqual(hit.value as? String, "2")

        hit.tap()
        waitForPage(app, "Page 2 of 3")
    }

    func testTheHitsInFrenchAndSpanish() async throws {
        for (language, page) in [("fr", "Page 2"), ("es", "Página 2")] {
            let directory = try await seed()
            let app = launch(directory, language: language)
            defer { app.terminate() }
            guard let hit = search(app, "invoice") else { return }
            XCTAssertTrue(hit.label.contains(page), "\(language): \(hit.label)")
            XCTAssertTrue(hit.isHittable, "\(language): the hit is out of reach")
            snap(app, "hits-\(language)")
            app.terminate()
        }
    }
}
