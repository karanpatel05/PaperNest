import XCTest
import PaperNestCore
import PaperNestStore

/// Adding a page of the new papers from the Insert tool: the page is the
/// paper chosen, a meeting page arrives with its headings in the reader's
/// language, and every paper is offered. Checked by reading the library back
/// from disk.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class StationeryUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func open(language: String) async throws -> (XCUIApplication, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-stationery-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Stationery", pages: [
            .init(sourceSize: LibraryStore.notebookPageSize, content: .template(.lined))
        ], assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Stationery", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        XCTAssertTrue(app.buttons["studio-tool-lasso"].waitForExistence(timeout: 30))
        return (app, store, item.id)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-stationery-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// A tool on the main toolbar, scrolled into reach on a phone.
    private func tool(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "no \(identifier)")
        let bar = app.scrollViews["notebook-tool-bar"]
        let reach = bar.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 10, dy: 0)
        for _ in 0..<8 where button.frame.midX > reach.maxX { bar.swipeLeft() }
        for _ in 0..<8 where button.frame.midX < reach.minX { bar.swipeRight() }
        return button
    }

    /// A card in the sideways row, brought fully into view by short, slow
    /// drags towards it: a swipe flings the row past the card.
    private func bringIntoView(_ card: XCUIElement, in row: XCUIElement) {
        for _ in 0..<12 {
            let visible = row.frame
            if card.isHittable && card.frame.minX >= visible.minX - 1 && card.frame.maxX <= visible.maxX + 1 { return }
            let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            let towards: CGFloat = card.frame.midX > visible.midX ? -110 : 110
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: towards, dy: 0)),
                        withVelocity: .slow, thenHoldForDuration: 0.15)
        }
    }

    private func headings(_ store: LibraryStore, _ page: PageID) async throws -> [String] {
        try await store.objects(on: page).compactMap { if case .text(let box) = $0.payload { box.text } else { nil } }
    }

    private func addMeetingPage(language: String, title: String) async throws {
        let (app, store, item) = try await open(language: language)
        defer { app.terminate() }
        tool("studio-tool-insert", in: app).tap()
        let meeting = app.buttons["insert-page-meeting"]
        XCTAssertTrue(meeting.waitForExistence(timeout: 10), "the Insert panel did not open")
        snap(app, "insert-\(language)")
        // Every paper is offered, in a row that scrolls sideways.
        let row = app.scrollViews["insert-page-papers"]
        for paper in ["blank", "lined", "grid", "dotted", "cornell", "checklist", "meeting", "planner", "form"] {
            let card = app.buttons["insert-page-\(paper)"]
            bringIntoView(card, in: row)
            XCTAssertTrue(card.isHittable, "\(language): the \(paper) paper cannot be reached")
        }
        bringIntoView(meeting, in: row)
        // The panel's other tools are still in view beside the papers.
        XCTAssertTrue(app.buttons["insert-date-time"].exists, "\(language): the papers pushed the other tools out")
        meeting.tap()

        var pages: [Page] = []
        for _ in 0..<40 {
            pages = try await store.pages(of: item)
            if pages.count == 2 { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(pages.count, 2, "\(language): no page was added")
        guard let added = pages.last else { return }
        XCTAssertEqual(added.content, .template(.meeting))
        let written = try await headings(store, added.id)
        XCTAssertEqual(written.count, 5, "\(language): \(written)")
        XCTAssertEqual(written.first, title, "\(language): the title heading is not in the reader's language")
        let firstPage = try await headings(store, pages[0].id)
        XCTAssertTrue(firstPage.isEmpty, "the lined page gained headings")
        try await Task.sleep(for: .milliseconds(600))
        snap(app, "meeting-page-\(language)")
    }

    func testAMeetingPageArrivesWithItsHeadings() async throws {
        try await addMeetingPage(language: "en", title: "Meeting")
    }

    func testTheHeadingsAreInTheReadersLanguage() async throws {
        try await addMeetingPage(language: "fr", title: "Réunion")
        try await addMeetingPage(language: "es", title: "Reunión")
    }
}
