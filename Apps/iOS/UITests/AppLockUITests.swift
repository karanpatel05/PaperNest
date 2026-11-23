import XCTest
import PaperNestCore
import PaperNestStore

/// The app lock, driven as a person would. The device's own Face ID or
/// passcode prompt cannot be answered from a test, so these use the DEBUG
/// seam `-PaperNestDebugAppLock`, which stands in for that prompt
/// (`LAContext`) and nothing else; everything around it is the real app.
/// One test reads the Simulator's real answer, with no seam. Each test
/// makes a library of its own, so none needs the shared seeded one.
@MainActor final class AppLockUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// A library holding one notebook, removed after the test.
    private func library() async throws -> URL {
        let directory = URL(fileURLWithPath: "/tmp/papernest-applock-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        _ = try await store.createItem(kind: .notebook, name: "Lock test", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
        ], assets: [])
        return directory
    }

    private func launch(_ directory: URL, script: String?, language: String = "en", extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "\(language)_\(language.uppercased())"]
            + (script.map { ["-PaperNestDebugAppLock", $0] } ?? []) + extra
        app.launch()
        return app
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "\(isPad ? "ipad" : "iphone")-\(name)"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openSettings(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let seeAll = app.buttons["home-see-all"]
        if seeAll.waitForExistence(timeout: 15) {
            for _ in 0..<8 where !seeAll.isHittable { app.swipeUp() }
            seeAll.tap()
        }
        let gear = app.buttons["library-settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 10), "no Settings button", file: file, line: line)
        gear.tap()
    }

    /// Scrolls Settings until the lock's switch can be tapped.
    private func lockSwitch(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let toggle = app.switches["settings-app-lock"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "no lock switch", file: file, line: line)
        for _ in 0..<6 where !toggle.isHittable { app.swipeUp() }
        return toggle
    }

    /// On the switch itself: a tap on the middle of a SwiftUI toggle's row
    /// lands on its label, which does not flip it.
    private func flip(_ toggle: XCUIElement) {
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }

    private func waitFor(_ element: XCUIElement, value: String, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Turn the lock on in Settings, leave, come back: PaperNest is locked
    /// over the open Settings sheet itself, a refused prompt keeps it so and
    /// says so, and Unlock opens it where it was. Then turned off again.
    func testTurningItOnThenComingBackLocksOverTheSheet() async throws {
        continueAfterFailure = false
        let app = launch(try await library(), script: "succeed,fail,succeed", extra: ["-PaperNestDebugAppLockReset", "YES"])
        defer { app.terminate() }
        openSettings(app)
        let toggle = lockSwitch(app)
        XCTAssertEqual(toggle.value as? String, "0")
        XCTAssertEqual(toggle.label, "Require Face ID")
        flip(toggle)
        XCTAssertTrue(waitFor(toggle, value: "1"), "the lock did not turn on")
        let immediately = app.buttons["settings-app-lock-grace-0"]
        XCTAssertTrue(immediately.waitForExistence(timeout: 5))
        XCTAssertEqual(immediately.value as? String, "Selected")
        snap(app, "settings-on")

        XCUIDevice.shared.press(.home)
        app.activate()
        let screen = app.descendants(matching: .any)["app-lock-screen"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 10), "not locked on coming back")
        // The automatic prompt is refused: still locked, and said so.
        XCTAssertTrue(app.staticTexts["app-lock-failed"].waitForExistence(timeout: 10))
        XCTAssertFalse(toggle.isHittable, "the Settings sheet can be reached through the lock")
        snap(app, "locked")

        app.buttons["app-lock-unlock"].tap()
        XCTAssertTrue(screen.waitForNonExistence(timeout: 10), "Unlock did not open it")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.isHittable, "not back where it was")

        flip(toggle)
        XCTAssertTrue(waitFor(toggle, value: "0"), "the lock did not turn off")
        XCTAssertFalse(immediately.exists)
    }

    /// On at launch, in French: nothing of the library is there before the
    /// lock is opened, and a refused Unlock leaves it shut.
    func testLockedAtLaunchStaysShutWhenRefused() async throws {
        continueAfterFailure = false
        let app = launch(try await library(), script: "fail", language: "fr", extra: ["-PaperNestAppLockEnabled", "YES"])
        defer { app.terminate() }
        let screen = app.descendants(matching: .any)["app-lock-screen"].firstMatch
        XCTAssertTrue(screen.waitForExistence(timeout: 15), "not locked at launch")
        XCTAssertFalse(app.buttons["home-see-all"].isHittable, "the library can be reached")
        XCTAssertTrue(app.staticTexts["app-lock-failed"].waitForExistence(timeout: 10))
        let unlock = app.buttons["app-lock-unlock"]
        XCTAssertEqual(unlock.label, "Déverrouiller")
        XCTAssertTrue(app.staticTexts["PaperNest est verrouillé"].exists)
        unlock.tap()
        sleep(2)
        XCTAssertTrue(screen.exists, "a refused Unlock opened it")
        snap(app, "locked-fr")
    }

    /// A device with no passcode: the switch cannot be turned on, and
    /// Settings says what to do.
    func testADeviceWithoutAPasscodeCannotTurnItOn() async throws {
        continueAfterFailure = false
        let app = launch(try await library(), script: "cannotask", language: "es", extra: ["-PaperNestDebugAppLockReset", "YES"])
        defer { app.terminate() }
        openSettings(app)
        let toggle = lockSwitch(app)
        XCTAssertFalse(toggle.isEnabled)
        let footer = app.staticTexts["settings-app-lock-footer"]
        XCTAssertTrue(footer.exists)
        XCTAssertTrue(footer.label.hasPrefix("Para usarlo"), footer.label)
        snap(app, "cannot-ask-es")
    }

    /// No seam: what this Simulator's own owner check reports, and that
    /// Settings tells the same story either way.
    func testSettingsMatchTheDevicesOwnAnswer() async throws {
        continueAfterFailure = false
        let app = launch(try await library(), script: nil)
        defer { app.terminate() }
        openSettings(app)
        let toggle = lockSwitch(app)
        let footer = app.staticTexts["settings-app-lock-footer"]
        XCTAssertTrue(footer.exists)
        if toggle.isEnabled {
            XCTAssertTrue(footer.label.hasPrefix("PaperNest asks"), footer.label)
        } else {
            XCTAssertTrue(footer.label.hasPrefix("To use this"), footer.label)
        }
        print("APP-LOCK-DEVICE switch enabled: \(toggle.isEnabled), label: \(toggle.label)")
    }
}
