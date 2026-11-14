import XCTest
import PaperNestCore
import PaperNestStore

/// Read Aloud in the running app: it reads from the page being read, lights
/// the word it is saying, turns the page itself, pauses, resumes and stops.
///
/// Every run passes `-PaperNestDebugSpeechVolume 0`: the voice speaks at no
/// volume, so the tests watch the words go by without talking through the
/// Mac's speakers. The synthesizer reports its words just the same (checked
/// on the Mac: eight of eight words reported at volume 0 and at 0.01).
@MainActor final class ReadAloudUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-read-aloud-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    private func open(_ data: Data, pages: Int, language: String = "en") async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-read-aloud-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Budget.pdf")
        _ = try await store.createItem(kind: .document, name: "Budget", pages: (0..<pages).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Budget", "-AppleLanguages", "(\(language))",
                               "-PaperNestDebugSpeechVolume", "0"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        // The page as well as the toolbar: a tap on the title in the first
        // second, while the document was still loading, once left no menu up.
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 15))
        return app
    }

    private func startReading(_ app: XCUIApplication, menuItem: String = "Read Aloud",
                              file: StaticString = #filePath, line: UInt = #line) {
        let title = app.navigationBars.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Budget")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "no title to open the menu from", file: file, line: line)
        title.tap()
        let item = app.buttons[menuItem]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "\(menuItem) is not in the title menu", file: file, line: line)
        item.tap()
        XCTAssertTrue(app.descendants(matching: .any)["read-aloud-bar"].firstMatch.waitForExistence(timeout: 10),
                      "the read aloud bar did not appear", file: file, line: line)
    }

    private func word(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["read-aloud-word"].firstMatch
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { usleep(100_000) }
        XCTAssertTrue(condition(), what, file: file, line: line)
    }

    /// Two pages of running text. Long on purpose: the Simulator's voice
    /// runs several times faster than real speech (measured: two short lines
    /// were read, page turn included, in about a second and a half), so a
    /// short page is over before a test can look at it.
    private static let pages = [
        (1...18).map { "Line \($0) of the quarterly budget review for the city council" }.joined(separator: "\n"),
        (1...6).map { "Second page line \($0) closes the report" }.joined(separator: "\n"),
    ]

    func testItReadsLightsEachWordPausesResumesTurnsThePageAndStops() async throws {
        let app = try await open(SyntheticDocuments.textPDF(pages: Self.pages), pages: 2)
        defer { app.terminate() }
        startReading(app)

        let lit = word(app)
        waitFor("no word was lit") { lit.exists && !((lit.value as? String) ?? "").isEmpty }
        let first = lit.value as? String ?? ""
        XCTAssertTrue(Self.pages[0].contains(first), "lit \"\(first)\", which is not on page 1")
        waitFor("the light did not move past \"\(first)\"") { (lit.value as? String).map { !$0.isEmpty && $0 != first } ?? false }
        snap(app, "reading")

        // Pause holds the word; Resume moves it on.
        let pause = app.buttons["read-aloud-pause"]
        pause.tap()
        waitFor("Pause did not pause") { (pause.value as? String) == "paused" }
        // The voice pauses at the end of the word it is on, and the next
        // word's notice may already be on its way: let that land first.
        usleep(500_000)
        let held = lit.value as? String
        sleep(2)
        XCTAssertEqual(lit.value as? String, held, "the word moved while paused")
        pause.tap()
        waitFor("Resume did not move the word on", timeout: 20) { lit.exists && (lit.value as? String) != held }

        // It turns to page 2 on its own and reads it.
        let page = app.images["document-page-image"]
        waitFor("it did not turn to page 2", timeout: 120) { page.label == "Page 2 of 2" }
        waitFor("nothing on page 2 was lit") { (lit.value as? String).map { Self.pages[1].contains($0) && !$0.isEmpty } ?? false }

        app.buttons["read-aloud-stop"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["read-aloud-bar"].firstMatch.waitForNonExistence(timeout: 5),
                      "Stop left the bar up")
        XCTAssertFalse(word(app).exists, "Stop left a word lit")
    }

    /// The speed button goes round its values and reading carries on.
    func testTheSpeedButtonChangesSpeedAndReadingCarriesOn() async throws {
        let app = try await open(SyntheticDocuments.textPDF(pages: Self.pages), pages: 2)
        defer { app.terminate() }
        startReading(app)
        let speed = app.buttons["read-aloud-speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: 5))
        XCTAssertEqual(speed.value as? String, "1×")
        speed.tap()
        XCTAssertEqual(speed.value as? String, "1.25×")
        let lit = word(app)
        waitFor("no word was lit after the speed changed") { lit.exists && !((lit.value as? String) ?? "").isEmpty }
        let now = lit.value as? String
        waitFor("reading stopped after the speed changed") { (lit.value as? String).map { $0 != now } ?? false }
        app.buttons["read-aloud-stop"].tap()
    }

    /// A scan nobody has recognised has nothing to say, and the bar says why.
    func testAPageWithNoTextSaysSo() async throws {
        let app = try await open(SyntheticDocuments.scannedPDF(pages: 1), pages: 1)
        defer { app.terminate() }
        startReading(app)
        XCTAssertTrue(app.staticTexts["read-aloud-message"].waitForExistence(timeout: 10), "no message for a page with no text")
        XCTAssertFalse(app.buttons["read-aloud-pause"].exists)
        snap(app, "no-text")
        app.buttons["read-aloud-stop"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["read-aloud-bar"].firstMatch.waitForNonExistence(timeout: 5))
    }

    /// In French and Spanish the menu item is named and the bar fits.
    func testReadAloudIsNamedAndFitsInFrenchAndSpanish() async throws {
        for (language, item) in [("fr", "Lire à voix haute"), ("es", "Leer en voz alta")] {
            let app = try await open(SyntheticDocuments.textPDF(pages: Self.pages), pages: 2, language: language)
            startReading(app, menuItem: item)
            let window = app.windows.firstMatch.frame
            for id in ["read-aloud-speed", "read-aloud-pause", "read-aloud-stop"] {
                let control = app.buttons[id]
                XCTAssertTrue(control.waitForExistence(timeout: 5), "\(id) is missing in \(language)")
                XCTAssertTrue(window.contains(control.frame), "\(id) is off screen in \(language): \(control.frame)")
            }
            let status = app.staticTexts["read-aloud-status"]
            XCTAssertTrue(status.exists, "no status in \(language)")
            XCTAssertGreaterThan(status.frame.width, 120, "the \(language) status is squeezed to \(status.frame.width)")
            snap(app, "bar-\(language)")
            app.buttons["read-aloud-stop"].tap()
            app.terminate()
        }
    }
}
