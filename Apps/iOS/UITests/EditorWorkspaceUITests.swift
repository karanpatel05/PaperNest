import XCTest
import PaperNestCore
import PaperNestStore

/// Exercises the shared PDF/notebook chrome against disposable real libraries.
@MainActor final class EditorWorkspaceUITests: XCTestCase {
    func testPinchZoomWithLassoAndPen() async throws { try await checkZoom(pinch: true) }
    func testZoomButtonsWithLassoAndPen() async throws { try await checkZoom(pinch: false) }
    private func checkZoom(pinch: Bool) async throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: "/tmp/papernest-zoom-\(UUID())")
        let store = try LibraryStore(directory: directory)
        _ = try await store.createItem(kind: .notebook, name: "Zoom check", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Zoom check", "-AppleLanguages", "(en)", "-PaperNestDebugZoomTrace", "YES"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["studio-tool-lasso"].waitForExistence(timeout: 20))
        let page = app.images["document-page-image"]
        // Pinch the paper, not the scroll view. The scroll view is the whole
        // viewport — on an 11-inch iPad 481x1210 — and a *closing* pinch starts
        // its two touches near opposite edges of whatever it is given, so on
        // the scroll view they begin above and below the paper and the
        // recognizer never sees two touches on it. Measured: pinching the
        // scroll view closed never changes the zoom, whether the page fits
        // (100% -> 100%) or overflows (150% -> 150%), while pinching the paper
        // shrinks it in both states (100% -> 50%, 150% -> 75%). An opening
        // pinch starts centred, which is why only the shrink half ever failed.
        for tool in ["studio-tool-lasso", "studio-tool-pen"] {
            if app.buttons[tool].value as? String != "Selected" { app.buttons[tool].tap() }
            let before = page.frame.width
            if pinch { page.pinch(withScale: 1.5, velocity: 1) }
            else { app.buttons["editor-zoom-in"].tap() }
            XCTAssertGreaterThan(page.frame.width, before * 1.1, "Pinch must enlarge paper with \(tool)")
            let enlarged = page.frame.width
            if pinch { page.pinch(withScale: 0.7, velocity: -1) }
            else { app.buttons["editor-zoom-out"].tap() }
            for _ in 0..<30 where page.frame.width >= enlarged * 0.95 { try await Task.sleep(for: .milliseconds(100)) }
            XCTAssertLessThan(page.frame.width, enlarged * 0.95, "Pinch must shrink paper with \(tool)")
        }
        app.buttons["editor-zoom-fit"].tap()
        XCTAssertEqual(app.buttons["editor-zoom-fit"].value as? String, "100%")
    }

    func testNotebookWorkspaceEnglish() async throws { try await checkWorkspace(kind: .notebook, language: "en") }
    func testPDFWorkspaceEnglish() async throws { try await checkWorkspace(kind: .document, language: "en") }
    func testPDFWorkspaceFrench() async throws { try await checkWorkspace(kind: .document, language: "fr") }
    func testPDFWorkspaceSpanish() async throws { try await checkWorkspace(kind: .document, language: "es") }

    private func checkWorkspace(kind: ItemKind, language: String) async throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: "/tmp/papernest-editor-workspace-\(UUID())")
        let store = try LibraryStore(directory: directory)
        _ = try await store.createItem(kind: kind, name: "Workspace", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path,
            "-PaperNestDebugSkipWelcome", "YES", "-PaperNestDebugOpenItem", "Workspace",
            "-AppleLanguages", "(\(language))", "-AppleLocale", "\(language)_US",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        defer { app.terminate() }
        // One control shows and hides Document Utilities — pages and tools
        // together — on every device (owner's 2026-11-12 redesign). The page
        // strip and the tools list no longer have a switch each.
        let onPad = UIDevice.current.userInterfaceIdiom == .pad
        let panels = app.buttons["editor-panels"]
        XCTAssertTrue(panels.waitForExistence(timeout: 20))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "editor-toggle-thumbnails").count, 0,
                       "There is no separate page-strip control")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "editor-toggle-pdf-tools").count, 0,
                       "There is no separate tools control")
        let sidebar = app.scrollViews["pdf-tools-list"]
        if onPad {
            let writingTools = app.scrollViews["notebook-tool-bar"]
            XCTAssertLessThanOrEqual(panels.frame.maxY, writingTools.frame.minY,
                                     "The panel control belongs in the navigation header above the writing tools")
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            panels.tap()
            XCTAssertTrue(sidebar.waitForNonExistence(timeout: 5))
            panels.tap()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["page-thumbnail-1"].exists, "pages and tools share the one panel")
        } else {
            XCTAssertFalse(sidebar.exists, "a phone opens with the page to itself")
            panels.tap()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["page-thumbnail-1"].exists, "pages and tools share the one panel")
            app.buttons["pdf-tools-close"].tap()
            XCTAssertTrue(sidebar.waitForNonExistence(timeout: 5))
        }
        attachWorkspace(app, stage: "initial", kind: kind, language: language)
        let text = app.buttons["editor-text-box"]
        XCTAssertTrue(text.exists)
        // A named tool is wider than its icon; the 2026-11-12 redesign names
        // tools wherever there is room, so the compact target is a phone's.
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertLessThanOrEqual(text.frame.width, 48, "PDF and notebook Text Box use the same compact icon target")
        }
        XCTAssertTrue(app.buttons["studio-drawing-toggle"].exists, "Both document types expose the floating palette")
        let pen = app.buttons["studio-tool-pen"]
        pen.tap(); pen.tap()
        let width = app.sliders["studio-width-slider"]
        XCTAssertTrue(width.waitForExistence(timeout: 5))
        let done = app.buttons["studio-settings-done"]
        XCTAssertTrue(done.exists)
        // Opacity sits below the stroke preview and may need scrolling into reach.
        let opacity = app.sliders["studio-opacity-slider"]
        let settingsForm = app.scrollViews["tool-panel-scroll"]
        XCTAssertTrue(settingsForm.exists)
        let settingsFrame = settingsForm.frame.intersection(app.frame)
        for _ in 0..<6 where !opacity.isHittable {
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: settingsFrame.maxX - 8, dy: settingsFrame.maxY - 40))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -250)))
        }
        XCTAssertTrue(opacity.waitForExistence(timeout: 5))
        XCTAssertTrue(opacity.isHittable)
        let previousOpacity = opacity.value as? String
        opacity.adjust(toNormalizedSliderPosition: 0.6)
        XCTAssertNotEqual(opacity.value as? String, previousOpacity)
        // Dismiss the anchored settings through their own action.
        done.tap()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let signature = revealTool("editor-signature", in: app, isPad: isPad)
        signature.tap()
        XCTAssertTrue(app.buttons["signature-cancel"].waitForExistence(timeout: 5))
        attachWorkspace(app, stage: "signature", kind: kind, language: language)
        if isPad {
            XCTAssertTrue(pen.isHittable, "Signature lives beside the still-interactive document")
            XCTAssertEqual(app.sheets.count, 0)
        }
        app.buttons["signature-cancel"].tap()
        XCTAssertTrue(app.buttons["signature-cancel"].waitForNonExistence(timeout: 5))
        let pages = revealTool("editor-pages", in: app, isPad: isPad)
        pages.tap()
        XCTAssertTrue(app.buttons["pages-done"].waitForExistence(timeout: 5))
        if isPad { XCTAssertEqual(app.sheets.count, 0) }
        app.buttons["pages-select-2"].tap()
        XCTAssertNotEqual(app.buttons["pages-select-1"].value as? String,
                          app.buttons["pages-select-2"].value as? String)
        app.buttons["pages-done"].tap()
        XCTAssertTrue(pen.exists)
    }


    private func revealTool(_ identifier: String, in app: XCUIApplication, isPad: Bool) -> XCUIElement {
        let target = app.buttons[identifier]
        if isPad {
            let sidebar = app.scrollViews["pdf-tools-list"]
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            for _ in 0..<10 where !target.isHittable { sidebar.swipeUp() }
        } else {
            // A phone reaches the same tools in the same Document Utilities
            // panel, drawn as a drawer (owner's 2026-11-12 redesign). This
            // used to scroll the native More menu, which on a short screen
            // shows too few rows to drag between.
            let sidebar = app.scrollViews["pdf-tools-list"]
            if !sidebar.exists { app.buttons["editor-panels"].tap() }
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            for _ in 0..<10 where !(target.exists && target.isHittable) { sidebar.swipeUp() }
        }
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        XCTAssertTrue(target.isHittable)
        return target
    }

    private func attachWorkspace(_ app: XCUIApplication, stage: String, kind: ItemKind, language: String) {
        let device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "editor-\(stage)-\(kind.rawValue)-\(language)-\(device)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFrenchSignatureAtLargestTextSize() async throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: "/tmp/papernest-signature-large-\(UUID())")
        let store = try LibraryStore(directory: directory)
        _ = try await store.createItem(kind: .document, name: "Signature layout", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path,
            "-PaperNestDebugSkipWelcome", "YES", "-PaperNestDebugOpenItem", "Signature layout",
            "-AppleLanguages", "(fr)", "-AppleLocale", "fr_FR",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        defer { app.terminate() }
        let editorLoaded = app.buttons["editor-panels"]
        XCTAssertTrue(editorLoaded.waitForExistence(timeout: 20))
        revealTool("editor-signature", in: app, isPad: UIDevice.current.userInterfaceIdiom == .pad).tap()
        let cancel = app.buttons["signature-cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertTrue(cancel.isHittable)
        let place = app.buttons["signature-place"]
        XCTAssertTrue(place.exists)
        XCTAssertFalse(place.isEnabled, "Empty signatures cannot be placed")
        XCTAssertTrue(app.frame.contains(place.frame), "Placement must fit inside the visible viewport")
        attachWorkspace(app, stage: "signature-XXXL", kind: .document, language: "fr")
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
    }

    func testScrollAppendsOneMatchingNotebookPage() async throws {
        continueAfterFailure = false
        let directory = URL(fileURLWithPath: "/tmp/papernest-scroll-\(UUID())")
        let store = try LibraryStore(directory: directory)
        let id = try await store.createItem(kind: .notebook, name: "Scroll notebook", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.grid))
        ], assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path,
            "-PaperNestDebugSkipWelcome", "YES", "-PaperNestDebugOpenItem", "Scroll notebook",
            "-AppleLanguages", "(en)"]
        app.launch()
        defer { app.terminate() }
        let scroll = app.scrollViews["document-page-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 20))
        let initial = try await store.pages(of: id.id)
        XCTAssertEqual(initial.count, 1)
        let drawing = app.buttons["studio-drawing-toggle"]
        if drawing.value as? String == "Selected" { drawing.tap() }
        var pages = initial
        // A phone's page is taller than its viewport: scroll to the bottom
        // before expecting continuation. Stop as soon as one page is added.
        for _ in 0..<4 where pages.count == 1 {
            scroll.swipeUp(velocity: .slow)
            for _ in 0..<5 where pages.count == 1 {
                try await Task.sleep(for: .milliseconds(200))
                pages = try await store.pages(of: id.id)
            }
        }
        XCTAssertEqual(pages.count, 2, "A deliberate bottom scroll appends exactly one page")
        XCTAssertEqual(pages.last?.content, .template(.grid))
        XCTAssertEqual(pages.last?.sourceSize, initial.last?.sourceSize)
        app.terminate(); app.launch()
        XCTAssertTrue(scroll.waitForExistence(timeout: 20))
        let reopened = try await store.pages(of: id.id)
        XCTAssertEqual(reopened, pages)
    }

    func testNotebookScrollsBetweenExistingPages() async throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: "/tmp/papernest-continuous-\(UUID())")
        let store = try LibraryStore(directory: root)
        let item = try await store.createItem(kind: .notebook, name: "Continuous", pages:
            [PageTemplate.lined, .grid, .blank].map {
                .init(sourceSize: CGSize(width: 600, height: 800), content: .template($0))
            }, assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", root.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Continuous", "-AppleLanguages", "(en)"]
        app.launch(); defer { app.terminate() }
        let scroll = app.scrollViews["document-page-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 20))
        let drawing = app.buttons["studio-drawing-toggle"]
        if drawing.value as? String == "Selected" { drawing.tap() }
        let active = app.images["document-page-image"]
        XCTAssertEqual(active.label, "Page 1 of 3")
        for _ in 0..<8 where active.label == "Page 1 of 3" {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertEqual(active.label, "Page 2 of 3")
        for _ in 0..<8 where active.label != "Page 1 of 3" {
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
                .press(forDuration: 0.1, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)),
                       withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTAssertEqual(active.label, "Page 1 of 3")
        let pages = try await store.pages(of: item.id)
        XCTAssertEqual(pages.count, 3)
    }

    func testTwoFingerContactDoesNotDrawAndSingleFingerStillWrites() async throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad touch routing") }
        continueAfterFailure = false
        let root = URL(fileURLWithPath: "/tmp/papernest-touch-routing-\(UUID())")
        let store = try LibraryStore(directory: root)
        let item = try await store.createItem(kind: .notebook, name: "Touch routing", pages:
            [PageTemplate.lined, .grid].map {
                .init(sourceSize: CGSize(width: 600, height: 800), content: .template($0))
            }, assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", root.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", "Touch routing", "-AppleLanguages", "(en)"]
        app.launch(); defer { app.terminate() }
        let lasso = app.buttons["studio-tool-lasso"]
        XCTAssertTrue(lasso.waitForExistence(timeout: 20))
        let page = app.images["document-page-image"]
        page.twoFingerTap()
        XCTAssertEqual(lasso.value as? String, "Selected")
        let pen = app.buttons["studio-tool-pen"]
        pen.tap(); pen.tap()
        let settings = app.scrollViews["tool-panel-scroll"]
        let finger = app.switches["studio-finger-drawing"]
        for _ in 0..<8 where !finger.isHittable { settings.swipeUp() }
        XCTAssertTrue(finger.isHittable)
        if finger.value as? String != "1" {
            finger.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        app.closeToolSettings()
        page.twoFingerTap()
        XCTAssertEqual(pen.value as? String, "Selected")
        let original = try await store.pages(of: item.id)
        for sheet in original {
            let marks = try await store.objects(on: sheet.id)
            XCTAssertTrue(marks.isEmpty, "Two-finger contacts must not save ink or lasso moves")
        }
        // Existing one-finger drawing continues to work after a navigation contact.
        let canvas = app.descendants(matching: .any)["ink-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 5))
        canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4))
            .press(forDuration: 0.1, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        var marks = try await store.objects(on: original[0].id)
        for _ in 0..<20 where marks.isEmpty {
            try await Task.sleep(for: .milliseconds(200))
            marks = try await store.objects(on: original[0].id)
        }
        XCTAssertFalse(marks.isEmpty)
    }

}
