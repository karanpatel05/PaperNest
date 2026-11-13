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
