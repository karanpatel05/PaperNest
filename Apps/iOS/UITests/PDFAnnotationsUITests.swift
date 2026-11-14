import XCTest
import PaperNestCore
import PaperNestStore

/// What a PDF keeps in annotations — a form's typed answers, boxes another app
/// drew — *looked at* on the simulator's screen. Until these existed the page
/// PaperNest showed had none of them: a filled-in form opened with empty
/// boxes. The unit tests run on the Mac; this is where PDFKit's drawing into
/// an iOS context is checked to land the right way up and in the right place.
@MainActor final class PDFAnnotationsUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-annotation-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    private func open(_ data: Data, named name: String) async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-annotations-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "\(name).pdf")
        _ = try await store.createItem(kind: .document, name: name, pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", name]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 15))
        return app
    }

    /// The screen's pixels inside a rectangle of the page given in PDF user
    /// space (612 × 792, y up), counted by `test`, out of how many.
    private func count(_ app: XCUIApplication, pdfRect: CGRect,
                       where test: (_ r: Int, _ g: Int, _ b: Int) -> Bool) -> (hits: Int, of: Int) {
        let page = app.images["document-page-image"].frame
        guard let image = XCUIScreen.main.screenshot().image.cgImage else { return (0, 0) }
        let scale = CGFloat(image.width) / app.frame.width
        let onScreen = CGRect(x: (page.minX + page.width * pdfRect.minX / 612) * scale,
                              y: (page.minY + page.height * (792 - pdfRect.maxY) / 792) * scale,
                              width: page.width * pdfRect.width / 612 * scale,
                              height: page.height * pdfRect.height / 792 * scale).integral
        guard let patch = image.cropping(to: onScreen) else { return (0, 0) }
        let width = patch.width, height = patch.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(patch, in: CGRect(x: 0, y: 0, width: width, height: height))
        var hits = 0
        for pixel in 0..<(width * height) where test(Int(buffer[pixel * 4]), Int(buffer[pixel * 4 + 1]),
                                                     Int(buffer[pixel * 4 + 2])) {
            hits += 1
        }
        return (hits, width * height)
    }

    private func waitFor(_ what: String, timeout: TimeInterval = 10, file: StaticString = #filePath, line: UInt = #line,
                         _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !condition() { usleep(200_000) }
        XCTAssertTrue(condition(), what, file: file, line: line)
    }

    private static func isDark(_ r: Int, _ g: Int, _ b: Int) -> Bool { r < 90 && g < 90 && b < 90 }

    /// A form with two answers typed in, of the shape `acroFormPDF` makes: the
    /// first field at [72 600 300 630], the second at [72 560 300 590], and an
    /// empty third at [72 520 300 550].
    func testAFilledInFormShowsItsAnswersOnThePage() async throws {
        let form = SyntheticDocuments.acroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "family", value: "MMMMMMMM"),
            SyntheticDocuments.FormFieldSpec(name: "given", value: "WWWWWWWW"),
            SyntheticDocuments.FormFieldSpec(name: "middle"),
        ])
        let app = try await open(form, named: "Form")
        defer { app.terminate() }

        // The answers are text on white: a good share of each answer's box is
        // ink, the rest is paper.
        let first = CGRect(x: 72, y: 600, width: 228, height: 30)
        let second = CGRect(x: 72, y: 560, width: 228, height: 30)
        waitFor("the first answer is not on the page") {
            let seen = count(app, pdfRect: first, where: Self.isDark)
            return seen.hits * 50 > seen.of
        }
        let seenSecond = count(app, pdfRect: second, where: Self.isDark)
        XCTAssertGreaterThan(seenSecond.hits * 50, seenSecond.of, "the second answer is not on the page")
        // The empty field is empty, and the paper between the boxes is paper:
        // nothing is drawn where there is no answer.
        let empty = count(app, pdfRect: CGRect(x: 72, y: 520, width: 228, height: 30), where: Self.isDark)
        XCTAssertLessThan(empty.hits * 200, empty.of, "the empty field shows something")
        snap(app, "form-answers")
    }

    /// Reaches Fill PDF Form: the tools list on iPad, the overflow menu on a
    /// phone. The same route `AppUITests.revealEditorTool` takes.
    private func openFillForm(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let tool = app.buttons["editor-fill-form"]
        if !tool.isHittable {
            if isPad {
                let list = app.scrollViews["pdf-tools-list"]
                if !list.exists { app.buttons["editor-panels"].tap() }
                XCTAssertTrue(list.waitForExistence(timeout: 5), file: file, line: line)
                for _ in 0..<10 where !tool.isHittable { list.swipeUp() }
                for _ in 0..<10 where !tool.isHittable { list.swipeDown() }
            } else if app.scrollViews["notebook-tool-bar"].exists {
                let bar = app.scrollViews["notebook-tool-bar"], more = app.buttons["studio-more-tools"]
                for _ in 0..<10 where !more.isHittable { bar.swipeLeft() }
                more.tap()
                let menu = app.collectionViews.containing(.button, identifier: "editor-shapes").firstMatch
                XCTAssertTrue(menu.waitForExistence(timeout: 5), file: file, line: line)
                for _ in 0..<10 where !tool.exists && menu.exists { menu.swipeUp() }
            } else {
                app.buttons["editor-more"].tap()
            }
        }
        XCTAssertTrue(tool.waitForExistence(timeout: 5), "Fill PDF Form cannot be reached", file: file, line: line)
        tool.tap()
    }

    /// The case people met, end to end in the running app: a form whose author
    /// switched copying off — as every USCIS form has — filled in PaperNest's
    /// own form sheet, saved as a copy, and that copy opened again. The answer
    /// has to be on the page, not only in the file.
    func testAFormFilledInPaperNestShowsTheAnswerWhenOpenedAgain() async throws {
        let directory = URL(fileURLWithPath: "/tmp/papernest-annotations-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let form = SyntheticDocuments.restrictedAcroFormPDF(fields: [SyntheticDocuments.FormFieldSpec(name: "customer")])
        let asset = try store.assets.store(form, kind: .pdf, originalFilename: "Form.pdf")
        _ = try await store.createItem(kind: .document, name: "Form", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        let app = XCUIApplication()
        func launch(opening name: String) {
            app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                                   "-PaperNestDebugOpenItem", name, "-AppleLanguages", "(en)"]
            app.launch()
            XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
            XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 15))
        }
        launch(opening: "Form")
        defer { app.terminate() }
        let field = CGRect(x: 72, y: 600, width: 228, height: 30)
        let before = count(app, pdfRect: field, where: Self.isDark)
        XCTAssertLessThan(before.hits * 200, before.of, "the field is not empty to begin with")

        openFillForm(app)
        let customer = app.textFields["form-field-customer"]
        XCTAssertTrue(customer.waitForExistence(timeout: 15))
        customer.tap()
        customer.typeText("MMMMMMMM")
        let copyName = "Filled \(UUID().uuidString.prefix(8))"
        let name = app.textFields["form-copy-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (name.value as? String)?.count ?? 0))
        name.typeText(copyName)
        app.buttons["form-save-copy"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["form-saved"].firstMatch.waitForExistence(timeout: 20),
                      "the filled copy was not saved")
        app.buttons["form-close"].tap()
        app.terminate()

        launch(opening: copyName)
        waitFor("the answer typed in the form sheet is not on the reopened page") {
            let seen = count(app, pdfRect: field, where: Self.isDark)
            return seen.hits * 50 > seen.of
        }
        snap(app, "form-filled-in-app")
    }

    /// Boxes another app drew, only as annotations: each where it belongs, the
    /// right way up — red top left, blue top right — and nothing for the
    /// hidden one or the link.
    func testMarksAnotherAppLeftAreWhereTheyBelong() async throws {
        let app = try await open(SyntheticDocuments.markedUpPDF(), named: "Marked up")
        defer { app.terminate() }

        let inner = { (rect: CGRect) in rect.insetBy(dx: 16, dy: 16) }
        waitFor("the red box is not on the page") {
            let red = count(app, pdfRect: inner(SyntheticDocuments.MarkedUp.shownAndPrinted)) { r, g, b in r > 180 && g < 90 && b < 90 }
            return red.hits * 10 > red.of * 9
        }
        let blue = count(app, pdfRect: inner(SyntheticDocuments.MarkedUp.shownOnly)) { r, g, b in b > 180 && r < 90 && g < 90 }
        XCTAssertGreaterThan(blue.hits * 10, blue.of * 9, "the blue box is not on the page")
        let hidden = count(app, pdfRect: SyntheticDocuments.MarkedUp.hidden) { r, g, b in g > 150 && r < 90 && b < 90 }
        XCTAssertEqual(hidden.hits, 0, "the hidden box was drawn")
        let link = count(app, pdfRect: inner(SyntheticDocuments.MarkedUp.link)) { r, g, b in r < 200 || g < 200 || b < 200 }
        XCTAssertLessThan(link.hits * 20, link.of, "something was drawn for the link")
        snap(app, "marked-up")
    }
}
