import XCTest
import PaperNestCore
import PaperNestStore

/// Find in a notebook over handwriting (synthetic single-stroke print,
/// `SyntheticHandwriting`, nobody's real hand). Find is opened before the
/// app's background pass has read the page, so the match has to arrive on its
/// own when the reading does; then the ink is rewritten, and the old word is
/// not found while the new one is, once read.
@MainActor final class HandwritingFindUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func write(_ text: String, on pageID: PageID, in store: LibraryStore, prefix: String) async throws {
        for (index, path) in try SyntheticHandwriting.strokes(text, origin: CGPoint(x: 100, y: 240), size: 24).enumerated() {
            try await store.saveObject(PageObject(
                pageID: pageID, zKey: String(format: "\(prefix)%03d", index),
                payload: .ink(InkStroke(tool: .pen, color: .black, width: 2.6,
                                        points: path.map { InkPoint(x: $0.x, y: $0.y) })),
                modifiedAt: Date(timeIntervalSince1970: 1_700_000_000)))
        }
    }

    private func launch(_ directory: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Journal", "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        return app
    }

    private func find(_ word: String, in app: XCUIApplication) {
        let field = app.textFields["find-field"]
        if !field.exists { app.buttons["editor-find"].tap() }
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        // Clears what is there; an empty field reports its placeholder, and
        // deleting from an empty field does nothing.
        if let current = field.value as? String, !current.isEmpty {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        }
        field.typeText(word)
    }

    private func status(_ app: XCUIApplication) -> String? {
        let element = app.descendants(matching: .any).matching(identifier: "find-status").firstMatch
        return element.exists ? element.label : nil
    }

    /// Waits, up to `seconds`, for find to say `expected`; the background
    /// pass starts a few seconds after the last change and then reads.
    private func waitForStatus(_ app: XCUIApplication, _ expected: String, seconds: TimeInterval = 45,
                               file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, status(app) != expected { usleep(200_000) }
        XCTAssertEqual(status(app) ?? "<absent>", expected, file: file, line: line)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-handwriting-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testFindHighlightsAHandwrittenWordOnceItIsRead() async throws {
        let directory = URL(fileURLWithPath: "/tmp/papernest-handwriting-find-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Journal", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        let pageID = try await store.pages(of: item.id)[0].id
        try await write("plan lunch", on: pageID, in: store, prefix: "K")

        // Find opened at once, before the page is read: the match comes when
        // the reading does, without typing again.
        var app = launch(directory)
        find("lunch", in: app)
        waitForStatus(app, "1 of 1")
        let highlights = app.descendants(matching: .any).matching(identifier: "find-highlights").firstMatch
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline, highlights.value as? String != "1" { usleep(200_000) }
        XCTAssertEqual(highlights.exists ? highlights.value as? String : "<absent>", "1", "the handwritten word is not highlighted")
        snap(app, "find-handwriting")
        app.terminate()

        // The writing rewritten while the app was closed: the old word is not
        // found from the stale reading, and the new one is once it is read.
        for object in try await store.objects(on: pageID) { try await store.deleteObject(object.id) }
        try await write("send notes", on: pageID, in: store, prefix: "N")
        app = launch(directory)
        find("lunch", in: app)
        usleep(1_500_000)
        XCTAssertNotEqual(status(app), "1 of 1", "the erased word was found from the old reading")
        find("notes", in: app)
        waitForStatus(app, "1 of 1")
        find("lunch", in: app)
        usleep(1_000_000)
        XCTAssertNotEqual(status(app), "1 of 1", "the erased word is found after the new reading")
        app.terminate()
    }
}
