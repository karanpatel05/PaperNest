import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// The reader's bookmarks: schema v11 and the four calls that use it.
@Suite struct BookmarkTests {
    private func document(_ store: LibraryStore, pages: Int = 3, name: String = "Report") async throws -> LibraryItem {
        let asset = try store.assets.store(Data("%PDF-bookmarks-\(UUID().uuidString)".utf8), kind: .pdf,
                                           originalFilename: "report.pdf")
        return try await store.createItem(kind: .document, name: name, pages: samplePages(asset, count: pages),
                                          assets: [asset])
    }

    @Test func aMarkedPageIsListedAndTheListIsInPageOrder() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)

        let third = try await store.addBookmark(on: pages[2].id)
        let first = try await store.addBookmark(on: pages[0].id, name: "  Summary\n")

        #expect(first.name == "Summary")
        #expect(third.name.isEmpty)
        #expect(first.itemID == item.id && first.pageID == pages[0].id)
        #expect(try await store.bookmarks(of: item.id) == [first, third])
    }

    /// Committed before the call returns: another connection sees it at once.
    @Test func aBookmarkIsOnDiskWhenTheCallReturns() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[1]

        let bookmark = try await store.addBookmark(on: page.id, name: "Clause 4")

        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.bookmarks(of: item.id) == [bookmark])
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func markingAMarkedPageKeepsTheBookmarkItHas() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]
        let first = try await store.addBookmark(on: page.id, name: "Start")

        let again = try await store.addBookmark(on: page.id, name: "Something else")

        #expect(again == first)
        #expect(try await store.bookmarks(of: item.id) == [first])
    }

    /// A bookmark is on a page, not on a page number.
    @Test func aBookmarkFollowsItsPageWhenThePagesAreReordered() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)
        let onFirst = try await store.addBookmark(on: pages[0].id, name: "Was first")
        let onSecond = try await store.addBookmark(on: pages[1].id, name: "Was second")

        try await store.movePage(pages[0].id, toIndex: 2)

        let listed = try await store.bookmarks(of: item.id)
        #expect(listed.map(\.id) == [onSecond.id, onFirst.id])
        #expect(listed.map(\.pageID) == [pages[1].id, pages[0].id])
    }

    @Test func renamingTidiesTheNameAndAnEmptyOneIsAllowed() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url, now: Self.ticking())
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]
        let made = try await store.addBookmark(on: page.id)

        let named = try await store.renameBookmark(made.id, to: "  Where the\nfigures are  ")
        #expect(named.name == "Where the figures are")
        #expect(named.id == made.id && named.createdAt == made.createdAt)
        #expect(named.modifiedAt > made.modifiedAt)
        #expect(try await store.bookmarks(of: item.id) == [named])

        let long = try await store.renameBookmark(made.id, to: String(repeating: "x", count: 500))
        #expect(long.name.count == Bookmark.maximumNameLength)

        let cleared = try await store.renameBookmark(made.id, to: "   ")
        #expect(cleared.name.isEmpty)
        #expect(try await store.bookmarks(of: item.id).map(\.name) == [""])
    }

    @Test func aRemovedBookmarkIsGoneAndRemovingItAgainIsNotAnError() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)
        let keep = try await store.addBookmark(on: pages[0].id)
        let drop = try await store.addBookmark(on: pages[1].id)

        try await store.removeBookmark(drop.id)
        try await store.removeBookmark(drop.id)

        #expect(try await store.bookmarks(of: item.id) == [keep])
        await #expect(throws: StoreError.bookmarkNotFound) { try await store.renameBookmark(drop.id, to: "Gone") }
        // The page can be marked afresh.
        let fresh = try await store.addBookmark(on: pages[1].id)
        #expect(fresh.id != drop.id)
    }

    /// A ribbon in a book does not change the book: no new thumbnail, no
    /// second pass of text recognition, no move to the top of Recent.
    @Test func markingAPageDoesNotCountAsEditingIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url, now: Self.ticking())
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]

        let bookmark = try await store.addBookmark(on: page.id)
        try await store.renameBookmark(bookmark.id, to: "Named")
        try await store.removeBookmark(bookmark.id)

        #expect(try await store.pages(of: item.id)[0] == page)
        #expect(try await store.item(item.id) == item)
    }

    @Test func aBookmarkIsOnlyListedForItsOwnDocument() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let one = try await document(store, name: "One")
        let two = try await document(store, name: "Two")
        let inOne = try await store.addBookmark(on: try await store.pages(of: one.id)[0].id)
        let inTwo = try await store.addBookmark(on: try await store.pages(of: two.id)[1].id)

        #expect(try await store.bookmarks(of: one.id) == [inOne])
        #expect(try await store.bookmarks(of: two.id) == [inTwo])
    }

    @Test func aPageThatIsNotThereCannotBeMarked() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)

        await #expect(throws: StoreError.pageNotFound) { try await store.addBookmark(on: PageID(rawValue: "no-such-page")) }
        try await store.deletePages([pages[0].id])
        await #expect(throws: StoreError.pageNotFound) { try await store.addBookmark(on: pages[0].id) }
        try await store.moveToRecentlyDeleted([item.id])
        await #expect(throws: StoreError.pageNotFound) { try await store.addBookmark(on: pages[1].id) }
        try await store.restore([item.id])
        #expect(try await store.bookmarks(of: item.id).isEmpty)
    }

    /// Deleting a page can be undone for the rest of the session, and the
    /// undo has to bring back everything that was on the page.
    @Test func aDeletedPagesBookmarkIsHiddenAndComesBackWithThePage() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)
        let bookmark = try await store.addBookmark(on: pages[1].id, name: "Appendix")

        let deleted = try await store.deletePages([pages[1].id])
        #expect(try await store.bookmarks(of: item.id).isEmpty)
        await #expect(throws: StoreError.bookmarkNotFound) { try await store.renameBookmark(bookmark.id, to: "Ghost") }

        try await store.restorePages(deleted)
        #expect(try await store.bookmarks(of: item.id) == [bookmark])
    }

    @Test func aPageDeletedForGoodTakesItsBookmarkWithIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let pages = try await store.pages(of: item.id)
        try await store.addBookmark(on: pages[0].id)
        try await store.addBookmark(on: pages[1].id)

        try await store.deletePages([pages[1].id])
        #expect(try await store.purgeDeletedPages() == 1)

        #expect(try await store.testBookmarkRowCount() == 1)
        #expect(try await store.bookmarks(of: item.id).map(\.pageID) == [pages[0].id])
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func aDocumentDeletedForGoodTakesItsBookmarksWithIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let other = try await document(store, name: "Other")
        try await store.addBookmark(on: try await store.pages(of: item.id)[0].id)
        let kept = try await store.addBookmark(on: try await store.pages(of: other.id)[0].id)

        try await store.moveToRecentlyDeleted([item.id])
        // Still there for a restore.
        #expect(try await store.testBookmarkRowCount() == 2)
        try await store.deletePermanently([item.id])

        #expect(try await store.testBookmarkRowCount() == 1)
        #expect(try await store.bookmarks(of: other.id) == [kept])
    }

    /// A copy is a new document with new pages. Whether the reader's own
    /// place-marks should be copied with it was decided: they are not.
    @Test func aDuplicatedDocumentStartsWithNoBookmarks() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await document(store)
        let bookmark = try await store.addBookmark(on: try await store.pages(of: item.id)[0].id)

        let copy = try #require(try await store.duplicateItems([item.id]).first)

        #expect(try await store.bookmarks(of: copy.id).isEmpty)
        #expect(try await store.bookmarks(of: item.id) == [bookmark])
    }

    // MARK: - Schema v11

    /// A library as schema v10 left it: a document with two pages.
    private func makeV10Library(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 10 { try raw.execute(migration.sql) }
        try raw.setUserVersion(10)
        let transform = #"{"crop":{"x":0,"y":0,"width":1,"height":1},"rotation":0,"filter":"original","brightness":0,"contrast":1}"#
        try raw.execute("""
            INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
                VALUES ('i1', 'document', 'Lease', NULL, 1, 100, 100, NULL, 1, 'blue');
            INSERT INTO assets VALUES ('aaa', 'pdf', 1234, 'lease.pdf', 'local', 100);
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id,
                               pdf_page_index, template, transform_json, revision, created_at, modified_at)
                VALUES ('p1', 'i1', 'V', 612, 792, 'pdfPage', 'aaa', 0, NULL, '\(transform)', 1, 100, 100);
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id,
                               pdf_page_index, template, transform_json, revision, created_at, modified_at)
                VALUES ('p2', 'i1', 'W', 612, 792, 'pdfPage', 'aaa', 1, NULL, '\(transform)', 1, 100, 100);
            """)
        raw.close()
    }

    @Test func aLibraryFromSchemaTenKeepsEverythingAndCanBeBookmarked() async throws {
        let dir = TempDirectory()
        try makeV10Library(at: dir.url)

        let store = try LibraryStore(directory: dir.url)

        #expect(try await store.schemaVersion() == 11)
        #expect(Schema.latestVersion == 11)
        let item = try #require(try await store.item(ItemID(rawValue: "i1")))
        #expect(item.name == "Lease" && item.isFavorite && item.colorLabel == .blue)
        let pages = try await store.pages(of: item.id)
        #expect(pages.map(\.id.rawValue) == ["p1", "p2"])
        #expect(try await store.bookmarks(of: item.id).isEmpty)
        let bookmark = try await store.addBookmark(on: pages[1].id, name: "Signature page")
        #expect(try await store.bookmarks(of: item.id) == [bookmark])
        // The database itself is sound; the one complaint is this
        // fixture's original, which was never a file.
        #expect(try await store.integrityCheck() == ["missing asset aaa"])
    }

    /// v11 adds a table and rebuilds none, so every sync trigger v10 made
    /// must still be there afterwards. The handoff's warning, kept as a test.
    @Test func theMigrationLeavesEverySyncTriggerInPlace() async throws {
        let dir = TempDirectory()
        try makeV10Library(at: dir.url)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        let before = Set(try raw.query("SELECT name FROM sqlite_master WHERE type = 'trigger'") { $0.text(0) })
        raw.close()
        #expect(before.count >= 24)

        let store = try LibraryStore(directory: dir.url)

        #expect(try await store.testAllTriggerNames() == before)
    }

    /// The decision, pinned: with sync on, a bookmark queues nothing for
    /// iCloud — not itself, and not its page or document either.
    @Test func bookmarksAreNotSentToICloud() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        try await store.syncSetEnabled(true)
        let item = try await document(store)
        let page = try await store.pages(of: item.id)[0]
        let queued = try await store.testQueuedForSync()

        let bookmark = try await store.addBookmark(on: page.id, name: "Mine")
        try await store.renameBookmark(bookmark.id, to: "Still mine")
        #expect(try await store.testQueuedForSync() == queued)
        try await store.removeBookmark(bookmark.id)

        #expect(try await store.testQueuedForSync() == queued)
    }

    /// A clock that never gives the same time twice, so "later" can be asserted.
    private static func ticking() -> @Sendable () -> Date {
        let clock = Ticker()
        return { clock.next() }
    }

    private final class Ticker: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func next() -> Date {
            lock.lock()
            defer { lock.unlock() }
            value += 1
            return value
        }
    }
}

extension LibraryStore {
    /// Every bookmark row, whatever page it is on, including deleted ones.
    func testBookmarkRowCount() throws -> Int {
        try db.query("SELECT COUNT(*) FROM bookmarks") { $0.int(0) }.first ?? 0
    }

    func testAllTriggerNames() throws -> Set<String> {
        Set(try db.query("SELECT name FROM sqlite_master WHERE type = 'trigger'") { $0.text(0) })
    }

    /// What is waiting in the sync outbox, as "type id change seq" lines.
    func testQueuedForSync() throws -> [String] {
        try db.query("SELECT record_type, record_id, change, seq FROM sync_outbox ORDER BY seq") {
            "\($0.text(0)) \($0.text(1)) \($0.text(2)) \($0.int(3))"
        }
    }
}
