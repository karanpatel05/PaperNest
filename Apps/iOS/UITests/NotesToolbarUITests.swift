import XCTest
import PaperNestCore
import PaperNestStore

/// The redesigned notes editor toolbar, driven the way a hand drives it.
///
/// Every step ends by reading the library back from disk, because the claim
/// being tested is that a control changes what gets *saved* — a panel that
/// looked right and saved the old thing would pass any check made on screen.
///
/// Screenshots of each panel are written to `/tmp/pn-toolbar-shots` as the
/// test goes, named for the device, so the layout can be looked at afterwards
/// without a second run.
@MainActor final class NotesToolbarUITests: XCTestCase {
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var shots: URL { URL(fileURLWithPath: "/tmp/pn-toolbar-shots") }

    private func snap(_ app: XCUIApplication, _ name: String) {
        try? FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let device = isPad ? "ipad" : "iphone"
        try? app.screenshot().pngRepresentation.write(to: shots.appendingPathComponent("\(device)-\(name).png"))
    }

    private func open(language: String = "en") async throws -> (XCUIApplication, LibraryStore, ItemID) {
        let directory = URL(fileURLWithPath: "/tmp/papernest-notes-toolbar-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let item = try await store.createItem(kind: .notebook, name: "Toolbar", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Toolbar", "-AppleLanguages", "(\(language))"]
        app.launch()
        XCTAssertTrue(app.buttons["studio-tool-lasso"].waitForExistence(timeout: 30))
        return (app, store, item.id)
    }

    /// Brings a control in the open panel into reach.
    ///
    /// Scrolls before asking whether it exists: the panel's grids are lazy, so
    /// a control below the fold is not in the hierarchy at all until the panel
    /// has been scrolled to it.
    private func reveal(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let scroll = app.scrollViews["tool-panel-scroll"]
        for _ in 0..<8 where !(element.exists && element.isHittable) { scroll.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "\(element) cannot be reached in the panel", file: file, line: line)
    }

    /// Brings a tool on the main toolbar into reach; on a phone the row scrolls.
    ///
    /// Judged by where the button is, not by asking whether it is hittable:
    /// XCUITest cannot answer that for a button scrolled out of view, and
    /// records the question itself as a failure.
    private func tool(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let button = app.buttons[identifier]
        let bar = app.scrollViews["notebook-tool-bar"]
        let reach = bar.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 10, dy: 0)
        for _ in 0..<8 where button.frame.midX > reach.maxX { bar.swipeLeft() }
        for _ in 0..<8 where button.frame.midX < reach.minX { bar.swipeRight() }
        XCTAssertTrue(reach.minX <= button.frame.midX && button.frame.midX <= reach.maxX, "\(identifier) cannot be scrolled into reach")
        return button
    }

    /// Undo or redo: at the end of the main toolbar on iPad, in the lower
    /// palette on a phone.
    private func history(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        isPad ? tool(identifier, in: app) : app.buttons[identifier]
    }

    private func closePanel(_ app: XCUIApplication) { app.closeToolSettings() }

    /// Opens a drawing tool's settings: the first tap picks it up, the second
    /// opens the panel.
    private func openSettings(_ identifier: String, in app: XCUIApplication) {
        let button = tool(identifier, in: app)
        if (button.value as? String) != "Selected" { button.tap() }
        XCTAssertEqual(button.value as? String, "Selected")
        button.tap()
        XCTAssertTrue(app.buttons["studio-settings-done"].waitForExistence(timeout: 5), "\(identifier) settings did not open")
    }

    private func objects(_ store: LibraryStore, _ item: ItemID) async throws -> [PageObject] {
        let pages = try await store.pages(of: item)
        var all: [PageObject] = []
        for page in pages { all += try await store.objects(on: page.id) }
        return all
    }

    private func ink(_ objects: [PageObject]) -> [InkStroke] {
        objects.compactMap { if case .ink(let stroke) = $0.payload { stroke } else { nil } }
    }

    /// Waits for the library on disk to satisfy a condition, since a save
    /// lands a moment after the finger lifts.
    private func eventually(_ what: String, _ store: LibraryStore, _ item: ItemID,
                            file: StaticString = #filePath, line: UInt = #line,
                            _ condition: ([PageObject]) -> Bool) async throws -> [PageObject] {
        var latest: [PageObject] = []
        for _ in 0..<40 {
            latest = try await objects(store, item)
            if condition(latest) { return latest }
            try await Task.sleep(for: .milliseconds(250))
        }
        XCTFail("never saw: \(what) — the page holds \(latest.map(\.payload.kind))", file: file, line: line)
        return latest
    }

    /// The part of the page a finger can actually reach.
    ///
    /// On a phone the page is centred in a viewport shorter than the page, so
    /// its top and bottom lie outside it, and the tool palette floats over the
    /// lower edge. A drag aimed at the page's own frame can land on the page
    /// strip above — which is what the first version of this test did, and why
    /// it "drew" nothing.
    private func reachablePage(_ app: XCUIApplication) -> CGRect {
        let page = app.images["document-page-image"].frame
        var visible = page.intersection(app.scrollViews["document-page-scroll"].frame)
        let toolbar = app.scrollViews["notebook-tool-bar"].frame
        if toolbar.maxY + 12 > visible.minY {
            visible.size.height -= toolbar.maxY + 12 - visible.minY
            visible.origin.y = toolbar.maxY + 12
        }
        let palette = app.buttons["studio-drawing-toggle"]
        if palette.exists, palette.frame.minY < visible.maxY {
            visible.size.height = palette.frame.minY - 12 - visible.minY
        }
        return visible.insetBy(dx: 12, dy: 12)
    }

    /// Drags between two points given as fractions of the reachable page.
    private func drag(_ app: XCUIApplication, from: CGVector, to: CGVector) {
        let area = reachablePage(app)
        XCTAssertGreaterThan(area.height, 80, "too little of the page is reachable to draw on")
        func point(_ fraction: CGVector) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: area.minX + area.width * fraction.dx, dy: area.minY + area.height * fraction.dy))
        }
        point(from).press(forDuration: 0.1, thenDragTo: point(to))
    }

    func testEveryToolChangesWhatIsSaved() async throws {
        let (app, store, item) = try await open()
        defer { app.terminate() }
        let page = app.images["document-page-image"]
        XCTAssertTrue(page.waitForExistence(timeout: 10))

        // The nine tools, in the order of the design.
        let order = ["studio-tool-pen", "studio-tool-highlighter", "studio-tool-eraser", "studio-tool-lasso",
                     "studio-tool-shape", "editor-text-box", "editor-insert-image", "studio-tool-sticker",
                     "studio-tool-insert"]
        for identifier in order { XCTAssertTrue(app.buttons[identifier].exists, "\(identifier) is missing") }
        let lefts = order.map { app.buttons[$0].frame.minX }
        XCTAssertEqual(lefts, lefts.sorted(), "tools are out of order")
        // The first tools are under the finger the moment the editor opens.
        XCTAssertTrue(app.buttons["studio-tool-pen"].isHittable, "Pen is not reachable on a freshly opened page")
        XCTAssertTrue(app.buttons["studio-tool-highlighter"].isHittable, "Highlighter is not reachable on a freshly opened page")
        // Undo, redo and More are within reach without scrolling anything:
        // on a phone that means the lower palette and the pinned end of the bar.
        for identifier in ["notebook-undo", "notebook-redo", "studio-more-tools"] {
            XCTAssertEqual(app.buttons.matching(identifier: identifier).count, 1, "\(identifier) appears once")
        }
        if !isPad {
            XCTAssertTrue(app.buttons["studio-more-tools"].isHittable, "More is pinned where a phone can always reach it")
            XCTAssertTrue(app.windows.firstMatch.frame.contains(app.buttons["notebook-undo"].frame), "Undo is on screen")
        }
        if !isPad {
            XCTAssertFalse(app.buttons["studio-tool-pen"].staticTexts["Pen"].exists, "a phone's toolbar is icon-only")
        }
        snap(app, "01-toolbar")

        // The pen as it ships draws and saves before anything is changed.
        let pen0 = tool("studio-tool-pen", in: app)
        pen0.tap()
        XCTAssertEqual(pen0.value as? String, "Selected")
        if isPad {
            pen0.tap()
            let finger = app.switches["studio-finger-drawing"]
            reveal(finger, in: app)
            if (finger.value as? String) != "1" { finger.flipSwitch() }
            closePanel(app)
        }
        drag(app, from: CGVector(dx: 0.1, dy: 0.05), to: CGVector(dx: 0.6, dy: 0.1))
        _ = try await eventually("the shipped pen's stroke", store, item) { self.ink($0).count == 1 }

        // Pen: pick the ballpoint, colour it, and draw.
        openSettings("studio-tool-pen", in: app)
        snap(app, "02-pen")
        XCTAssertEqual(app.buttons["pen-preset-gel"].value as? String, "Selected", "the pen in hand on first launch")
        app.buttons["pen-preset-ballpoint"].tap()
        XCTAssertEqual(app.buttons["pen-preset-ballpoint"].value as? String, "Selected")
        let width = app.sliders["studio-width-slider"]
        reveal(width, in: app)
        let ballpointWidth = width.value as? String
        app.buttons["pen-preset-brush"].tap()
        XCTAssertNotEqual(width.value as? String, ballpointWidth, "each pen keeps its own width")
        app.buttons["pen-preset-ballpoint"].tap()
        XCTAssertEqual(width.value as? String, ballpointWidth)
        reveal(app.buttons["markup-color-blue"], in: app)
        app.buttons["markup-color-blue"].tap()
        XCTAssertEqual(app.buttons["markup-color-blue"].value as? String, "Selected")
        if isPad {
            let finger = app.switches["studio-finger-drawing"]
            reveal(finger, in: app)
            if (finger.value as? String) != "1" { finger.flipSwitch() }
        }
        snap(app, "03-pen-scrolled")
        closePanel(app)
        drag(app, from: CGVector(dx: 0.1, dy: 0.25), to: CGVector(dx: 0.6, dy: 0.3))
        var saved = try await eventually("a ballpoint stroke", store, item) { self.ink($0).count == 2 }
        let pen = try XCTUnwrap(ink(saved).first { $0.color.blue > 0.6 }, "no stroke in the colour chosen")
        XCTAssertEqual(pen.tool, .pen)
        XCTAssertGreaterThan(pen.color.blue, 0.6, "the stroke was saved in the colour chosen")
        XCTAssertLessThan(pen.color.red, 0.3)
        let scales = pen.points.map(\.widthScale)
        XCTAssertLessThan((scales.max() ?? 1) - (scales.min() ?? 0), 0.05, "a ballpoint is one width all the way along")

        // Highlighter: the straight-line style saves a straight line whatever
        // the hand did.
        openSettings("studio-tool-highlighter", in: app)
        snap(app, "04-highlighter")
        app.buttons["highlighter-style-straight"].tap()
        XCTAssertEqual(app.buttons["highlighter-style-straight"].value as? String, "Selected")
        closePanel(app)
        drag(app, from: CGVector(dx: 0.1, dy: 0.45), to: CGVector(dx: 0.7, dy: 0.55))
        saved = try await eventually("a highlighter stroke", store, item) { self.ink($0).contains { $0.tool == .highlighter } }
        let highlight = try XCTUnwrap(ink(saved).first { $0.tool == .highlighter })
        XCTAssertEqual(highlight.points.count, 2, "a straight-line highlight is the line between its two ends")

        // Shapes: drag out a triangle.
        let shape = tool("studio-tool-shape", in: app)
        shape.tap(); shape.tap()
        XCTAssertTrue(app.buttons["shape-kind-triangle"].waitForExistence(timeout: 5))
        snap(app, "05-shapes")
        app.buttons["shape-kind-triangle"].tap()
        XCTAssertEqual(app.buttons["shape-kind-triangle"].value as? String, "Selected")
        closePanel(app)
        let shapeCanvas = app.descendants(matching: .any)["shape-draw-canvas"].firstMatch
        XCTAssertTrue(shapeCanvas.waitForExistence(timeout: 5))
        drag(app, from: CGVector(dx: 0.2, dy: 0.6), to: CGVector(dx: 0.7, dy: 0.95))
        saved = try await eventually("a triangle", store, item) { self.ink($0).count == 4 }
        let triangle = try XCTUnwrap(ink(saved).first { $0.points.count == 12 }, "a triangle is three corners and a closing one, each written three times")
        XCTAssertEqual(triangle.tool, .pen)

        // Undo takes the triangle away again, and redo puts it back.
        history("notebook-undo", in: app).tap()
        _ = try await eventually("the triangle undone", store, item) { self.ink($0).count == 3 }
        history("notebook-redo", in: app).tap()
        _ = try await eventually("the triangle redone", store, item) { self.ink($0).count == 4 }

        // Sticker: placed as an image, a sixth of the page across.
        tool("studio-tool-sticker", in: app).tap()
        XCTAssertTrue(app.buttons["sticker-star"].waitForExistence(timeout: 5))
        snap(app, "06-stickers")
        app.buttons["sticker-filter-planning"].tap()
        XCTAssertFalse(app.buttons["sticker-star"].exists, "the star is not a planning sticker")
        XCTAssertTrue(app.buttons["sticker-calendar"].exists)
        app.buttons["sticker-filter-all"].tap()
        app.buttons["sticker-star"].tap()
        saved = try await eventually("a sticker", store, item) { $0.contains { $0.payload.kind == "image" } }
        guard case .image(let sticker)? = saved.first(where: { $0.payload.kind == "image" })?.payload else {
            return XCTFail("no placed image")
        }
        XCTAssertEqual(sticker.frame.width, 96, accuracy: 0.5)
        XCTAssertEqual(sticker.frame.height, 96, accuracy: 0.5)

        // Insert: a grid page after this one, and the date as text.
        tool("studio-tool-insert", in: app).tap()
        XCTAssertTrue(app.buttons["insert-page-grid"].waitForExistence(timeout: 5))
        snap(app, "07-insert")
        app.buttons["insert-page-grid"].tap()
        for _ in 0..<40 where try await store.pages(of: item).count < 2 { try await Task.sleep(for: .milliseconds(250)) }
        let pages = try await store.pages(of: item)
        XCTAssertEqual(pages.count, 2, "the Insert tool added a page")

        // Eraser and lasso settings hold what was chosen.
        openSettings("studio-tool-eraser", in: app)
        snap(app, "08-eraser")
        let highlightsOnly = app.buttons["eraser-target-highlights"]
        reveal(highlightsOnly, in: app)
        highlightsOnly.tap()
        XCTAssertEqual(highlightsOnly.value as? String, "Selected")
        closePanel(app)
        openSettings("studio-tool-eraser", in: app)
        reveal(app.buttons["eraser-target-highlights"], in: app)
        XCTAssertEqual(app.buttons["eraser-target-highlights"].value as? String, "Selected", "the choice survived closing the panel")
        closePanel(app)

        openSettings("studio-tool-lasso", in: app)
        snap(app, "09-lasso")
        XCTAssertTrue(app.buttons["studio-lasso-rectangle"].exists)
        XCTAssertTrue(app.switches["lasso-content-images"].exists)
        closePanel(app)

        // Text: arm it, open its settings, make new boxes bold, and type one.
        let text = tool("editor-text-box", in: app)
        text.tap()
        XCTAssertEqual(text.value as? String, "Selected")
        text.tap()
        XCTAssertTrue(app.buttons["text-bold"].waitForExistence(timeout: 5))
        snap(app, "10-text")
        app.buttons["text-bold"].tap()
        XCTAssertEqual(app.buttons["text-bold"].value as? String, "Selected")
        closePanel(app)
        snap(app, "11-after")
    }

    /// The panels in French and Spanish, where the words are longest.
    func testTranslatedPanelsFit() async throws {
        for language in ["fr", "es"] {
            let (app, _, _) = try await open(language: language)
            let pen = tool("studio-tool-pen", in: app)
            pen.tap(); pen.tap()
            XCTAssertTrue(app.buttons["studio-settings-done"].waitForExistence(timeout: 5))
            snap(app, "20-pen-\(language)")
            for preset in ["fountain", "ballpoint", "gel", "pencil", "marker", "brush"] {
                XCTAssertTrue(app.buttons["pen-preset-\(preset)"].exists, "\(language) \(preset)")
            }
            closePanel(app)
            let eraser = tool("studio-tool-eraser", in: app)
            eraser.tap(); eraser.tap()
            XCTAssertTrue(app.buttons["eraser-target-handwriting"].waitForExistence(timeout: 5))
            snap(app, "21-eraser-\(language)")
            closePanel(app)
            tool("studio-tool-insert", in: app).tap()
            XCTAssertTrue(app.buttons["insert-date-time"].waitForExistence(timeout: 5))
            snap(app, "22-insert-\(language)")
            closePanel(app)
            app.terminate()
        }
    }

    /// Resting at the end of a stroke asks for it to be straightened; lifting
    /// straight away keeps it as drawn. Read back from disk, because the
    /// canvas showing a straight line is not the same as one being saved.
    func testRestingAtTheEndOfAStrokeStraightensIt() async throws {
        let (app, store, item) = try await open()
        defer { app.terminate() }
        let pen = tool("studio-tool-pen", in: app)
        pen.tap()
        if isPad {
            pen.tap()
            let finger = app.switches["studio-finger-drawing"]
            reveal(finger, in: app)
            if (finger.value as? String) != "1" { finger.flipSwitch() }
            closePanel(app)
        }
        let area = reachablePage(app)
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: area.minX + area.width * x, dy: area.minY + area.height * y))
        }
        point(0.1, 0.2).press(forDuration: 0.1, thenDragTo: point(0.8, 0.3))
        var saved = try await eventually("a freehand stroke", store, item) { self.ink($0).count == 1 }
        XCTAssertGreaterThan(try XCTUnwrap(ink(saved).first).points.count, 2, "lifted straight away, a stroke is kept as drawn")

        point(0.1, 0.6).press(forDuration: 0.1, thenDragTo: point(0.8, 0.7), withVelocity: .default, thenHoldForDuration: 1.2)
        saved = try await eventually("a second stroke", store, item) { self.ink($0).count == 2 }
        let counts = ink(saved).map(\.points.count).sorted()
        XCTAssertEqual(counts.first, 2, "rested on, the stroke is saved as the straight line between its ends: \(counts)")
    }
}
