import XCTest
import PaperNestCore
import PaperNestStore

/// The export sheet says how large the export will be before it is made:
/// exact for a couple of pages, "about" for more, following the format, in
/// French and Spanish too.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class ExportSizeUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func openExport(pages count: Int, language: String = "en") async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-export-size-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let report = try store.assets.store(SyntheticDocuments.textPDF(pages: (1...count).map {
            "Page \($0) of the quarterly report: sales, costs and the plan for next year"
        }), kind: .pdf, originalFilename: "Report.pdf")
        _ = try await store.createItem(kind: .document, name: "Report", pages: (0..<count).map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(report.id, index: $0))
        }, assets: [report])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Report", "-PaperNestDebugShowExport", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        XCTAssertTrue(app.buttons["export-format-pdf"].waitForExistence(timeout: 30), "the export sheet did not open")
        return app
    }

    /// The size line once it has been worked out (not while it is being).
    private func sizeLine(_ app: XCUIApplication, startingWith prefix: String, excluding working: String) -> String? {
        let line = app.staticTexts["export-size-estimate"]
        for _ in 0..<80 {
            if line.exists, line.label.hasPrefix(prefix), line.label != working { return line.label }
            usleep(250_000)
        }
        return line.exists ? line.label : nil
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-export-size-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testTwoPagesAreSizedExactly() async throws {
        let app = try await openExport(pages: 2)
        defer { app.terminate() }
        let line = sizeLine(app, startingWith: "Size: ", excluding: "Working out the size…")
        XCTAssertNotNil(line, "no size was given")
        XCTAssertFalse(line?.contains("about") ?? true, "two pages are all measured, so exactly: \(line ?? "")")
        snap(app, "exact-en")
    }

    func testManyPagesAreEstimatedAndTheFormatChangesIt() async throws {
        let app = try await openExport(pages: 10)
        defer { app.terminate() }
        let pdf = sizeLine(app, startingWith: "Size: about", excluding: "Working out the size…")
        XCTAssertNotNil(pdf, "no estimate for ten pages")
        snap(app, "about-en")

        app.buttons["export-format-jpeg"].tap()
        var jpeg: String?
        for _ in 0..<80 {
            jpeg = sizeLine(app, startingWith: "Size: about", excluding: "Working out the size…")
            if jpeg != pdf { break }
            usleep(250_000)
        }
        XCTAssertNotNil(jpeg)
        XCTAssertNotEqual(jpeg, pdf, "choosing pictures did not change the size")
    }

    func testTheSizeInFrenchAndSpanish() async throws {
        for (language, prefix, working) in [("fr", "Taille", "Calcul de la taille…"), ("es", "Tamaño", "Calculando el tamaño…")] {
            let app = try await openExport(pages: 10, language: language)
            defer { app.terminate() }
            let line = sizeLine(app, startingWith: prefix, excluding: working)
            XCTAssertNotNil(line, "\(language): no size")
            XCTAssertTrue(app.staticTexts["export-size-estimate"].isHittable, "\(language): the size line is out of sight")
            snap(app, "about-\(language)")
            app.terminate()
        }
    }
}
