import XCTest
import UIKit

@MainActor final class ScannerWorkspaceUITests: XCTestCase {
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
        let enhance = app.buttons["scanner.tool.sparkles"]
        let beforeEnhance = enhance.value as? String
        enhance.tap()
        XCTAssertNotEqual(enhance.value as? String, beforeEnhance)
        app.buttons["scanner.tool.rotate.right"].tap()
        let preview = app.descendants(matching: .any)["scanner.preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue((preview.value as? String ?? "").contains("Rotate 1"))
        app.buttons["scanner.tool.crop"].tap()
        let corner = app.descendants(matching: .any)["scanner.corner.0"].firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["scanner.zoom.in"].exists)
        let initial = corner.value as? String
        let start = corner.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 24, dy: 28)))
        XCTAssertNotEqual(corner.value as? String, initial)
        app.buttons["scanner.tool.crop"].tap()
        app.buttons["scanner.tool.arrow.counterclockwise"].tap()
        XCTAssertTrue(preview.waitForExistence(timeout: 10))
        XCTAssertTrue((preview.value as? String ?? "").contains("Rotate 0"))
        app.buttons["scanner.page.1"].press(forDuration: 1)
        app.buttons["Duplicate"].tap()
        XCTAssertTrue(app.buttons["scanner.page.2"].waitForExistence(timeout: 5))
        app.buttons["scanner.page.2"].press(forDuration: 1)
        app.buttons["Move earlier"].tap()
        app.buttons["scanner.tool.trash"].tap()
        XCTAssertFalse(app.buttons["scanner.page.2"].exists)
        XCTAssertTrue(finish.isHittable, "Save must remain reachable after review edits")
        XCTAssertEqual(name.value as? String, "Scanner workflow")
        finish.tap()
        XCTAssertTrue(app.buttons["import-location-save"].waitForExistence(timeout: 15))
        app.buttons["import-location-save"].tap()
        XCTAssertTrue(app.buttons["editor-export"].waitForExistence(timeout: 20))
        app.terminate()
        app.launchArguments = base + ["-PaperNestDebugOpenItem", "Scanner workflow"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-export"].waitForExistence(timeout: 20))
    }
    func testIPadKeepsOrDeletesCaptureBeforeQueueing() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad capture decisions") }
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

}
