import XCTest
import PaperNestCore
import PaperNestStore

/// Redacting a page from Document Tools: drag across a line, review the page
/// as it will be written and what goes with it, apply, and find the words
/// gone from the library. And Cancel writes nothing.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class RedactUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// A one-page digital statement whose line "ACCOUNT 55512345 SECRET" sits
    /// about 0.15 of the way down the page.
    private func seed() async throws -> (URL, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-redact-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["ACCOUNT 55512345 SECRET"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Statement.pdf")
        let item = try await store.createItem(kind: .document, name: "Statement", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        return (directory, item.id)
    }

    private func launch(_ directory: URL, language: String = "en", showingRedact: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Statement", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        if showingRedact { app.launchArguments += ["-PaperNestDebugShowRedact", "YES"] }
        app.launch()
        return app
    }

    private func page(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["redact-page"]
    }

    /// Drags across the statement's line of text, edge to edge.
    private func markTheLine(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let target = page(app)
        guard target.waitForExistence(timeout: 30) else {
            XCTFail("the Redact screen did not open", file: file, line: line); return false
        }
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.11))
            .press(forDuration: 0.15, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.21)))
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, target.value as? String != "1" { usleep(100_000) }
        XCTAssertEqual(target.value as? String, "1", "the drag did not mark an area", file: file, line: line)
        return target.value as? String == "1"
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let folder = URL(fileURLWithPath: "/tmp/pn-redact-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testARedactedLineIsGoneFromThePageAndTheLibrary() async throws {
        let (directory, itemID) = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard app.images["document-page-image"].waitForExistence(timeout: 30) else { return XCTFail("no document") }
        let redact = app.buttons["utilities-redact"]
        app.revealInDocumentTools(redact)
        redact.tap()
        guard markTheLine(app) else { return }
        snap(app, "marked-en")

        app.buttons["redact-review"].tap()
        guard app.descendants(matching: .any)["redact-preview"].waitForExistence(timeout: 30) else {
            return XCTFail("no review")
        }
        for warning in ["redact-warning-flatten", "redact-warning-text", "redact-warning-undo"] {
            XCTAssertTrue(app.descendants(matching: .any)[warning].exists, "\(warning) is not said")
        }
        snap(app, "review-en")
        let apply = app.buttons["redact-apply"]
        if !apply.isHittable { app.swipeUp() }
        apply.tap()
        XCTAssertTrue(apply.waitForNonExistence(timeout: 30), "the Redact screen stayed open")

        let store = try LibraryStore(directory: directory)
        let redacted = try await store.pages(of: itemID)
        guard case .image = redacted.first?.content else { return XCTFail("the page is still the PDF's page") }
        let gone = try await store.search("SECRET")
        XCTAssertTrue(gone.isEmpty, "the redacted words still answer a search")
    }

    func testCancelWritesNothing() async throws {
        let (directory, itemID) = try await seed()
        let app = launch(directory, showingRedact: true)
        defer { app.terminate() }
        guard markTheLine(app) else { return }
        app.buttons["redact-cancel"].tap()
        XCTAssertTrue(page(app).waitForNonExistence(timeout: 10))

        let store = try LibraryStore(directory: directory)
        guard case .pdfPage = try await store.pages(of: itemID).first?.content else {
            return XCTFail("cancelling changed the page")
        }
    }

    /// The marking bar and the review in French and Spanish, for the layout
    /// review: Review and Redact Page in reach.
    func testTheScreenInFrenchAndSpanish() async throws {
        for language in ["fr", "es"] {
            let (directory, _) = try await seed()
            let app = launch(directory, language: language, showingRedact: true)
            defer { app.terminate() }
            guard markTheLine(app) else { return }
            XCTAssertTrue(app.buttons["redact-review"].isHittable, "\(language): Review is out of reach")
            snap(app, "marked-\(language)")
            app.buttons["redact-review"].tap()
            guard app.buttons["redact-apply"].waitForExistence(timeout: 30) else { return XCTFail("\(language): no review") }
            XCTAssertTrue(app.buttons["redact-apply"].isHittable, "\(language): Redact Page is out of reach")
            snap(app, "review-\(language)")
            app.terminate()
        }
    }
}
