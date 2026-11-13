import XCTest
import PaperNestCore
import PaperNestStore

/// Selecting the words on a page: press and hold on one, drag on, then copy
/// or mark what is selected.
@MainActor final class TextSelectionUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-find-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// One page of a digital PDF whose first line is "Quarterly budget
    /// review", drawn in 18-point Helvetica from x = 72 with its baseline 140
    /// points down a 612 × 792 page.
    private func openReport() async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-select-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["Quarterly budget review\nThe budget grew"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Report.pdf")
        _ = try await store.createItem(kind: .document, name: "Report", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Report", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        return app
    }

    /// A point on the page, given in the PDF's own points from its top-left.
    private func point(_ x: Double, _ y: Double, on page: XCUIElement) -> XCUICoordinate {
        page.coordinate(withNormalizedOffset: CGVector(dx: x / 612, dy: y / 792))
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { usleep(100_000) }
        XCTAssertTrue(condition(), what, file: file, line: line)
    }

    func testPressingAWordSelectsItAndTheSelectionIsCopiedAndHighlighted() async throws {
        let app = try await openReport()
        defer { app.terminate() }
        let page = app.images["document-page-image"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let selection = app.descendants(matching: .any).matching(identifier: "text-selection").firstMatch
        // It appears once the page's words have been read.
        XCTAssertTrue(selection.waitForExistence(timeout: 10))
        func selected() -> String { selection.exists ? (selection.value as? String ?? "") : "<absent>" }
        XCTAssertEqual(selected(), "")
        XCTAssertFalse(app.buttons["text-selection-copy"].exists)

        // Press and hold on "Quarterly".
        point(109, 134, on: page).press(forDuration: 0.9)
        waitFor("pressing a word did not select it: \(selected())") { selected() == "Quarterly" }
        let copy = app.buttons["text-selection-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        snap(app, "select-word")

        copy.tap()
        waitFor("Copy did not say it had copied") { copy.label == "Copied" }

        // What was copied can be pasted: into the find field, by hand.
        app.buttons["editor-find"].tap()
        let field = app.textFields["find-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.press(forDuration: 1.2)
        let paste = app.menuItems["Paste"]
        XCTAssertTrue(paste.waitForExistence(timeout: 5), "no Paste in the field's menu")
        paste.tap()
        waitFor("the clipboard did not hold the selected word: \(field.value as? String ?? "")") {
            field.value as? String == "Quarterly"
        }
        app.buttons["find-done"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))

        // Press and hold, then drag on past the end of the line: the whole
        // phrase. A selection grows a letter at a time, so stopping inside
        // "review" would stop inside it — the margin beyond means its end.
        point(109, 134, on: page).press(forDuration: 0.9, thenDragTo: point(330, 134, on: page))
        waitFor("dragging on did not extend the selection: \(selected())") { selected() == "Quarterly budget review" }
        snap(app, "select-phrase")

        // Highlighting saves a mark on the page and lets go of the selection.
        XCTAssertEqual(page.value as? String, "0 strokes")
        app.buttons["text-selection-highlight"].tap()
        waitFor("no highlight was saved: \(page.value as? String ?? "")") { page.value as? String == "1 stroke" }
        waitFor("the selection was kept after highlighting: \(selected())") { selected() == "" }
        snap(app, "select-highlighted")

        // A tap elsewhere lets go of a selection without doing anything.
        point(109, 134, on: page).press(forDuration: 0.9)
        waitFor("could not select again: \(selected())") { selected() == "Quarterly" }
        point(400, 600, on: page).tap()
        waitFor("a tap elsewhere kept the selection: \(selected())") { selected() == "" }
        XCTAssertEqual(page.value as? String, "1 stroke", "letting go of a selection changed the page")
    }

    /// A press on empty paper is not a request for the nearest word.
    func testPressingEmptyPaperSelectsNothing() async throws {
        let app = try await openReport()
        defer { app.terminate() }
        let page = app.images["document-page-image"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))
        let selection = app.descendants(matching: .any).matching(identifier: "text-selection").firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: 10))

        point(400, 600, on: page).press(forDuration: 0.9)
        usleep(500_000)

        XCTAssertEqual(selection.value as? String ?? "", "")
        XCTAssertFalse(app.buttons["text-selection-copy"].exists)
    }
}
