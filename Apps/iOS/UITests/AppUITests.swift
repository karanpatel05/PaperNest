import XCTest

/// Drives the real app in the iOS Simulator. Run with `scripts/ui-test-ios.sh`,
/// which seeds the library at `libraryPath` with a page named "Crop target".
@MainActor
final class AppUITests: XCTestCase {
    static let libraryPath = "/tmp/papernest-uitest-library"

    private func launch(_ extra: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", Self.libraryPath, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
        app.launch()
        return app
    }

    /// "70% wide by 75% tall" → (70, 75)
    private func keptPercentages(_ value: Any?) throws -> (Double, Double) {
        let text = try XCTUnwrap(value as? String)
        let numbers = text.split(whereSeparator: { !$0.isNumber }).compactMap { Double($0) }
        XCTAssertEqual(numbers.count, 2, "unexpected crop value: \(text)")
        return (numbers[0], numbers[1])
    }

    func testDraggingTheTopLeftCornerCropsThePageAndTheCropIsSaved() throws {
        continueAfterFailure = false
        let app = launch(["-PaperNestDebugOpenItem", "Crop target", "-PaperNestDebugShowCrop", "YES"])
        let area = app.descendants(matching: .any)["crop-area"]
        XCTAssertTrue(area.waitForExistence(timeout: 15), "crop editor did not open")
        let start = try keptPercentages(area.value)
        XCTAssertEqual(start.0, 100)
        XCTAssertEqual(start.1, 100)

        // Grab the top-left corner and drag it 30% across and 25% down.
        let corner = area.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.01))
        let target = area.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.26))
        corner.press(forDuration: 0.3, thenDragTo: target)
        let dragged = try keptPercentages(area.value)
        XCTAssertEqual(dragged.0, 70, accuracy: 4)
        XCTAssertEqual(dragged.1, 75, accuracy: 4)

        app.buttons["crop-done"].tap()
        XCTAssertTrue(area.waitForNonExistence(timeout: 10), "crop editor did not close")

        // Reopening shows the saved crop, not the full page.
        app.buttons["Crop"].tap()
        let reopened = app.descendants(matching: .any)["crop-area"]
        XCTAssertTrue(reopened.waitForExistence(timeout: 10))
        let saved = try keptPercentages(reopened.value)
        XCTAssertEqual(saved.0, dragged.0, accuracy: 1)
        XCTAssertEqual(saved.1, dragged.1, accuracy: 1)
    }

    /// Smoke test for iPhone sidebar navigation: back to the sidebar, into
    /// another scope and back again, then open a document. It does not
    /// reproduce the one-off "thumbnail tap selected Favorites" glitch seen on
    /// 2026-10-21 (it also passes with the old binding); see TEST_MATRIX.md.
    func testSidebarNavigationKeepsWorkingAfterGoingBack() throws {
        continueAfterFailure = false
        let app = launch([])
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("compact-width behaviour") }
        let document = app.descendants(matching: .any)["Crop target, 1 page"]
        XCTAssertTrue(document.waitForExistence(timeout: 15), "library did not open")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["Favorites"].tap()
        XCTAssertTrue(app.staticTexts["No Favorites"].waitForExistence(timeout: 5))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.staticTexts["All Documents"].tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5), "All Documents did not reopen")

        document.tap()
        XCTAssertTrue(app.buttons["Crop"].waitForExistence(timeout: 5), "document did not open")
    }

    func testSettingsShowsTheLibraryAndExportsABackup() throws {
        continueAfterFailure = false
        let app = launch([])
        XCTAssertTrue(app.descendants(matching: .any)["Crop target, 1 page"].waitForExistence(timeout: 15))

        // iPhone: Settings lives in the navigation bar's overflow menu.
        let more = app.navigationBars.buttons["More"]
        if more.exists { more.tap() }
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Documents"].exists)

        app.buttons["Export All Documents…"].tap()
        XCTAssertTrue(app.buttons["Save…"].waitForExistence(timeout: 20), "backup did not finish")

        app.navigationBars["Settings"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
    }
}
