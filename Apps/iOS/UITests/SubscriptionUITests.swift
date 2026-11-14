import XCTest

@MainActor final class SubscriptionUITests: XCTestCase {
    func testWelcomeDoesNotStartTrialOrRepeat() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-pro-welcome-\(UUID().uuidString)",
            "-PaperNestDebugSkipWelcome", "NO", "-PaperNestDebugWelcomeKey", "pro-welcome-\(UUID().uuidString)",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.buttons["welcome-continue"].waitForExistence(timeout: 20))
        app.buttons["welcome-continue"].tap()
        XCTAssertTrue(app.buttons["home-profile"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["pro-purchase"].exists)
        app.buttons["home-profile"].tap()
        let state = app.staticTexts["profile-subscription-state"]
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertEqual(state.value as? String, "free")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["home-profile"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["welcome-continue"].exists)
        app.terminate()
    }

    func testProfilePaywallDismissalAndLocalization() throws {
        continueAfterFailure = false
        for language in ["en", "fr", "es"] {
            let app = XCUIApplication()
            app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-profile-\(UUID().uuidString)",
                "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            if language == "es" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launch()
            let profile = app.buttons["home-profile"]
            XCTAssertTrue(profile.waitForExistence(timeout: 20))
            profile.tap()
            let state = app.staticTexts["profile-subscription-state"]
            XCTAssertTrue(state.waitForExistence(timeout: 10))
            XCTAssertEqual(state.value as? String, "free")
            app.buttons["profile-upgrade"].tap()
            XCTAssertTrue(app.buttons["pro-close"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["pro-purchase"].exists, "Unconfigured products must not offer a purchase")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "pro-paywall-\(language)"; shot.lifetime = .keepAlways; add(shot)
            let free = app.buttons["pro-continue-free"]
            // The list of what Pro unlocks is eight rows; at the largest type it is several screens.
            for _ in 0..<14 where !free.isHittable { app.swipeUp() }
            XCTAssertTrue(free.isHittable, "Continue with Free could not be reached in \(language)"); free.tap()
            XCTAssertTrue(app.buttons["profile-upgrade"].waitForExistence(timeout: 5))
            let profileShot = XCTAttachment(screenshot: app.screenshot())
            profileShot.name = "pro-profile-\(language)"; profileShot.lifetime = .keepAlways; add(profileShot)
            app.buttons["profile-done"].tap()
            XCTAssertTrue(profile.waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    /// With products configured and no subscription, a Pro export is refused
    /// with the paywall, which names what was refused and can be closed
    /// without losing the export sheet underneath.
    func testAFreeUserGetsThePaywallNamingTheRefusedFeature() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", AppUITests.libraryPath, "-PaperNestDebugSkipWelcome", "YES",
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-PaperNestDebugOpenItem", "Crop target", "-PaperNestDebugShowExport", "YES",
            "-PaperNestDebugProProducts", "test.papernest.pro.monthly,test.papernest.pro.yearly"]
        app.launch()
        let txt = app.buttons["export-format-txt"]
        XCTAssertTrue(txt.waitForExistence(timeout: 20), "export sheet did not open")
        txt.tap()
        let start = app.buttons["export-start"].firstMatch
        for _ in 0..<5 where !start.isHittable { app.swipeUp() }
        start.tap()
        let locked = app.descendants(matching: .any)["pro-locked-feature"]
        XCTAssertTrue(locked.waitForExistence(timeout: 10), "a Pro export went ahead without a subscription")
        XCTAssertEqual(locked.value as? String, "textExport")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "pro-paywall-locked-feature"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["pro-close"].tap()
        XCTAssertTrue(txt.waitForExistence(timeout: 5), "closing the paywall lost the export sheet")
        XCTAssertFalse(app.descendants(matching: .any)["export-share"].exists, "the refused export still ran")
        app.terminate()
    }
}
