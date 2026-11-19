import XCTest
import UIKit

/// Book mode through the real capture path: the debug camera delivers a
/// photo of an open book, the shutter detects it in Book mode, the capture
/// is shown with its fold marked ("Two pages"), and Keep makes it two pages,
/// each cropped to its half. What is a spread and where the fold is are
/// fixed by `ScanSpreadTests` and `ScanBookTests`.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class BookCaptureUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// A photo, 1600 × 1200, of an open book on a dark table: the spread
    /// from 10% to 90% across and 18% to 84% down, a page of print each
    /// side, and a soft shadow at the fold.
    private func bookPhoto() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/papernest-book-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 1600, height: 1200), spread = CGRect(x: 160, y: 216, width: 1280, height: 792)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.2, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.93, alpha: 1).setFill(); context.fill(spread)
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14),
                                                             .foregroundColor: UIColor(white: 0.1, alpha: 1)]
            for left in [spread.minX + 50, spread.midX + 50] {
                var y = spread.minY + 50
                while y < spread.maxY - 50 {
                    ("The quarterly report shows steady growth in every region." as NSString)
                        .draw(at: CGPoint(x: left, y: y), withAttributes: attributes)
                    y += 24
                }
            }
            // The fold's shadow: 6% of the spread wide, down to 0.6.
            for i in -30...30 {
                let shade = 0.93 - 0.33 * (1 - abs(CGFloat(i)) / 30)
                UIColor(white: shade, alpha: 1).setFill()
                context.fill(CGRect(x: spread.midX + CGFloat(i) * spread.width * 0.001 - 1, y: spread.minY,
                                    width: spread.width * 0.001 + 1, height: spread.height))
            }
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// The scanner with `photo` waiting for Keep or Delete; the shutter then
    /// delivers the same photo, as a camera still would.
    private func launchCapture(_ photo: URL, language: String = "en", largestText: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-book-library-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language,
                               "-PaperNestDebugScannerImages", photo.path, "-PaperNestDebugScannerPendingCapture", "YES",
                               "-scanner.defaultMode", "document", "-scanner.defaultPreset", "original", "-scanner.autoOnEntry", "NO"]
        if largestText { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        return app
    }

    /// A photo, 1200 × 1600, of one upright page of print on a dark table.
    private func uprightPagePhoto() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/papernest-book-page-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 1200, height: 1600), sheet = CGRect(x: 240, y: 160, width: 720, height: 1280)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.2, alpha: 1).setFill(); context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.93, alpha: 1).setFill(); context.fill(sheet)
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 14),
                                                             .foregroundColor: UIColor(white: 0.1, alpha: 1)]
            var y = sheet.minY + 50
            while y < sheet.maxY - 50 {
                ("The quarterly report shows steady growth." as NSString).draw(at: CGPoint(x: sheet.minX + 50, y: y), withAttributes: attributes)
                y += 24
            }
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// A photo with no outline in it at all: a smooth shade from dark to light.
    private func featurelessPhoto() throws -> URL {
        let url = URL(fileURLWithPath: "/tmp/papernest-book-none-\(UUID().uuidString).png")
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 1600, height: 1200)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            let colours = [UIColor(white: 0.3, alpha: 1).cgColor, UIColor(white: 0.7, alpha: 1).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1])!
            context.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
        }
        try XCTUnwrap(image.pngData()).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Takes a Book capture of the debug camera's photo and keeps it, then
    /// says how many pages the scan has and what the capture's preview said.
    private func captureInBook(_ app: XCUIApplication) -> (pages: String, preview: String) {
        app.buttons["scanner.shutter"].tap()
        let keep = app.buttons["scanner.capture-keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 25))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: keep)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
        let preview = app.descendants(matching: .any)["scanner.preview"].firstMatch.value as? String ?? ""
        keep.tap()
        let review = app.buttons["scanner.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        // The seeded page made it 1; wait for what Keep added.
        let grown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", "1"), object: review)
        _ = XCTWaiter.wait(for: [grown], timeout: 15)
        return (review.value as? String ?? "", preview)
    }

    private func keepCapture(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let keep = app.buttons["scanner.capture-keep"]
        XCTAssertTrue(keep.waitForExistence(timeout: 25), "the capture is shown for Keep or Delete", file: file, line: line)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: keep)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed, file: file, line: line)
        keep.tap()
    }

    /// Book is the last chip; where the chips do not fit, the pill scrolls.
    private func chooseBook(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let book = app.buttons["scanner.kind.book"]
        XCTAssertTrue(book.waitForExistence(timeout: 10), "Book is offered", file: file, line: line)
        // Drag along the strip itself: a chip swiped on moves off with it.
        for _ in 0..<5 where !(book.isHittable && book.frame.maxX <= app.frame.maxX) {
            let y = book.frame.midY
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.85, dy: y))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: app.frame.width * 0.15, dy: y)))
        }
        book.tap()
        XCTAssertTrue(book.isSelected, "Book is chosen", file: file, line: line)
    }

    /// A crop corner's place, as whole percentages of the photo.
    private func corner(_ app: XCUIApplication, _ index: Int) -> (x: Int, y: Int)? {
        let value = app.descendants(matching: .any)["scanner.corner.\(index)"].firstMatch.value as? String ?? ""
        let parts = value.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-book-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testABookCaptureBecomesItsTwoPages() throws {
        let app = launchCapture(try bookPhoto())
        defer { app.terminate() }
        keepCapture(app)  // the seeded capture: one page, as taken
        chooseBook(app)
        snap(app, "capture-en")

        app.buttons["scanner.shutter"].tap()
        let preview = app.descendants(matching: .any)["scanner.preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 25), "the capture is not shown")
        // The preview adds its zoom to its value: "Two pages; 100%; 0, 0".
        let marked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value BEGINSWITH %@", "Two pages"), object: preview)
        XCTAssertEqual(XCTWaiter.wait(for: [marked], timeout: 20), .completed, "the spread is not shown as two pages: \(preview.value ?? "")")
        snap(app, "pending-en")
        keepCapture(app)

        let review = app.buttons["scanner.review"]
        let three = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "3"), object: review)
        XCTAssertEqual(XCTWaiter.wait(for: [three], timeout: 20), .completed, "one capture kept should be two pages: \(review.value ?? "")")
        review.tap()
        XCTAssertTrue(app.buttons["scanner.page.2"].waitForExistence(timeout: 15))

        // Each page cropped to its half of the spread: 10–50% and 50–90% across, 18–84% down.
        for (index, left, right) in [(1, 10, 50), (2, 50, 90)] {
            app.buttons["scanner.page.\(index)"].tap()
            app.buttons["scanner.tool.crop"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["scanner.corner.0"].firstMatch.waitForExistence(timeout: 10))
            let topLeft = try XCTUnwrap(corner(app, 0)), bottomRight = try XCTUnwrap(corner(app, 2))
            XCTAssertTrue(abs(topLeft.x - left) <= 3 && abs(topLeft.y - 18) <= 3, "page \(index + 1) starts at \(topLeft)")
            XCTAssertTrue(abs(bottomRight.x - right) <= 3 && abs(bottomRight.y - 84) <= 3, "page \(index + 1) ends at \(bottomRight)")
            app.buttons["scanner.tool.crop"].tap()
        }
        app.buttons["scanner.page.1"].tap()
        snap(app, "review-en")
    }

    /// The mode pill, five chips now: Book is offered and can be chosen in
    /// French and Spanish, where the names are longer.
    func testBookIsOfferedInFrenchAndSpanish() throws {
        let photo = try bookPhoto()
        for language in ["fr", "es"] {
            let app = launchCapture(photo, language: language)
            keepCapture(app)
            chooseBook(app)
            snap(app, "capture-\(language)")
            app.terminate()
        }
    }

    /// One upright page in Book mode stays one page: cutting a page in half
    /// is the costly mistake.
    func testAnUprightPageInBookModeStaysOnePage() throws {
        let app = launchCapture(try uprightPagePhoto())
        defer { app.terminate() }
        keepCapture(app)
        chooseBook(app)
        let (pages, preview) = captureInBook(app)
        XCTAssertFalse(preview.hasPrefix("Two pages"), "an upright page was offered as two: \(preview)")
        XCTAssertEqual(pages, "2", "one seeded page and the page just kept")
    }

    /// A photo with no outline found keeps the whole frame, one page.
    func testABookPhotoWithNoOutlineStaysOnePage() throws {
        let app = launchCapture(try featurelessPhoto())
        defer { app.terminate() }
        keepCapture(app)
        chooseBook(app)
        let (pages, preview) = captureInBook(app)
        XCTAssertFalse(preview.hasPrefix("Two pages"), "a photo with no outline was offered as two: \(preview)")
        XCTAssertEqual(pages, "2")
    }

    /// At the largest text size, in French and Spanish: Book reached in the
    /// mode strip, the capture shown as two pages, kept as two.
    func testABookCaptureAtTheLargestTextSize() throws {
        let photo = try bookPhoto()
        for (language, two) in [("fr", "Deux pages"), ("es", "Dos páginas")] {
            let app = launchCapture(photo, language: language, largestText: true)
            keepCapture(app)
            chooseBook(app)
            snap(app, "xxxl-capture-\(language)")
            let (pages, preview) = captureInBook(app)
            XCTAssertTrue(preview.hasPrefix(two), "\(language): \(preview)")
            XCTAssertEqual(pages, "3", "\(language): one seeded page and the spread's two")
            app.buttons["scanner.review"].tap()
            XCTAssertTrue(app.buttons["scanner.page.2"].waitForExistence(timeout: 15), "\(language): no third page")
            snap(app, "xxxl-review-\(language)")
            app.terminate()
        }
    }
}
