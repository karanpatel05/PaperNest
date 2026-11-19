import XCTest
import UIKit

/// The scanner's after-capture advice at the largest text size
/// (Accessibility XXXL), in English, French and Spanish: the notes and the
/// filmstrip labels still say everything, and the screenshots are kept for
/// a look (`/tmp/pn-scanner-xxxl-shots`). A dark page with a reflection
/// carries the longest note, two issues joined.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class ScannerLargeTextUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private static let words = ["the", "report", "shows", "steady", "growth", "in", "every", "region", "we", "serve",
                                "costs", "held", "flat", "while", "orders", "rose", "by", "a", "third", "over"]

    /// A page of print, 1200 × 1560, each line its own words (`seed`), on
    /// `paper`; `glare` adds a strong reflection in the middle, light added
    /// twice over so it blows out even dark paper; `shift` sits it as a second
    /// photograph would.
    private func page(seed: UInt64, paper: CGFloat = 0.96, ink: CGFloat = 0.1, glare: Bool = false,
                      shift: CGPoint = .zero) throws -> Data {
        var state = seed &* 0x9E3779B97F4A7C15 | 1
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 1200, height: 1560)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: paper, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 22),
                                                             .foregroundColor: UIColor(white: ink, alpha: 1)]
            var y: CGFloat = 80 + shift.y
            while y < size.height - 80 {
                let text = (0..<(8 + next(5))).map { _ in Self.words[next(Self.words.count)] }.joined(separator: " ")
                (text as NSString).draw(at: CGPoint(x: 84 + shift.x, y: y), withAttributes: attributes)
                y += 35
            }
            if glare {
                let cg = context.cgContext
                cg.setBlendMode(.plusLighter)
                let colours = [UIColor(white: 1, alpha: 1).cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colours, locations: [0, 1])!
                let centre = CGPoint(x: 600, y: 700)
                for _ in 0..<2 {
                    cg.drawRadialGradient(gradient, startCenter: centre, startRadius: 0, endCenter: centre, endRadius: 180, options: [])
                }
            }
        }
        return try XCTUnwrap(image.pngData())
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-scanner-xxxl-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    private func launch(_ pages: [URL], language: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-xxxl-library-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES",
                               "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
                               "-PaperNestDebugScannerImages", pages.map(\.path).joined(separator: ";"),
                               "-scanner.defaultMode", "document", "-scanner.defaultPreset", "original",
                               "-scanner.autoOnEntry", "NO"]
        app.launch()
        return app
    }

    /// Waits until `element`'s label contains `text`.
    private func expectLabel(_ element: XCUIElement, contains text: String, _ message: String,
                             file: StaticString = #filePath, line: UInt = #line) {
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: element)
        if XCTWaiter().wait(for: [shown], timeout: 40) != .completed {
            XCTFail("\(message): label is “\(element.exists ? element.label : "missing")”", file: file, line: line)
        }
    }

    /// The note sits on screen, side to side, and says all of `text`.
    private func expectNote(_ app: XCUIApplication, _ text: String, _ message: String,
                            file: StaticString = #filePath, line: UInt = #line) {
        let note = app.descendants(matching: .any)["scanner.quality"]
        XCTAssertTrue(note.waitForExistence(timeout: 15), "\(message): no note", file: file, line: line)
        XCTAssertEqual(note.label, text, message, file: file, line: line)
        XCTAssertGreaterThanOrEqual(note.frame.minX, app.frame.minX, "\(message): the note runs off the left", file: file, line: line)
        XCTAssertLessThanOrEqual(note.frame.maxX, app.frame.maxX, "\(message): the note runs off the right", file: file, line: line)
    }

    /// Taps a filmstrip page, which at this size may need the strip moved.
    private func open(_ page: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !page.isHittable { app.buttons["scanner.page.0"].swipeLeft() }
        page.tap()
    }

    func testTheAdviceNotesAtTheLargestTextSize() throws {
        let folder = URL(fileURLWithPath: "/tmp/papernest-xxxl-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let sharp = folder.appendingPathComponent("sharp.png"), retaken = folder.appendingPathComponent("retaken.png")
        let darkGlare = folder.appendingPathComponent("dark-glare.png")
        try page(seed: 1).write(to: sharp)
        try page(seed: 1, paper: 0.9, shift: CGPoint(x: 12, y: 9)).write(to: retaken)
        try page(seed: 3, paper: 0.18, ink: 0.04, glare: true).write(to: darkGlare)

        let expected = [
            "en": (repeat: "Same as page 1", both: "Too dark · Glare on the page"),
            "fr": (repeat: "Identique à la page 1", both: "Trop sombre · Reflet sur la page"),
            "es": (repeat: "Igual que la página 1", both: "Demasiado oscuro · Reflejo en la página"),
        ]
        for language in ["en", "fr", "es"] {
            let words = try XCTUnwrap(expected[language])
            let app = launch([sharp, retaken, darkGlare], language: language)
            XCTAssertTrue(app.buttons["scanner.finish"].waitForExistence(timeout: 30), "\(language): review did not open")
            let second = app.buttons["scanner.page.1"], third = app.buttons["scanner.page.2"]
            expectLabel(second, contains: words.repeat, "\(language): the retake is not named")
            expectLabel(third, contains: words.both.components(separatedBy: " · ")[1], "\(language): the reflection is not named")
            XCTAssertTrue(third.label.contains(words.both.components(separatedBy: " · ")[0]), "\(language): \(third.label)")

            open(second, in: app)
            expectNote(app, words.repeat, "\(language) repeat")
            snap(app, "repeat-\(language)")
            open(third, in: app)
            expectNote(app, words.both, "\(language) dark and glare")
            snap(app, "dark-glare-\(language)")
            app.terminate()
        }
    }
}
