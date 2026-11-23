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
        let list = scrollViews["pdf-tools-list"]
        // Wholly in the list and clear of the pinned Export / Save below it. A
        // tile under that button still counts as hittable, but a tap there
        // lands on something else: on a phone's short drawer it folded the
        // Edit PDF card instead of opening Filter (2026-11-21).
        func clear() -> Bool {
            guard tool.exists, tool.isHittable else { return false }
            // Not one of the panel's tiles (the bottom bar's Undo, say):
            // hittable is enough, and no scrolling of the panel brings it.
            guard list.exists, list.descendants(matching: .any)[tool.identifier].exists else { return true }
            // Each frame read once: every read is a query of the app.
            let frame = tool.frame, area = list.frame
            var bottom = area.maxY
            let export = buttons["utilities-export"]
            if export.exists {
                let pinned = export.frame
                if pinned.minY > frame.minY { bottom = min(bottom, pinned.minY) }
            }
            return frame.minY >= area.minY - 1 && frame.maxY <= bottom + 1
        }
        // Reachable already: outside the panel (or the panel closed), or in
        // it and clear. The iPad column stays open between calls, so a tile
        // left under Export by the last one is not taken as reachable.
        if tool.exists && tool.isHittable && (!list.exists || clear()) { return }
        if !list.exists { buttons["editor-panels"].tap() }
        XCTAssertTrue(list.waitForExistence(timeout: 5), "Document Tools did not open", file: file, line: line)
        // From the list's left margin, outside every card: a drag that starts
        // on a tile can open its menu (Rotate, Filter, Replace Page) instead
        // of scrolling, which on the iPhone Duo's drawer is where the middle
        // of the list lands.
        func nudge(_ dy: CGFloat) {
            let margin = list.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 5, dy: 0))
            // Slowly, and held at the end, so the list stops where the finger
            // does. A flick coasts on: in the iPhone Duo's 213-point drawer a
            // 140-point drag moved the list about 330 and carried a section
            // header from below the window to above it in one step.
            margin.press(forDuration: 0.05, thenDragTo: margin.withOffset(CGVector(dx: 0, dy: dy)),
                         withVelocity: .slow, thenHoldForDuration: 0.15)
        }
        // Stops as soon as the tool is clear. A `for … where` loop would go on
        // asking all 58 times, about 15 queries each: over a minute a call
        // on an iPad even when one drag was enough (2026-11-21).
        var drags = 0
        while drags < 24, !clear() { nudge(-100); drags += 1 }
        drags = 0
        while drags < 34, !clear() { nudge(100); drags += 1 }
    }
}
