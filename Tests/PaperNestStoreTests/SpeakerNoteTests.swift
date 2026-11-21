import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// A presenter's notes, one per page: schema v16 and the three calls that
/// use it. Private and not an edit, like a bookmark.
@Suite struct SpeakerNoteTests {
    private func document(_ store: LibraryStore, pages: Int = 3, name: String = "Talk") async throws -> LibraryItem {
        let asset = try store.assets.store(Data("%PDF-notes-\(UUID().uuidString)".utf8), kind: .pdf,
                                           originalFilename: "talk.pdf")
        return try await store.createItem(kind: .document, name: name, pages: samplePages(asset, count: pages),
                                          assets: [asset])
    }

    @Test func aNoteIsKeptForItsPageAndReplacedWhenWrittenAgain() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)

        try await store.setSpeakerNote("Open with the numbers", on: pages[0].id)
        try await store.setSpeakerNote("Thank the team", on: pages[2].id)
        #expect(try await store.speakerNote(on: pages[0].id) == "Open with the numbers")
        #expect(try await store.speakerNote(on: pages[1].id) == nil)
        #expect(try await store.speakerNotes(of: item.id) == [pages[0].id: "Open with the numbers", pages[2].id: "Thank the team"])

        try await store.setSpeakerNote("Open with the chart", on: pages[0].id)
        #expect(try await store.speakerNote(on: pages[0].id) == "Open with the chart")
        #expect(try await store.testSpeakerNoteRowCount() == 2)
    }

    /// On disk when the call returns: a second store opened on the same
    /// library reads it.
    @Test func aNoteIsOnDiskWhenTheCallReturns() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]
        try await store.setSpeakerNote("Pause here", on: page.id)

        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.speakerNote(on: page.id) == "Pause here")
    }

    @Test func blankTextRemovesTheNote() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]
        try await store.setSpeakerNote("Something", on: page.id)

        try await store.setSpeakerNote("  \n\t ", on: page.id)
        #expect(try await store.speakerNote(on: page.id) == nil)
        #expect(try await store.testSpeakerNoteRowCount() == 0)
        try await store.setSpeakerNote("", on: page.id)  // removing nothing is not an error
    }

    @Test func writingANoteDoesNotCountAsEditingThePage() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]

        try await store.setSpeakerNote("A note", on: page.id)
        try await store.setSpeakerNote("", on: page.id)

        #expect(try await store.pages(of: item.id)[0] == page)
        #expect(try await store.item(item.id) == item)
    }

    @Test func aPageThatIsNotThereGetsNoNote() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)
        try await store.deletePages([pages[0].id])

        await #expect(throws: StoreError.pageNotFound) { try await store.setSpeakerNote("x", on: pages[0].id) }
        await #expect(throws: StoreError.pageNotFound) { try await store.setSpeakerNote("x", on: PageID(rawValue: UUID().uuidString)) }
    }

    /// Deleting a page can be undone for the rest of the session, and the
    /// undo brings its note back; deleted for good, the note goes too.
    @Test func aNoteGoesWithItsPage() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)
        try await store.setSpeakerNote("First", on: pages[0].id)
        try await store.setSpeakerNote("Second", on: pages[1].id)

        let deleted = try await store.deletePages([pages[1].id])
        #expect(try await store.speakerNotes(of: item.id) == [pages[0].id: "First"])
        #expect(try await store.speakerNote(on: pages[1].id) == nil)
        try await store.restorePages(deleted)
        #expect(try await store.speakerNote(on: pages[1].id) == "Second")

        try await store.deletePages([pages[1].id])
        #expect(try await store.purgeDeletedPages() == 1)
        #expect(try await store.testSpeakerNoteRowCount() == 1)
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func aDocumentDeletedForGoodTakesItsNotesAndACopyStartsWithout() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        try await store.setSpeakerNote("Mine", on: try await store.pages(of: item.id)[0].id)

        let copy = try await store.duplicateItems([item.id])[0]
        #expect(try await store.speakerNotes(of: copy.id).isEmpty, "a copy starts without notes")

        try await store.moveToRecentlyDeleted([item.id])
        #expect(try await store.testSpeakerNoteRowCount() == 1, "kept for a restore")
        try await store.deletePermanently([item.id])
        #expect(try await store.testSpeakerNoteRowCount() == 0)
    }

    /// Private: a note's words do not answer a search.
    @Test func aNoteIsNotFoundBySearch() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        try await store.setSpeakerNote("zanzibarquorum", on: try await store.pages(of: item.id)[0].id)
        #expect(try await store.search("zanzibarquorum").isEmpty)
    }

    /// With sync on, a note queues nothing for iCloud — not itself, and not
    /// its page or document either.
    @Test func notesAreNotSentToICloud() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        try await store.syncSetEnabled(true)
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]
        let queued = try await store.testQueuedForSync()

        try await store.setSpeakerNote("Private", on: page.id)
        try await store.setSpeakerNote("", on: page.id)

        #expect(try await store.testQueuedForSync() == queued)
    }

    /// A library from v15 opens at v16, everything in it kept, and takes
    /// notes; the migration rebuilds nothing, so v10's sync triggers stay.
    @Test func aLibraryFromSchemaFifteenOpensAndTakesNotes() async throws {
        let dir = TempDirectory()
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 15 { try raw.execute(migration.sql) }
        try raw.setUserVersion(15)
        let triggers = Set(try raw.query("SELECT name FROM sqlite_master WHERE type = 'trigger'") { $0.text(0) })
        raw.close()

        let store = try LibraryStore(directory: dir.url)
        #expect(try await store.schemaVersion() == Schema.latestVersion)
        // v16 rebuilt nothing; v17 added only the handwriting triggers.
        #expect(try await store.testAllTriggerNames().subtracting(HandwritingSearchTests.handwritingTriggers) == triggers)
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]
        try await store.setSpeakerNote("Works", on: page.id)
        #expect(try await store.speakerNote(on: page.id) == "Works")
    }
}

extension LibraryStore {
    /// Every note row, whatever page it is on, including deleted pages'.
    func testSpeakerNoteRowCount() throws -> Int {
        try db.query("SELECT COUNT(*) FROM speaker_notes") { $0.int(0) }.first ?? 0
    }
}
