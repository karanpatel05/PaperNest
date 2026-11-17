import XCTest
import PaperNestCore
import PaperNestStore

/// Redact and Compress are Pro (the owner's Free/Pro list): with products
/// configured and no subscription, each Document Tools button opens the
/// paywall naming it, and its screen does not open. Without products, both
/// open as before (`RedactUITests`, `CompressSheet`'s tests).
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class ProToolGateUITests: XCTestCase {
    private func seed() async throws -> URL {
        let directory = URL(fileURLWithPath: "/tmp/papernest-pro-tools-\(UUID())")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["ACCOUNT 55512345 SECRET"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Statement.pdf")
        _ = try await store.createItem(kind: .document, name: "Statement", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        return directory
    }

    private func launchAsFreeUser(_ directory: URL) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Statement", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               // Turns the Free/Pro boundary on; nothing is bought, so this is a free user.
                               "-PaperNestDebugProProducts", "test.papernest.pro.monthly,test.papernest.pro.yearly"]
        app.launch()
        return app
    }

    /// Taps a Document Tools button and expects the paywall naming `feature`,
    /// then closes it and expects neither the paywall nor the tool's screen.
    private func expectPaywall(_ app: XCUIApplication, tool: String, feature: String, screen: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        let button = app.buttons[tool]
        app.revealInDocumentTools(button, file: file, line: line)
        button.tap()
        let locked = app.descendants(matching: .any)["pro-locked-feature"]
        guard locked.waitForExistence(timeout: 15) else {
            return XCTFail("\(tool) opened without a subscription", file: file, line: line)
        }
        XCTAssertEqual(locked.value as? String, feature, file: file, line: line)
        XCTAssertFalse(app.descendants(matching: .any)[screen].exists, "\(screen) opened behind the paywall",
                       file: file, line: line)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "pro-paywall-\(feature)"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["pro-close"].tap()
        XCTAssertTrue(locked.waitForNonExistence(timeout: 10), "the paywall did not close", file: file, line: line)
        XCTAssertFalse(app.descendants(matching: .any)[screen].exists, "\(screen) opened after the paywall closed",
                       file: file, line: line)
    }

    func testRedactOpensThePaywallForAFreeUser() async throws {
        let directory = try await seed()
        let app = launchAsFreeUser(directory)
        defer { app.terminate() }
        guard app.images["document-page-image"].waitForExistence(timeout: 30) else { return XCTFail("no document") }
        expectPaywall(app, tool: "utilities-redact", feature: "redact", screen: "redact-page")
    }

    func testCompressOpensThePaywallForAFreeUser() async throws {
        let directory = try await seed()
        let app = launchAsFreeUser(directory)
        defer { app.terminate() }
        guard app.images["document-page-image"].waitForExistence(timeout: 30) else { return XCTFail("no document") }
        expectPaywall(app, tool: "utilities-compress", feature: "compress", screen: "compress-level")
    }
}
