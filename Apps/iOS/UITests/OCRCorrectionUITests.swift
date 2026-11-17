import XCTest
import PaperNestCore
import PaperNestStore

/// Correcting recognized text, from the OCR panel to Find.
///
/// The page is a scan with a recognition result saved straight into the
/// library — no Vision run, so the words are known — and one of them misread:
/// "Invocie". The test corrects it in the editor, then checks the library
/// holds the correction and Find answers the corrected word and not the
/// misread one, which is the whole point of correcting it.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure, either left the runner idle in tear-down (2026-11-16, iPad and
/// iPhone). Steps return instead, and the library goes in a teardown block.
@MainActor final class OCRCorrectionUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// `TextRecognizer.engineVersion`. The same as the app's, so automatic
    /// recognition at launch takes the seeded result for current and leaves
    /// it alone instead of reading the synthetic picture again.
    private let engineVersion = "vision.accurate.1"

    private func seed() async throws -> (URL, PageID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-ocr-correction-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let png = SyntheticDocuments.image(width: 1200, height: 1600, type: .png)
        let asset = try store.assets.store(png, kind: .png, originalFilename: "Receipt.png")
        let item = try await store.createItem(kind: .document, name: "Receipt scan", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(asset.id)),
        ], assets: [asset])
        let page = try await store.pages(of: item.id)[0]
        try await store.saveRecognition(PageRecognition(
            pageID: page.id, sourceRevision: page.revision, engineVersion: engineVersion, status: .completed,
            languages: ["en-US"], lines: [
                RecognizedLine(text: "Invocie total 42", box: .exact(x: 0.1, y: 0.3, width: 0.6, height: 0.04),
                               confidence: 0.3),
                RecognizedLine(text: "Thank you", box: .exact(x: 0.1, y: 0.4, width: 0.4, height: 0.04),
                               confidence: 1),
            ]))
        return (directory, page.id)
    }

    private func launch(_ directory: URL, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Receipt scan", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        return app
    }

    /// Opens the OCR panel and brings Correct Text into reach.
    private func openCorrection(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard app.images["document-page-image"].waitForExistence(timeout: 30) else {
            XCTFail("the document did not open", file: file, line: line); return false
        }
        let recognize = app.buttons["editor-recognize"]
        if !recognize.isHittable, !app.scrollViews["pdf-tools-list"].exists, !app.buttons["editor-panels"].exists,
           app.buttons["OverflowBarButtonItem"].exists {
            app.buttons["OverflowBarButtonItem"].tap()
        }
        app.revealInDocumentTools(recognize)
        recognize.tap()
        let status = app.descendants(matching: .any)["ocr-current-status"]
        guard status.waitForExistence(timeout: 10) else {
            XCTFail("the OCR panel did not open", file: file, line: line); return false
        }
        waitForValue(status, "recognized", file: file, line: line)
        let open = app.buttons["ocr-correct-open"]
        // The panel's own list, not the app: on iPad the panel sits beside
        // the page, and a swipe on the app scrolls the page.
        let panel = app.scrollViews.containing(.any, identifier: "ocr-page-count").firstMatch
        for _ in 0..<6 where !(open.exists && open.isHittable) && panel.exists { panel.swipeUp() }
        guard open.exists && open.isHittable else {
            XCTFail("Correct Text is not offered for a recognized page", file: file, line: line); return false
        }
        open.tap()
        guard app.textViews["ocr-line-0"].waitForExistence(timeout: 10)
                || app.textFields["ocr-line-0"].waitForExistence(timeout: 2) else {
            XCTFail("the editor did not open", file: file, line: line); return false
        }
        return true
    }

    private func lineField(_ app: XCUIApplication, _ index: Int) -> XCUIElement {
        let view = app.textViews["ocr-line-\(index)"]
        return view.exists ? view : app.textFields["ocr-line-\(index)"]
    }

    private func waitForValue(_ element: XCUIElement, _ expected: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(element.exists && element.value as? String == expected) { usleep(100_000) }
        XCTAssertEqual(element.exists ? (element.value as? String ?? "<no value>") : "<absent>", expected,
                       file: file, line: line)
    }

    /// Replaces a field's text: the cursor to the end, every character out,
    /// then the new text in.
    private func replaceText(of field: XCUIElement, with text: String) {
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.5)).tap()
        let current = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count + 2))
        if !text.isEmpty { field.typeText(text) }
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let folder = URL(fileURLWithPath: "/tmp/pn-ocr-correction-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testACorrectedWordIsSavedAndFindAnswersIt() async throws {
        let (directory, pageID) = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard openCorrection(app) else { return }

        let first = lineField(app, 0)
        XCTAssertEqual(first.value as? String, "Invocie total 42")
        XCTAssertTrue(app.images["ocr-line-0-unsure"].exists || app.descendants(matching: .any)["ocr-line-0-unsure"].exists,
                      "the line recognition was unsure of is marked")
        XCTAssertFalse(app.buttons["ocr-correct-save"].isEnabled, "nothing to save yet")
        snap(app, "editor-opened-en")

        replaceText(of: first, with: "Invoice total 42")
        XCTAssertEqual(first.value as? String, "Invoice total 42")
        waitForValue(app.descendants(matching: .any)["ocr-correct-count"], "1")
        waitForValue(app.descendants(matching: .any)["ocr-correct-preview"], "1")
        snap(app, "editor-corrected-en")
        let save = app.buttons["ocr-correct-save"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10), "the editor stayed open after saving")

        // The panel says so, warns that recognizing the page again would
        // replace the correction, and the library holds it.
        waitForValue(app.descendants(matching: .any)["ocr-current-status"], "corrected")
        XCTAssertTrue(app.descendants(matching: .any)["ocr-replaces-corrections"].waitForExistence(timeout: 5),
                      "the panel does not warn before recognizing a corrected page again")
        let store = try LibraryStore(directory: directory)
        let stored = try await store.recognition(for: pageID)
        XCTAssertEqual(stored?.lines.map(\.text), ["Invoice total 42", "Thank you"])
        XCTAssertNotNil(stored?.correctedAt)

        // Find answers the corrected word, and no longer the misread one.
        app.buttons["ocr-close"].tap()
        let findButton = app.buttons["editor-find"]
        guard findButton.waitForExistence(timeout: 10) else { return XCTFail("no Find") }
        findButton.tap()
        let field = app.textFields["find-field"]
        guard field.waitForExistence(timeout: 5) else { return XCTFail("Find did not open") }
        field.typeText("Invoice")
        let findStatus = app.descendants(matching: .any).matching(identifier: "find-status").firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, !(findStatus.exists && findStatus.label == "1 of 1") { usleep(100_000) }
        XCTAssertEqual(findStatus.exists ? findStatus.label : "<absent>", "1 of 1", "Find did not see the correction")
        app.buttons["find-clear"].tap()
        field.typeText("Invocie")
        let after = Date().addingTimeInterval(10)
        while Date() < after, !(findStatus.exists && findStatus.label == "No Results") { usleep(100_000) }
        XCTAssertEqual(findStatus.exists ? findStatus.label : "<absent>", "No Results",
                       "Find still answers the misread word")
    }

    func testCancellingAfterAChangeAsksAndSavesNothing() async throws {
        let (directory, pageID) = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard openCorrection(app) else { return }

        replaceText(of: lineField(app, 1), with: "")
        waitForValue(app.descendants(matching: .any)["ocr-correct-count"], "1")
        app.buttons["ocr-correct-cancel"].tap()
        // `firstMatch`: the confirmation's action sheet reports the button
        // twice on iPhone.
        let discard = app.buttons["ocr-correct-discard"].firstMatch
        guard discard.waitForExistence(timeout: 5) else { return XCTFail("cancelling a change did not ask") }
        snap(app, "editor-discard-en")
        discard.tap()
        XCTAssertTrue(app.buttons["ocr-correct-save"].waitForNonExistence(timeout: 10))

        let store = try LibraryStore(directory: directory)
        let stored = try await store.recognition(for: pageID)
        XCTAssertEqual(stored?.lines.map(\.text), ["Invocie total 42", "Thank you"], "a discarded change was saved")
        XCTAssertNil(stored?.correctedAt)
        waitForValue(app.descendants(matching: .any)["ocr-current-status"], "recognized")
    }

    /// The editor and the panel's status in French and Spanish, for the
    /// layout review: the lines, the count and Save in reach.
    func testTheEditorInFrenchAndSpanish() async throws {
        for language in ["fr", "es"] {
            let (directory, _) = try await seed()
            let app = launch(directory, language: language)
            defer { app.terminate() }
            guard openCorrection(app) else { return }
            replaceText(of: lineField(app, 0), with: "Facture réglée")
            waitForValue(app.descendants(matching: .any)["ocr-correct-count"], "1")
            XCTAssertTrue(app.buttons["ocr-correct-save"].isHittable, "\(language): Save is out of reach")
            snap(app, "editor-\(language)")
            app.terminate()
        }
    }
}
