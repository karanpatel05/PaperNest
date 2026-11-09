import XCTest

@MainActor final class HomeToolsUITests: XCTestCase {
    func testHomeHasOneBrandAndProfileRemainsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-home-brand-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["home-profile"].waitForExistence(timeout: 20))
        let brand = app.staticTexts.matching(NSPredicate(format: "label == %@", "PaperNest"))
        XCTAssertEqual(brand.allElementsBoundByIndex.filter(\.isHittable).count, 1,
                       "Home should show the brand once across the sidebar and dashboard")
        let home = app.staticTexts.matching(NSPredicate(format: "label == %@", "Home"))
        XCTAssertEqual(home.allElementsBoundByIndex.filter(\.isHittable).count, 1,
                       "Keep the Home tab/sidebar entry without a second dashboard heading")
        app.buttons["home-profile"].tap()
        XCTAssertTrue(app.buttons["profile-done"].waitForExistence(timeout: 5))
        app.buttons["profile-done"].tap()
        XCTAssertTrue(app.buttons["home-profile"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "home-single-brand"; shot.lifetime = .keepAlways; add(shot)
    }

    func testHomeToolsEnglish() { checkLanguages(["en"]) }
    func testHomeToolsFrench() { checkLanguages(["fr"]) }
    func testHomeToolsSpanishLargestText() { checkLanguages(["es"]) }

    private func checkLanguages(_ languages: [String]) {
        continueAfterFailure = false
        for language in languages {
            let app = XCUIApplication()
            app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-home-tools-\(UUID().uuidString)",
                "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_US",
                "-UIPreferredContentSizeCategoryName", language == "es" ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            app.launch()
            XCTAssertTrue(app.buttons["home-import"].waitForExistence(timeout: 20))
            XCTAssertFalse(app.buttons["library-tools"].exists)
            let merge = app.buttons["home-tool-merge"]
            let extract = app.buttons["home-tool-extract"]
            reveal(merge, in: app)
            XCTAssertLessThan(app.buttons["home-import"].frame.minY, merge.frame.minY)
            if UIDevice.current.userInterfaceIdiom == .phone {
                XCTAssertEqual(merge.frame.minY, extract.frame.minY, accuracy: 2)
                XCTAssertLessThan(merge.frame.maxX, extract.frame.maxX)
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "home-tools-\(language)"; shot.lifetime = .keepAlways; add(shot)
            for tool in ["merge", "extract", "split", "archive"] {
                let card = app.buttons["home-tool-\(tool)"]
                reveal(card, in: app)
                let title = card.label
                XCTAssertFalse(title.isEmpty)
                XCTAssertFalse((card.value as? String ?? "").isEmpty)
                card.tap()
                let next = app.buttons["pick-continue"]
                XCTAssertTrue(next.waitForExistence(timeout: 8), "\(tool) did not open its picker")
                XCTAssertFalse(next.isEnabled, "Empty library cannot start an operation")
                XCTAssertTrue(app.navigationBars[title].exists)
                if app.buttons["tools-done"].isHittable { app.buttons["tools-done"].tap() }
                else {
                    app.navigationBars.buttons.firstMatch.tap()
                    app.buttons["tools-done"].tap()
                }
                XCTAssertTrue(app.buttons["home-tools-all"].waitForExistence(timeout: 5))
            }
            reveal(app.buttons["home-tools-all"], in: app)
            app.buttons["home-tools-all"].tap()
            XCTAssertTrue(app.buttons["tool-notebook"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["tool-import"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["tool-photos"].firstMatch.exists)
            app.buttons["tools-done"].tap()
            app.terminate()
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let top = app.frame.minY + 160
        let bottom = app.frame.maxY - (UIDevice.current.userInterfaceIdiom == .phone ? 140 : 40)
        // isHittable can be true for a thin exposed strip of a large card.
        // Keep its entire touch target clear of navigation before tapping.
        for _ in 0..<20 {
            let frame = element.frame
            if element.isHittable && frame.minY >= top && frame.maxY <= bottom { break }
            let direction = frame.minY < top ? 1.0 : -1.0
            let origin = app.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.55))
            let destination = origin.withOffset(CGVector(dx: 0, dy: direction * 110))
            origin.press(forDuration: 0.01, thenDragTo: destination)
        }
        XCTAssertGreaterThanOrEqual(element.frame.minY, top)
        XCTAssertLessThanOrEqual(element.frame.maxY, bottom)
        XCTAssertTrue(element.isHittable)
    }
}


extension HomeToolsUITests {
    func testIPadSidebarNeverAddsBrandHeadingWhenChangingDestinations() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad sidebar") }
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-sidebar-brand-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["home-profile"].waitForExistence(timeout: 20))
        let brand = app.staticTexts.matching(NSPredicate(format: "label == %@", "PaperNest"))
        XCTAssertEqual(brand.allElementsBoundByIndex.filter(\.isHittable).count, 1)
        for title in ["Notes", "All Documents", "Favorites"] {
            let row = app.cells.containing(.staticText, identifier: title).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            XCTAssertEqual(brand.allElementsBoundByIndex.filter(\.isHittable).count, 0,
                           "Sidebar brand heading must stay hidden in \(title)")
        }
        app.buttons["sidebar-new-folder"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Study UI")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Study UI"].waitForExistence(timeout: 5))
        XCTAssertEqual(brand.allElementsBoundByIndex.filter(\.isHittable).count, 0,
                       "Sidebar brand heading must stay hidden in a folder")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ipad-folder-no-sidebar-brand"; shot.lifetime = .keepAlways; add(shot)
        app.cells.containing(.any, identifier: "sidebar-home").firstMatch.tap()
        XCTAssertTrue(app.buttons["home-profile"].waitForExistence(timeout: 5))
        XCTAssertEqual(brand.allElementsBoundByIndex.filter(\.isHittable).count, 1,
                       "Returning Home must retain the dashboard logo/name")
    }
}
