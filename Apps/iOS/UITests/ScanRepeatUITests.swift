import XCTest
import UIKit

/// A page photographed twice, in the running scanner: of four pages — a
/// page, a second photograph of it (shifted, scaled, turned a little, lit
/// differently), another page set the same way, and a byte-for-byte copy of
/// the first — only the second photograph is named "Same as page 1", in its
/// filmstrip label and in the note over it. What counts as the same page is
/// fixed by `ScanRepeatTests` and `ScanLikenessTests`.
///
/// No `continueAfterFailure = false` and no `async` `tearDown`: after a
/// failure either left the runner idle in tear-down.
@MainActor final class ScanRepeatUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private static let vocabulary = ["the", "report", "shows", "steady", "growth", "in", "every", "region", "we", "serve",
                                     "costs", "held", "flat", "while", "orders", "rose", "by", "a", "third", "over",
                                     "spring", "and", "summer", "our", "teams", "expect", "more", "of", "same", "next"]

    /// Lines of words picked by a generator seeded with `seed`.
    private func lines(seed: UInt64, count: Int) -> [String] {
        var state = seed &* 0x9E3779B97F4A7C15 | 1
        func next(_ bound: Int) -> Int {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return Int((state >> 33) % UInt64(bound))
        }
        return (0..<count).map { _ in (0..<(8 + next(5))).map { _ in Self.vocabulary[next(Self.vocabulary.count)] }.joined(separator: " ") }
    }

    /// A page of `seed`'s print, 1200 × 1560, as a photograph would sit:
    /// shifted by `shift` points, scaled and turned `degrees` about its middle.
    private func page(seed: UInt64, shift: CGPoint = .zero, scale: CGFloat = 1, degrees: CGFloat = 0,
                      paper: CGFloat = 0.96) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 1200, height: 1560)
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: paper, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let cg = context.cgContext
            cg.translateBy(x: size.width / 2 + shift.x, y: size.height / 2 + shift.y)
            cg.rotate(by: degrees * .pi / 180)
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -size.width / 2, y: -size.height / 2)
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 22),
                                                             .foregroundColor: UIColor(white: 0.1, alpha: 1)]
            var y: CGFloat = 80
            for text in lines(seed: seed, count: 60) where y < size.height - 80 {
                (text as NSString).draw(at: CGPoint(x: 84, y: y), withAttributes: attributes)
                y += 35
            }
        }
        return try XCTUnwrap(image.pngData())
    }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-scan-repeat-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation.write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    func testASecondPhotographOfAPageIsNamedAsItsRepeat() throws {
        let folder = URL(fileURLWithPath: "/tmp/papernest-scan-repeat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("first.png"), retaken = folder.appendingPathComponent("retaken.png")
        let other = folder.appendingPathComponent("other.png")
        try page(seed: 1).write(to: first)
        try page(seed: 1, shift: CGPoint(x: 12, y: 9), scale: 1.01, degrees: 0.4, paper: 0.9).write(to: retaken)
        try page(seed: 2).write(to: other)

        let words = ["en": "Same as page 1", "fr": "Identique à la page 1", "es": "Igual que la página 1"]
        for language in ["en", "fr", "es"] {
            let sameAs = try XCTUnwrap(words[language])
            let app = XCUIApplication()
            app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-scan-repeat-library-\(UUID().uuidString)",
                                   "-PaperNestDebugSkipWelcome", "YES",
                                   "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : language,
                                   "-PaperNestDebugScannerImages", [first, retaken, other, first].map(\.path).joined(separator: ";"),
                                   "-scanner.defaultMode", "document", "-scanner.defaultPreset", "original",
                                   "-scanner.autoOnEntry", "NO"]
            app.launch()
            XCTAssertTrue(app.buttons["scanner.finish"].waitForExistence(timeout: 30), "\(language): review did not open")

            let retake = app.buttons["scanner.page.1"]
            let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", sameAs), object: retake)
            if XCTWaiter().wait(for: [shown], timeout: 40) != .completed {
                XCTFail("\(language): the second photograph is not named as a repeat: “\(retake.label)”")
            }
            // Give the others time to be compared before saying they are not repeats.
            sleep(3)
            for index in [0, 2, 3] {
                let label = app.buttons["scanner.page.\(index)"].label
                XCTAssertFalse(label.contains(sameAs.dropLast()), "\(language): page \(index + 1) is called a repeat: \(label)")
            }

            retake.tap()
            let note = app.descendants(matching: .any)["scanner.quality"]
            XCTAssertTrue(note.waitForExistence(timeout: 10), "\(language): no note over the second photograph")
            XCTAssertEqual(note.label, sameAs, "\(language)")
            snap(app, "retaken-\(language)")
            app.buttons["scanner.page.3"].tap()
            XCTAssertTrue(note.waitForNonExistence(timeout: 10), "\(language): the copy made on purpose has a note")
            app.terminate()
        }
    }
}
