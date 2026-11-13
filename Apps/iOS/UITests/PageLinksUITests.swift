import XCTest
import PaperNestCore
import PaperNestStore

/// Following the links a PDF carries, and going to a page by its number.
@MainActor final class PageLinksUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-find-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Three pages. Page 1 carries a link to page 3 and a link to the web.
    private func openLinkedReport() async throws -> XCUIApplication {
        // Written by hand, so this is a test of reading a link, not of the
        // simulator's PDF writer. See `handBuiltLinkedPDF`.
        let data = SyntheticDocuments.handBuiltLinkedPDF()

        let directory = URL(fileURLWithPath: "/tmp/papernest-links-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Report.pdf")
        _ = try await store.createItem(kind: .document, name: "Report", pages: (0..<3).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Report", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        return app
    }

    private func waitForPage(_ app: XCUIApplication, _ label: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let page = app.images["document-page-image"]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(page.exists && page.label == label) { usleep(100_000) }
        XCTAssertEqual(page.exists ? page.label : "<absent>", label, file: file, line: line)
    }

    func testALinkToAPageTurnsToItAndAWebLinkAsksFirst() async throws {
        let app = try await openLinkedReport()
        defer { app.terminate() }
        waitForPage(app, "Page 1 of 3")
        let internalLink = app.buttons["Go to page 3"]
        let webLink = app.buttons["Link: https://example.com/invoice"]
        XCTAssertTrue(internalLink.waitForExistence(timeout: 10))
        XCTAssertTrue(webLink.exists)
        XCTAssertEqual(app.buttons.matching(identifier: "page-link").count, 2)

        // A link out of the document shows where it goes and waits.
        webLink.tap()
        let alert = app.alerts["Open this link?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["https://example.com/invoice"].exists, "the address is not shown before opening")
        snap(app, "link-ask")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        waitForPage(app, "Page 1 of 3")

        // A link to a page of this document turns straight to it.
        internalLink.tap()
        waitForPage(app, "Page 3 of 3")
        XCTAssertEqual(app.buttons.matching(identifier: "page-link").count, 0, "page 3 has no links of its own")
    }

    func testGoToPageTakesANumberFromTheTitleMenu() async throws {
        let app = try await openLinkedReport()
        defer { app.terminate() }
        waitForPage(app, "Page 1 of 3")

        func goTo(_ typed: String) {
            // The title carries the document's menu.
            let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Report"))
                .firstMatch
            XCTAssertTrue(title.waitForExistence(timeout: 5), "no title to open the menu from")
            title.tap()
            let item = app.buttons["Go to Page…"]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Go to Page… is not in the title menu")
            item.tap()
            let alert = app.alerts["Go to Page…"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            XCTAssertTrue(alert.staticTexts["This document has 3 pages."].exists)
            let field = alert.textFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.typeText(typed)
            alert.buttons["Go"].tap()
            XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        }

        goTo("3")
        waitForPage(app, "Page 3 of 3")
        // Past the end means the end, and before the start the start.
        goTo("0")
        waitForPage(app, "Page 1 of 3")
        goTo("250")
        waitForPage(app, "Page 3 of 3")
    }
}
