import XCTest
import PaperNestCore
import PaperNestStore

/// Find in a document, driven the way a reader drives it: open the bar, type,
/// step through the hits, close it.
@MainActor final class DocumentFindUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-find-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// A three-page digital PDF: "budget" on pages 1 and 3, twice on page 1.
    private func openReport(language: String = "en") async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-find-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["Quarterly budget review\nThe budget grew", "Nothing on this one",
                                                      "Final budget"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Report.pdf")
        _ = try await store.createItem(kind: .document, name: "Report", pages: (0..<3).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset])
        return launch(directory, item: "Report", language: language)
    }

    private func launch(_ directory: URL, item: String, language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", item, "-AppleLanguages", "(\(language))"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        return app
    }

    private func status(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "find-status").firstMatch
    }

    private func waitForStatus(_ app: XCUIApplication, _ expected: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let element = status(app)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(element.exists && element.label == expected) { usleep(100_000) }
        XCTAssertEqual(element.exists ? element.label : "<absent>", expected, file: file, line: line)
    }

    private func waitForPage(_ app: XCUIApplication, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let page = app.images["document-page-image"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(page.exists && page.label == label) { usleep(100_000) }
        XCTAssertEqual(page.exists ? page.label : "<absent>", label, file: file, line: line)
    }

    private func waitForHighlights(_ app: XCUIApplication, _ count: String,
                                   file: StaticString = #filePath, line: UInt = #line) {
        let highlights = app.descendants(matching: .any).matching(identifier: "find-highlights").firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(highlights.exists && highlights.value as? String == count) { usleep(100_000) }
        XCTAssertEqual(highlights.exists ? (highlights.value as? String ?? "<no value>") : "<absent>", count,
                       file: file, line: line)
    }

    func testFindCountsHitsStepsAcrossPagesAndCloses() async throws {
        let app = try await openReport()
        defer { app.terminate() }
        waitForPage(app, "Page 1 of 3")

        app.buttons["editor-find"].tap()
        let field = app.textFields["find-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // The bar opens ready to type into.
        field.typeText("BUDGET")

        waitForStatus(app, "1 of 3")
        // Every letter landed: the bar reflowing as the count appeared once
        // took the keyboard away after the first one.
        XCTAssertEqual(field.value as? String, "BUDGET")
        waitForHighlights(app, "2")
        snap(app, "find-first-hit")

        app.buttons["find-next"].tap()
        waitForStatus(app, "2 of 3")
        waitForPage(app, "Page 1 of 3")

        // The third hit is two pages on: the page turns to it.
        app.buttons["find-next"].tap()
        waitForStatus(app, "3 of 3")
        waitForPage(app, "Page 3 of 3")
        waitForHighlights(app, "1")
        snap(app, "find-third-hit")

        // Past the last hit is the first again, and back from the first is the last.
        app.buttons["find-next"].tap()
        waitForStatus(app, "1 of 3")
        waitForPage(app, "Page 1 of 3")
        app.buttons["find-previous"].tap()
        waitForStatus(app, "3 of 3")
        waitForPage(app, "Page 3 of 3")

        // A word that is not there.
        app.buttons["find-clear"].tap()
        field.typeText("zebra")
        waitForStatus(app, "No Results")
        XCTAssertFalse(app.buttons["find-next"].isEnabled)

        app.buttons["find-done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "find-highlights").count, 0,
                       "highlights were left on the page after find closed")
        // The page is still the reader's: the editor's own controls answer.
        XCTAssertTrue(app.buttons["editor-panels"].isHittable)
    }

    /// Words typed onto a notebook page are found, and a page with nothing on
    /// it says there is no text rather than "No Results".
    func testFindReadsTypedTextAndSaysWhenThereIsNone() async throws {
        let directory = URL(fileURLWithPath: "/tmp/papernest-find-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Notes", pages: (0..<2).map { _ in
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        }, assets: [])
        let app = launch(directory, item: "Notes", language: "en")
        defer { app.terminate() }

        app.buttons["editor-find"].tap()
        let field = app.textFields["find-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("bank")
        waitForStatus(app, "No Text")
        XCTAssertTrue(app.staticTexts["find-no-text-detail"].exists)
        snap(app, "find-no-text")
        app.buttons["find-done"].tap()
        app.terminate()

        // Now with something typed on the second page.
        let pages = try await store.pages(of: item.id)
        try await store.placeText("Call the bank on Monday", on: pages[1].id,
                                  frame: CGRect(x: 80, y: 200, width: 300, height: 40), fontSize: 18,
                                  color: .black, alignment: .leading)
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        app.buttons["editor-find"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("the bank")
        waitForStatus(app, "1 of 1")
        waitForHighlights(app, "1")
        snap(app, "find-typed-text")
    }

    /// The bar has to hold its words in the longer languages, at phone width.
    func testFindBarFitsInFrenchAndSpanish() async throws {
        for (language, none, count) in [("fr", "Aucun résultat", "1 sur 3"), ("es", "Sin resultados", "1 de 3")] {
            let app = try await openReport(language: language)
            app.buttons["editor-find"].tap()
            let field = app.textFields["find-field"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText("budget")
            waitForStatus(app, count)
            XCTAssertEqual(field.value as? String, "budget", "the field lost the keyboard while typing, in \(language)")
            app.buttons["find-clear"].tap()
            field.typeText("zebra")
            waitForStatus(app, none)
            snap(app, "find-\(language)")

            // Everything in the bar is on screen and nothing overlaps.
            let window = app.windows.firstMatch.frame
            let parts = [field, status(app), app.buttons["find-previous"], app.buttons["find-next"],
                         app.buttons["find-done"]]
            for part in parts {
                XCTAssertTrue(window.contains(part.frame), "\(part) runs off the screen in \(language)")
            }
            // The bar may take one row or two; either way no two parts share space.
            for (index, first) in parts.enumerated() {
                for second in parts[(index + 1)...] {
                    XCTAssertFalse(first.frame.insetBy(dx: 1, dy: 1).intersects(second.frame),
                                   "\(first) overlaps \(second) in \(language)")
                }
            }
            XCTAssertGreaterThanOrEqual(field.frame.width, 150, "the field has no room to type in, in \(language)")
            app.terminate()
        }
    }
}
