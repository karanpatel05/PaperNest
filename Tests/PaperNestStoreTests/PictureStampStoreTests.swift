import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Images kept as stamps (schema v15): kept, listed, brought forward and
/// deleted; placed as ordinary placed images; and **their originals kept
/// alive by every check of whether an asset is still used** — the launch
/// sweep, deleting for good, deleting one asset, redaction and sync.
@Suite struct PictureStampStoreTests {
    private let logoSize = CGSize(width: 400, height: 200)

    private func logo(_ store: LibraryStore, _ bytes: String = "logo") throws -> AssetFileStore.StagedAsset {
        try store.assets.store(Data(bytes.utf8), kind: .png, originalFilename: "logo.png")
    }

    private func document(_ store: LibraryStore, content asset: AssetFileStore.StagedAsset? = nil) async throws -> (LibraryItem, Page) {
        let paper = try asset ?? store.assets.store(Data("a PDF".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Invoice", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792),
                  content: paper.kind == .pdf ? .pdfPage(paper.id, index: 0) : .image(paper.id))
        ], assets: [paper])
        return (item, try #require(try await store.pages(of: item.id).first))
    }

    @Test func aPictureStampIsKeptListedNewestFirstBroughtForwardAndDeleted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let first = try await store.savePictureStamp(try logo(store, "logo"), pixelSize: logoSize)
        let second = try await store.savePictureStamp(try logo(store, "seal"), pixelSize: CGSize(width: 300, height: 300))

        #expect(try await store.savedPictureStamps().map(\.id) == [second.id, first.id])
        #expect(try await store.savedPictureStamps().last?.pixelSize == logoSize)
        #expect(try await store.savedPictureStamps().last?.kind == .png)

        // The same image again — the same asset — is the same stamp, at the front.
        let again = try await store.savePictureStamp(try logo(store, "logo"), pixelSize: logoSize)
        #expect(again.id == first.id)
        #expect(try await store.savedPictureStamps().map(\.id) == [first.id, second.id])

        try await store.deleteSavedPictureStamp(first.id)
        #expect(try await store.savedPictureStamps().map(\.id) == [second.id])
    }

    @Test func onlyAnImageWithASizeCanBeKept() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let pdf = try store.assets.store(Data("a PDF".utf8), kind: .pdf, originalFilename: nil)
        await #expect(throws: StoreError.invalidPlacement) { try await store.savePictureStamp(pdf, pixelSize: logoSize) }
        await #expect(throws: StoreError.invalidPlacement) { try await store.savePictureStamp(try logo(store), pixelSize: .zero) }
        #expect(try await store.savedPictureStamps().isEmpty)
    }

    @Test func placingWritesAnOrdinaryPlacedImageOnTop() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await document(store)
        let stamp = try await store.savePictureStamp(try logo(store), pixelSize: logoSize)
        let frame = CGRect(x: 400, y: 40, width: 120, height: 60)

        let (updated, object) = try await store.placePictureStamp(stamp.id, on: page.id, frame: frame)

        #expect(updated.revision > page.revision)
        #expect(try await store.objects(on: page.id).map(\.id) == [object.id])
        #expect(object.payload == .image(PlacedImage(assetID: stamp.assetID, frame: frame)))
        await #expect(throws: StoreError.itemNotFound) {
            try await store.placePictureStamp(SavedPictureStampID.make(), on: page.id, frame: frame)
        }
    }

    /// The launch housekeeping, in the order the app runs it, keeps an image
    /// only a picture stamp uses — its row, its file, and placing it after.
    @Test func launchHousekeepingKeepsAnImageOnlyAPictureStampUses() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await document(store)
        let stamp = try await store.savePictureStamp(try logo(store), pixelSize: logoSize)

        try await store.purgeDeletedPages()
        try await store.purgeReplacedPageContent()
        try await store.purgeExpiredDeletions()
        let swept = try await store.sweepOrphanAssets(gracePeriod: 0)

        #expect(swept == 0, "the sweep took something a picture stamp keeps")
        #expect(try await store.assetRecord(stamp.assetID) != nil)
        #expect(FileManager.default.fileExists(atPath: store.assets.url(for: stamp.assetID, kind: .png).path))
        #expect(try await store.isAssetReferenced(stamp.assetID))
        #expect(try await !store.deleteAssetIfUnreferenced(stamp.assetID), "refused while the stamp keeps it")
        _ = try await store.placePictureStamp(stamp.id, on: page.id, frame: CGRect(x: 1, y: 1, width: 40, height: 20))
    }

    /// Placed on a page that is then deleted for good: the stamp still keeps
    /// its image. Deleted itself: the image goes at the next sweep.
    @Test func theStampKeepsItsImageUntilItIsDeleted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await document(store)
        let stamp = try await store.savePictureStamp(try logo(store), pixelSize: logoSize)
        _ = try await store.placePictureStamp(stamp.id, on: page.id, frame: CGRect(x: 1, y: 1, width: 40, height: 20))

        try await store.moveToRecentlyDeleted([item.id])
        #expect(try await store.deletePermanently([item.id]) == 1)
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)
        #expect(try await store.assetRecord(stamp.assetID) != nil, "deleting the page for good took the stamp's image")

        try await store.deleteSavedPictureStamp(stamp.id)
        #expect(try await store.sweepOrphanAssets(gracePeriod: 0) >= 1)
        #expect(try await store.assetRecord(stamp.assetID) == nil)
        #expect(!FileManager.default.fileExists(atPath: store.assets.url(for: stamp.assetID, kind: .png).path))
    }

    /// A page still showing the image keeps it after the stamp is deleted.
    @Test func aPlacedCopyKeepsTheImageAfterTheStampIsDeleted() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await document(store)
        let stamp = try await store.savePictureStamp(try logo(store), pixelSize: logoSize)
        _ = try await store.placePictureStamp(stamp.id, on: page.id, frame: CGRect(x: 1, y: 1, width: 40, height: 20))

        try await store.deleteSavedPictureStamp(stamp.id)
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)

        #expect(try await store.assetRecord(stamp.assetID) != nil)
    }

    /// Redacting a page whose paper is the image a picture stamp keeps
    /// cannot remove that image.
    @Test func theRedactionCheckCountsAPictureStamp() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let scan = try logo(store, "scan")
        let (_, page) = try await document(store, content: scan)
        #expect(try await !store.isAssetUsedElsewhere(scan.id, besides: page.id))

        _ = try await store.savePictureStamp(scan, pixelSize: logoSize)

        #expect(try await store.isAssetUsedElsewhere(scan.id, besides: page.id))
    }

    /// Picture stamps are not synced: an image one keeps is never offered for
    /// removal from the device.
    @Test func syncNeverEvictsAnImageAPictureStampKeeps() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        try await store.syncSetEnabled(true)
        let scan = try logo(store, "scan")
        let (item, _) = try await document(store, content: scan)
        for upload in try await store.syncAssetsPendingUpload() { try await store.syncAssetDidUpload(upload.record.id) }
        #expect(try await store.syncEvictableAssets(of: item.id).map(\.id) == [scan.id], "precondition: evictable")

        _ = try await store.savePictureStamp(scan, pixelSize: logoSize)

        #expect(try await store.syncEvictableAssets(of: item.id).isEmpty)
    }

    @Test func aLibraryFromSchemaFourteenKeepsItsStampsAndCanKeepPictures() async throws {
        let dir = TempDirectory()
        try FileManager.default.createDirectory(at: dir.url, withIntermediateDirectories: true)
        let raw = try SQLiteDatabase(path: dir.url.appendingPathComponent(LibraryStore.databaseFilename).path)
        for migration in Schema.migrations where migration.version <= 14 { try raw.execute(migration.sql) }
        try raw.setUserVersion(14)
        try raw.execute("""
            INSERT INTO saved_stamps (id, design_json, created_at)
                VALUES ('s1', '{"text":"Paid","style":"outlined","color":{"red":0,"green":0.5,"blue":0,"alpha":1}}', 100);
            """)
        raw.close()

        let store = try LibraryStore(directory: dir.url)

        #expect(try await store.schemaVersion() == Schema.latestVersion)
        #expect(try await store.savedStamps().map(\.design.text) == ["Paid"])
        _ = try await store.savePictureStamp(try logo(store), pixelSize: logoSize)
        #expect(try await store.savedPictureStamps().count == 1)
    }
}
