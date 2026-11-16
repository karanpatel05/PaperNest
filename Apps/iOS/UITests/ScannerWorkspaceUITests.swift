import XCTest
import UIKit

@MainActor final class ScannerWorkspaceUITests: XCTestCase {
    /// The scanner opens as its stored defaults say (Scan settings). Every test
    /// but the one about those settings pins them, so it starts in Document
    /// mode with no default filter and the shutter manual, whatever an
    /// earlier run left stored on the simulator.
    private static let standardScanDefaults = ["-scanner.defaultMode", "document", "-scanner.defaultPreset", "original",
                                               "-scanner.autoOnEntry", "NO"]

    func testReviewEditsSaveAndReopen() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: "/tmp/papernest-scanner-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
            UIColor.purple.setFill(); context.fill(CGRect(x: 24, y: 36, width: 120, height: 200))
        }
        try XCTUnwrap(image.pngData()).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let library = "/tmp/papernest-scanner-ui-\(UUID().uuidString)"
        let app = XCUIApplication()
        let base = ["-PaperNestLibraryPath", library, "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)",
                    "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launchArguments = base + ["-PaperNestDebugScannerImages", fixture.path + ";" + fixture.path]
        app.launchArguments += Self.standardScanDefaults
        app.launch()
        defer { app.terminate() }
        let finish = app.buttons["scanner.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 25))
        XCTAssertTrue(finish.isHittable, "Scan Save must be reachable below the status area")
        let statusBar = app.statusBars.firstMatch
        let safeTop = statusBar.exists ? statusBar.frame.maxY : app.frame.minY + (UIDevice.current.userInterfaceIdiom == .phone ? 44 : 24)
        XCTAssertGreaterThanOrEqual(finish.frame.minY, safeTop,
                                    "Custom scanner review must respect the device's top safe area")
        let name = app.textFields["scanner.name"]
        name.tap()
        name.press(forDuration: 1.2)
        // A tap can place the insertion point inside the generated timestamp;
        // deleting value.count characters only removes text before that caret.
        let selectAll = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Select All")).firstMatch
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()
        name.typeText(XCUIKeyboardKey.delete.rawValue)
        let clearedName = name.value as? String ?? ""
        XCTAssertTrue(clearedName.isEmpty || clearedName == name.placeholderValue,
                      "Clear the entire generated name, including its time suffix")
        name.typeText("Scanner workflow\n")
        XCTAssertEqual(name.value as? String, "Scanner workflow")
        app.buttons["scanner.page.1"].tap()
        let zoomIn = app.buttons["scanner.zoom.in"]
        XCTAssertTrue(zoomIn.waitForExistence(timeout: 10))
        zoomIn.tap()
        XCTAssertEqual(app.buttons["scanner.zoom.fit"].value as? String, "150%")
        let zoomedPreview = app.descendants(matching: .any)["scanner.preview"].firstMatch
        let beforePan = zoomedPreview.value as? String
        let panStart = zoomedPreview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        panStart.press(forDuration: 0.1, thenDragTo: panStart.withOffset(CGVector(dx: 20, dy: 25)))
        XCTAssertNotEqual(zoomedPreview.value as? String, beforePan)
        app.buttons["scanner.zoom.fit"].tap()
        XCTAssertEqual(app.buttons["scanner.zoom.fit"].value as? String, "100%")
        let enhance = tool(app, "sparkles")
        let beforeEnhance = enhance.value as? String
        enhance.tap()
        XCTAssertNotEqual(enhance.value as? String, beforeEnhance)
        tool(app, "rotate.right").tap()
        let preview = app.descendants(matching: .any)["scanner.preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue((preview.value as? String ?? "").contains("Rotate 1"))
        tool(app, "crop").tap()
        let corner = app.descendants(matching: .any)["scanner.corner.0"].firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scanner.zoom.in"].exists)
        let initial = corner.value as? String
        let start = corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 24, dy: 28)))
        XCTAssertNotEqual(corner.value as? String, initial)
        tool(app, "crop").tap()
        tool(app, "arrow.counterclockwise").tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue((preview.value as? String ?? "").contains("Rotate 0"))
        // On iPad the tools panel has its own Duplicate and Move earlier, so
        // the page's menu items are the ones without a tool identifier.
        func menuItem(_ title: String) -> XCUIElement {
            app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "scanner.tool.")).firstMatch
        }
        app.buttons["scanner.page.1"].press(forDuration: 1)
        XCTAssertTrue(menuItem("Duplicate").waitForExistence(timeout: 5))
        menuItem("Duplicate").tap()
        XCTAssertTrue(app.buttons["scanner.page.2"].waitForExistence(timeout: 5))
        app.buttons["scanner.page.2"].press(forDuration: 1)
        XCTAssertTrue(menuItem("Move earlier").waitForExistence(timeout: 5))
        menuItem("Move earlier").tap()
        tool(app, "trash").tap()
        XCTAssertFalse(app.buttons["scanner.page.2"].exists)
        XCTAssertTrue(finish.isHittable, "Save must remain reachable after review edits")
        XCTAssertEqual(name.value as? String, "Scanner workflow")
        finish.tap()
        XCTAssertTrue(app.buttons["import-location-save"].waitForExistence(timeout: 15))
        app.buttons["import-location-save"].tap()
        // A saved scan stays closed. Export opens for it by itself, and
        // closing Export goes back to Home.
        let export = app.buttons["export-destination-share"].firstMatch
        XCTAssertTrue(export.waitForExistence(timeout: 30), "saving a scan must open its export screen")
        XCTAssertFalse(app.buttons["editor-back"].exists, "a saved scan must not open in the editor")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scan-saved-export"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["home-see-all"].waitForExistence(timeout: 15), "closing Export returns to Home")
        XCTAssertFalse(app.buttons["editor-back"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Scanner workflow, 2 pages")).firstMatch
            .waitForExistence(timeout: 15), "the saved scan is in Home's recent documents")
        app.terminate()
        app.launchArguments = base + ["-PaperNestDebugOpenItem", "Scanner workflow"]
        app.launchArguments += Self.standardScanDefaults
        app.launch()
        // The editor's Back button says the saved scan opens; which toolbar
        // items fit beside it is the editor's business, not the scanner's.
        XCTAssertTrue(app.buttons["editor-back"].waitForExistence(timeout: 30))
        XCTAssertEqual(app.descendants(matching: .any)["document-page-image"].firstMatch.label, "Page 1 of 2")
    }

    /// The owner's rule for a saved scan, on its own and without the long
    /// editing sequence above: Export opens by itself, the editor does not,
    /// and closing Export without exporting lands on Home.
    func testSavingAScanOpensExportAndClosingItReturnsHome() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: "/tmp/papernest-scanner-export-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
            UIColor.purple.setFill(); context.fill(CGRect(x: 24, y: 36, width: 120, height: 200))
        }
        try XCTUnwrap(image.pngData()).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-scanner-export-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-PaperNestDebugScannerImages", fixture.path]
        app.launchArguments += Self.standardScanDefaults
        app.launch()
        defer { app.terminate() }
        let finish = app.buttons["scanner.finish"]
        XCTAssertTrue(finish.waitForExistence(timeout: 25))
        finish.tap()
        XCTAssertTrue(app.buttons["import-location-save"].waitForExistence(timeout: 15))
        app.buttons["import-location-save"].tap()
        XCTAssertTrue(app.buttons["export-destination-share"].firstMatch.waitForExistence(timeout: 30),
                      "saving a scan must open its export screen without being asked")
        XCTAssertFalse(app.buttons["editor-back"].exists, "a saved scan must not open in the editor")
        XCTAssertEqual(app.alerts.count, 0, "nothing stands between saving and the export screen")
        app.buttons["Cancel"].firstMatch.tap()
        XCTAssertTrue(app.buttons["home-see-all"].waitForExistence(timeout: 15), "closing Export returns to Home")
        XCTAssertFalse(app.buttons["export-destination-share"].exists)
        XCTAssertFalse(app.buttons["editor-back"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Scan ")).firstMatch
            .waitForExistence(timeout: 15), "the saved scan is in Home's recent documents")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scan-saved-home"; shot.lifetime = .keepAlways; add(shot)
    }

    /// Photo is a mode that does something: it keeps the whole frame instead of
    /// cropping to detected edges, and it has no automatic shutter. The shutter
    /// takes the test's fixture bytes through the same path a camera still takes.
    func testPhotoModeKeepsTheWholeFrameAndTurnsAutoOff() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: "/tmp/papernest-scanner-photo-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
            UIColor.purple.setFill(); context.fill(CGRect(x: 24, y: 36, width: 120, height: 200))
        }
        try XCTUnwrap(image.pngData()).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-scanner-photo-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-PaperNestDebugScannerImages", fixture.path, "-PaperNestDebugScannerPendingCapture", "YES"]
        app.launchArguments += Self.standardScanDefaults
        app.launch()
        defer { app.terminate() }
        // The fixture arrives as a capture waiting for its answer. Keeping it
        // leaves one page in the queue and the camera screen in front.
        let keepButton = app.buttons["scanner.capture-keep"]
        func keepPendingCapture() {
            XCTAssertTrue(keepButton.waitForExistence(timeout: 25))
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: keepButton)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
            keepButton.tap()
        }
        keepPendingCapture()

        let document = app.buttons["scanner.kind.document"]
        let photo = app.buttons["scanner.kind.photo"]
        let auto = app.buttons["scanner.mode"]
        XCTAssertTrue(photo.waitForExistence(timeout: 10))
        XCTAssertTrue(document.isSelected)
        XCTAssertTrue(auto.isEnabled)
        XCTAssertFalse(app.buttons["scanner.kind.idcard"].exists, "only modes that do something are offered")
        XCTAssertFalse(app.buttons["scanner.kind.book"].exists, "only modes that do something are offered")
        auto.tap()
        XCTAssertEqual(auto.value as? String, "On")
        photo.tap()
        XCTAssertTrue(photo.isSelected)
        XCTAssertFalse(auto.isEnabled, "a photo has no sheet to wait for, so no automatic shutter")
        XCTAssertEqual(auto.value as? String, "Off", "choosing Photo turns Auto off")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scanner-photo-mode"; shot.lifetime = .keepAlways; add(shot)

        let review = app.buttons["scanner.review"]
        XCTAssertEqual(review.value as? String, "1")
        app.buttons["scanner.shutter"].tap()
        // The photo is shown for Keep or Delete like any capture, and is not
        // in the queue until it is kept.
        XCTAssertTrue(keepButton.waitForExistence(timeout: 20))
        XCTAssertFalse(review.exists, "an undecided capture is not in the queue")
        keepPendingCapture()
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "2"), evaluatedWith: review)], timeout: 20)
        review.tap()
        XCTAssertTrue(app.buttons["scanner.page.1"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["scanner.page.1"].isSelected, "the new capture is the page being shown")
        tool(app, "crop").tap()
        let topLeft = app.descendants(matching: .any)["scanner.corner.0"].firstMatch
        let bottomRight = app.descendants(matching: .any)["scanner.corner.2"].firstMatch
        XCTAssertTrue(topLeft.waitForExistence(timeout: 10))
        XCTAssertEqual(topLeft.value as? String, "0, 0", "a photo keeps its whole frame")
        XCTAssertEqual(bottomRight.value as? String, "100, 100", "a photo keeps its whole frame")
    }

    /// Every capture waits for Keep or Delete before it joins the queue, on
    /// iPhone as on iPad (owner, 2026-11-13).
    func testCaptureIsKeptOrDeletedBeforeQueueing() throws {
        continueAfterFailure = false
        let fixture = URL(fileURLWithPath: "/tmp/papernest-capture-decision-\(UUID()).png")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
            UIColor.purple.setFill(); context.fill(CGRect(x: 24, y: 36, width: 120, height: 200))
        }
        try XCTUnwrap(image.pngData()).write(to: fixture)
        defer { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        defer { app.terminate() }
        for keep in [false, true] {
            app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-capture-review-\(UUID())",
                "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)",
                "-PaperNestDebugScannerImages", fixture.path + ";" + fixture.path,
                "-PaperNestDebugScannerPendingCapture", "YES"]
            app.launchArguments += Self.standardScanDefaults
            app.launch()
            let keepButton = app.buttons["scanner.capture-keep"]
            let deleteButton = app.buttons["scanner.capture-delete"]
            XCTAssertTrue(keepButton.waitForExistence(timeout: 25))
            XCTAssertTrue(deleteButton.isHittable)
            XCTAssertFalse(app.buttons["scanner.finish"].exists, "Unaccepted scan cannot be saved as part of the queue")
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: keepButton)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
            XCTAssertTrue(keepButton.isHittable)
            if keep {
                XCUIDevice.shared.press(.home)
                app.activate()
                XCTAssertTrue(keepButton.waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["scanner.review"].exists,
                               "Returning from background must retain the undecided scan")
            }
            (keep ? keepButton : deleteButton).tap()
            let queue = app.buttons["scanner.review"]
            XCTAssertTrue(queue.waitForExistence(timeout: 10))
            XCTAssertEqual(queue.value as? String, keep ? "2" : "1")
            // A second capture uses the actual correction/review path. The
            // accepted queue cannot change while the decision is pending.
            if !keep {
                app.buttons["scanner.shutter"].tap()
                XCTAssertTrue(keepButton.waitForExistence(timeout: 15))
                let secondReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: keepButton)
                XCTAssertEqual(XCTWaiter.wait(for: [secondReady], timeout: 10), .completed)
                keepButton.tap()
                XCTAssertTrue(queue.waitForExistence(timeout: 10))
                XCTAssertEqual(queue.value as? String, "2")
            }
            queue.tap()
            XCTAssertTrue(app.buttons["scanner.page.0"].waitForExistence(timeout: 10))
            XCTAssertTrue(app.buttons["scanner.page.1"].exists)
            XCTAssertFalse(app.buttons["scanner.page.2"].exists)
            app.terminate()
        }
    }

    // MARK: - Scan Studio: presets, Cleanup and several pages at once

    /// Opens the review screen on `pageCount` copies of one synthetic page.
    private func launchReview(pageCount: Int, named name: String) throws -> XCUIApplication {
        let fixture = URL(fileURLWithPath: "/tmp/papernest-scan-studio-\(name)-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 320), format: format).image { context in
            UIColor(red: 0.88, green: 0.85, blue: 0.78, alpha: 1).setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 320))
            UIColor.purple.setFill(); context.fill(CGRect(x: 24, y: 36, width: 120, height: 200))
        }
        try XCTUnwrap(image.pngData()).write(to: fixture)
        addTeardownBlock { try? FileManager.default.removeItem(at: fixture) }
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-scan-studio-\(name)-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-PaperNestDebugScannerImages", Array(repeating: fixture.path, count: pageCount).joined(separator: ";")]
        app.launchArguments += Self.standardScanDefaults
        app.launch()
        return app
    }

    /// The page on screen says its number, turn, preset and Cleanup amounts.
    private func expectPage(_ app: XCUIApplication, toShow text: String, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let preview = app.descendants(matching: .any)["scanner.preview"].firstMatch
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value CONTAINS %@", text), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 20), .completed,
                       "\(message): expected \"\(text)\" in \"\(preview.value as? String ?? "nothing")\"", file: file, line: line)
    }

    /// A page tool, brought into view first. On a phone the tools are one
    /// row wider than the screen, and a tool that starts off its edge cannot
    /// be tapped until the row is dragged along. Position decides, not
    /// `isHittable`: asking that of a tool off the edge is itself a failure.
    private func tool(_ app: XCUIApplication, _ symbol: String) -> XCUIElement {
        let wanted = app.buttons["scanner.tool.\(symbol)"]
        let screen = app.windows.firstMatch.frame
        func isInView(_ element: XCUIElement) -> Bool {
            element.frame.minX >= screen.minX + 8 && element.frame.maxX <= screen.maxX - 8
        }
        let row = ["crop", "rotate.right", "camera.filters", "sparkles", "slider.horizontal.3", "checklist",
                   "arrow.counterclockwise", "trash"].map { app.buttons["scanner.tool.\($0)"] }
        for _ in 0..<5 where wanted.exists && !isInView(wanted) {
            let showing = row.filter { $0.exists && isInView($0) }
            guard let first = showing.first, let last = showing.last else { break }
            // Drag from the far end of what is showing, toward the tool.
            let isToTheRight = wanted.frame.midX > screen.midX
            let grip = (isToTheRight ? last : first).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            grip.press(forDuration: 0.05, thenDragTo: grip.withOffset(CGVector(dx: isToTheRight ? -150 : 150, dy: 0)))
        }
        return wanted
    }

    /// A menu's item, as distinct from a tile or tool that carries the same name.
    private func menuItem(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@ AND NOT (identifier BEGINSWITH %@)", title, "scanner.")).firstMatch
    }

    /// Cleanup opens, its controls move, and what it changes is exactly what
    /// the button pressed says: this page, or every page, or nothing on Cancel.
    func testCleanupAppliesToThisPageOrToAllPages() throws {
        continueAfterFailure = false
        let app = try launchReview(pageCount: 3, named: "cleanup")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["scanner.finish"].waitForExistence(timeout: 25))
        expectPage(app, toShow: "1; Rotate 0; Filter original; Cleanup 0/0/0", "a new page has no Cleanup")
        let cleanup = tool(app, "slider.horizontal.3")
        XCTAssertEqual(cleanup.value as? String, "Not selected")

        cleanup.tap()
        let shadows = app.sliders["scanner.cleanup.shadows"]
        XCTAssertTrue(shadows.waitForExistence(timeout: 10), "the Cleanup tool opens Cleanup")
        XCTAssertTrue(app.sliders["scanner.cleanup.whiten"].exists)
        XCTAssertTrue(app.sliders["scanner.cleanup.sharpen"].exists)
        let amounts = app.descendants(matching: .any)["scanner.cleanup.preview"].firstMatch
        XCTAssertEqual(amounts.value as? String, "0/0/0", "the sheet starts from what the page has")
        shadows.adjust(toNormalizedSliderPosition: 0.7)
        let moved = amounts.value as? String ?? ""
        XCTAssertFalse(moved.hasPrefix("0/"), "moving Remove shadows changes its amount, got \(moved)")
        XCTAssertTrue(moved.hasSuffix("/0/0"), "and no other amount, got \(moved)")
        app.buttons["scanner.cleanup.recommended"].tap()
        XCTAssertEqual(amounts.value as? String, "85/50/40")
        app.buttons["Before"].tap()
        XCTAssertEqual(amounts.label, "Before")
        XCTAssertEqual(amounts.value as? String, "0/0/0", "Before is the page without Cleanup")
        app.buttons["After"].tap()
        XCTAssertEqual(amounts.value as? String, "85/50/40", "comparing does not lose the amounts")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scanner-cleanup-sheet"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["scanner.cleanup.apply-page"].tap()
        XCTAssertTrue(shadows.waitForNonExistence(timeout: 10), "applying closes Cleanup")
        expectPage(app, toShow: "1; Rotate 0; Filter original; Cleanup 85/50/40", "Apply to this page changes the page shown")
        XCTAssertEqual(cleanup.value as? String, "Selected", "the tool shows that this page has Cleanup")

        app.buttons["scanner.page.1"].tap()
        expectPage(app, toShow: "2; Rotate 0; Filter original; Cleanup 0/0/0", "and no other page")
        XCTAssertEqual(cleanup.value as? String, "Not selected")

        // Cancel changes nothing, whatever the sliders said.
        app.buttons["scanner.preset.cleanup"].tap()
        XCTAssertTrue(shadows.waitForExistence(timeout: 10), "the strip's Cleanup tile opens Cleanup too")
        app.buttons["scanner.cleanup.recommended"].tap()
        app.buttons["scanner.cleanup.cancel"].tap()
        XCTAssertTrue(shadows.waitForNonExistence(timeout: 10))
        expectPage(app, toShow: "2; Rotate 0; Filter original; Cleanup 0/0/0", "Cancel leaves the page as it was")

        app.buttons["scanner.preset.cleanup"].tap()
        XCTAssertTrue(shadows.waitForExistence(timeout: 10))
        app.sliders["scanner.cleanup.whiten"].adjust(toNormalizedSliderPosition: 1)
        app.buttons["scanner.cleanup.recommended"].tap()
        XCTAssertEqual(amounts.value as? String, "85/50/40", "Recommended replaces whatever the sliders said")
        app.buttons["scanner.cleanup.apply-all"].tap()
        XCTAssertTrue(shadows.waitForNonExistence(timeout: 10))
        for index in 0..<3 {
            app.buttons["scanner.page.\(index)"].tap()
            expectPage(app, toShow: "\(index + 1); Rotate 0; Filter original; Cleanup 85/50/40", "Apply to all pages reaches page \(index + 1)")
        }

        // Reset is still the way back, one page at a time.
        tool(app, "arrow.counterclockwise").tap()
        expectPage(app, toShow: "3; Rotate 0; Filter original; Cleanup 0/0/0", "Reset removes Cleanup from the page shown")
        app.buttons["scanner.page.0"].tap()
        expectPage(app, toShow: "1; Rotate 0; Filter original; Cleanup 85/50/40", "and from no other page")

        app.buttons["scanner.finish"].tap()
        XCTAssertTrue(app.buttons["import-location-save"].waitForExistence(timeout: 20), "cleaned pages still save")
    }

    /// Each page has its own preset, and the strip, the Filter menu and
    /// Enhance all show and set that one value.
    func testPresetsBelongToEachPageAndEveryControlShowsThem() throws {
        continueAfterFailure = false
        let app = try launchReview(pageCount: 2, named: "presets")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["scanner.finish"].waitForExistence(timeout: 25))
        func tile(_ preset: String) -> XCUIElement { app.buttons["scanner.preset.\(preset)"] }
        XCTAssertTrue(tile("original").waitForExistence(timeout: 10))
        XCTAssertEqual(tile("original").value as? String, "Selected")
        XCTAssertEqual(tile("grayscale").value as? String, "Not selected")

        tile("grayscale").tap()
        XCTAssertEqual(tile("grayscale").value as? String, "Selected")
        XCTAssertEqual(tile("original").value as? String, "Not selected", "a page has one preset at a time")
        expectPage(app, toShow: "1; Rotate 0; Filter grayscale", "the tile changes the page")

        app.buttons["scanner.page.1"].tap()
        expectPage(app, toShow: "2; Rotate 0; Filter original", "the other page keeps its own preset")
        XCTAssertEqual(tile("original").value as? String, "Selected", "the strip follows the page shown")
        XCTAssertEqual(tile("grayscale").value as? String, "Not selected")

        let enhance = tool(app, "sparkles")
        enhance.tap()
        XCTAssertEqual(enhance.value as? String, "Selected")
        XCTAssertEqual(tile("auto").value as? String, "Selected", "Enhance is the Auto preset")
        expectPage(app, toShow: "2; Rotate 0; Filter auto", "Enhance changes the page")

        let filter = tool(app, "camera.filters")
        filter.tap()
        XCTAssertTrue(menuItem(app, "High Contrast").waitForExistence(timeout: 5), "the Filter menu names every preset")
        XCTAssertTrue(menuItem(app, "Black & White").exists)
        menuItem(app, "High Contrast").tap()
        expectPage(app, toShow: "2; Rotate 0; Filter highContrast", "the menu changes the page")
        XCTAssertEqual(tile("highContrast").value as? String, "Selected")
        XCTAssertEqual(enhance.value as? String, "Not selected")
        XCTAssertEqual(filter.value as? String, "High Contrast")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scanner-presets"; shot.lifetime = .keepAlways; add(shot)

        app.buttons["scanner.page.0"].tap()
        expectPage(app, toShow: "1; Rotate 0; Filter grayscale", "page 1 still has what it was given")
        XCTAssertEqual(tile("grayscale").value as? String, "Selected")
        tool(app, "arrow.counterclockwise").tap()
        expectPage(app, toShow: "1; Rotate 0; Filter original", "Reset returns the page to Original")
        XCTAssertEqual(tile("original").value as? String, "Selected")
    }

    /// Picking pages in the filmstrip, then one action for all of them:
    /// filter, Cleanup, move as a group, duplicate, and delete, which asks
    /// first only when more than one page would go.
    func testPickedPagesAreChangedMovedDuplicatedAndDeletedTogether() throws {
        continueAfterFailure = false
        let app = try launchReview(pageCount: 3, named: "batch")
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["scanner.finish"].waitForExistence(timeout: 25))
        func page(_ index: Int) -> XCUIElement { app.buttons["scanner.page.\(index)"] }
        let count = app.staticTexts["scanner.batch.count"]
        func startPicking() {
            tool(app, "checklist").tap()
            XCTAssertTrue(count.waitForExistence(timeout: 10), "Select pages shows the selection bar")
        }
        func stopPicking() {
            app.buttons["scanner.batch.close"].tap()
            XCTAssertTrue(count.waitForNonExistence(timeout: 10))
        }

        startPicking()
        XCTAssertEqual(count.value as? String, "0")
        XCTAssertFalse(app.buttons["scanner.batch.delete"].isEnabled, "nothing is picked, so nothing can be deleted")
        page(0).tap(); page(2).tap()
        XCTAssertEqual(count.value as? String, "2")
        XCTAssertEqual(page(0).value as? String, "Selected")
        XCTAssertEqual(page(1).value as? String, "Not selected")
        page(2).tap()
        XCTAssertEqual(count.value as? String, "1", "a second tap unpicks")
        page(2).tap()
        XCTAssertEqual(count.value as? String, "2")
        let picked = XCTAttachment(screenshot: app.screenshot())
        picked.name = "scanner-pages-picked"; picked.lifetime = .keepAlways; add(picked)

        app.buttons["scanner.batch.filter"].tap()
        XCTAssertTrue(menuItem(app, "Grayscale").waitForExistence(timeout: 5))
        menuItem(app, "Grayscale").tap()
        app.buttons["scanner.batch.cleanup"].tap()
        XCTAssertTrue(app.buttons["scanner.cleanup.recommended"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["scanner.cleanup.apply-all"].exists, "picked pages are offered the picked pages, not all")
        app.buttons["scanner.cleanup.recommended"].tap()
        app.buttons["scanner.cleanup.apply-selected"].tap()
        XCTAssertTrue(app.buttons["scanner.cleanup.recommended"].waitForNonExistence(timeout: 10))
        stopPicking()
        for (index, look) in [(0, "Filter grayscale; Cleanup 85/50/40"), (1, "Filter original; Cleanup 0/0/0"),
                              (2, "Filter grayscale; Cleanup 85/50/40")] {
            page(index).tap()
            expectPage(app, toShow: "\(index + 1); Rotate 0; \(look)", "page \(index + 1) after the batch filter and Cleanup")
        }

        // Move: the one untouched page, second of three, goes to the front.
        startPicking()
        page(1).tap()
        XCTAssertTrue(app.buttons["scanner.batch.earlier"].isEnabled)
        app.buttons["scanner.batch.earlier"].tap()
        XCTAssertEqual(page(0).value as? String, "Selected", "the picked page is now first and still picked")
        XCTAssertFalse(app.buttons["scanner.batch.earlier"].isEnabled, "it cannot go earlier than first")
        stopPicking()
        page(0).tap()
        expectPage(app, toShow: "1; Rotate 0; Filter original; Cleanup 0/0/0", "the untouched page moved to the front")
        page(1).tap()
        expectPage(app, toShow: "2; Rotate 0; Filter grayscale; Cleanup 85/50/40", "and the others moved down")

        // Duplicate: each copy follows its page and carries its look.
        startPicking()
        page(0).tap(); page(1).tap()
        app.buttons["scanner.batch.duplicate"].tap()
        XCTAssertTrue(page(4).waitForExistence(timeout: 10), "two copies make five pages")
        XCTAssertFalse(page(5).exists)
        stopPicking()
        for (index, look) in [(0, "Filter original; Cleanup 0/0/0"), (1, "Filter original; Cleanup 0/0/0"),
                              (2, "Filter grayscale; Cleanup 85/50/40"), (3, "Filter grayscale; Cleanup 85/50/40")] {
            page(index).tap()
            expectPage(app, toShow: "\(index + 1); Rotate 0; \(look)", "page \(index + 1) after duplicating")
        }

        // Delete several: asked first, and Cancel keeps them.
        startPicking()
        page(2).tap(); page(3).tap(); page(4).tap()
        app.buttons["scanner.batch.delete"].tap()
        let alert = app.alerts["Delete 3 pages?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10), "deleting several pages asks first")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(page(4).exists, "Cancel keeps the pages")
        XCTAssertEqual(count.value as? String, "3")
        app.buttons["scanner.batch.delete"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Delete"].tap()
        XCTAssertTrue(page(2).waitForNonExistence(timeout: 10), "three of five pages are gone")
        XCTAssertTrue(page(1).exists)
        XCTAssertEqual(count.value as? String, "0")
        // Delete one: no question, as with the single-page Delete.
        page(1).tap()
        app.buttons["scanner.batch.delete"].tap()
        XCTAssertTrue(page(1).waitForNonExistence(timeout: 10))
        XCTAssertEqual(app.alerts.count, 0, "one page is deleted without asking")
        stopPicking()
        expectPage(app, toShow: "1; Rotate 0; Filter original; Cleanup 0/0/0", "the page left is the untouched one")
        XCTAssertTrue(app.buttons["scanner.finish"].isEnabled)
    }

    // MARK: - Scan Studio: Whiteboard, ID / Card and Scan settings

    /// A picture `size` with one light rectangle on a dark ground, written to a file.
    private func fixture(_ name: String, size: CGSize, shape: CGRect) throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/papernest-scan-mode-\(name)-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.25, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.9, alpha: 1).setFill(); context.fill(shape)
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Opens the scanner with `picture` waiting for Keep or Delete; the
    /// shutter then delivers the same picture, as a camera still would.
    private func launchCapture(_ picture: URL, named name: String, pinningDefaults: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-scan-mode-\(name)-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-PaperNestDebugScannerImages", picture.path, "-PaperNestDebugScannerPendingCapture", "YES"]
        if pinningDefaults { app.launchArguments += Self.standardScanDefaults }
        app.launch()
        return app
    }

    private func keepCapture(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let keep = app.buttons["scanner.capture-keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 25), "the capture is shown for Keep or Delete", file: file, line: line)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: keep)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, file: file, line: line)
        keep.tap()
    }

    /// A crop corner's place, as whole percentages of the capture.
    private func corner(_ app: XCUIApplication, _ index: Int) -> (x: Int, y: Int)? {
        let value = app.descendants(matching: .any)["scanner.corner.\(index)"].firstMatch.value as? String ?? ""
        let parts = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    /// Whiteboard is a mode that does something: it crops to a board that
    /// Document mode does not find, and the capture starts with the board's
    /// look. The chips that said Coming soon are gone.
    func testWhiteboardModeFindsTheBoardAndStartsWithItsLook() throws {
        continueAfterFailure = false
        // A board much wider than it is tall, as a wall board is: 0.4 of its long side.
        let board = try fixture("board", size: CGSize(width: 800, height: 600), shape: CGRect(x: 40, y: 156, width: 720, height: 288))
        let app = launchCapture(board, named: "whiteboard")
        defer { app.terminate() }
        keepCapture(app)
        for mode in ["document", "whiteboard", "photo", "card"] {
            XCTAssertTrue(app.buttons["scanner.kind.\(mode)"].waitForExistence(timeout: 10), "\(mode) is offered")
        }
        XCTAssertEqual(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "coming soon")).count, 0,
                       "a mode that works is not marked Coming soon")
        XCTAssertTrue(app.buttons["scanner.kind.document"].isSelected)

        // The same picture in Document mode first: that board is not a document's shape.
        app.buttons["scanner.shutter"].tap()
        keepCapture(app)
        app.buttons["scanner.kind.whiteboard"].tap()
        XCTAssertTrue(app.buttons["scanner.kind.whiteboard"].isSelected)
        XCTAssertTrue(app.buttons["scanner.mode"].isEnabled, "a board is a rectangle to wait for, so Auto is offered")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scanner-four-modes"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["scanner.shutter"].tap()
        keepCapture(app)

        let review = app.buttons["scanner.review"]
        wait(for: [expectation(for: NSPredicate(format: "value == %@", "3"), evaluatedWith: review)], timeout: 20)
        review.tap()
        expectPage(app, toShow: "3; Rotate 0; Filter highContrast; Cleanup 100/60/20", "a board capture starts with the board's look")
        tool(app, "crop").tap()
        XCTAssertTrue(app.descendants(matching: .any)["scanner.corner.0"].firstMatch.waitForExistence(timeout: 10))
        let topLeft = try XCTUnwrap(corner(app, 0)), bottomRight = try XCTUnwrap(corner(app, 2))
        XCTAssertTrue(abs(topLeft.x - 5) <= 3 && abs(topLeft.y - 26) <= 3, "Whiteboard crops to the board, got \(topLeft)")
        XCTAssertTrue(abs(bottomRight.x - 95) <= 3 && abs(bottomRight.y - 74) <= 3, "Whiteboard crops to the board, got \(bottomRight)")
        tool(app, "crop").tap()

        app.buttons["scanner.page.1"].tap()
        expectPage(app, toShow: "2; Rotate 0; Filter original; Cleanup 0/0/0", "a document capture has no look of its own")
        tool(app, "crop").tap()
        XCTAssertTrue(app.descendants(matching: .any)["scanner.corner.0"].firstMatch.waitForExistence(timeout: 10))
        let whole = try XCTUnwrap(corner(app, 0)), wholeEnd = try XCTUnwrap(corner(app, 2))
        XCTAssertTrue(whole == (0, 0) && wholeEnd == (100, 100), "Document mode does not take that board, got \(whole) to \(wholeEnd)")
        tool(app, "crop").tap()

        // The look is a starting point: Reset still gives back the capture as taken.
        app.buttons["scanner.page.2"].tap()
        tool(app, "arrow.counterclockwise").tap()
        expectPage(app, toShow: "3; Rotate 0; Filter original; Cleanup 0/0/0", "Reset removes the board's look")
    }

    /// A card is two captures: the front, then a question, then the back if
    /// asked for. The two stay separate pages that say which side they are.
    func testCardModeAsksForTheBackAndNamesBothSides() throws {
        continueAfterFailure = false
        // 85.6 by 54 in proportion: 300 by 189, a quarter of the way in.
        let card = try fixture("card", size: CGSize(width: 600, height: 800), shape: CGRect(x: 150, y: 320, width: 300, height: 189))
        let app = launchCapture(card, named: "card")
        defer { app.terminate() }
        keepCapture(app)
        let side = app.staticTexts["scanner.card.side"]
        let scanBack = app.buttons["scanner.card.scan-back"], carryOn = app.buttons["scanner.card.continue"]
        XCTAssertTrue(app.buttons["scanner.kind.card"].waitForExistence(timeout: 10))
        XCTAssertFalse(side.exists, "sides are a card's; a document has none")
        app.buttons["scanner.kind.card"].tap()
        XCTAssertTrue(side.waitForExistence(timeout: 5))
        XCTAssertEqual(side.label, "Front")

        app.buttons["scanner.shutter"].tap()
        keepCapture(app)
        XCTAssertTrue(scanBack.waitForExistence(timeout: 10), "keeping a front asks about its back")
        XCTAssertTrue(app.staticTexts["Front saved"].exists)
        XCTAssertEqual(side.label, "Front", "nothing is a back until it is asked for")
        let asked = XCTAttachment(screenshot: app.screenshot())
        asked.name = "scanner-card-back-offer"; asked.lifetime = .keepAlways; add(asked)
        scanBack.tap()
        XCTAssertTrue(scanBack.waitForNonExistence(timeout: 5))
        XCTAssertEqual(side.label, "Back")

        app.buttons["scanner.shutter"].tap()
        keepCapture(app)
        XCTAssertTrue(side.waitForExistence(timeout: 10))
        XCTAssertEqual(side.label, "Front", "the card is complete; the next capture starts another")
        XCTAssertFalse(scanBack.exists, "a back is not asked about")

        // A second card, front only.
        app.buttons["scanner.shutter"].tap()
        keepCapture(app)
        XCTAssertTrue(carryOn.waitForExistence(timeout: 10))
        carryOn.tap()
        XCTAssertTrue(carryOn.waitForNonExistence(timeout: 5))
        XCTAssertEqual(side.label, "Front")

        // A third, and the mode is left with the question still up.
        app.buttons["scanner.shutter"].tap()
        keepCapture(app)
        XCTAssertTrue(scanBack.waitForExistence(timeout: 10))
        app.buttons["scanner.kind.document"].tap()
        XCTAssertTrue(scanBack.waitForNonExistence(timeout: 5), "leaving Card mode withdraws the question")
        XCTAssertFalse(side.exists)

        let review = app.buttons["scanner.review"]
        XCTAssertEqual(review.value as? String, "5")
        review.tap()
        func page(_ index: Int) -> XCUIElement { app.buttons["scanner.page.\(index)"] }
        XCTAssertTrue(page(4).waitForExistence(timeout: 10))
        XCTAssertEqual(page(0).label, "Review scan 1", "the page kept before Card mode is not a side")
        XCTAssertEqual(page(1).label, "Review scan 2, Front")
        XCTAssertEqual(page(2).label, "Review scan 3, Back", "the back follows its front")
        XCTAssertEqual(page(3).label, "Review scan 4, Front")
        XCTAssertEqual(page(4).label, "Review scan 5, Front")
        let sides = XCTAttachment(screenshot: app.screenshot())
        sides.name = "scanner-card-sides"; sides.lifetime = .keepAlways; add(sides)

        // Card mode cropped to the card, not to the frame.
        page(1).tap()
        tool(app, "crop").tap()
        XCTAssertTrue(app.descendants(matching: .any)["scanner.corner.0"].firstMatch.waitForExistence(timeout: 10))
        let topLeft = try XCTUnwrap(corner(app, 0)), bottomRight = try XCTUnwrap(corner(app, 2))
        XCTAssertTrue(abs(topLeft.x - 25) <= 3 && abs(topLeft.y - 40) <= 3, "Card mode crops to the card, got \(topLeft)")
        XCTAssertTrue(abs(bottomRight.x - 75) <= 3 && abs(bottomRight.y - 63) <= 3, "Card mode crops to the card, got \(bottomRight)")
        tool(app, "crop").tap()

        // Each side is its own page: deleting the front leaves the back, still named.
        tool(app, "trash").tap()
        XCTAssertTrue(page(4).waitForNonExistence(timeout: 10))
        XCTAssertEqual(page(1).label, "Review scan 2, Back")
        XCTAssertEqual(page(2).label, "Review scan 3, Front")
    }

    /// Scan settings are defaults: they decide how the scanner opens next
    /// time and what a new capture starts with, and nothing about now.
    /// This test is the one that does not pin them, and puts them back.
    func testScanSettingsDecideHowTheScannerOpensNextTime() throws {
        continueAfterFailure = false
        let card = try fixture("settings", size: CGSize(width: 600, height: 800), shape: CGRect(x: 150, y: 320, width: 300, height: 189))
        var app = launchCapture(card, named: "settings", pinningDefaults: false)
        defer { app.terminate() }
        func openSettings() {
            app.buttons["scanner.more"].tap()
            let item = app.buttons["Scan settings"]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Scan settings is in More")
            item.tap()
            XCTAssertTrue(app.buttons["scanner.settings.done"].waitForExistence(timeout: 10))
        }
        func choose(mode: String, preset: String, automatic: Bool) {
            app.buttons["scanner.settings.mode.\(mode)"].tap()
            app.buttons["scanner.settings.preset.\(preset)"].tap()
            XCTAssertEqual(app.buttons["scanner.settings.mode.\(mode)"].value as? String, "Selected")
            XCTAssertEqual(app.buttons["scanner.settings.preset.\(preset)"].value as? String, "Selected")
            // The list makes its rows as they come into view, so on a sheet
            // shorter than the list the last row does not exist until it is
            // scrolled to, and then it can still be lying under Done, which
            // stays put below the list. Scroll until it is clear of Done.
            let toggle = app.switches["scanner.settings.auto"]
            let done = app.buttons["scanner.settings.done"]
            for _ in 0..<3 where !toggle.exists || toggle.frame.maxY > done.frame.minY - 8 { app.swipeUp() }
            XCTAssertTrue(toggle.waitForExistence(timeout: 5), "the Auto capture switch is in the list")
            XCTAssertLessThanOrEqual(toggle.frame.maxY, done.frame.minY, "the last setting scrolls clear of Done")
            if (toggle.value as? String == "1") != automatic {
                // The switch itself, at the row's trailing edge; the row's middle is its name.
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
            }
            XCTAssertEqual(toggle.value as? String, automatic ? "1" : "0")
            app.buttons["scanner.settings.done"].tap()
            XCTAssertTrue(app.buttons["scanner.settings.done"].waitForNonExistence(timeout: 10))
        }
        func relaunch() {
            app.terminate()
            app = launchCapture(card, named: "settings", pinningDefaults: false)
            keepCapture(app)
            XCTAssertTrue(app.buttons["scanner.kind.document"].waitForExistence(timeout: 10))
        }

        // Whatever an earlier run left: start from the standard defaults.
        keepCapture(app)
        XCTAssertTrue(app.buttons["scanner.more"].waitForExistence(timeout: 10))
        openSettings()
        choose(mode: "document", preset: "original", automatic: false)
        relaunch()
        XCTAssertTrue(app.buttons["scanner.kind.document"].isSelected)
        XCTAssertEqual(app.buttons["scanner.mode"].value as? String, "Off")

        openSettings()
        XCTAssertEqual(app.buttons["scanner.settings.mode.document"].value as? String, "Selected", "the sheet shows what is stored")
        XCTAssertEqual(app.buttons["scanner.settings.mode.card"].value as? String, "Not selected")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "scanner-settings"; shot.lifetime = .keepAlways; add(shot)
        choose(mode: "card", preset: "grayscale", automatic: true)
        XCTAssertTrue(app.buttons["scanner.kind.document"].isSelected, "a default is for next time; the mode in use stays")
        XCTAssertEqual(app.buttons["scanner.mode"].value as? String, "Off")

        relaunch()
        XCTAssertTrue(app.buttons["scanner.kind.card"].isSelected, "the scanner opens in the default mode")
        XCTAssertEqual(app.buttons["scanner.mode"].value as? String, "On", "and with the automatic shutter on")
        app.buttons["scanner.shutter"].tap()
        keepCapture(app)
        XCTAssertTrue(app.buttons["scanner.card.continue"].waitForExistence(timeout: 10))
        app.buttons["scanner.card.continue"].tap()
        app.buttons["scanner.review"].tap()
        expectPage(app, toShow: "2; Rotate 0; Filter grayscale; Cleanup 0/0/0", "a new capture starts with the default filter")
        app.buttons["scanner.page.0"].tap()
        expectPage(app, toShow: "1; Rotate 0; Filter original", "a page that was already there keeps its look")

        // Back as they were.
        app.buttons["scanner.add-page"].tap()
        XCTAssertTrue(app.buttons["scanner.more"].waitForExistence(timeout: 10))
        openSettings()
        choose(mode: "document", preset: "original", automatic: false)
        relaunch()
        XCTAssertTrue(app.buttons["scanner.kind.document"].isSelected, "the defaults are back to standard")
        XCTAssertEqual(app.buttons["scanner.mode"].value as? String, "Off")
    }

}
