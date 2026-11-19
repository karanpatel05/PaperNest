import XCTest
import UIKit
import CoreImage

/// The check after a capture, in the running scanner: of three pages, a
/// sharp one, a blurred one and a dark one, the blurred and the dark are
/// named for what is wrong in their filmstrip labels (their thumbnails carry
/// the mark), and the note over the page being reviewed says it in words.
/// What each measure means is fixed by `ScanQualityAnalyzerTests`; a steep
/// angle needs corners, which seeded pages do not have, so it is unit-tested
/// only.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class ScanQualityUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    /// A page of `words`, 1200 × 1560 pixels, on paper of `paper` white.
    private func page(paper: CGFloat, ink: CGFloat, blur: Double = 0,
                      words: String = "The quarterly report shows steady growth in every region we serve.") throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 1200, height: 1560)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: paper, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 26),
                                                             .foregroundColor: UIColor(white: ink, alpha: 1)]
            var y: CGFloat = 80
            while y < size.height - 80 {
                (words as NSString).draw(at: CGPoint(x: 72, y: y), withAttributes: attributes)
                y += 42
            }
        }
        guard blur > 0 else { return try XCTUnwrap(image.pngData()) }
        let source = try XCTUnwrap(CIImage(image: image))
        let soft = source.clampedToExtent().applyingGaussianBlur(sigma: blur).cropped(to: source.extent)
        let drawn = try XCTUnwrap(CIContext().createCGImage(soft, from: source.extent))
        return try XCTUnwrap(UIImage(cgImage: drawn).pngData())
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-scan-quality-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// Waits until `element`'s label contains `text`.
    private func expectLabel(_ element: XCUIElement, contains text: String, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        if XCTWaiter().wait(for: [shown], timeout: 30) != .completed {
            XCTFail("\(message): label is “\(element.exists ? element.label : "missing")”", file: file, line: line)
        }
    }

    func testABlurredAndADarkPageAreNamedForWhatIsWrong() throws {
        let folder = URL(fileURLWithPath: "/tmp/papernest-scan-quality-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let sharp = folder.appendingPathComponent("sharp.png"), blurred = folder.appendingPathComponent("blurred.png")
        let dark = folder.appendingPathComponent("dark.png")
        try page(paper: 0.96, ink: 0.1).write(to: sharp)
        // About 5 pixels at the size pages are measured at: well past reading.
        // Its own words: the sharp page blurred would be that page again
        // (`ScanRepeatUITests`).
        try page(paper: 0.96, ink: 0.1, blur: 8, words: "Orders rose by a third over spring and summer, costs held flat.")
            .write(to: blurred)
        try page(paper: 0.12, ink: 0.02).write(to: dark)

        let words = ["en": ("Looks blurry", "Too dark"), "fr": ("Semble flou", "Trop sombre"),
                     "es": ("Parece borroso", "Demasiado oscuro")]
        for language in ["en", "fr", "es"] {
            let (blurry, tooDark) = try XCTUnwrap(words[language])
            let app = XCUIApplication()
            app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-scan-quality-library-\(UUID().uuidString)",
                                   "-PaperNestDebugSkipWelcome", "YES",
                                   "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language,
                                   "-PaperNestDebugScannerImages", [sharp, blurred, dark].map(\.path).joined(separator: ";"),
                                   "-scanner.defaultMode", "document", "-scanner.defaultPreset", "original",
                                   "-scanner.autoOnEntry", "NO"]
            app.launch()
            XCTAssertTrue(app.buttons["scanner.finish"].waitForExistence(timeout: 30), "\(language): review did not open")

            let first = app.buttons["scanner.page.0"], second = app.buttons["scanner.page.1"]
            let third = app.buttons["scanner.page.2"]
            expectLabel(second, contains: blurry, "\(language): the blurred page is not called blurry")
            expectLabel(third, contains: tooDark, "\(language): the dark page is not called too dark")
            XCTAssertFalse(third.label.contains(blurry), "\(language): a dark page should not also be called blurry")
            for word in [blurry, tooDark] {
                XCTAssertFalse(first.label.contains(word), "\(language): the sharp page is called “\(word)”: \(first.label)")
            }

            second.tap()
            let note = app.descendants(matching: .any)["scanner.quality"]
            XCTAssertTrue(note.waitForExistence(timeout: 10), "\(language): no note over the blurred page")
            XCTAssertEqual(note.label, blurry, "\(language)")
            snap(app, "blurred-\(language)")
            first.tap()
            XCTAssertTrue(note.waitForNonExistence(timeout: 10), "\(language): the sharp page has a note")
            if language == "en" {
                // The capture screen's stack shows the latest page, the dark
                // one, with its mark: looked at in the screenshot. Its button
                // says "Review scan" and the count, not the issue.
                app.buttons["Scan Pages"].firstMatch.tap()
                XCTAssertTrue(app.buttons["scanner.review"].waitForExistence(timeout: 15), "no capture screen")
                sleep(2)
                snap(app, "capture-stack-en")
            }
            app.terminate()
        }
    }
}
