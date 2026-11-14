import XCTest
import PaperNestCore
import PaperNestStore

/// A PDF whose author switched copying off — every USCIS form is one — in the
/// running app: it opens, its words can be marked but not copied out, and
/// Export offers the one format that keeps the author's limits.
@MainActor final class RestrictedPDFUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-restricted-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Two pages, copying off, printing on. Page 1's first line is
    /// "Quarterly budget review", where `TextSelectionUITests` expects it.
    private func openForm(language: String = "en") async throws -> (XCUIApplication, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-restricted-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.restrictedPDF(pages: ["Quarterly budget review\nThe budget grew", "Signature"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Form.pdf")
        let item = try await store.createItem(kind: .document, name: "Form", pages: (0..<2).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Form", "-AppleLanguages", "(\(language))"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 15))
        return (app, store, item.id)
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { usleep(100_000) }
        XCTAssertTrue(condition(), what, file: file, line: line)
    }

    func testARestrictedFormOpensItsWordsCanBeMarkedButNotCopied() async throws {
        let (app, store, item) = try await openForm()
        defer { app.terminate() }
        let page = app.images["document-page-image"]
        // It opens: this is the file PaperNest used to turn away.
        XCTAssertEqual(page.label, "Page 1 of 2")
        let selection = app.descendants(matching: .any).matching(identifier: "text-selection").firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 10), "the page's words were not read")

        // Press and hold on "Quarterly".
        page.coordinate(withNormalizedOffset: CGVector(dx: 109.0 / 612, dy: 134.0 / 792)).press(forDuration: 0.9)
        waitFor("pressing a word did not select it") { (selection.value as? String) == "Quarterly" }
        let copy = app.buttons["text-selection-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertFalse(copy.isEnabled, "Copy is offered for a PDF whose author switched copying off")
        snap(app, "selection")

        // Marking is not copying: a highlight is saved as it would be anywhere.
        let highlight = app.buttons["text-selection-highlight"]
        XCTAssertTrue(highlight.isEnabled)
        highlight.tap()
        waitFor("the highlight was not saved") { (page.value as? String) == "1 stroke" }
        let pageID = try await store.pages(of: item)[0].id
        let saved = try await store.objects(on: pageID)
        XCTAssertEqual(saved.count, 1)
    }

    func testExportOffersOnlyTheFormatThatKeepsTheAuthorsLimits() async throws {
        for (language, phrase) in [("en", "only as a PDF"), ("fr", "qu’en PDF"), ("es", "como PDF")] {
            let (app, _, _) = try await openForm(language: language)
            app.buttons["editor-export"].tap()
            let pdf = app.buttons["export-format-pdf"]
            XCTAssertTrue(pdf.waitForExistence(timeout: 10), "the export sheet did not open in \(language)")
            for other in ["jpeg", "png", "heic", "txt", "docx"] {
                XCTAssertFalse(app.buttons["export-format-\(other)"].exists, "\(other) is offered for a restricted PDF")
            }
            let note = app.staticTexts["export-restricted-note"]
            XCTAssertTrue(note.waitForExistence(timeout: 5), "nothing says why the other formats are missing")
            XCTAssertTrue(note.label.contains(phrase), "the \(language) note says: \(note.label)")
            let window = app.windows.firstMatch.frame
            XCTAssertTrue(window.contains(note.frame), "the \(language) note runs off the screen: \(note.frame)")
            snap(app, "export-\(language)")
            app.terminate()
        }
    }
}
