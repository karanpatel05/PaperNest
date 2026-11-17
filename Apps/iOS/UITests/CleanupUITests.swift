import XCTest
import ImageIO
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore

/// Cleaning up a document from Document Tools: a repeated page and a read
/// blank scan are offered and chosen, reviewed, confirmed and deleted, read
/// back from disk.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class CleanupUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func whitePage() -> Data {
        let context = CGContext(data: nil, width: 600, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 600, height: 800))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    private func seed() async throws -> (URL, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-cleanup-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let statement = try store.assets.store(SyntheticDocuments.textPDF(pages: ["Account statement for November, three payments"]),
                                               kind: .pdf, originalFilename: "Statement.pdf")
        let blank = try store.assets.store(whitePage(), kind: .png, originalFilename: "blank.png")
        let item = try await store.createItem(kind: .document, name: "Bundle", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(statement.id, index: 0)),
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(statement.id, index: 0)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(blank.id)),
        ], assets: [statement, blank])
        let pages = try await store.pages(of: item.id)
        try await store.saveRecognition(PageRecognition(pageID: pages[2].id, sourceRevision: pages[2].revision, engineVersion: "test",
                                                        status: .completed, languages: ["en-US"], lines: []))
        return (directory, store, item.id)
    }

    private func launch(_ directory: URL, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Bundle", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-cleanup-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    private func openCleanup(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard app.descendants(matching: .any)["document-page-image"].firstMatch.waitForExistence(timeout: 30) else {
            XCTFail("no document", file: file, line: line); return false
        }
        let button = app.buttons["utilities-cleanup"]
        app.revealInDocumentTools(button)
        button.tap()
        guard app.buttons["cleanup-page-2"].waitForExistence(timeout: 30) else {
            XCTFail("no suggestions", file: file, line: line); return false
        }
        return true
    }

    func testARepeatedAndABlankPageAreChosenReviewedAndDeleted() async throws {
        let (directory, store, item) = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard openCleanup(app) else { return }

        XCTAssertEqual(app.buttons["cleanup-page-2"].value as? String, "Selected", "the repeated page")
        XCTAssertEqual(app.buttons["cleanup-page-3"].value as? String, "Selected", "the read blank scan")
        XCTAssertFalse(app.buttons["cleanup-page-1"].exists, "the page kept is not offered")
        snap(app, "suggestions-en")

        app.buttons["cleanup-review"].tap()
        // An action sheet on a phone, a popover on a pad.
        let delete = isPad ? app.popovers.buttons["Delete Pages"].firstMatch : app.sheets.buttons["Delete Pages"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10), "deleting was not asked first")
        snap(app, "confirm-en")
        delete.tap()

        var left: [Page] = []
        for _ in 0..<40 {
            left = try await store.pages(of: item)
            if left.count == 1 { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(left.count, 1, "the two chosen pages were not deleted")
    }

    /// Unchoosing a page leaves it: only what is chosen goes.
    func testAnUnchosenPageStays() async throws {
        let (directory, store, item) = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard openCleanup(app) else { return }
        app.buttons["cleanup-page-3"].tap()
        XCTAssertEqual(app.buttons["cleanup-page-3"].value as? String, "Not selected")
        app.buttons["cleanup-review"].tap()
        let delete = isPad ? app.popovers.buttons["Delete Pages"].firstMatch : app.sheets.buttons["Delete Pages"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        var left: [Page] = []
        for _ in 0..<40 {
            left = try await store.pages(of: item)
            if left.count == 2 { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(left.count, 2)
        XCTAssertEqual(left.last?.content.assetID == left.first?.content.assetID, false, "the blank scan stayed")
    }

    func testTheCleanupInFrenchAndSpanish() async throws {
        for language in ["fr", "es"] {
            let (directory, _, _) = try await seed()
            let app = launch(directory, language: language)
            defer { app.terminate() }
            guard openCleanup(app) else { return }
            XCTAssertTrue(app.buttons["cleanup-page-2"].isHittable && app.buttons["cleanup-page-3"].isHittable, "\(language): rows")
            XCTAssertTrue(app.buttons["cleanup-review"].isHittable, "\(language): Review out of reach")
            snap(app, "suggestions-\(language)")
            app.terminate()
        }
    }
}
