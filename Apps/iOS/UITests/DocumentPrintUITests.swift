import XCTest
import PaperNestCore
import PaperNestStore

/// Print, from the document's title menu to the system's print panel.
@MainActor final class DocumentPrintUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-print-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// A three-page digital PDF.
    private func openReport(language: String = "en") async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-print-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["Quarterly budget review", "Nothing on this one", "Final budget"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Report.pdf")
        _ = try await store.createItem(kind: .document, name: "Report", pages: (0..<3).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Report", "-AppleLanguages", "(\(language))"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        // The page as well as the toolbar: a tap on the title in the first
        // second, while the document was still loading, once left no menu up.
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 15))
        return app
    }

    private func openTitleMenu(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Report")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "no title to open the menu from", file: file, line: line)
        title.tap()
    }

    /// The system's print panel. Its bar is titled Options on iOS 26 and 27.
    private func printPanel(_ app: XCUIApplication) -> XCUIElement {
        app.navigationBars["Options"]
    }

    /// The panel's own way out: "Cancel" on iOS 27, "Close" on iPadOS 26.
    private func dismissPrintPanel(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let panel = printPanel(app)
        let button = panel.buttons.matching(NSPredicate(format: "label IN %@", ["Cancel", "Close"])).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5), "the print panel has no way out", file: file, line: line)
        button.tap()
        XCTAssertTrue(panel.waitForNonExistence(timeout: 10), file: file, line: line)
    }

    private func choosePrint(_ app: XCUIApplication, named name: String = "Print…",
                             file: StaticString = #filePath, line: UInt = #line) {
        openTitleMenu(app, file: file, line: line)
        let item = app.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(name) is not in the title menu", file: file, line: line)
        item.tap()
    }

    func testPrintFromTheTitleMenuHandsTheWholeDocumentToThePrintPanel() async throws {
        let app = try await openReport()
        defer { app.terminate() }

        choosePrint(app)
        let panel = printPanel(app)
        XCTAssertTrue(panel.waitForExistence(timeout: 20), "the print panel did not appear")
        // The panel previews what it was given: three pages, the first of
        // them here. Only the panel has cells; the editor's page is an image.
        let firstPage = app.cells["Page 1 of 3"]
        XCTAssertTrue(firstPage.waitForExistence(timeout: 10), "the panel is not showing a three-page document")
        XCTAssertTrue(app.staticTexts["Pages 1-3"].exists, "the panel's range is not the whole document")
        snap(app, "panel")

        // Cancelling leaves the editor as it was, and able to print again:
        // the document made for the first panel is gone, a new one is made.
        dismissPrintPanel(app)
        XCTAssertEqual(app.images["document-page-image"].label, "Page 1 of 3")
        XCTAssertTrue(app.buttons["editor-find"].isHittable)

        choosePrint(app)
        XCTAssertTrue(printPanel(app).waitForExistence(timeout: 20), "Print did not work a second time")
        XCTAssertTrue(app.cells["Page 1 of 3"].waitForExistence(timeout: 10))
        dismissPrintPanel(app)
    }

    func testPrintIsInTheTitleMenuInFrenchAndSpanish() async throws {
        for (language, name) in [("fr", "Imprimer…"), ("es", "Imprimir…")] {
            let app = try await openReport(language: language)
            openTitleMenu(app)
            let item = app.buttons[name]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "\(name) is not in the \(language) title menu")
            XCTAssertTrue(item.isEnabled)
            snap(app, "menu-\(language)")
            app.terminate()
        }
    }
}
