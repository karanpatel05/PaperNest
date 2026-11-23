import XCTest

/// Home after the owner's redesign of 2026-11-13: one row of quick actions
/// and recent documents. It has no Tools button; the owner had it removed.
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
        // Home is named once in navigation on every platform: the phone's
        // bottom bar, the wide layouts' sidebar. The dashboard's own title is
        // left blank on purpose (`RootView`, "Home appears once").
        let home = app.staticTexts.matching(NSPredicate(format: "label == %@", "Home"))
        XCTAssertEqual(home.allElementsBoundByIndex.filter(\.isHittable).count, 1)
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
            let largestText = language == "es"
            let app = XCUIApplication()
            app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-home-tools-\(UUID().uuidString)",
                "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_US",
                "-UIPreferredContentSizeCategoryName", largestText ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            app.launch()
            let newNote = app.buttons["home-new-note"]
            let importFile = app.buttons["home-import"]
            let newFolder = app.buttons["home-new-folder"]
            XCTAssertTrue(importFile.waitForExistence(timeout: 20))
            XCTAssertFalse(app.buttons["library-tools"].exists)
            XCTAssertFalse(app.buttons["home-tool-merge"].exists, "Tools are behind the header button, not a second grid on Home")
            for action in [newNote, importFile, newFolder] {
                XCTAssertTrue(action.exists)
                XCTAssertFalse(action.label.isEmpty)
            }
            if largestText {
                // At the largest text the actions stack so each keeps its whole name.
                XCTAssertLessThanOrEqual(newNote.frame.maxY, importFile.frame.minY + 1)
                XCTAssertLessThanOrEqual(importFile.frame.maxY, newFolder.frame.minY + 1)
            } else {
                // One row, in order, inside the screen, in every language.
                XCTAssertEqual(newNote.frame.minY, importFile.frame.minY, accuracy: 2)
                XCTAssertEqual(importFile.frame.minY, newFolder.frame.minY, accuracy: 2)
                XCTAssertLessThanOrEqual(newNote.frame.maxX, importFile.frame.minX + 1)
                XCTAssertLessThanOrEqual(importFile.frame.maxX, newFolder.frame.minX + 1)
                XCTAssertGreaterThanOrEqual(newNote.frame.minX, app.frame.minX)
                XCTAssertLessThanOrEqual(newFolder.frame.maxX, app.frame.maxX)
                for action in [newNote, importFile, newFolder] {
                    XCTAssertTrue(action.isHittable)
                    XCTAssertGreaterThanOrEqual(action.frame.height, 44)
                }
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "home-tools-\(language)"; shot.lifetime = .keepAlways; add(shot)

            // The owner removed Tools from Home; nothing there opens the hub.
            XCTAssertFalse(app.buttons["home-tools-all"].exists)
            XCTAssertTrue(app.buttons["home-profile"].exists)
            app.terminate()
        }
    }
}


extension HomeToolsUITests {
    /// The wide sidebar carries the brand, once, wherever the detail goes, and
    /// Folders is one row that leads to every folder.
    func testIPadSidebarKeepsTheBrandAndFoldersIsOneDestination() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad sidebar") }
        continueAfterFailure = false
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
            XCTAssertEqual(brand.allElementsBoundByIndex.filter(\.isHittable).count, 1,
                           "The brand must show once, in the sidebar, in \(title)")
        }
        let folders = app.cells.containing(.any, identifier: "sidebar-folders").firstMatch
        XCTAssertTrue(folders.waitForExistence(timeout: 5))
        folders.tap()
        XCTAssertTrue(app.staticTexts["folders-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(folders.isSelected)
        app.buttons["folders-new"].tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Study UI")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Study UI"].waitForExistence(timeout: 5))
        XCTAssertTrue(folders.isSelected, "Folders stays lit while one of its folders is showing")
        XCTAssertEqual(brand.allElementsBoundByIndex.filter(\.isHittable).count, 1)

        // Back to the Folders screen: the new folder is a card with its real count.
        folders.tap()
        let card = app.buttons.matching(identifier: "folder-card").matching(NSPredicate(format: "label == %@", "Study UI")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertEqual(card.value as? String, "0 items")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ipad-folders-screen"; shot.lifetime = .keepAlways; add(shot)
        card.tap()
        XCTAssertTrue(app.navigationBars["Study UI"].waitForExistence(timeout: 5))

        // Home shows the same folder under its Folders heading.
        app.cells.containing(.any, identifier: "sidebar-home").firstMatch.tap()
        XCTAssertTrue(app.buttons["home-profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(identifier: "folder-card").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-folders-all"].exists)
        XCTAssertEqual(brand.allElementsBoundByIndex.filter(\.isHittable).count, 1)
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "ipad-home-with-folder"; home.lifetime = .keepAlways; add(home)
    }
}
