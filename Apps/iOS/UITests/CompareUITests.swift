import XCTest
import PaperNestCore
import PaperNestStore

/// Comparing a document with a newer copy from Document Tools: one changed
/// word and one added page, shown side by side, laid over each other and as
/// text, and every view says what was compared.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class CompareUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// "Statement" (two pages) and "Statement v2": its second page says
    /// April where the first said March, and it has a third page.
    private func seed() async throws -> URL {
        let directory = URL(fileURLWithPath: "/tmp/papernest-compare-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        func add(_ name: String, _ texts: [String]) async throws {
            let data = SyntheticDocuments.textPDF(pages: texts)
            let asset = try store.assets.store(data, kind: .pdf, originalFilename: "\(name).pdf")
            _ = try await store.createItem(kind: .document, name: name, pages: texts.indices.map {
                .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
            }, assets: [asset])
        }
        try await add("Statement v2", ["Chapter one begins with the harbour at dawn", "Invoice total 42 paid in April",
                                       "An appendix about the lighthouse keeper"])
        try await add("Statement", ["Chapter one begins with the harbour at dawn", "Invoice total 42 paid in March"])
        return directory
    }

    private func launch(_ directory: URL, language: String = "en", showingCompare: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Statement", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        if showingCompare { app.launchArguments += ["-PaperNestDebugShowCompare", "YES"] }
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let folder = URL(fileURLWithPath: "/tmp/pn-compare-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Chooses "Statement v2" and waits for the result.
    private func chooseTheNewVersion(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let choose = app.buttons["compare-choose"]
        guard choose.waitForExistence(timeout: 20) else { XCTFail("Compare did not open", file: file, line: line); return false }
        choose.tap()
        let row = app.buttons.matching(identifier: "compare-document").matching(NSPredicate(format: "label CONTAINS %@", "Statement v2")).firstMatch
        guard row.waitForExistence(timeout: 10) else { XCTFail("Statement v2 is not offered", file: file, line: line); return false }
        row.tap()
        guard element(app, "compare-summary").waitForExistence(timeout: 30) else {
            XCTFail("no comparison", file: file, line: line); return false
        }
        return true
    }

    func testComparingWithANewerCopyShowsTheChangedWordAndTheAddedPage() async throws {
        let directory = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard app.images["document-page-image"].waitForExistence(timeout: 30) else { return XCTFail("no document") }
        let compare = app.buttons["utilities-compare"]
        app.revealInDocumentTools(compare)
        compare.tap()
        guard chooseTheNewVersion(app) else { return }

        XCTAssertEqual(element(app, "compare-summary").value as? String, "text:1 picture:0 added:1 removed:0 moved:0")
        // It opens on the first page that differs: page 2 of 3, changed, compared by its words.
        XCTAssertEqual(element(app, "compare-position").value as? String, "2/3")
        XCTAssertEqual(element(app, "compare-page-status").value as? String, "changed")
        XCTAssertEqual(element(app, "compare-method").value as? String, "text-embedded")
        let oldPage = element(app, "compare-old-page"), newPage = element(app, "compare-new-page")
        XCTAssertTrue(oldPage.waitForExistence(timeout: 10))
        XCTAssertEqual(oldPage.value as? String, "1", "the removed word is not marked on the original")
        XCTAssertEqual(newPage.value as? String, "1", "the added word is not marked on the new page")
        snap(app, "side-by-side-en")

        let modes = app.segmentedControls["compare-mode"]
        modes.buttons["Overlay"].tap()
        XCTAssertTrue(element(app, "compare-overlay").waitForExistence(timeout: 15), "no overlay")
        snap(app, "overlay-en")
        modes.buttons["Text"].tap()
        let change = element(app, "compare-change-1")
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        XCTAssertTrue(change.label.contains("March") && change.label.contains("April"), change.label)
        snap(app, "text-en")

        modes.buttons["Side by Side"].tap()
        let next = app.buttons["compare-next"]
        if !next.isHittable { app.swipeUp() }
        next.tap()
        XCTAssertEqual(element(app, "compare-position").value as? String, "3/3")
        XCTAssertEqual(element(app, "compare-page-status").value as? String, "added")
        XCTAssertEqual(element(app, "compare-old-page").value as? String, "missing")
        XCTAssertFalse(next.isEnabled, "Next past the last page")

        app.buttons["compare-done"].tap()
        XCTAssertTrue(app.buttons["compare-choose"].waitForNonExistence(timeout: 10), "Compare stayed open")
    }

    /// French and Spanish: the views, the result and Done in reach.
    func testTheScreenInFrenchAndSpanish() async throws {
        for language in ["fr", "es"] {
            let directory = try await seed()
            let app = launch(directory, language: language, showingCompare: true)
            defer { app.terminate() }
            guard chooseTheNewVersion(app) else { return }
            let modes = app.segmentedControls["compare-mode"]
            XCTAssertTrue(modes.waitForExistence(timeout: 10))
            XCTAssertEqual(modes.buttons.count, 3)
            for index in 0..<3 { XCTAssertTrue(modes.buttons.element(boundBy: index).isHittable, "\(language): view \(index)") }
            XCTAssertTrue(app.buttons["compare-done"].isHittable, "\(language): Done is out of reach")
            snap(app, "side-by-side-\(language)")
            modes.buttons.element(boundBy: 2).tap()
            XCTAssertTrue(element(app, "compare-change-1").waitForExistence(timeout: 5), "\(language): no text change")
            snap(app, "text-\(language)")
            app.terminate()
        }
    }
}
