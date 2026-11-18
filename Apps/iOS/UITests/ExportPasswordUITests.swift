import XCTest
import PaperNestCore
import PaperNestStore

/// A password typed into the export sheet, and what the sheet says about a
/// form's fillable fields. XCUITest cannot read the file a Copy or Save hands
/// over, so what the written file asks for is proved by the engine
/// (`ProtectedFormExportTests`, `EncryptedExportTests`) and the sheet's model
/// (`ExportPasswordWorkflowTests`); this proves the typing, the refusal of a
/// password the writer cannot store, and that the protected export completes.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class ExportPasswordUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func openExport(_ name: String, document: Data, language: String = "en") async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-export-password-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let asset = try store.assets.store(document, kind: .pdf, originalFilename: "\(name).pdf")
        _ = try await store.createItem(kind: .document, name: name, pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", name, "-PaperNestDebugShowExport", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        XCTAssertTrue(app.buttons["export-format-pdf"].waitForExistence(timeout: 30), "the export sheet did not open")
        return app
    }

    /// Where the export form's own list is on screen, noted while its PDF
    /// tile is in it (the list is found by that tile, which scrolls away).
    /// On iPad the form sits beside the page list, so swiping the app would
    /// scroll the page instead.
    private var formFrame: CGRect?

    private func noteForm(in app: XCUIApplication) {
        let form = app.collectionViews.containing(.button, identifier: "export-format-pdf").firstMatch
        if formFrame == nil, form.exists { formFrame = form.frame }
    }

    /// Scrolls the export form until `element` can be tapped, above the bottom
    /// bar: down the form first, then back up, since a row scrolled out of
    /// sight is not in the list at all.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        noteForm(in: app)
        let bar = app.buttons["export-destination-save"]
        func inSight() -> Bool {
            element.exists && element.isHittable && (!bar.exists || element.frame.maxY < bar.frame.minY - 8)
        }
        func drag(_ dy: CGFloat) {
            guard let frame = formFrame else { return dy < 0 ? app.swipeUp(velocity: .slow) : app.swipeDown(velocity: .slow) }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy)),
                        withVelocity: .slow, thenHoldForDuration: 0.1)
        }
        for _ in 0..<10 where !inSight() { drag(-220) }
        for _ in 0..<14 where !inSight() { drag(220) }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-export-password-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Types into the secure field after emptying it.
    private func type(_ text: String, into field: XCUIElement, replacing count: Int) {
        field.tap()
        if count > 0 { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count)) }
        field.typeText(text)
    }

    func testAPasswordTheWriterCannotStoreIsRefusedAndAGoodOneExports() async throws {
        for language in ["en", "fr", "es"] {
            let app = try await openExport("Report", document: SyntheticDocuments.textPDF(pages: ["Quarterly report"]),
                                           language: language)
            defer { app.terminate() }
            let field = app.secureTextFields["export-password"]
            reveal(field, in: app)
            XCTAssertTrue(field.exists, "\(language): no password field")

            type("été2026", into: field, replacing: 0)
            let problem = app.staticTexts["export-password-problem"]
            XCTAssertTrue(problem.waitForExistence(timeout: 5), "\(language): an accented password was not refused")
            let copy = app.buttons["export-destination-copy"]
            XCTAssertFalse(copy.isEnabled, "\(language): Copy is offered for a password that cannot be written")
            snap(app, "refused-\(language)")

            type("correct-horse", into: field, replacing: 7)
            XCTAssertTrue(problem.waitForNonExistence(timeout: 5), "\(language): the refusal stayed")
            XCTAssertTrue(copy.isEnabled, "\(language): Copy is off for a usable password")
            copy.tap()
            XCTAssertTrue(app.descendants(matching: .any)["export-copied"].waitForExistence(timeout: 30),
                          "\(language): the protected export did not finish")
            app.terminate()
        }
    }

    /// A fillable form: the sheet says its fields are kept when the export is
    /// the unchanged original — a password included — and lost on other paper.
    func testAFormSaysWhetherItsFieldsStayFillable() async throws {
        let app = try await openExport("Agreement", document: SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")]))
        defer { app.terminate() }
        let note = app.staticTexts["export-form-fields"]
        reveal(note, in: app)
        XCTAssertTrue(note.waitForExistence(timeout: 20), "the sheet says nothing about the form's fields")
        XCTAssertEqual(note.value as? String, "kept")
        snap(app, "form-kept-en")

        let field = app.secureTextFields["export-password"]
        reveal(field, in: app)
        type("correct-horse", into: field, replacing: 0)
        // Return puts the keyboard away; over the form it would stop the scrolling.
        field.typeText("\n")
        reveal(note, in: app)
        for _ in 0..<20 where (note.value as? String) != "kept" { usleep(250_000) }
        XCTAssertEqual(note.value as? String, "kept", "a password should no longer cost the form")

        let a4 = app.buttons["A4"]
        reveal(a4, in: app)
        a4.tap()
        reveal(note, in: app)
        for _ in 0..<20 where (note.value as? String) != "lost" { usleep(250_000) }
        XCTAssertEqual(note.value as? String, "lost", "other paper redraws the page")
        snap(app, "form-lost-en")
    }
}
