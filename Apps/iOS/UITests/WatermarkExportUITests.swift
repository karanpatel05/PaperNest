import XCTest
import PaperNestCore
import PaperNestStore

/// Export watermarks, as someone adding one to an export meets them.
///
/// What ends up in the file — its position, colour, rotation, opacity, and
/// that the words are shapes rather than text — is checked by the engine's
/// tests (`WatermarkTests`, `WatermarkExportTests`). These check the sheet: a
/// preset fills in its own controls, the preview follows every change, the
/// three ways out export with it, and closing the sheet forgets it.
@MainActor final class WatermarkExportUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func openExport(language: String = "en", extra: [String] = []) async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-watermark-export-\(UUID())")
        // A plain teardown block, not an async main-actor `tearDown`: when a
        // query finds nothing, XCTest interrupts the test and waits on the
        // main thread for an async tearDown, which needs the main thread
        // itself, and the runner sits idle until XCTest gives up.
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let store = try LibraryStore(directory: directory)
        _ = try await store.createItem(kind: .notebook, name: "Contract", pages: (0..<2).map { _ in
            .init(sourceSize: CGSize(width: 612, height: 792), content: .template(.lined))
        }, assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Contract", "-PaperNestDebugShowExport", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language]
            + extra
        app.launch()
        XCTAssertTrue(app.buttons["export-format-pdf"].waitForExistence(timeout: 30), "the export sheet did not open")
        return app
    }

    /// Scrolls the export form until `element` is on screen: below the bar
    /// across the top and above the bar of ways out along the bottom. A tile
    /// half under the sheet's navigation bar still reports itself hittable,
    /// but a tap on it lands on the bar. Short drags that stop dead, so the
    /// form never flies past the element; and if it does go past, the next
    /// drags come back for it.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, upward: Bool = false) {
        let bar = app.buttons["export-destination-save"]
        var upward = upward
        var seen = false
        for _ in 0..<16 {
            if element.exists {
                // The close button is the top bar's own, so it is never below it.
                let clearOfTop = element.identifier == "export-close" || element.frame.minY >= formTop(in: app)
                if element.isHittable, clearOfTop, !bar.exists || element.frame.maxY < bar.frame.minY { return }
                seen = true
            } else if seen {
                upward.toggle()
                seen = false
            }
            dragForm(in: app, upward: upward)
        }
    }

    /// The bottom of what covers the top of the form: the sheet's navigation
    /// bar on a phone, the panel's header (with its close button) on an iPad.
    private func formTop(in app: XCUIApplication) -> CGFloat {
        let close = app.buttons["export-close"]
        guard close.exists else { return app.frame.minY }
        let navigation = app.navigationBars.containing(.button, identifier: "export-close").firstMatch
        return max(close.frame.maxY, navigation.exists ? navigation.frame.maxY : 0)
    }

    /// Drags the form a third of its height, between the bar across its top
    /// and the bar along the bottom. It starts at the left edge of the form's
    /// column — on an iPad the form is a sidebar beside the page — clear of
    /// the sliders, and holds still before letting go, so nothing coasts.
    private func dragForm(in app: XCUIApplication, upward: Bool) {
        let bar = app.buttons["export-destination-save"]
        let window = app.frame
        let top = app.buttons["export-close"].exists ? formTop(in: app) : window.minY + window.height * 0.2
        let bottom = bar.exists ? bar.frame.minY : window.maxY - window.height * 0.2
        let x = bar.exists ? bar.frame.minX + 10 : window.midX
        let middle = (top + bottom) / 2, span = (bottom - top) * 0.35
        let from = upward ? middle - span / 2 : middle + span / 2
        let to = upward ? middle + span / 2 : middle - span / 2
        let origin = app.coordinate(withNormalizedOffset: .zero)
        origin.withOffset(CGVector(dx: x, dy: from))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: to)),
                   withVelocity: .default, thenHoldForDuration: 0.3)
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        let folder = URL(fileURLWithPath: "/tmp/pn-watermark-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    private func choose(_ preset: String, in app: XCUIApplication) -> XCUIElement {
        let tile = app.buttons["export-watermark-\(preset)"]
        reveal(tile, in: app)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "no \(preset) watermark tile")
        tile.tap()
        XCTAssertTrue(tile.isSelected, "\(preset) did not become the selected watermark")
        return tile
    }

    private func previewValue(_ app: XCUIApplication) -> String {
        let preview = app.descendants(matching: .any)["export-watermark-preview"]
        reveal(preview, in: app, upward: true)
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "no watermark preview")
        return preview.value as? String ?? ""
    }

    func testNoneIsTheDefaultAndAPresetFillsInItsOwnControls() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        let none = app.buttons["export-watermark-none"]
        reveal(none, in: app)
        XCTAssertTrue(none.waitForExistence(timeout: 5), "the export sheet offers no watermark")
        XCTAssertTrue(none.isSelected, "an export starts with no watermark")
        XCTAssertFalse(app.textFields["export-watermark-text"].exists, "controls shown for no watermark")
        XCTAssertFalse(app.descendants(matching: .any)["export-watermark-preview"].exists)

        _ = choose("confidential", in: app)
        XCTAssertFalse(none.isSelected)
        let text = app.textFields["export-watermark-text"]
        reveal(text, in: app)
        XCTAssertEqual(text.value as? String, "CONFIDENTIAL", "the preset's word is filled in")
        let center = app.buttons["export-watermark-placement-center"]
        reveal(center, in: app)
        XCTAssertTrue(center.isSelected, "Confidential starts in the middle")
        let value = previewValue(app)
        XCTAssertTrue(value.contains("Confidential"), "preview says \(value)")
        XCTAssertTrue(value.contains("Center"), "preview says \(value)")
        snap(app, "confidential-en")

        _ = choose("approved", in: app)
        reveal(text, in: app)
        XCTAssertEqual(text.value as? String, "APPROVED", "switching preset fills in its own word")
        let bottomRight = app.buttons["export-watermark-placement-bottomRight"]
        reveal(bottomRight, in: app)
        XCTAssertTrue(bottomRight.isSelected, "Approved starts bottom right")
    }

    func testPlacementOpacityAndRotationChangeThePreview() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        _ = choose("draft", in: app)
        XCTAssertTrue(previewValue(app).contains("Top right"))

        let bottom = app.buttons["export-watermark-placement-bottomRight"]
        reveal(bottom, in: app)
        bottom.tap()
        XCTAssertTrue(bottom.isSelected)
        XCTAssertFalse(app.buttons["export-watermark-placement-topRight"].isSelected)
        XCTAssertTrue(previewValue(app).contains("Bottom right"), "the preview did not follow the placement")

        let opacity = app.sliders["export-watermark-opacity"]
        reveal(opacity, in: app)
        let before = opacity.value as? String
        opacity.adjust(toNormalizedSliderPosition: 0.2)
        // Read before scrolling up to the preview, which can take the slider
        // off screen and out of the form's rows.
        let moved = opacity.value as? String
        XCTAssertNotEqual(moved, before, "the opacity slider did not move")
        XCTAssertTrue(previewValue(app).contains(moved ?? "?"),
                      "the preview does not say the new opacity")

        let rotation = app.sliders["export-watermark-rotation"]
        reveal(rotation, in: app)
        let turned = rotation.value as? String
        rotation.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertNotEqual(rotation.value as? String, turned, "the rotation slider did not move")
        snap(app, "draft-moved-en")
    }

    func testCustomAsksForTextBeforeItExports() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        _ = choose("custom", in: app)
        let text = app.textFields["export-watermark-text"]
        reveal(text, in: app)
        XCTAssertTrue(app.staticTexts["export-watermark-text-missing"].exists, "an empty custom watermark says nothing")
        XCTAssertFalse(app.buttons["export-destination-copy"].isEnabled, "an export with no watermark text was offered")

        text.tap()
        text.typeText("Acme Ltd")
        XCTAssertTrue(app.staticTexts["export-watermark-text-missing"].waitForNonExistence(timeout: 5))
        if app.keyboards.count > 0 { app.keyboards.buttons.element(boundBy: app.keyboards.buttons.count - 1).tap() }
        XCTAssertTrue(previewValue(app).contains("Custom"))
        XCTAssertTrue(app.buttons["export-destination-copy"].isEnabled, "typed text did not make the export possible")
    }

    /// A format with nowhere to draw a watermark says so where the section
    /// was, and the choice comes back with a format that can carry it.
    func testATextFormatSaysItCannotCarryTheWatermark() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        _ = choose("confidential", in: app)
        let txt = app.buttons["export-format-txt"]
        reveal(txt, in: app, upward: true)
        txt.tap()
        XCTAssertTrue(app.descendants(matching: .any)["export-watermark-unsupported"].waitForExistence(timeout: 5),
                      "a text export dropped the watermark without saying so")
        XCTAssertFalse(app.buttons["export-watermark-confidential"].exists)
        let pdf = app.buttons["export-format-pdf"]
        reveal(pdf, in: app, upward: true)
        pdf.tap()
        let confidential = app.buttons["export-watermark-confidential"]
        reveal(confidential, in: app)
        XCTAssertTrue(confidential.waitForExistence(timeout: 5))
        XCTAssertTrue(confidential.isSelected, "the watermark was forgotten on the way back to PDF")
    }

    func testCopyExportsWithTheWatermark() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        _ = choose("confidential", in: app)
        let copy = app.buttons["export-destination-copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.descendants(matching: .any)["export-copied"].waitForExistence(timeout: 30),
                      "a watermarked export was not copied")
    }

    func testShareExportsWithTheWatermark() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        _ = choose("draft", in: app)
        app.buttons["export-destination-share"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 30),
                      "Share with a watermark did not open the share sheet")
        snap(app, "draft-share-en")
    }

    func testSaveExportsWithTheWatermark() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        _ = choose("approved", in: app)
        app.buttons["export-destination-save"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 30),
                      "Save with a watermark did not open the save dialog")
    }

    func testClosingTheSheetForgetsTheWatermark() async throws {
        let app = try await openExport()
        defer { app.terminate() }
        _ = choose("confidential", in: app)
        let close = app.buttons["export-close"]
        reveal(close, in: app, upward: true)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        let export = app.buttons["editor-export"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        export.tap()
        let none = app.buttons["export-watermark-none"]
        reveal(none, in: app)
        XCTAssertTrue(none.waitForExistence(timeout: 10))
        XCTAssertTrue(none.isSelected, "a closed sheet's watermark came back")
        XCTAssertFalse(app.buttons["export-watermark-confidential"].isSelected)
    }

    /// French at the largest accessibility size: the long names stay readable
    /// and every control can still be reached.
    func testFrenchAtTheLargestTextSizeKeepsEveryControlReachable() async throws {
        let app = try await openExport(language: "fr", extra: [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        defer { app.terminate() }
        _ = choose("approved", in: app)
        for identifier in ["export-watermark-placement-tiled", "export-watermark-opacity",
                           "export-watermark-rotation", "export-watermark-date"] {
            let element = app.descendants(matching: .any)[identifier]
            reveal(element, in: app)
            XCTAssertTrue(element.exists && element.isHittable, "\(identifier) cannot be reached in French at XXXL")
        }
        let text = app.textFields["export-watermark-text"]
        reveal(text, in: app, upward: true)
        XCTAssertEqual(text.value as? String, "APPROUVÉ", "the stamped word is not in French")
        snap(app, "approved-fr-xxxl")
    }
}
