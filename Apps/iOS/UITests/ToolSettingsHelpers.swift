import XCTest

extension XCUIApplication {
    /// Closes the open tool settings and waits until a touch on the page is
    /// the page's again.
    ///
    /// On a phone the settings are a bottom sheet. Its close button leaves the
    /// hierarchy before the sheet has finished sliding away, and a touch that
    /// lands on a sheet in mid-flight belongs to the sheet — so a test that
    /// closes the settings and draws in the same breath draws nothing, and
    /// reports a failure the app did not have.
    @MainActor func closeToolSettings(file: StaticString = #filePath, line: UInt = #line) {
        let done = buttons["studio-settings-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "no tool settings are open", file: file, line: line)
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5), "the tool settings did not close", file: file, line: line)
        Thread.sleep(forTimeInterval: 0.7)
    }
}

extension XCUIApplication {
    /// Brings a tool in Document Tools into reach: opens the panel through its
    /// one toggle if it is closed (a column on iPad, a drawer on a phone), then
    /// scrolls the panel in short drags until the tool can be tapped. Replaces
    /// opening the toolbar's More menu, which was removed on 2026-11-14 because
    /// everything in it is in this panel.
    @MainActor func revealInDocumentTools(_ tool: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        if tool.exists && tool.isHittable { return }
        let list = scrollViews["pdf-tools-list"]
        if !list.exists { buttons["editor-panels"].tap() }
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Document Tools did not open", file: file, line: line)
        func nudge(_ dy: CGFloat) {
            let middle = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            middle.press(forDuration: 0.05, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: dy)))
        }
        for _ in 0..<14 where !(tool.exists && tool.isHittable) { nudge(-140) }
        for _ in 0..<20 where !(tool.exists && tool.isHittable) { nudge(140) }
    }
}
