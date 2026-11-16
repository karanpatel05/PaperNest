import XCTest

/// Owner, 2026-11-15: a folder offers New Note beside Import File, and the
/// note it makes is in that folder.
@MainActor final class FolderNoteUITests: XCTestCase {
    func testANewFolderOffersNewNoteAndKeepsTheNoteInIt() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-PaperNestLibraryPath", "/tmp/papernest-folder-note-\(UUID().uuidString)",
                               "-PaperNestDebugSkipWelcome", "YES", "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
                               "-libraryLayout", "list"]
        app.launch()
        defer { app.terminate() }

        let newFolder = app.buttons["home-new-folder"]
        XCTAssertTrue(newFolder.waitForExistence(timeout: 20))
        newFolder.tap()
        let name = app.alerts.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.typeText("Biology")
        app.alerts.buttons["OK"].tap()
        XCTAssertTrue(app.navigationBars["Biology"].waitForExistence(timeout: 10))

        // The empty folder offers both, side by side.
        let newNote = app.buttons["folder-new-note"]
        XCTAssertTrue(newNote.waitForExistence(timeout: 5), "an empty folder should offer New Note")
        XCTAssertTrue(app.buttons["Import…"].exists || app.buttons["library-import"].exists, "Import File is still offered")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "empty-folder-new-note"; shot.lifetime = .keepAlways; add(shot)
        newNote.tap()

        let notebookName = app.textFields["notebook-name"]
        XCTAssertTrue(notebookName.waitForExistence(timeout: 5))
        notebookName.tap()
        notebookName.typeText("Cells")
        app.buttons["notebook-create"].tap()
        XCTAssertTrue(app.buttons["editor-back"].waitForExistence(timeout: 15), "the new note did not open")
        app.buttons["editor-back"].tap()

        // Back in the folder: the note is in it, and New Note is still on hand.
        XCTAssertTrue(app.navigationBars["Biology"].waitForExistence(timeout: 10))
        let note = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Cells")).firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10), "the note should be in the folder it was made in")
        XCTAssertFalse(app.buttons["folder-new-note"].exists, "the empty-folder message is gone once it has a note")
        XCTAssertTrue(app.buttons["library-new-note"].firstMatch.exists, "New Note stays in the folder's toolbar")
    }
}
