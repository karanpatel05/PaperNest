import XCTest

/// Owner, 2026-11-15: "all files should be editable", then "Yes, build both".
/// Word and Excel files are laid out as pages on iPhone and iPad, so they open
/// in the editor to be marked up. `scripts/ui-test-ios.sh` makes the files.
@MainActor final class OfficeImportUITests: XCTestCase {
    private static let fixtures = "/tmp/papernest-office-fixtures"

    /// Imports one file through the same path as the file picker and answers
    /// the destination sheet.
    private func importFile(_ name: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-office-import-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-PaperNestDebugImportFile", "\(Self.fixtures)/\(name)"]
        app.launch()
        XCTAssertTrue(app.buttons["import-location-save"].waitForExistence(timeout: 20), "no destination sheet for \(name)")
        app.buttons["import-location-save"].tap()
        return app
    }

    /// The editor is open on the imported document and says how many pages it has.
    private func pageCount(_ app: XCUIApplication, timeout: TimeInterval = 40) -> Int {
        XCTAssertTrue(app.buttons["editor-back"].waitForExistence(timeout: timeout), "the file did not open in the editor")
        XCTAssertFalse(app.buttons["file-preview-done"].exists, "it opened as a read-only preview")
        let page = app.images["document-page-image"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        // "Page 1 of N".
        return Int(page.label.split(separator: " ").last ?? "") ?? 0
    }

    /// The words are on the pages as text: find in the document finds them.
    private func find(_ app: XCUIApplication, _ word: String) {
        app.buttons["editor-find"].tap()
        let field = app.textFields["find-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(word)
        let status = app.descendants(matching: .any).matching(identifier: "find-status").firstMatch
        let found = NSPredicate(format: "label MATCHES %@", "[0-9]+ of [0-9]+")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: found, evaluatedWith: status)], timeout: 30), .completed,
                       "\"\(word)\" is not on the pages as text")
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testAWordFileOpensAsPagesWithItsWords() {
        let app = importFile("Proposal.docx")
        defer { app.terminate() }
        XCTAssertGreaterThanOrEqual(pageCount(app), 2, "a heading and 120 wrapped lines run past one page")
        snap(app, "office-docx")
        find(app, "Line 120 of the proposal")
    }

    func testAnOlderWordFileOpensAsPagesToo() {
        let app = importFile("Legacy proposal.doc")
        defer { app.terminate() }
        XCTAssertGreaterThanOrEqual(pageCount(app), 2)
        find(app, "Project proposal")
    }

    func testASpreadsheetOpensAsAPageWithItsCells() {
        let app = importFile("Budget.xlsx")
        defer { app.terminate() }
        XCTAssertGreaterThanOrEqual(pageCount(app), 1)
        snap(app, "office-xlsx")
        find(app, "1234.5")
    }

    /// Laying out runs on the main thread: a long file must still finish and
    /// leave the app responsive.
    func testALongWordFileStillOpens() {
        let app = importFile("Long report.docx")
        defer { app.terminate() }
        XCTAssertGreaterThanOrEqual(pageCount(app, timeout: 90), 30, "2,400 paragraphs run to dozens of pages")
        find(app, "Paragraph 2400 of a long report")
    }

    /// A file that only claims to be a spreadsheet is kept as a file, not
    /// turned into a page showing an error.
    func testABrokenSpreadsheetStaysAFile() {
        let app = importFile("Broken.xlsx")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["file-preview-done"].waitForExistence(timeout: 40), "a broken spreadsheet should stay a file")
        XCTAssertFalse(app.buttons["editor-back"].exists)
    }
}
