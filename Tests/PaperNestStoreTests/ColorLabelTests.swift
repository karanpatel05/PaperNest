import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

@Suite struct ColorLabelTests {
    @Test func labelsSurviveRelaunchAndCanBeRemovedWithoutChangingPages() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .document, name: "Receipt", pages: [], assets: [])
        try await store.setColorLabel(.blue, for: [item.id])
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.item(item.id)?.colorLabel == .blue)
        try await reopened.setColorLabel(nil, for: [item.id])
        #expect(try await reopened.item(item.id)?.colorLabel == nil)
        #expect(try await reopened.pages(of: item.id).isEmpty)
    }

    @Test func batchLabelChangeRollsBackIfAnyItemIsMissingOrDeleted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let a = try await store.createItem(kind: .document, name: "A", pages: [], assets: [])
        let b = try await store.createItem(kind: .document, name: "B", pages: [], assets: [])
        try await store.setColorLabel(.green, for: [a.id, b.id])
        await #expect(throws: StoreError.itemNotFound) {
            try await store.setColorLabel(.red, for: [a.id, .make()])
        }
        #expect(try await store.item(a.id)?.colorLabel == .green)
        try await store.moveToRecentlyDeleted([b.id])
        await #expect(throws: StoreError.itemNotFound) {
            try await store.setColorLabel(.red, for: [a.id, b.id])
        }
        #expect(try await store.item(a.id)?.colorLabel == .green)
    }

    @Test func v3LibraryMigratesWithoutLosingDocuments() async throws {
        let dir = TempDirectory()
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 3 { try raw.execute(migration.sql) }
        try raw.setUserVersion(3)
        try raw.execute("INSERT INTO items VALUES ('legacy', 'document', 'Legacy', NULL, 0, 100, 100, NULL, 1)")
        raw.close()
        let store = try LibraryStore(directory: dir.url)
        let item = try #require(try await store.item(ItemID(rawValue: "legacy")))
        #expect(item.name == "Legacy")
        #expect(item.colorLabel == nil)
        try await store.setColorLabel(.purple, for: [item.id])
        #expect(try await store.item(item.id)?.colorLabel == .purple)
    }
}
