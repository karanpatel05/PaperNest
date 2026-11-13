import XCTest
import PaperNestCore
import PaperNestStore

/// Night mode, switched on from Display settings and then *looked at*: these
/// tests read the colours the simulator's screen is showing.
@MainActor final class NightModeUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    private func snap(_ app: XCUIApplication, _ name: String) {
        let folder = URL(fileURLWithPath: "/tmp/pn-night-shots")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? app.screenshot().pngRepresentation
            .write(to: folder.appendingPathComponent("\(isPad ? "ipad" : "iphone")-\(name).png"))
    }

    /// One page of print. `marked` adds what a reader leaves on a page: a red
    /// pen stroke and a highlight in the default colour.
    private func openStatement(marked: Bool, language: String = "en") async throws
        -> (XCUIApplication, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-night-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let data = SyntheticDocuments.textPDF(pages: ["Statement"])
        let asset = try store.assets.store(data, kind: .pdf, originalFilename: "Statement.pdf")
        let item = try await store.createItem(kind: .document, name: "Statement", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        if marked {
            let page = try await store.pages(of: item.id)[0]
            try await store.saveObject(PageObject(
                pageID: page.id, zKey: "m",
                payload: .ink(InkStroke(tool: .highlighter, color: RGBAColor(red: 1, green: 0.82, blue: 0), width: 60,
                                        points: [InkPoint(x: 150, y: 250), InkPoint(x: 450, y: 250)])),
                modifiedAt: Date()))
            try await store.saveObject(PageObject(
                pageID: page.id, zKey: "n",
                payload: .ink(InkStroke(tool: .pen, color: RGBAColor(red: 0.85, green: 0.1, blue: 0.1), width: 40,
                                        points: [InkPoint(x: 150, y: 350), InkPoint(x: 450, y: 350)])),
                modifiedAt: Date()))
        }
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Statement", "-AppleLanguages", "(\(language))"]
        app.launch()
        XCTAssertTrue(app.buttons["editor-find"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.images["document-page-image"].waitForExistence(timeout: 10))
        return (app, store, item.id)
    }

    // MARK: - Reading the screen

    private struct Seen: CustomStringConvertible {
        var red, green, blue: Int
        var description: String { "rgb(\(red),\(green),\(blue))" }
        var brightest: Int { max(red, green, blue) }
    }

    /// The colour on screen at a point of the page, given in the page's own
    /// points (612 by 792, from its top-left corner): the average of a few
    /// pixels around it.
    private func seen(_ app: XCUIApplication, x: CGFloat, y: CGFloat) -> Seen {
        let page = app.images["document-page-image"].frame
        let shot = XCUIScreen.main.screenshot().image
        guard let image = shot.cgImage else { return Seen(red: -1, green: -1, blue: -1) }
        let scale = CGFloat(image.width) / app.frame.width
        let centre = CGPoint(x: (page.minX + page.width * x / 612) * scale, y: (page.minY + page.height * y / 792) * scale)
        let side = 4
        guard let patch = image.cropping(to: CGRect(x: Int(centre.x) - side / 2, y: Int(centre.y) - side / 2,
                                                    width: side, height: side)) else {
            return Seen(red: -1, green: -1, blue: -1)
        }
        var buffer = [UInt8](repeating: 0, count: side * side * 4)
        let context = CGContext(data: &buffer, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(patch, in: CGRect(x: 0, y: 0, width: side, height: side))
        var sums = [0, 0, 0]
        for pixel in 0..<(side * side) {
            for channel in 0..<3 { sums[channel] += Int(buffer[pixel * 4 + channel]) }
        }
        return Seen(red: sums[0] / (side * side), green: sums[1] / (side * side), blue: sums[2] / (side * side))
    }

    /// Waits for the paper to be dark or light: the night picture is made
    /// off the main thread and arrives a moment after the switch.
    private func waitForPaper(_ app: XCUIApplication, dark: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(10)
        var paper = seen(app, x: 306, y: 480)
        while Date() < deadline, dark ? paper.brightest > 40 : paper.brightest < 215 {
            usleep(200_000)
            paper = seen(app, x: 306, y: 480)
        }
        XCTAssertTrue(dark ? paper.brightest <= 40 : paper.brightest >= 215,
                      "the paper is \(paper), which is not \(dark ? "dark" : "light")", file: file, line: line)
    }

    /// Brings a control of Display settings wholly on screen. On a phone
    /// the settings are a half-height sheet that scrolls.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication,
                        file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews["display-settings-scroll"]
        let window = app.windows.firstMatch.frame
        for _ in 0..<4 where scroll.exists && !(element.isHittable && window.contains(element.frame)) {
            scroll.swipeUp()
        }
        XCTAssertTrue(element.isHittable && window.contains(element.frame),
                      "\(element) cannot be brought on screen: \(element.frame) in \(window)", file: file, line: line)
    }

    private func openDisplaySettings(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line)
        -> XCUIElement {
        app.buttons["studio-tool-settings"].tap()
        let night = app.switches["display-night-mode"]
        XCTAssertTrue(night.waitForExistence(timeout: 5), "Display settings has no Night Mode switch",
                      file: file, line: line)
        reveal(night, in: app, file: file, line: line)
        return night
    }

    private func setNightMode(_ app: XCUIApplication, _ on: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let night = openDisplaySettings(app, file: file, line: line)
        if (night.value as? String) != (on ? "1" : "0") { night.flipSwitch() }
        XCTAssertEqual(night.value as? String, on ? "1" : "0", file: file, line: line)
        app.closeToolSettings(file: file, line: line)
    }

    // MARK: - Tests

    func testNightModeShowsThePageLightOnDarkAndChangesNothingSaved() async throws {
        let (app, store, item) = try await openStatement(marked: true)
        defer { app.terminate() }
        let before = try await store.pages(of: item)[0]
        let objectsBefore = try await store.objects(on: before.id)

        // By day: white paper, a black marker, an amber highlight, red ink.
        waitForPaper(app, dark: false)
        XCTAssertLessThan(seen(app, x: 50, y: 50).brightest, 60, "the fixture's black marker is not where it is expected")
        let dayHighlight = seen(app, x: 300, y: 250)
        XCTAssertGreaterThan(dayHighlight.red - dayHighlight.blue, 50, "no highlight by day: \(dayHighlight)")
        snap(app, "day")

        setNightMode(app, true)
        waitForPaper(app, dark: true)
        snap(app, "night")

        // Print reads light on the dark page.
        let marker = seen(app, x: 50, y: 50)
        XCTAssertGreaterThan(min(marker.red, marker.green, marker.blue), 215, "black print is not light at night: \(marker)")
        // The highlight is still there, and still its own colour: a dim
        // amber band, not black and not blue.
        let paper = seen(app, x: 306, y: 480)
        let highlight = seen(app, x: 300, y: 250)
        XCTAssertGreaterThan(highlight.red - paper.red, 45, "the highlight has vanished into the night page: \(highlight)")
        XCTAssertGreaterThan(highlight.red - highlight.blue, 45, "the highlight is no longer amber: \(highlight)")
        XCTAssertEqual(Double(highlight.red), 89, accuracy: 26, "not the palette's amber: \(highlight)")
        XCTAssertEqual(Double(highlight.green), 73, accuracy: 26, "not the palette's amber: \(highlight)")
        XCTAssertLessThan(highlight.blue, 30, "not the palette's amber: \(highlight)")
        // Red ink is still red, and light enough to read.
        let ink = seen(app, x: 300, y: 350)
        XCTAssertGreaterThan(ink.red, 215, "red ink is not light at night: \(ink)")
        XCTAssertGreaterThan(ink.red - ink.green, 60, "red ink is no longer red: \(ink)")
        XCTAssertGreaterThan(ink.red - ink.blue, 60, "red ink is no longer red: \(ink)")
        // The page is the same page to everything else.
        XCTAssertEqual(app.images["document-page-image"].label, "Page 1 of 1")
        XCTAssertEqual(app.images["document-page-image"].value as? String, "2 strokes")

        // Nothing about the document was touched by looking at it this way.
        let during = try await store.pages(of: item)[0]
        XCTAssertEqual(during.revision, before.revision)
        XCTAssertEqual(during.transform, before.transform)
        let objectsDuring = try await store.objects(on: before.id)
        XCTAssertEqual(objectsDuring, objectsBefore)

        // And back.
        setNightMode(app, false)
        waitForPaper(app, dark: false)
        XCTAssertLessThan(seen(app, x: 50, y: 50).brightest, 60)
        let again = seen(app, x: 300, y: 250)
        XCTAssertEqual(Double(again.red), Double(dayHighlight.red), accuracy: 6)
        XCTAssertEqual(Double(again.blue), Double(dayHighlight.blue), accuracy: 6)
        let after = try await store.pages(of: item)[0]
        XCTAssertEqual(after.revision, before.revision)
    }

    /// The stroke under the finger is drawn by the ink canvas, not by the
    /// page's picture. It has to turn with the page, or a black pen would be
    /// invisible exactly while it is being used — and what is saved must be
    /// the colour that was chosen, not the colour it was shown in.
    func testInkDrawnAtNightShowsLightAndIsSavedInTheColourChosen() async throws {
        let (app, store, item) = try await openStatement(marked: false)
        defer { app.terminate() }
        waitForPaper(app, dark: false)

        let night = openDisplaySettings(app)
        if (night.value as? String) != "1" { night.flipSwitch() }
        XCTAssertEqual(night.value as? String, "1")
        let finger = app.switches["studio-finger-drawing"]
        XCTAssertTrue(finger.waitForExistence(timeout: 5))
        reveal(finger, in: app)
        if (finger.value as? String) != "1" { finger.flipSwitch() }
        XCTAssertEqual(finger.value as? String, "1")
        snap(app, "settings")
        app.closeToolSettings()
        waitForPaper(app, dark: true)

        let drawing = app.buttons["studio-drawing-toggle"]
        if (drawing.value as? String) != "Selected" { drawing.tap() }
        XCTAssertEqual(drawing.value as? String, "Selected")
        let pen = app.buttons["studio-tool-pen"]
        XCTAssertTrue(pen.waitForExistence(timeout: 5))
        if (pen.value as? String) != "Selected" { pen.tap() }

        // Straight across the page, level, so the stroke's place is known.
        let page = app.images["document-page-image"]
        page.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.42))
            .press(forDuration: 0.1, thenDragTo: page.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.42)))
        var strokes: [InkStroke] = []
        for _ in 0..<40 where strokes.isEmpty {
            try await Task.sleep(for: .milliseconds(250))
            let pageID = try await store.pages(of: item)[0].id
            strokes = try await store.objects(on: pageID)
                .compactMap { if case .ink(let stroke) = $0.payload { stroke } else { nil } }
        }
        let stroke = try XCTUnwrap(strokes.first, "the finger drew nothing")
        XCTAssertLessThan(max(stroke.color.red, stroke.color.green, stroke.color.blue), 0.1,
                          "the pen was black and must be saved black, whatever night mode showed")

        // The brightest thing in a short column across the stroke's path:
        // the stroke itself, while the ink canvas is still the one drawing it.
        func brightestAcrossTheStroke() -> Int {
            stride(from: -8.0, through: 8.0, by: 2).map { seen(app, x: 306, y: 792 * 0.42 + $0).brightest }.max() ?? 0
        }
        XCTAssertGreaterThan(brightestAcrossTheStroke(), 170, "the stroke is not light while the pen is in hand")
        snap(app, "ink-live")

        // And once the pen is put down, when the page's own picture draws it.
        drawing.tap()
        XCTAssertNotEqual(drawing.value as? String, "Selected")
        usleep(1_500_000)
        XCTAssertGreaterThan(brightestAcrossTheStroke(), 170, "the saved stroke is not light on the night page")
        waitForPaper(app, dark: true)
        snap(app, "ink-saved")
    }

    func testTheNightModeSwitchFitsInFrenchAndSpanish() async throws {
        for (language, title) in [("fr", "Mode nuit"), ("es", "Modo nocturno")] {
            let (app, _, _) = try await openStatement(marked: false, language: language)
            let night = openDisplaySettings(app)
            XCTAssertTrue(night.label.contains(title), "the switch is called \(night.label)")
            // Not squeezed: the row has the width of the panel it is in.
            XCTAssertGreaterThan(night.frame.width, 240, "the \(language) switch row is \(night.frame.width) wide")
            snap(app, "settings-\(language)")
            night.flipSwitch()
            XCTAssertEqual(night.value as? String, "1")
            app.closeToolSettings()
            waitForPaper(app, dark: true)
            app.terminate()
        }
    }
}
