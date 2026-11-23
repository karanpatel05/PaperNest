import XCTest
import PaperNestCore
import PaperNestStore

/// The export sheet's Include Comments switch. XCUITest cannot read the file
/// a Copy or Save hands over, so the notes in the written PDF are proved by
/// the engine (`CommentExportTests`); this proves the switch is there for a
/// PDF, starts off, turns on, says what it does, and reads in each language.
///
/// No `async` `tearDown`: clean-up goes through `addTeardownBlock`.
@MainActor final class CommentExportUITests: XCTestCase {
    private func openExport(language: String = "en") async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-comment-export-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Notes", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let page = try await store.pages(of: item.id)[0]
        _ = try await store.setPageComment(on: page.id, replacing: nil, text: "Check the total")
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Notes", "-PaperNestDebugShowExport", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        let pdf = app.buttons["export-format-pdf"]
        XCTAssertTrue(pdf.waitForExistence(timeout: 30), "the export sheet did not open")
        pdf.tap()
        return app
    }

    /// Scrolls the export form until `element` can be tapped above the
    /// sheet's bottom bar.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let form = app.collectionViews.containing(.button, identifier: "export-format-pdf").firstMatch
        let frame = form.exists ? form.frame : app.frame
        let bar = app.buttons["export-destination-save"]
        func inSight() -> Bool {
            element.exists && element.isHittable && (!bar.exists || element.frame.maxY < bar.frame.minY - 8)
        }
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        for _ in 0..<10 where !inSight() {
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -220)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    func testIncludeCommentsStartsOffAndTurnsOn() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        let toggle = app.switches["export-comments"]
        reveal(toggle, in: app)
        XCTAssertTrue(toggle.exists, "no Include Comments switch for a PDF")
        XCTAssertEqual(toggle.value as? String, "0", "comments must stay out unless asked")
        XCTAssertFalse(app.staticTexts["Each page\u{2019}s comments are added as notes that other PDF apps can open."].exists)
        toggle.flipSwitch()
        XCTAssertEqual(toggle.value as? String, "1", "the switch did not turn on")
        let note = app.staticTexts["Each page\u{2019}s comments are added as notes that other PDF apps can open."]
        reveal(note, in: app)
        XCTAssertTrue(note.exists, "no note saying what the switch does")

        // Not offered for a picture: a PNG has nowhere to keep a note.
        let png = app.buttons["export-format-png"]
        for _ in 0..<6 where !png.isHittable { app.swipeDown(velocity: .slow) }
        if png.exists {
            png.tap()
            XCTAssertFalse(app.switches["export-comments"].exists, "Include Comments offered for a PNG")
        }
    }

    func testIncludeCommentsInFrenchAndSpanish() async throws {
        for (language, label) in [("fr", "Inclure les commentaires"), ("es", "Incluir comentarios")] {
            let app = try await openExport(language: language)
            let toggle = app.switches["export-comments"]
            reveal(toggle, in: app)
            XCTAssertTrue(toggle.exists, "\(language): no switch")
            XCTAssertEqual(toggle.label, label, "\(language): the switch's name")
            XCTAssertLessThanOrEqual(toggle.frame.maxX, app.frame.maxX, "\(language): the switch runs off the screen")
            app.terminate()
        }
    }
}
