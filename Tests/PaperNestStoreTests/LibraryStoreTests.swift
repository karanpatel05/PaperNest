import CoreGraphics
import Foundation
import SQLite3
import Testing
import PaperNestCore
@testable import PaperNestStore

/// A controllable clock for retention and ordering tests.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(days: Double) { lock.withLock { current = current.addingTimeInterval(days * 86_400) } }
}

/// A unique directory per test, removed afterwards.
struct TempDirectory: ~Copyable {
    let url: URL
    init() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit { try? FileManager.default.removeItem(at: url) }
}

func samplePages(_ asset: AssetFileStore.StagedAsset, count: Int) -> [LibraryStore.NewPage] {
    (0..<count).map { LibraryStore.NewPage(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0)) }
}

@Suite struct LibraryStoreTests {
    @Test func itemAndPagesSurviveReopening() async throws {
        let dir = TempDirectory()
        let created: LibraryItem
        let originalPages: [Page]
        do {
            let store = try LibraryStore(directory: dir.url)
            let asset = try store.assets.store(Data("%PDF-fake".utf8), kind: .pdf, originalFilename: "Lease.pdf")
            created = try await store.createItem(kind: .document, name: "Lease", pages: samplePages(asset, count: 3), assets: [asset])
            let pages = try await store.pages(of: created.id)
            try await store.updateTransform(pages[1].id, to: PageTransform(rotation: .clockwise90, filter: .grayscale))
            originalPages = try await store.pages(of: created.id)
        }
        // A fresh store instance over the same directory sees committed state.
        let reopened = try LibraryStore(directory: dir.url)
        let reopenedItem = try #require(try await reopened.item(created.id))
        #expect(reopenedItem.name == created.name && reopenedItem.createdAt == created.createdAt)
        // Editing a page bumps the item's modification date.
        #expect(reopenedItem.modifiedAt >= created.modifiedAt)
        let pages = try await reopened.pages(of: created.id)
        #expect(pages == originalPages)
        #expect(pages.map { $0.content } == [0, 1, 2].map { PageContent.pdfPage(originalPages[0].content.assetID!, index: $0) })
        #expect(pages[1].transform.rotation == .clockwise90)
        #expect(pages[1].revision == 2)
        #expect(try await reopened.integrityCheck().isEmpty)
    }

    @Test func movingAPageChangesOnlyThatPageAndPersists() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("pdf".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Doc", pages: samplePages(asset, count: 5), assets: [asset])
        let before = try await store.pages(of: item.id)

        try await store.movePage(before[4].id, toIndex: 0)
        try await store.movePage(before[1].id, toIndex: 4)
        let expected = [before[4], before[0], before[2], before[3], before[1]].map(\.id)
        #expect(try await store.pages(of: item.id).map(\.id) == expected)

        let unchanged = try await store.pages(of: item.id).filter { [before[0].id, before[2].id, before[3].id].contains($0.id) }
        #expect(unchanged.allSatisfy { p in p.sortKey == before.first { $0.id == p.id }!.sortKey })

        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.pages(of: item.id).map(\.id) == expected)
        await #expect(throws: StoreError.invalidOrder) { try await store.movePage(before[0].id, toIndex: 9) }
    }

    @Test func tiedSortKeysFromAMergeAreRebalancedBeforeMoving() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("pdf".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Doc", pages: samplePages(asset, count: 3), assets: [asset])
        let pages = try await store.pages(of: item.id)
        // Simulate two devices having chosen the same key.
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        try raw.run("UPDATE pages SET sort_key = 'V'", [])
        raw.close()
        let tiedOrder = try await store.pages(of: item.id).map(\.id)
        #expect(tiedOrder == pages.map(\.id).sorted { $0.rawValue < $1.rawValue })

        try await store.movePage(tiedOrder[0], toIndex: 2)
        let after = try await store.pages(of: item.id)
        #expect(after.map(\.id) == [tiedOrder[1], tiedOrder[2], tiedOrder[0]])
        #expect(zip(after, after.dropFirst()).allSatisfy { $0.sortKey < $1.sortKey })
    }

    @Test func transformHistoryKeepsEveryPreviousState() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("img".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Scan",
                                              pages: [.init(sourceSize: CGSize(width: 500, height: 700), content: .image(asset.id))], assets: [asset])
        let page = try await store.pages(of: item.id)[0]
        let t1 = PageTransform(rotation: .clockwise90)
        let t2 = PageTransform(crop: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), rotation: .clockwise90, filter: .blackAndWhite)
        try await store.updateTransform(page.id, to: t1)
        let updated = try await store.updateTransform(page.id, to: t2)
        #expect(updated.revision == 3)
        #expect(try await store.transformHistory(page.id) == [.identity, t1])
        // A no-op update records nothing and keeps the revision.
        #expect(try await store.updateTransform(page.id, to: t2).revision == 3)
        // The original bytes are untouched by edits.
        #expect(try store.assets.read(asset.id, kind: .jpeg) == Data("img".utf8))
    }

    @Test func pageDeletionCanBeUndoneExactly() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("pdf".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .notebook, name: "Notes", pages: samplePages(asset, count: 3), assets: [asset])
        let pages = try await store.pages(of: item.id)
        let ink = PageObject(pageID: pages[1].id, zKey: "V", payload: .ink(InkStroke(tool: .pen, color: .black, width: 2, points: [InkPoint(x: 1, y: 1)])),
                             modifiedAt: Date(timeIntervalSince1970: 5))
        try await store.saveObject(ink)
        let recognition = PageRecognition(pageID: pages[1].id, sourceRevision: 2, engineVersion: "test", status: .completed, languages: ["fr-FR"],
                                          lines: [RecognizedLine(text: "Été", box: .full, confidence: 0.9)])
        try await store.saveRecognition(recognition)
        let before = try await store.pages(of: item.id)

        let deleted = try await store.deletePages([pages[1].id])
        #expect(try await store.pages(of: item.id).count == 2)
        #expect(try await store.page(pages[1].id) == nil)

        try await store.restorePages(deleted)
        #expect(try await store.pages(of: item.id) == before)
        #expect(try await store.objects(on: pages[1].id) == [ink])
        #expect(try await store.recognition(for: pages[1].id) == recognition)
    }

    @Test func insertingPagesKeepsOrderAndDedupesAssets() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let a = try store.assets.store(Data("A".utf8), kind: .png, originalFilename: "a.png")
        let item = try await store.createItem(kind: .document, name: "Mixed",
                                              pages: [.init(sourceSize: CGSize(width: 100, height: 100), content: .image(a.id))], assets: [a])
        let first = try await store.pages(of: item.id)[0]
        let b = try store.assets.store(Data("B".utf8), kind: .png, originalFilename: "b.png")
        let again = try store.assets.store(Data("A".utf8), kind: .png, originalFilename: "copy.png")
        #expect(again.id == a.id)
        let inserted = try await store.insertPages(
            [.init(sourceSize: CGSize(width: 100, height: 100), content: .image(b.id)),
             .init(sourceSize: CGSize(width: 100, height: 100), content: .image(again.id))],
            into: item.id, after: nil, assets: [b, again])
        let front = try await store.insertPages([.init(sourceSize: CGSize(width: 50, height: 50), content: .template(.lined))],
                                                into: item.id, after: nil, assets: [])
        let order = try await store.pages(of: item.id).map(\.id)
        #expect(order == [first.id] + inserted.map(\.id) + front.map(\.id))
        let afterFirst = try await store.insertPages([.init(sourceSize: CGSize(width: 50, height: 50), content: .template(.grid))],
                                                     into: item.id, after: first.id, assets: [])
        #expect(try await store.pages(of: item.id).map(\.id)[1] == afterFirst[0].id)
    }
}

@Suite struct DurabilityTests {
    @Test func crashBetweenAssetWriteAndCommitLeavesOnlyASweepableFile() async throws {
        let dir = TempDirectory()
        let orphan: AssetFileStore.StagedAsset
        do {
            let store = try LibraryStore(directory: dir.url)
            orphan = try store.assets.store(Data("never committed".utf8), kind: .jpeg, originalFilename: nil)
            // The process "dies" here: no createItem call.
        }
        // Real clock: the sweep compares against file modification dates.
        let store = try LibraryStore(directory: dir.url)
        #expect(try await store.items(in: .all).isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.assets.url(for: orphan.id, kind: .jpeg).path))
        // Within the grace period an in-flight import is left alone.
        #expect(try await store.sweepOrphanAssets(gracePeriod: 86_400 * 365 * 100) == 0)
        #expect(try await store.sweepOrphanAssets(gracePeriod: -60) == 1)
        #expect(!FileManager.default.fileExists(atPath: store.assets.url(for: orphan.id, kind: .jpeg).path))
    }

    @Test func failedTransactionLeavesNoPartialItem() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let missing = AssetFileStore.StagedAsset(id: AssetID(sha256: String(repeating: "9", count: 64)), kind: .pdf, byteCount: 1, originalFilename: nil)
        await #expect(throws: StoreError.assetMissing(missing.id.sha256)) {
            try await store.createItem(kind: .document, name: "Broken", pages: samplePages(missing, count: 2), assets: [missing])
        }
        #expect(try await store.items(in: .all).isEmpty)
        #expect(try await store.search("Broken").isEmpty)
    }

    @Test func uncommittedWritesFromAnAbandonedConnectionAreDiscarded() async throws {
        let dir = TempDirectory()
        _ = try LibraryStore(directory: dir.url)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        try raw.execute("BEGIN IMMEDIATE")
        try raw.run("INSERT INTO items (id, kind, name, is_favorite, created_at, modified_at, schema_version) VALUES ('X', 'document', 'Ghost', 0, 0, 0, 1)")
        raw.close() // closing mid-transaction is how a killed process looks to SQLite

        let store = try LibraryStore(directory: dir.url)
        #expect(try await store.items(in: .all).isEmpty)
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func libraryFromANewerAppVersionIsRefusedAndUntouched() throws {
        let dir = TempDirectory()
        _ = try LibraryStore(directory: dir.url)
        let path = dir.url.appendingPathComponent(LibraryStore.databaseFilename).path
        let raw = try SQLiteDatabase(path: path)
        try raw.setUserVersion(99)
        raw.close()
        #expect(throws: StoreError.newerSchema(found: 99, supported: Schema.latestVersion)) {
            try LibraryStore(directory: dir.url)
        }
        let check = try SQLiteDatabase(path: path)
        #expect(try check.userVersion == 99)
    }

    @Test func versionOneLibraryMigratesWithoutLosingPages() async throws {
        let dir = TempDirectory()
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        // Build a library exactly as schema v1 left it.
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        try raw.execute(Schema.migrations[0].sql)
        try raw.setUserVersion(1)
        try raw.run("INSERT INTO items (id, kind, name, is_favorite, created_at, modified_at, schema_version) VALUES ('I', 'document', 'Old', 0, 0, 0, 1)")
        try raw.run("""
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, template, transform_json, revision, created_at, modified_at)
            VALUES ('P', 'I', 'V', 612, 792, 'template', 'lined', ?, 1, 0, 0)
            """, [.text(String(decoding: try JSONEncoder().encode(PageTransform.identity), as: UTF8.self))])
        raw.close()

        let store = try LibraryStore(directory: dir.url)
        #expect(try await store.schemaVersion() == Schema.latestVersion)
        let pages = try await store.pages(of: ItemID(rawValue: "I"))
        #expect(pages.map(\.id.rawValue) == ["P"])
        #expect(pages.first?.content == .template(.lined))
    }

    @Test func reopeningAnUpToDateLibraryRunsNoMigrations() async throws {
        let dir = TempDirectory()
        let first = try LibraryStore(directory: dir.url)
        #expect(try await first.schemaVersion() == Schema.latestVersion)
        let second = try LibraryStore(directory: dir.url)
        #expect(try await second.schemaVersion() == Schema.latestVersion)
    }

    @Test func damagedAssetFileIsDetectedAndReplacedOnReimport() throws {
        let dir = TempDirectory()
        let assets = try AssetFileStore(rootURL: dir.url)
        let data = Data("original bytes".utf8)
        let staged = try assets.store(data, kind: .png, originalFilename: nil)
        try Data("corrupted".utf8).write(to: assets.url(for: staged.id, kind: .png))
        #expect(throws: StoreError.assetChecksumMismatch(staged.id.sha256)) { try assets.verify(staged.id, kind: .png) }
        _ = try assets.store(data, kind: .png, originalFilename: nil)
        try assets.verify(staged.id, kind: .png)
    }
}

@Suite struct DeletionTests {
    /// An undoable page deletion must survive permanently deleting some other
    /// item, including one that shares the same original.
    @Test(arguments: [false, true])
    func undoablePageDeletionSurvivesPermanentDeleteElsewhere(sharedOriginal: Bool) async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let a = try store.assets.store(Data("only used by doc 1".utf8), kind: .png, originalFilename: nil)
        let doc1 = try await store.createItem(kind: .document, name: "One",
                                              pages: [.init(sourceSize: CGSize(width: 10, height: 10), content: .image(a.id))], assets: [a])
        let b = sharedOriginal ? a : try store.assets.store(Data("doc 2".utf8), kind: .png, originalFilename: nil)
        let doc2 = try await store.createItem(kind: .document, name: "Two",
                                              pages: [.init(sourceSize: CGSize(width: 10, height: 10), content: .image(b.id))], assets: [b])
        let page = try await store.pages(of: doc1.id)[0]
        let deleted = try await store.deletePages([page.id])

        try await store.moveToRecentlyDeleted([doc2.id])
        try await store.deletePermanently([doc2.id])

        #expect(FileManager.default.fileExists(atPath: store.assets.url(for: a.id, kind: .png).path))
        try await store.restorePages(deleted)
        #expect(try await store.pages(of: doc1.id).map(\.id) == [page.id])
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func deletedPagesArePurgedAtTheNextLaunch() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let a = try store.assets.store(Data("page original".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Doc",
                                              pages: [.init(sourceSize: CGSize(width: 10, height: 10), content: .image(a.id))], assets: [a])
        let page = try await store.pages(of: item.id)[0]
        let deleted = try await store.deletePages([page.id])
        #expect(try await store.page(page.id) == nil)
        #expect(try await store.items(in: .all).first?.pageCount == 0)

        // Launch housekeeping: purge, then sweep with no grace period.
        #expect(try await store.purgeDeletedPages() == 1)
        try await store.sweepOrphanAssets(gracePeriod: -60)
        #expect(!FileManager.default.fileExists(atPath: store.assets.url(for: a.id, kind: .jpeg).path))
        await #expect(throws: StoreError.pageNotFound) { try await store.restorePages(deleted) }
    }

    @Test func recentlyDeletedRestoreAndPurge() async throws {
        let dir = TempDirectory()
        let clock = TestClock()
        let store = try LibraryStore(directory: dir.url, now: { clock.now })
        let shared = try store.assets.store(Data("shared".utf8), kind: .pdf, originalFilename: nil)
        let keep = try await store.createItem(kind: .document, name: "Keep", pages: samplePages(shared, count: 1), assets: [shared])
        let drop = try await store.createItem(kind: .document, name: "Drop", pages: samplePages(shared, count: 1), assets: [shared])
        let own = try store.assets.store(Data("own".utf8), kind: .png, originalFilename: nil)
        let dropOwn = try await store.createItem(kind: .document, name: "Drop own",
                                                 pages: [.init(sourceSize: CGSize(width: 10, height: 10), content: .image(own.id))], assets: [own])

        try await store.moveToRecentlyDeleted([drop.id, dropOwn.id])
        #expect(try await store.items(in: .all).map(\.id) == [keep.id])
        #expect(Set(try await store.items(in: .recentlyDeleted).map(\.id)) == [drop.id, dropOwn.id])
        #expect(try await store.search("Drop").isEmpty)

        try await store.restore([drop.id])
        #expect(try await store.search("Drop").map { $0 } == [drop.id])
        try await store.moveToRecentlyDeleted([drop.id])

        clock.advance(days: 29)
        #expect(try await store.purgeExpiredDeletions() == 0)
        clock.advance(days: 2)
        #expect(try await store.purgeExpiredDeletions() == 2)
        #expect(try await store.items(in: .recentlyDeleted).isEmpty)
        // The shared original is still used by "Keep"; the other is gone.
        #expect(FileManager.default.fileExists(atPath: store.assets.url(for: shared.id, kind: .pdf).path))
        #expect(!FileManager.default.fileExists(atPath: store.assets.url(for: own.id, kind: .png).path))
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func permanentDeleteOnlyAffectsRecentlyDeletedItems() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("x".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Live", pages: samplePages(asset, count: 1), assets: [asset])
        #expect(try await store.deletePermanently([item.id]) == 0)
        #expect(try await store.item(item.id) != nil)
    }
}

@Suite struct PageReplacementTests {
    func imagePage(_ asset: AssetFileStore.StagedAsset, _ size: CGSize = CGSize(width: 500, height: 700)) -> LibraryStore.NewPage {
        .init(sourceSize: size, content: .image(asset.id))
    }

    @Test func replacingKeepsThePageInPlaceAndCanBeReversed() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let old = try store.assets.store(Data("old scan".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Doc",
                                              pages: [imagePage(old), imagePage(old), imagePage(old)], assets: [old])
        let before = try await store.pages(of: item.id)
        let target = before[1]
        try await store.updateTransform(target.id, to: PageTransform(
            crop: NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), rotation: .clockwise90, filter: .grayscale, brightness: 0.2))
        let edited = try #require(try await store.page(target.id))

        let new = try store.assets.store(Data("new scan".utf8), kind: .png, originalFilename: nil)
        let snapshot = LibraryStore.PageContentSnapshot(sourceSize: CGSize(width: 600, height: 800), content: .image(new.id),
                                                        transform: PageTransform(filter: .grayscale, brightness: 0.2))
        let (previous, page) = try await store.replacePageContent(target.id, with: snapshot, assets: [new])

        #expect(page.id == target.id && page.sortKey == target.sortKey)
        #expect(page.content == .image(new.id) && page.sourceSize == CGSize(width: 600, height: 800))
        #expect(page.transform == snapshot.transform)
        #expect(page.revision == edited.revision + 1)
        #expect(previous == LibraryStore.PageContentSnapshot(page: edited))
        #expect(try await store.pages(of: item.id).map(\.id) == before.map(\.id))

        // Reversing restores the previous content exactly.
        let (_, restored) = try await store.replacePageContent(target.id, with: previous, assets: [])
        #expect(LibraryStore.PageContentSnapshot(page: restored) == previous)
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func aReplacedOriginalSurvivesUntilTheNextLaunch() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let old = try store.assets.store(Data("only used by the replaced page".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Doc", pages: [imagePage(old)], assets: [old])
        let other = try store.assets.store(Data("other".utf8), kind: .png, originalFilename: nil)
        let otherItem = try await store.createItem(kind: .document, name: "Other", pages: [imagePage(other)], assets: [other])
        let page = try await store.pages(of: item.id)[0]
        let new = try store.assets.store(Data("new".utf8), kind: .png, originalFilename: nil)
        let (previous, _) = try await store.replacePageContent(
            page.id, with: .init(sourceSize: CGSize(width: 10, height: 10), content: .image(new.id), transform: .identity), assets: [new])

        // Permanently deleting something else must not take the old scan
        // that undo still needs.
        try await store.moveToRecentlyDeleted([otherItem.id])
        try await store.deletePermanently([otherItem.id])
        #expect(FileManager.default.fileExists(atPath: store.assets.url(for: old.id, kind: .jpeg).path))
        _ = try await store.replacePageContent(page.id, with: previous, assets: [])

        // Next launch: the history goes, and the unused scan with it.
        _ = try await store.replacePageContent(
            page.id, with: .init(sourceSize: CGSize(width: 10, height: 10), content: .image(new.id), transform: .identity), assets: [])
        #expect(try await store.purgeReplacedPageContent() >= 1)
        try await store.sweepOrphanAssets(gracePeriod: -60)
        #expect(!FileManager.default.fileExists(atPath: store.assets.url(for: old.id, kind: .jpeg).path))
        #expect(FileManager.default.fileExists(atPath: store.assets.url(for: new.id, kind: .png).path))
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func replacingAMissingPageOrWithAMissingOriginalFails() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("x".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Doc", pages: [imagePage(asset)], assets: [asset])
        let page = try await store.pages(of: item.id)[0]
        let ghost = AssetID(sha256: String(repeating: "a", count: 64))
        await #expect(throws: StoreError.assetMissing(ghost.sha256)) {
            try await store.replacePageContent(page.id, with: .init(sourceSize: CGSize(width: 1, height: 1), content: .image(ghost), transform: .identity), assets: [])
        }
        await #expect(throws: StoreError.pageNotFound) {
            try await store.replacePageContent(PageID.make(), with: .init(sourceSize: CGSize(width: 1, height: 1), content: .image(asset.id), transform: .identity), assets: [])
        }
        #expect(try await store.page(page.id)?.content == .image(asset.id))
    }

    @Test func aRescanWithExtraPagesIsOneChangeThatRevertsAndReappliesWhole() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let old = try store.assets.store(Data("old".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Doc", pages: [imagePage(old), imagePage(old)], assets: [old])
        let before = try await store.pages(of: item.id)
        let new = try store.assets.store(Data("new".utf8), kind: .png, originalFilename: nil)
        let snapshot = LibraryStore.PageContentSnapshot(sourceSize: CGSize(width: 10, height: 10), content: .image(new.id), transform: .identity)

        let change = try await store.replacePage(before[0].id, with: snapshot,
                                                 inserting: [imagePage(new), imagePage(new)], assets: [new])
        #expect(change.previous == LibraryStore.PageContentSnapshot(page: before[0]))
        #expect(change.inserted.count == 2)
        let after = try await store.pages(of: item.id).map(\.id)
        #expect(after == [before[0].id] + change.inserted.map(\.id) + [before[1].id])

        try await store.revertPageReplacement(change)
        #expect(try await store.pages(of: item.id).map(\.id) == before.map(\.id))
        #expect(try await store.page(before[0].id)?.content == .image(old.id))

        try await store.reapplyPageReplacement(change)
        #expect(try await store.pages(of: item.id).map(\.id) == after)
        #expect(try await store.page(before[0].id)?.content == .image(new.id))
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func aRescanWhoseExtraPagesFailChangesNothing() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let old = try store.assets.store(Data("old".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Doc", pages: [imagePage(old)], assets: [old])
        let page = try await store.pages(of: item.id)[0]
        let new = try store.assets.store(Data("new".utf8), kind: .png, originalFilename: nil)
        let ghost = AssetID(sha256: String(repeating: "b", count: 64))

        // The replacement itself is valid; the extra page refers to an
        // original that was never stored, so the insert fails.
        await #expect(throws: StoreError.self) {
            try await store.replacePage(page.id, with: .init(sourceSize: CGSize(width: 10, height: 10), content: .image(new.id), transform: .identity),
                                        inserting: [.init(sourceSize: CGSize(width: 10, height: 10), content: .image(ghost))],
                                        assets: [new])
        }
        #expect(try await store.page(page.id) == page)
        #expect(try await store.pages(of: item.id).map(\.id) == [page.id])
        #expect(try await store.purgeReplacedPageContent() == 0)
        #expect(try await store.integrityCheck().isEmpty)
    }
}

@Suite struct StorageUsageTests {
    @Test func countsLiveDocumentsAndPagesAndTheSpaceTheLibraryUses() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let empty = try await store.storageUsage()
        #expect(empty.documents == 0 && empty.pages == 0)

        let asset = try store.assets.store(Data(repeating: 7, count: 50_000), kind: .pdf, originalFilename: nil)
        let a = try await store.createItem(kind: .document, name: "A", pages: samplePages(asset, count: 3), assets: [asset])
        _ = try await store.createItem(kind: .document, name: "B", pages: samplePages(asset, count: 2), assets: [asset])
        let usage = try await store.storageUsage()
        #expect(usage.documents == 2 && usage.pages == 5)
        #expect(usage.bytes >= 50_000) // the original plus the database

        // Recently Deleted and deleted pages are not counted as documents/pages.
        try await store.moveToRecentlyDeleted([a.id])
        let b = try await store.items(in: .all)[0]
        try await store.deletePages([try await store.pages(of: b.id)[0].id])
        let after = try await store.storageUsage()
        #expect(after.documents == 1 && after.pages == 1)
    }
}

@Suite struct NamingAndSearchTests {
    @Test func duplicateNamesAreNumberedPerFolder() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("x".utf8), kind: .pdf, originalFilename: nil)
        let a = try await store.createItem(kind: .document, name: "Invoice", pages: samplePages(asset, count: 1), assets: [asset])
        let b = try await store.createItem(kind: .document, name: "invoice", pages: samplePages(asset, count: 1), assets: [asset])
        #expect(a.name == "Invoice")
        #expect(b.name == "invoice 2")
        let folder = try await store.createFolder(named: "Taxes")
        let c = try await store.createItem(kind: .document, name: "Invoice", folderID: folder.id, pages: samplePages(asset, count: 1), assets: [asset])
        #expect(c.name == "Invoice")
        #expect(try await store.rename(c.id, to: "Invoice").name == "Invoice")
        try await store.move([c.id], to: nil)
        #expect(try await store.item(c.id)?.name == "Invoice 3")
        #expect(try await store.items(in: .folder(folder.id)).isEmpty)
    }

    @Test func searchMatchesPrefixesIgnoringAccentsAndIsInjectionSafe() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("x".utf8), kind: .pdf, originalFilename: nil)
        let fr = try await store.createItem(kind: .document, name: "Relevé bancaire Société Générale", pages: samplePages(asset, count: 1), assets: [asset])
        let es = try await store.createItem(kind: .document, name: "Contraseña del año", pages: samplePages(asset, count: 1), assets: [asset])
        #expect(try await store.search("releve societe") == [fr.id])
        #expect(try await store.search("ANO contra") == [es.id])
        #expect(try await store.search("banc") == [fr.id])
        #expect(try await store.search("   ").isEmpty)
        // FTS syntax characters are treated as text, not operators.
        #expect(try await store.search("\"unbalanced OR * NEAR(").isEmpty)
        try await store.rename(es.id, to: "Recibo")
        #expect(try await store.search("contrasena").isEmpty)
        #expect(try await store.search("recibo") == [es.id])
    }

    @Test func favoritesScope() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("x".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Fav", pages: samplePages(asset, count: 2), assets: [asset])
        try await store.setFavorite(item.id, true)
        let favorites = try await store.items(in: .favorites)
        #expect(favorites.map(\.id) == [item.id])
        #expect(favorites[0].pageCount == 2)
        #expect(favorites[0].coverPage?.content == .pdfPage(asset.id, index: 0))
    }
}

@Suite struct FolderTests {
    @Test func renamingAFolderKeepsNamesUniqueAmongSiblings() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        _ = try await store.createFolder(named: "Taxes")
        let receipts = try await store.createFolder(named: "Receipts")
        #expect(try await store.renameFolder(receipts.id, to: "taxes").name == "taxes 2")
        #expect(try await store.renameFolder(receipts.id, to: "Receipts 2026").name == "Receipts 2026")
        await #expect(throws: StoreError.folderNotFound) { try await store.renameFolder(FolderID.make(), to: "X") }
    }

    @Test func deletingAFolderKeepsEverythingInItAndMovesItUp() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("x".utf8), kind: .pdf, originalFilename: nil)
        let folder = try await store.createFolder(named: "Taxes")
        let nested = try await store.createFolder(named: "2026", parentID: folder.id)
        _ = try await store.createFolder(named: "2026")
        _ = try await store.createItem(kind: .document, name: "Invoice", pages: samplePages(asset, count: 1), assets: [asset])
        let inside = try await store.createItem(kind: .document, name: "Invoice", folderID: folder.id, pages: samplePages(asset, count: 2), assets: [asset])
        let trashed = try await store.createItem(kind: .document, name: "Old", folderID: folder.id, pages: samplePages(asset, count: 1), assets: [asset])
        try await store.moveToRecentlyDeleted([trashed.id])

        try await store.deleteFolder(folder.id)

        let folders = try await store.folders()
        #expect(!folders.contains { $0.id == folder.id })
        let lifted = try #require(folders.first { $0.id == nested.id })
        #expect(lifted.parentID == nil && lifted.name == "2026 2")
        let moved = try #require(try await store.item(inside.id))
        #expect(moved.folderID == nil && moved.name == "Invoice 2")
        #expect(try await store.pages(of: inside.id).count == 2)
        #expect(try await store.item(trashed.id)?.folderID == nil)
        try await store.restore([trashed.id])
        #expect(try await store.items(in: .folder(nil)).count == 3)
        #expect(try await store.integrityCheck().isEmpty)
    }

    @Test func scopeCountsMatchWhatEachScopeLists() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("x".utf8), kind: .pdf, originalFilename: nil)
        let folder = try await store.createFolder(named: "Receipts")
        let empty = try await store.createFolder(named: "Empty")
        let a = try await store.createItem(kind: .document, name: "A", pages: samplePages(asset, count: 1), assets: [asset])
        let b = try await store.createItem(kind: .document, name: "B", folderID: folder.id, pages: samplePages(asset, count: 1), assets: [asset])
        let c = try await store.createItem(kind: .document, name: "C", folderID: folder.id, pages: samplePages(asset, count: 1), assets: [asset])
        try await store.setFavorite(a.id, true)
        try await store.setFavorite(c.id, true)
        try await store.moveToRecentlyDeleted([c.id])

        let counts = try await store.scopeCounts()
        #expect(counts.all == 2 && counts.favorites == 1 && counts.recentlyDeleted == 1)
        #expect(counts.folders == [folder.id: 1])
        #expect(counts.all == (try await store.items(in: .all)).count)
        #expect(counts.favorites == (try await store.items(in: .favorites)).count)
        #expect(counts.recentlyDeleted == (try await store.items(in: .recentlyDeleted)).count)
        #expect(try await store.items(in: .folder(folder.id)).map(\.id) == [b.id])
        #expect(counts.folders[empty.id, default: 0] == 0)
    }
}
