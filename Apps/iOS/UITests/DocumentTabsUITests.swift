import XCTest
import PaperNestCore
import PaperNestStore

@MainActor final class DocumentTabsUITests: XCTestCase {
    func testOpenSwitchCloseAndReopenDocuments() async throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: "/tmp/papernest-tabs-\(UUID().uuidString)")
        let store = try LibraryStore(directory: directory)
        let first = try await store.createItem(kind: .notebook, name: "Tab Alpha", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let second = try await store.createItem(kind: .document, name: "Tab Beta", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
            "-PaperNestDebugOpenItem", "Tab Alpha", "-AppleLanguages", "(en)", "-libraryLayout", "list"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["document-tab-add"].waitForExistence(timeout: 20))
        app.buttons["document-tab-add"].tap()
        let documents = app.buttons["home-documents"]
        if documents.isHittable { documents.tap() }
        else {
            let row = app.cells.containing(.staticText, identifier: "All Documents").firstMatch
            if row.buttons["All Documents"].isHittable { row.buttons["All Documents"].tap() }
            else if row.isHittable { row.tap() }
        }
        let beta = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tab Beta")).firstMatch
        XCTAssertTrue(beta.waitForExistence(timeout: 10)); beta.tap()
        XCTAssertTrue(app.buttons["document-tab-add"].waitForExistence(timeout: 10))
        let menu = app.buttons["document-tabs-menu"]
        if menu.exists {
            menu.tap(); app.buttons["Tab Alpha"].firstMatch.tap()
            menu.tap(); app.buttons["Close document tab"].tap()
        } else {
            let alpha = app.buttons["document-tab-\(first.id.rawValue)"]
            XCTAssertTrue(alpha.exists); alpha.tap()
            XCTAssertEqual(alpha.value as? String, "Selected")
            app.buttons["document-tab-close-\(first.id.rawValue)"].tap()
            XCTAssertTrue(alpha.waitForNonExistence(timeout: 5), "Closing finishes its durable flush before removing the tab")
            XCTAssertTrue(app.buttons["document-tab-\(second.id.rawValue)"].exists)
        }
        XCTAssertTrue(app.navigationBars["Tab Beta"].waitForExistence(timeout: 5))
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["document-tab-add"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.navigationBars["Tab Alpha"].exists, "Closing a tab must never delete its document")
    }
}
