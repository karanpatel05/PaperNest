import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Text stamps in the library: placed as text boxes that stay stamps through
/// every edit, undo and move, findable by their words; and saved stamps
/// (schema v14) kept, listed, brought forward and deleted.
@Suite struct StampStoreTests {
    private func seeded(at url: URL) async throws -> (LibraryStore, Page) {
        let store = try LibraryStore(directory: url)
        let asset = try store.assets.store(Data("a PDF".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Invoice",
                                              pages: samplePages(asset, count: 1), assets: [asset])
        return (store, try await store.pages(of: item.id)[0])
    }

    private let frame = CGRect(x: 400, y: 40, width: 160, height: 44)
    private let green = StampPreset.approved.color

    private func placeStamp(_ store: LibraryStore, on page: Page) async throws -> PageObject {
        try await store.placeText("APPROVED", on: page.id, frame: frame, fontSize: 20, color: green,
                                  alignment: .center, isBold: true, stamp: .outlined).object
    }

    private func box(_ object: PageObject?) -> TextBox? {
        if case .text(let box)? = object?.payload { return box }
        return nil
    }

    @Test func aPlacedStampIsAStampedTextBoxAndItsWordIsFindable() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let object = try await placeStamp(store, on: page)

        let saved = box(try await store.objects(on: page.id).first)
        #expect(saved?.stamp == .outlined && saved?.text == "APPROVED" && saved?.color == green)
        #expect(saved == box(object))
        #expect(try await store.search("approved") == [page.itemID])
    }

    /// Changing its words, size or colour — through either editor, neither of
    /// which passes the style back — leaves it a stamp.
    @Test func changingAStampsWordsKeepsItAStamp() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let object = try await placeStamp(store, on: page)

        let (_, changed) = try await store.updateText(object, text: "APPROVED BY ANA", frame: frame, fontSize: 24,
                                                     color: .black, alignment: .center)

        #expect(box(changed)?.stamp == .outlined)
        #expect(box(try await store.objects(on: page.id).first)?.stamp == .outlined)
        #expect(box(try await store.objects(on: page.id).first)?.text == "APPROVED BY ANA")
    }

    /// Undo of an edit puts back the stamp as it was; undo of placing takes it away.
    @Test func undoRestoresTheStampAsItWas() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let object = try await placeStamp(store, on: page)
        let (_, changed) = try await store.updateText(object, text: "PAID", frame: frame, fontSize: 20,
                                                     color: green, alignment: .center)

        _ = try await store.applyInkChanges(on: page.id, saving: [object], replacing: [changed], deleting: [])
        #expect(box(try await store.objects(on: page.id).first) == box(object))

        _ = try await store.applyInkChanges(on: page.id, saving: [], replacing: [], deleting: [object])
        #expect(try await store.objects(on: page.id).isEmpty)
    }

    /// Moving keeps everything but the frame, as the move overlay writes it.
    @Test func movingAStampKeepsItAStamp() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let object = try await placeStamp(store, on: page)
        var moved = object
        guard case .text(var stamp) = moved.payload else { Issue.record("not a text box"); return }
        stamp.frame = frame.offsetBy(dx: -300, dy: 600)
        moved.payload = .text(stamp)

        _ = try await store.applyInkChanges(on: page.id, saving: [moved], replacing: [object], deleting: [])

        let saved = box(try await store.objects(on: page.id).first)
        #expect(saved?.stamp == .outlined && saved?.frame == frame.offsetBy(dx: -300, dy: 600))
    }

    // MARK: - Saved stamps

    @Test func aSavedStampIsKeptListedNewestFirstAndDeleted() async throws {
        let dir = TempDirectory()
        let (store, _) = try await seeded(at: dir.url)
        let checked = StampDesign(text: "Checked by Ana", style: .outlined, color: green, includesDate: true)
        let filed = StampDesign(text: "Filed", style: .filled, color: StampPreset.reviewed.color)

        let first = try await store.saveStamp(checked)
        let second = try await store.saveStamp(filed)

        #expect(try await store.savedStamps().map(\.id) == [second.id, first.id])
        #expect(try await store.savedStamps().map(\.design) == [filed, checked])

        try await store.deleteSavedStamp(second.id)
        #expect(try await store.savedStamps().map(\.id) == [first.id])
    }

    /// Kept again, the same stamp is not a second row: it comes to the front.
    @Test func keepingTheSameStampAgainBringsItForward() async throws {
        let dir = TempDirectory()
        let (store, _) = try await seeded(at: dir.url)
        let checked = StampDesign(text: "Checked", style: .outlined, color: green)
        let first = try await store.saveStamp(checked)
        let other = try await store.saveStamp(StampDesign(text: "Filed", style: .filled, color: green))

        let again = try await store.saveStamp(StampDesign(text: "  Checked ", style: .outlined, color: green))

        #expect(again.id == first.id)
        #expect(try await store.savedStamps().map(\.id) == [first.id, other.id])
        // A different date setting is a different stamp.
        _ = try await store.saveStamp(StampDesign(text: "Checked", style: .outlined, color: green, includesDate: true))
        #expect(try await store.savedStamps().count == 3)
    }

    @Test func aStampWithNoWordsIsNotKept() async throws {
        let dir = TempDirectory()
        let (store, _) = try await seeded(at: dir.url)
        await #expect(throws: StoreError.invalidPlacement) {
            try await store.saveStamp(StampDesign(text: " \n ", style: .outlined, color: .black))
        }
        #expect(try await store.savedStamps().isEmpty)
    }

    /// Saved stamps survive reopening the library.
    @Test func savedStampsSurviveReopening() async throws {
        let dir = TempDirectory()
        let design = StampDesign(text: "Received", style: .outlined, color: StampPreset.received.color, includesDate: true)
        do {
            let (store, _) = try await seeded(at: dir.url)
            try await store.saveStamp(design)
        }
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.savedStamps().map(\.design) == [design])
    }

    // MARK: - Schema v14

    @Test func aLibraryFromSchemaThirteenKeepsItsPagesAndCanKeepStamps() async throws {
        let dir = TempDirectory()
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 13 { try raw.execute(migration.sql) }
        try raw.setUserVersion(13)
        let transform = #"{"crop":{"x":0,"y":0,"width":1,"height":1},"rotation":0,"filter":"original","brightness":0,"contrast":1}"#
        try raw.execute("""
            INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
                VALUES ('d1', 'document', 'Receipt', NULL, 0, 100, 100, NULL, 1, NULL);
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id,
                               pdf_page_index, template, transform_json, revision, created_at, modified_at)
                VALUES ('p1', 'd1', 'V', 595.28, 841.89, 'template', NULL, NULL, 'blank', '\(transform)', 1, 100, 100);
            """)
        raw.close()

        let store = try LibraryStore(directory: dir.url)

        #expect(try await store.schemaVersion() == 14)
        #expect(try await store.pages(of: ItemID(rawValue: "d1")).map(\.id) == [PageID(rawValue: "p1")])
        try await store.saveStamp(StampDesign(text: "Paid", style: .outlined, color: green))
        #expect(try await store.savedStamps().count == 1)
    }

    /// A library a newer build has moved on is refused, as an older build refuses this v14 one.
    @Test func aLibraryANewerBuildMovedOnIsRefused() async throws {
        let dir = TempDirectory()
        #expect(try await LibraryStore(directory: dir.url).schemaVersion() == 14)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        try raw.setUserVersion(15)
        raw.close()
        #expect(throws: StoreError.newerSchema(found: 15, supported: 14)) { try LibraryStore(directory: dir.url) }
    }
}
