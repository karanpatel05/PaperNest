import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Schema v5 widens two CHECK constraints, which SQLite can only do by
/// rebuilding the tables. With foreign keys enforced, `DROP TABLE items`
/// cascades into `pages` and empties the library, so these tests exist to
/// prove the upgrade keeps everything.
@Suite struct FileItemMigrationTests {
    /// A v4 library with a document, two pages, an object, OCR text, a folder,
    /// a tag, a color label and a rescan history row: one of everything that
    /// hangs off `items` or `assets`.
    /// A v4 `PageTransform`, as the store writes it.
    private static let identityTransform =
        #"{"crop":{"x":0,"y":0,"width":1,"height":1},"rotation":0,"filter":"original","brightness":0,"contrast":1}"#

    private func makeV4Library(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 4 { try raw.execute(migration.sql) }
        try raw.setUserVersion(4)
        try raw.execute("""
            INSERT INTO folders VALUES ('f1', 'Receipts', NULL, 100, 100, NULL);
            INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
                VALUES ('i1', 'document', 'Lease', 'f1', 1, 100, 100, NULL, 1, 'blue');
            INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
                VALUES ('i2', 'notebook', 'Notes', NULL, 0, 100, 100, NULL, 1, NULL);
            INSERT INTO assets VALUES ('aaa', 'pdf', 1234, 'lease.pdf', 'local', 100);
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id,
                               pdf_page_index, template, transform_json, revision, created_at, modified_at)
                VALUES ('p1', 'i1', 'V', 612, 792, 'pdfPage', 'aaa', 0, NULL, '\(Self.identityTransform)', 1, 100, 100);
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id,
                               pdf_page_index, template, transform_json, revision, created_at, modified_at)
                VALUES ('p2', 'i1', 'W', 612, 792, 'pdfPage', 'aaa', 1, NULL, '\(Self.identityTransform)', 1, 100, 100);
            INSERT INTO tags VALUES ('t1', 'important');
            INSERT INTO item_tags VALUES ('i1', 't1');
            INSERT INTO search_index (item_id, page_id, field, content) VALUES ('i1', NULL, 'title', 'Lease');
            """)
        raw.close()
    }

    @Test func aV4LibraryKeepsEveryPageAndRowThroughTheV5Rebuild() async throws {
        let dir = TempDirectory()
        try makeV4Library(at: dir.url)

        let store = try LibraryStore(directory: dir.url)
        #expect(try await store.schemaVersion() == 5)

        let item = try #require(try await store.item(ItemID(rawValue: "i1")))
        #expect(item.name == "Lease")
        #expect(item.kind == .document)
        #expect(item.folderID?.rawValue == "f1")
        #expect(item.isFavorite)
        #expect(item.colorLabel == .blue)
        // The one that matters: the implicit delete behind `DROP TABLE items`
        // cascades into pages when foreign keys are on.
        let pages = try await store.pages(of: item.id)
        #expect(pages.count == 2, "the rebuild deleted pages")
        #expect(pages.map(\.id.rawValue) == ["p1", "p2"])
        #expect(try await store.item(ItemID(rawValue: "i2"))?.kind == .notebook)
        #expect(try await store.search("Lease") == [item.id])
        #expect(try await store.integrityCheck().filter { !$0.hasPrefix("missing asset") }.isEmpty)

        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        defer { raw.close() }
        #expect(try raw.query("PRAGMA foreign_key_check") { $0.text(0) }.isEmpty)
        #expect(try raw.query("SELECT count(*) FROM item_tags") { $0.int(0) }[0] == 1)
        #expect(try raw.query("SELECT count(*) FROM assets") { $0.int(0) }[0] == 1)
    }

    @Test func theRebuiltTablesAcceptFileRowsAndStillRejectNonsense() async throws {
        let dir = TempDirectory()
        try makeV4Library(at: dir.url)
        _ = try LibraryStore(directory: dir.url)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        defer { raw.close() }

        try raw.execute("""
            INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
            VALUES ('i3', 'file', 'Report.docx', NULL, 0, 100, 100, NULL, 5, NULL)
            """)
        try raw.execute("INSERT INTO assets VALUES ('bbb', 'file', 4096, 'Report.docx', 'local', 100)")
        try raw.execute("INSERT INTO file_items VALUES ('i3', 'bbb', 'org.openxmlformats.wordprocessingml.document', 'Report.docx', 4096)")
        #expect(try raw.query("SELECT uti FROM file_items WHERE item_id = 'i3'") { $0.text(0) }[0]
                == "org.openxmlformats.wordprocessingml.document")

        #expect(throws: (any Error).self) {
            try raw.execute("""
                INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
                VALUES ('i4', 'spreadsheet', 'Nope', NULL, 0, 100, 100, NULL, 5, NULL)
                """)
        }
        #expect(throws: (any Error).self) {
            try raw.execute("INSERT INTO assets VALUES ('ccc', 'movie', 1, NULL, 'local', 100)")
        }
        // A file item's row goes when the item is permanently deleted.
        try raw.execute("PRAGMA foreign_keys = ON; DELETE FROM items WHERE id = 'i3'")
        #expect(try raw.query("SELECT count(*) FROM file_items") { $0.int(0) }[0] == 0)
    }

    @Test func aFreshLibraryAndAMigratedOneHaveTheSameShape() async throws {
        let fresh = TempDirectory()
        _ = try LibraryStore(directory: fresh.url)
        let migrated = TempDirectory()
        try makeV4Library(at: migrated.url)
        _ = try LibraryStore(directory: migrated.url)

        func shape(_ url: URL) throws -> [String] {
            let raw = try SQLiteDatabase(path: url.appendingPathComponent(LibraryStore.databaseFilename).path)
            defer { raw.close() }
            return try raw.query("SELECT type || ' ' || name || ' ' || COALESCE(sql, '') FROM sqlite_master ORDER BY type, name") { $0.text(0) }
        }
        // A library upgraded from v4 must be indistinguishable from one created
        // at v5, or later migrations will behave differently on each.
        #expect(try shape(fresh.url) == shape(migrated.url))
    }
}
