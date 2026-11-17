import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Details a person kept for a document: one set per document, read off one
/// page, stale when that page's paper changes, gone with the document.
@Suite struct DocumentDetailsTests {
    private func receiptDocument(_ store: LibraryStore) async throws -> (LibraryItem, Page) {
        let scan = try store.assets.store(Data("receipt".utf8), kind: .png, originalFilename: "r.png")
        let item = try await store.createItem(kind: .document, name: "Receipt", pages: [
            .init(sourceSize: CGSize(width: 300, height: 600), content: .image(scan.id))
        ], assets: [scan])
        return (item, try #require(try await store.pages(of: item.id).first))
    }

    private var details: CapturedDetails {
        CapturedDetails(kind: .receipt, values: [.merchant: DetailValue(text: "Acme Market", confidence: 0.55),
                                                 .total: DetailValue(text: "4.54 €", confidence: 1)])
    }

    @Test func detailsAreKeptReplacedAndDeleted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await receiptDocument(store)
        #expect(try await store.documentDetails(of: item.id) == nil)

        try await store.saveDocumentDetails(details, for: item.id, readFrom: page.id)
        let stored = try #require(try await store.documentDetails(of: item.id))
        #expect(stored.details == details && stored.pageID == page.id && !stored.isStale)

        var edited = details
        edited.values[.total] = DetailValue(text: "4.64 €", confidence: 1)
        try await store.saveDocumentDetails(edited, for: item.id, readFrom: page.id)
        #expect(try await store.documentDetails(of: item.id)?.details[.total] == "4.64 €", "one set per document")

        try await store.deleteDocumentDetails(of: item.id)
        #expect(try await store.documentDetails(of: item.id) == nil)
    }

    /// Drawing on the page leaves the paper as it was; a new scan does not.
    @Test func detailsGoStaleWhenThePaperChangesNotWhenItIsDrawnOn() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await receiptDocument(store)
        try await store.saveDocumentDetails(details, for: item.id, readFrom: page.id)

        let stroke = InkStroke(tool: .pen, color: .black, width: 2, points: [InkPoint(x: 10, y: 10), InkPoint(x: 50, y: 20)])
        try await store.saveObject(PageObject(pageID: page.id, zKey: "V", payload: .ink(stroke), modifiedAt: Date()))
        #expect(try await store.documentDetails(of: item.id)?.isStale == false, "an ink stroke is not new paper")

        let rescan = try store.assets.store(Data("rescan".utf8), kind: .png, originalFilename: "r2.png")
        _ = try await store.replacePageContent(page.id, with: .init(sourceSize: page.sourceSize, content: .image(rescan.id),
                                                                    transform: page.transform), assets: [rescan])
        #expect(try await store.documentDetails(of: item.id)?.isStale == true)
    }

    @Test func detailsGoWithTheirDocument() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await receiptDocument(store)
        try await store.saveDocumentDetails(details, for: item.id, readFrom: page.id)
        try await store.moveToRecentlyDeleted([item.id])
        #expect(try await store.deletePermanently([item.id]) == 1)
        #expect(try await store.documentDetails(of: item.id) == nil)
    }

    @Test func detailsReadFromAPageAreDeletedWithIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await receiptDocument(store)
        try await store.saveDocumentDetails(details, for: item.id, readFrom: page.id)
        #expect(try await store.deleteDocumentDetails(readFrom: page.id) == 1)
        #expect(try await store.documentDetails(of: item.id) == nil)
    }

    @Test func aPageOfAnotherDocumentIsRefused() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, _) = try await receiptDocument(store)
        let (_, other) = try await receiptDocument(store)
        await #expect(throws: StoreError.pageNotFound) {
            try await store.saveDocumentDetails(details, for: item.id, readFrom: other.id)
        }
    }

    // MARK: - Schema v13

    @Test func aLibraryFromSchemaTwelveKeepsItsTemplatesAndCanKeepDetails() async throws {
        let dir = TempDirectory()
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 12 { try raw.execute(migration.sql) }
        try raw.setUserVersion(12)
        let transform = #"{"crop":{"x":0,"y":0,"width":1,"height":1},"rotation":0,"filter":"original","brightness":0,"contrast":1}"#
        try raw.execute("""
            INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
                VALUES ('d1', 'document', 'Receipt', NULL, 0, 100, 100, NULL, 1, NULL);
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id,
                               pdf_page_index, template, transform_json, revision, created_at, modified_at)
                VALUES ('p1', 'd1', 'V', 595.28, 841.89, 'template', NULL, NULL, 'blank', '\(transform)', 1, 100, 100);
            INSERT INTO saved_templates (id, name, source_width, source_height, content_kind, asset_id, pdf_page_index,
                                         template, transform_json, objects_json, created_at, modified_at)
                VALUES ('t1', 'Weekly', 595.28, 841.89, 'template', NULL, NULL, 'planner', '\(transform)', '[]', 100, 100);
            """)
        raw.close()

        let store = try LibraryStore(directory: dir.url)

        #expect(try await store.schemaVersion() >= 13, "moved on past twelve")
        #expect(try await store.savedTemplates().map(\.name) == ["Weekly"])
        try await store.saveDocumentDetails(details, for: ItemID(rawValue: "d1"), readFrom: PageID(rawValue: "p1"))
        #expect(try await store.documentDetails(of: ItemID(rawValue: "d1"))?.details == details)
    }
}
