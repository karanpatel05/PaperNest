import XCTest
import PaperNestCore
import PaperNestStore

/// The first thing you touch in a freshly opened document must actually happen.
///
/// On iPad the tools inspector was presented from the moment the editor
/// appeared. Where the window is too narrow for SwiftUI to lay `.inspector` out
/// as a column it presents as an **overlay**, and the overlay's
/// tap-outside-to-dismiss swallows the first touch outside it — so the first
/// tap, or the first pinch, after opening a notebook did nothing at all.
///
/// Measured before the fix (first tap on the pen, "Not selected" means it was
/// eaten): 834pt iPad portrait **eaten**; 1032pt iPad portrait landed;
/// 1210pt and 1376pt landscape landed. iPhone never auto-presented it and was
/// never affected.
@MainActor final class EditorFirstTouchUITests: XCTestCase {
    private func openNotebook(_ name: String) async throws -> XCUIApplication {
        let directory = URL(fileURLWithPath: "/tmp/papernest-firsttouch-\(UUID())")
        let store = try LibraryStore(directory: directory)
        _ = try await store.createItem(kind: .notebook, name: name, pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank))
        ], assets: [])
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", directory.path, "-PaperNestDebugSkipWelcome", "YES",
                               "-PaperNestDebugOpenItem", name, "-AppleLanguages", "(en)"]
        app.launch()
        XCTAssertTrue(app.buttons["studio-tool-lasso"].waitForExistence(timeout: 20))
        return app
    }


    /// Width, not orientation, decides whether the tools panel is opened for
    /// you: a 13-inch iPad in portrait is 1032pt and still fits a column, while
    /// an 11-inch in portrait is 834pt and would have to overlay. iPhone routes
    /// these tools through a sheet and never auto-presents them.
    private func assertToolsPanelMatchesWidth(_ app: XCUIApplication) {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        let width = app.windows.firstMatch.frame.width
        let panel = app.scrollViews["pdf-tools-list"]
        if width >= 900 {
            XCTAssertTrue(panel.waitForExistence(timeout: 10),
                          "at \(width)pt it fits as a column, so it is opened for you")
        } else {
            XCTAssertFalse(panel.exists,
                           "at \(width)pt it would have to overlay, so it is not opened for you")
            app.buttons["studio-more-tools"].tap()
            XCTAssertTrue(panel.waitForExistence(timeout: 10),
                          "and the toolbar button still opens it by hand")
        }
    }

    /// The narrow-window case that was broken. In portrait an 11-inch iPad is
    /// 834pt wide, which is below the width `.inspector` needs for a column.
    func testFirstTapOnAToolIsNotSwallowedInPortrait() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try await Task.sleep(for: .milliseconds(1000))
        let app = try await openNotebook("FirstTouchPortrait")
        defer { app.terminate() }

        let pen = app.buttons["studio-tool-pen"]
        XCTAssertEqual(pen.value as? String, "Not selected", "the pen should start unselected")
        pen.tap()
        let selected = expectation(for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: pen)
        await fulfillment(of: [selected], timeout: 10)

        assertToolsPanelMatchesWidth(app)
    }

    /// The wide case, which already worked — kept so a fix that trades one for
    /// the other cannot pass unnoticed.
    func testFirstTapOnAToolIsNotSwallowedInLandscape() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .landscapeLeft
        try await Task.sleep(for: .milliseconds(1000))
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = try await openNotebook("FirstTouchLandscape")
        defer { app.terminate() }

        assertToolsPanelMatchesWidth(app)

        let pen = app.buttons["studio-tool-pen"]
        XCTAssertEqual(pen.value as? String, "Not selected", "the pen should start unselected")
        pen.tap()
        let selected = expectation(for: NSPredicate(format: "value == %@", "Selected"), evaluatedWith: pen)
        await fulfillment(of: [selected], timeout: 10)
    }

    /// The owner's actual report: the first zoom interaction did nothing.
    func testFirstZoomTapChangesTheZoomInPortrait() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        try await Task.sleep(for: .milliseconds(1000))
        let app = try await openNotebook("FirstTouchZoom")
        defer { app.terminate() }

        let fit = app.buttons["editor-zoom-fit"]
        XCTAssertEqual(fit.value as? String, "100%", "a freshly opened page sits at 100%")
        app.buttons["editor-zoom-in"].tap()
        let enlarged = expectation(for: NSPredicate(format: "value != %@", "100%"), evaluatedWith: fit)
        await fulfillment(of: [enlarged], timeout: 10)
    }
}
