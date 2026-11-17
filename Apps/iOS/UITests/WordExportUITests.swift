import XCTest
import PaperNestCore
import PaperNestStore

/// Word export's two layouts, as someone choosing between them meets them.
///
/// The document is a two-page notebook with nothing written in it, which is
/// what makes the difference visible: there are no words for an editable
/// Word file, so that layout says why it cannot be made, and a Word file of
/// page pictures is made all the same. Two pages also prove Copy is offered
/// for a Word file of several pages — it is one file, not a ZIP, and the
/// sheet used to refuse it.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure, either left the runner idle in tear-down (2026-11-16, iPad and
/// iPhone) instead of ending the test. A step that later steps depend on
/// returns instead, and the library goes in a teardown block.
@MainActor final class WordExportUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func openExport(language: String = "en") async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-word-export-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        _ = try await store.createItem(kind: .notebook, name: "Sketches", pages: (0..<2).map { _ in
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        }, assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Sketches", "-PaperNestDebugShowExport", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        let word = app.buttons["export-format-docx"]
        XCTAssertTrue(word.waitForExistence(timeout: 30), "the export sheet did not open")
        word.tap()
        XCTAssertTrue(word.isSelected)
        return app
    }

    /// The export form's own scrolling list. On iPad the sheet is a panel
    /// beside the page, and a swipe on the app scrolls the page instead.
    private func exportForm(_ app: XCUIApplication) -> XCUIElement {
        app.collectionViews.containing(.button, identifier: "export-format-docx").firstMatch
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let folder = URL(fileURLWithPath: "/tmp/pn-word-export-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testPageImagesExportANotebookWithNoWordsInIt() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        let text = app.buttons["export-docx-layout-editableText"]
        let images = app.buttons["export-docx-layout-pageImages"]
        guard text.waitForExistence(timeout: 5) else { return XCTFail("Word offers no choice of layout") }
        XCTAssertTrue(text.isSelected, "Word opens on editable text, as before")
        XCTAssertFalse(images.isSelected)
        XCTAssertTrue(app.staticTexts["export-words-only-note"].exists, "editable text says it keeps only words")

        images.tap()
        XCTAssertTrue(images.isSelected)
        XCTAssertFalse(text.isSelected)
        XCTAssertTrue(app.buttons["export-format-docx"].isSelected, "choosing a layout changed the format")
        XCTAssertTrue(app.staticTexts["export-docx-images-note"].waitForExistence(timeout: 5),
                      "page images says its words cannot be edited")
        XCTAssertFalse(app.staticTexts["export-words-only-note"].exists,
                       "a Word file of pictures must not claim to leave pictures out")
        // A picture's controls appear: its resolution among them.
        snap(app, "word-page-images-en")
        let resolution = app.buttons["200 dpi"].firstMatch
        let form = exportForm(app)
        for _ in 0..<5 where !resolution.exists && form.exists { form.swipeUp() }
        XCTAssertTrue(resolution.exists, "page images shows no resolution")
        snap(app, "word-page-images-options-en")

        let copy = app.buttons["export-destination-copy"]
        guard copy.waitForExistence(timeout: 5) else { return XCTFail("no Copy") }
        XCTAssertTrue(copy.isEnabled, "two pages of Word are one file, so Copy is offered")
        copy.tap()
        XCTAssertTrue(app.descendants(matching: .any)["export-copied"].waitForExistence(timeout: 30),
                      "a notebook with no words did not export as page images")
        XCTAssertFalse(app.staticTexts["export-failed"].exists)
    }

    func testEditableTextSaysWhyANotebookWithNoWordsCannotBeExported() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["export-docx-layout-editableText"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export-docx-layout-editableText"].isSelected)

        let copy = app.buttons["export-destination-copy"]
        guard copy.waitForExistence(timeout: 5) else { return XCTFail("no Copy") }
        XCTAssertTrue(copy.isEnabled, "two pages of Word are one file, so Copy is offered")
        copy.tap()
        let failed = app.staticTexts["export-failed"]
        guard failed.waitForExistence(timeout: 30) else { return XCTFail("an editable Word file of no words was not refused") }
        XCTAssertTrue(failed.label.contains("None of these pages carry any text"), failed.label)
        XCTAssertFalse(app.descendants(matching: .any)["export-copied"].exists)
    }

    /// The tiles and the note in French and Spanish, whose words are longer:
    /// both tiles reachable, the note there, and a picture of each for the
    /// layout review.
    func testTheLayoutChoiceInFrenchAndSpanish() async throws {
        for language in ["fr", "es"] {
            let app = try await openExport(language: language)
            defer { app.terminate() }
            let text = app.buttons["export-docx-layout-editableText"]
            let images = app.buttons["export-docx-layout-pageImages"]
            guard text.waitForExistence(timeout: 5) else { return XCTFail("\(language): no layout tiles") }
            XCTAssertTrue(text.isHittable && images.isHittable, "\(language): a layout tile is out of reach")
            snap(app, "word-editable-text-\(language)")
            images.tap()
            XCTAssertTrue(images.isSelected, language)
            XCTAssertTrue(app.staticTexts["export-docx-images-note"].waitForExistence(timeout: 5), language)
            snap(app, "word-page-images-\(language)")
            app.terminate()
        }
    }
}
