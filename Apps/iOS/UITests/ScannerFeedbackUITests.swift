import XCTest

/// The scanner's live advice, on a simulator, which has no camera.
///
/// A recorded run of looks is played through the camera's own processing
/// (`-PaperNestDebugScannerFrames`), so what is tested is the real guide, the
/// real callback and the real label — everything but the camera and its
/// brightness reading, which unit tests cover. Each phase lasts about four
/// seconds, so a busy machine cannot skip one before it is read.
///
/// The scanner's defaults are pinned (Auto off), or a stored setting could
/// turn the automatic shutter on and fire it at a camera that is not there.
/// No `continueAfterFailure = false` and no `async` `tearDown`.
@MainActor final class ScannerFeedbackUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private let defaults = ["-scanner.defaultMode", "document", "-scanner.defaultPreset", "original",
                            "-scanner.autoOnEntry", "NO"]

    private typealias Look = (corners: [[Double]], luminance: Double?)

    /// A sheet covering 64% of the frame, clear of the edges.
    private let sheet: [[Double]] = [[0.1, 0.1], [0.9, 0.1], [0.9, 0.9], [0.1, 0.9]]

    private func repeated(_ corners: [[Double]], _ luminance: Double?, _ count: Int) -> [Look] {
        Array(repeating: (corners, luminance), count: count)
    }

    private func recording(_ looks: [Look]) throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/papernest-scanner-looks-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let json: [String: Any] = ["interval": 0.25, "looks": looks.map { look -> [String: Any] in
            var entry: [String: Any] = ["corners": look.corners]
            if let luminance = look.luminance { entry["luminance"] = luminance }
            return entry
        }]
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return url
    }

    private func launch(_ recording: URL, language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-scanner-feedback-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language,
                               "-PaperNestDebugScannerFrames", recording.path] + defaults
        app.launch()
        return app
    }

    private func waitForAdvice(_ app: XCUIApplication, _ expected: String, timeout: TimeInterval = 20,
                               file: StaticString = #filePath, line: UInt = #line) -> Bool {
        let label = app.descendants(matching: .any)["scanner.feedback"]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if label.exists, label.value as? String == expected { return true }
            usleep(100_000)
        }
        XCTFail("waited for \(expected); the label said \(label.exists ? (label.value as? String ?? "?") : "nothing")",
                file: file, line: line)
        return false
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let folder = URL(fileURLWithPath: "/tmp/pn-scanner-feedback-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testTheAdviceFollowsWhatTheCameraSees() throws {
        let small: [[Double]] = [[0.32, 0.32], [0.68, 0.32], [0.68, 0.68], [0.32, 0.68]]   // 13% of the frame
        let nearEdge: [[Double]] = [[0.017, 0.1], [0.8, 0.1], [0.8, 0.9], [0.017, 0.9]]  // 1.7% from the edge
        let shifted = sheet.map { [$0[0] + 0.05, $0[1]] }
        var looks = repeated(small, 0.5, 16)
        looks += repeated(nearEdge, 0.5, 16)
        looks += repeated(sheet, 0.05, 16)                                               // dark
        looks += (0..<16).map { ($0 % 2 == 0 ? sheet : shifted, 0.5) }                    // moving
        looks += repeated(sheet, 0.5, 24)                                                // still
        let app = launch(try recording(looks))
        defer { app.terminate() }

        guard waitForAdvice(app, "moveCloser", timeout: 40) else { return }
        snap(app, "move-closer-en")
        let label = app.descendants(matching: .any)["scanner.feedback"]
        XCTAssertEqual(label.label, "Move closer")
        guard waitForAdvice(app, "moveBack") else { return }
        guard waitForAdvice(app, "improveLighting") else { return }
        guard waitForAdvice(app, "holdSteady") else { return }
        guard waitForAdvice(app, "ready") else { return }
        XCTAssertEqual(label.label, "Ready")
        snap(app, "ready-en")
        XCTAssertTrue(app.buttons["scanner.shutter"].exists, "the label does not replace the shutter")
    }

    /// With nothing found and good light there is nothing to say.
    func testNothingFoundSaysNothing() throws {
        let app = launch(try recording(repeated([], 0.5, 12) + repeated(sheet, 0.5, 4)))
        defer { app.terminate() }
        // The page arrives after three seconds of empty frames.
        guard waitForAdvice(app, "holdSteady", timeout: 40) else { return }
        XCTAssertTrue(app.buttons["scanner.shutter"].exists)
    }

    func testTheAdviceInFrenchAndSpanish() throws {
        for (language, ready, closer) in [("fr", "Prêt", "Rapprochez-vous"), ("es", "Listo", "Acércate")] {
            let small: [[Double]] = [[0.32, 0.32], [0.68, 0.32], [0.68, 0.68], [0.32, 0.68]]
            let app = launch(try recording(repeated(small, 0.5, 16) + repeated(sheet, 0.5, 30)), language: language)
            defer { app.terminate() }
            let label = app.descendants(matching: .any)["scanner.feedback"]
            guard waitForAdvice(app, "moveCloser", timeout: 40) else { return }
            XCTAssertEqual(label.label, closer, language)
            snap(app, "move-closer-\(language)")
            guard waitForAdvice(app, "ready") else { return }
            XCTAssertEqual(label.label, ready, language)
            snap(app, "ready-\(language)")
            app.terminate()
        }
    }
}
