import XCTest

/// All Documents' search field takes the keyboard and finds a document, in
/// English and French. On a phone the large title used to be drawn over the
/// field, hiding what was typed and taking the tap, so the field never got
/// the keyboard (2026-11-21); the title is now inline there, in the bar above
/// the field.
@MainActor final class LibrarySearchUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-library-search-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testAllDocumentsSearchTakesTheKeyboardAndFinds() throws {
        for (language, title) in [("en", "All Documents"), ("fr", "Tous les documents")] {
            let app = XCUIApplication()
            app.launchArguments = ["-PaperNestLibraryPath", AppUITests.libraryPath, "-AppleLanguages", "(\(language))",
                                   "-AppleLocale", language == "en" ? "en_US" : "fr_FR", "-PaperNestDebugSkipWelcome", "YES"]
            app.launch()
            let seeAll = app.buttons["home-see-all"]
            if seeAll.waitForExistence(timeout: 15) {
                for _ in 0..<8 where !seeAll.isHittable { app.swipeUp() }
                seeAll.tap()
            }
            let field = app.searchFields.firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10), "\(language): no search field")

            // Nothing drawn over the field: the screen's title is not where the field is.
            let titleText = app.navigationBars.staticTexts[title]
            if titleText.exists {
                XCTAssertFalse(titleText.frame.intersects(field.frame),
                               "\(language): the title \(titleText.frame) is drawn over the field \(field.frame)")
            }
            snap(app, "before-\(language)")

            field.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "\(language): the field did not take the keyboard")
            field.typeText("Crop")
            XCTAssertEqual(field.value as? String, "Crop", "\(language): what was typed")
            let found = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Crop target")).firstMatch
            XCTAssertTrue(found.waitForExistence(timeout: 10), "\(language): the seeded document was not found")
            snap(app, "searching-\(language)")
            app.terminate()
        }
    }
}
