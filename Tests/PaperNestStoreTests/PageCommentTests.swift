import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct PageCommentTests {
    @Test func commentsRoundTripCopyAndUndoWithoutTouchingInk() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createItem(kind: .notebook, name: "Notes", pages: [], assets: [])
        let page = try await store.addNotebookPage(.lined, to: book.id, after: nil).page
        let added = try await store.setPageComment(on: page.id, replacing: nil, text: "  Review\nthis page  ")
        let original = try #require(added.after)
        #expect(original.commentText == "Review\nthis page")
        let edited = try await store.setPageComment(on: page.id, replacing: original, text: "Updated")
        _ = try await store.applyPageCommentChange(edited.inverse)
        #expect(try await store.objects(on: page.id) == [original])
        _ = try await store.applyPageCommentChange(edited)
        let removed = try await store.setPageComment(on: page.id, replacing: edited.after, text: nil)
        #expect(try await store.objects(on: page.id).isEmpty)
        _ = try await store.applyPageCommentChange(removed.inverse)
        let copy = try #require(try await store.duplicateItems([book.id]).first)
        let copiedPage = try #require(try await store.pages(of: copy.id).first)
        let copied = try #require(try await store.objects(on: copiedPage.id).first)
        #expect(copied.commentText == "Updated")
        #expect(copied.id != original.id)
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.objects(on: page.id).first?.commentText == "Updated")
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func staleEditsAndUndoPreserveNewerComments() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createItem(kind: .notebook, name: "Notes", pages: [], assets: [])
        let page = try await store.addNotebookPage(.blank, to: book.id, after: nil).page
        let a = try await store.setPageComment(on: page.id, replacing: nil, text: "A")
        let b = try await store.setPageComment(on: page.id, replacing: a.after, text: "B")
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.setPageComment(on: page.id, replacing: a.after, text: "stale")
        }
        await #expect(throws: StoreError.pageObjectsChanged) { try await store.applyPageCommentChange(a.inverse) }
        #expect(try await store.objects(on: page.id) == [b.after!])
        _ = try await store.applyPageCommentChange(b.inverse)
        _ = try await store.applyPageCommentChange(a.inverse)
        var foreign = try #require(a.after)
        let other = try await store.addNotebookPage(.grid, to: book.id, after: page.id).page
        foreign.pageID = other.id
        try await store.saveObject(foreign)
        await #expect(throws: StoreError.pageObjectsChanged) { try await store.applyPageCommentChange(a) }
        #expect(try await store.objects(on: other.id) == [foreign])
    }

    @Test func validatesTextAndActivePageParent() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let book = try await store.createItem(kind: .notebook, name: "Notes", pages: [], assets: [])
        let page = try await store.addNotebookPage(.blank, to: book.id, after: nil).page
        for text in [" \n ", String(repeating: "x", count: 10_001)] {
            await #expect(throws: StoreError.invalidComment) { try await store.setPageComment(on: page.id, replacing: nil, text: text) }
        }
        #expect(try await store.objects(on: page.id).isEmpty)
        let added = try await store.setPageComment(on: page.id, replacing: nil, text: "Keep")
        _ = try await store.deletePages([page.id])
        await #expect(throws: StoreError.pageNotFound) { try await store.applyPageCommentChange(added.inverse) }
        let other = try await store.addNotebookPage(.blank, to: book.id, after: nil).page
        try await store.moveToRecentlyDeleted([book.id])
        await #expect(throws: StoreError.pageNotFound) { try await store.setPageComment(on: other.id, replacing: nil, text: "Hidden") }
    }

    @Test func v6MigrationPreservesObjectsAndAcceptsComments() async throws {
        let dir = TempDirectory()
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 6 { try raw.execute(migration.sql) }
        try raw.setUserVersion(6)
        let transform = String(decoding: try JSONEncoder().encode(PageTransform.identity), as: UTF8.self)
        let payload = PageObject.Payload.text(.init(frame: .zero, text: "Legacy text"))
        let json = String(decoding: try JSONEncoder().encode(payload), as: UTF8.self)
        try raw.execute("INSERT INTO items (id,kind,name,created_at,modified_at,schema_version) VALUES ('i','notebook','Old',1,1,1)")
        try raw.run("INSERT INTO pages (id,item_id,sort_key,source_width,source_height,content_kind,template,transform_json,revision,created_at,modified_at) VALUES ('p','i','V',595,842,'template','blank',?,0,1,1)", [.text(transform)])
        try raw.run("INSERT INTO page_objects VALUES ('old','p','V','text',?,1)", [.text(json)])
        raw.close()
        let store = try LibraryStore(directory: dir.url)
        #expect(try await store.schemaVersion() == Schema.latestVersion)
        let pageID = PageID(rawValue: "p")
        #expect(try await store.objects(on: pageID).first?.payload == payload)
        _ = try await store.setPageComment(on: pageID, replacing: nil, text: "New comment")
        #expect(try await store.objects(on: pageID).count == 2)
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func corruptV6MigrationRollsBackWithoutLosingExistingData() async throws {
        let dir = TempDirectory()
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 6 { try raw.execute(migration.sql) }
        try raw.setUserVersion(6)
        // Keep an orphan-free schema migration fixture; existing payload data
        // is checked through SQL because old ink JSON need not be decoded here.
        try raw.execute("PRAGMA foreign_keys = OFF")
        try raw.execute("INSERT INTO page_objects VALUES ('legacy', 'p', 'V', 'text', '{}', 1)")
        try raw.execute("PRAGMA foreign_keys = ON")
        // A deliberate orphan must cause rollback rather than losing data.
        raw.close()
        #expect(throws: StoreError.self) { try LibraryStore(directory: dir.url) }
        let check = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        #expect(try check.userVersion == 6)
        #expect(try check.query("SELECT id FROM page_objects") { $0.text(0) } == ["legacy"])
        check.close()
    }
}
