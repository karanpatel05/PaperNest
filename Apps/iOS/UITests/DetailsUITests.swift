import XCTest
import PaperNestCore
import PaperNestStore

/// Reading an invoice's details from Document Tools, editing one, saving,
/// and finding them kept, read back from disk.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class DetailsUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func seed() async throws -> (URL, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-details-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["Northwind Supplies Invoice No. A-17 Amount due 99.50 EUR"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Invoice.pdf")
        let item = try await store.createItem(kind: .document, name: "Invoice", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        return (directory, store, item.id)
    }

    private func launch(_ directory: URL, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Invoice", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language]
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-details-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    private func openDetails(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        guard app.images["document-page-image"].waitForExistence(timeout: 30) else {
            XCTFail("no document", file: file, line: line); return false
        }
        let button = app.buttons["utilities-extract-details"]
        app.revealInDocumentTools(button)
        button.tap()
        guard app.textFields["details-field-total"].waitForExistence(timeout: 20) else {
            XCTFail("the review did not open", file: file, line: line); return false
        }
        return true
    }

    func testAnInvoicesDetailsAreReadEditedAndSaved() async throws {
        let (directory, store, item) = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard openDetails(app) else { return }

        XCTAssertEqual(app.buttons["details-kind-invoice"].value as? String, "Selected", "the page says it is an invoice")
        XCTAssertEqual(app.textFields["details-field-invoiceNumber"].value as? String, "A-17")
        XCTAssertEqual(app.textFields["details-field-total"].value as? String, "99.50 EUR")
        snap(app, "review-en")

        let number = app.textFields["details-field-invoiceNumber"]
        number.tap()
        number.typeText("B")
        app.buttons["details-save"].tap()
        XCTAssertTrue(app.buttons["details-save"].waitForNonExistence(timeout: 10), "the review stayed open")

        var kept: LibraryStore.StoredDetails?
        for _ in 0..<40 {
            kept = try await store.documentDetails(of: item)
            if kept != nil { break }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTAssertEqual(kept?.details.kind, .invoice)
        XCTAssertEqual(kept?.details[.invoiceNumber], "A-17B", "the edit was kept")
        XCTAssertEqual(kept?.details[.total], "99.50 EUR")
        XCTAssertEqual(kept?.details.values[.invoiceNumber]?.confidence, 1, "an edited value counts as certain")
    }

    /// A business card's review offers its contact card to share.
    func testChoosingABusinessCardOffersAContactCard() async throws {
        let (directory, _, _) = try await seed()
        let app = launch(directory)
        defer { app.terminate() }
        guard openDetails(app) else { return }
        app.buttons["details-kind-businessCard"].tap()
        XCTAssertEqual(app.buttons["details-kind-businessCard"].value as? String, "Selected")
        XCTAssertTrue(app.textFields["details-field-email"].waitForExistence(timeout: 5))
        let share = app.descendants(matching: .any)["details-share-card"].firstMatch
        for _ in 0..<6 where !share.isHittable { app.swipeUp() }
        XCTAssertTrue(share.exists, "no contact card to share")
    }

    /// French and Spanish: the kinds, the fields and Save in reach.
    func testTheReviewInFrenchAndSpanish() async throws {
        for language in ["fr", "es"] {
            let (directory, _, _) = try await seed()
            let app = launch(directory, language: language)
            defer { app.terminate() }
            guard openDetails(app) else { return }
            for kind in ["receipt", "businessCard", "invoice"] {
                XCTAssertTrue(app.buttons["details-kind-\(kind)"].isHittable, "\(language): \(kind) out of reach")
            }
            XCTAssertTrue(app.buttons["details-save"].isHittable, "\(language): Save out of reach")
            // The title is there (whether it fits is judged from the screenshot:
            // a cut-off title still reports its whole text).
            let title = language == "fr" ? "Vérification" : "Revisión"
            XCTAssertTrue(app.navigationBars.staticTexts[title].exists, "\(language): no title")
            snap(app, "review-\(language)")
            app.terminate()
        }
    }
}
