import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// F2a, store layer: a library item that is a file rather than a sequence of
/// pages, living beside documents in the same library.
@Suite struct FileItemTests {
    private func store(_ dir: borrowing TempDirectory) throws -> LibraryStore {
        try LibraryStore(directory: dir.url)
    }

    @Test func aFileItemKeepsItsBytesNameAndTypeAcrossAReopen() async throws {
        let dir = TempDirectory()
        let store = try store(dir)
        let bytes = Data("report body".utf8)
        let asset = try store.assets.store(bytes, kind: .file, originalFilename: "Report.docx")
        let folder = try await store.createFolder(named: "Work")
        let item = try await store.createFileItem(named: "Report", folderID: folder.id, asset: asset,
                                                  uti: "org.openxmlformats.wordprocessingml.document",
                                                  originalFilename: "Report.docx")
        #expect(item.kind == .file)
        #expect(item.folderID == folder.id)

        let reopened = try LibraryStore(directory: dir.url)
        let payload = try #require(try await reopened.filePayload(item.id))
        #expect(payload.originalFilename == "Report.docx")
        #expect(payload.uti == "org.openxmlformats.wordprocessingml.document")
        #expect(payload.byteCount == Int64(bytes.count))
        #expect(try await reopened.assetData(payload.assetID).0 == bytes)
        #expect(try await reopened.pages(of: item.id).isEmpty)

        let summary = try #require(try await reopened.items(in: .all).first { $0.id == item.id })
        #expect(summary.pageCount == 0)
        #expect(summary.file?.originalFilename == "Report.docx")
        // A page-based item still reports no payload.
        let doc = try await reopened.createItem(kind: .document, name: "Doc", pages: [], assets: [])
        #expect(try await reopened.filePayload(doc.id) == nil)
    }

    @Test func filesShareFoldersFavoritesLabelsSearchAndTrashWithDocuments() async throws {
        let dir = TempDirectory()
        let store = try store(dir)
        let asset = try store.assets.store(Data("x".utf8), kind: .file, originalFilename: "Budget.xlsx")
        let item = try await store.createFileItem(named: "Budget", asset: asset, uti: "com.microsoft.excel.xlsx",
                                                  originalFilename: "Budget.xlsx")
        try await store.setFavorite(item.id, true)
        try await store.setColorLabel(.green, for: [item.id])
        #expect(try await store.items(in: .favorites).map(\.id) == [item.id])
        #expect(try await store.search("Budget") == [item.id])

        _ = try await store.rename(item.id, to: "Budget 2026")
        #expect(try await store.search("2026") == [item.id])

        try await store.moveToRecentlyDeleted([item.id])
        #expect(try await store.items(in: .all).isEmpty)
        #expect(try await store.items(in: .recentlyDeleted).map(\.id) == [item.id])
        try await store.restore([item.id])
        let recovered = try #require(try await store.item(item.id))
        #expect(recovered.colorLabel == .green && recovered.isFavorite)
    }

    /// The hazard the F2 design called out: a document page and a file can
    /// hold the same bytes, and the sweep must not take them from either.
    @Test func sweepingKeepsBytesThatAFileItemStillReferences() async throws {
        let dir = TempDirectory()
        let store = try store(dir)
        let shared = Data("%PDF-1.4 shared bytes".utf8)
        let asset = try store.assets.store(shared, kind: .pdf, originalFilename: "shared.pdf")
        let document = try await store.createItem(kind: .document, name: "Doc", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        // Content addressing means the file item lands on the same asset row.
        let same = try store.assets.store(shared, kind: .pdf, originalFilename: "copy.pdf")
        #expect(same.id == asset.id)
        let file = try await store.createFileItem(named: "Shared copy", asset: same, uti: "com.adobe.pdf",
                                                  originalFilename: "copy.pdf")

        // Deleting the document for good must not take the file's bytes.
        try await store.moveToRecentlyDeleted([document.id])
        try await store.deletePermanently([document.id])
        try await store.purgeDeletedPages()
        #expect(try await store.sweepOrphanAssets(gracePeriod: 0) == 0, "the file item still references these bytes")
        #expect(try await store.assetData(asset.id).0 == shared)
        #expect(try await store.filePayload(file.id)?.assetID == asset.id)

        // Once the file goes too, the bytes are collectable.
        try await store.moveToRecentlyDeleted([file.id])
        try await store.deletePermanently([file.id])
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)
        // Whoever collects them — the delete itself or the sweep after it —
        // the bytes are gone once nothing references them.
        #expect(try await store.assetRecord(asset.id) == nil)
    }

    @Test func duplicatingAFileSharesTheBytesAndSurvivesTheOriginal() async throws {
        let dir = TempDirectory()
        let store = try store(dir)
        let bytes = Data("slides".utf8)
        let asset = try store.assets.store(bytes, kind: .file, originalFilename: "Deck.key")
        let item = try await store.createFileItem(named: "Deck", asset: asset, uti: "com.apple.keynote.key",
                                                  originalFilename: "Deck.key")
        try await store.setColorLabel(.red, for: [item.id])

        let copy = try await store.duplicateItems([item.id])[0]
        #expect(copy.name == "Deck 2")
        #expect(copy.kind == .file)
        #expect(copy.colorLabel == .red)
        let copied = try #require(try await store.filePayload(copy.id))
        #expect(copied.assetID == asset.id, "the copy shares the immutable bytes")
        #expect(copied.originalFilename == "Deck.key")

        try await store.moveToRecentlyDeleted([item.id])
        try await store.deletePermanently([item.id])
        #expect(try await store.sweepOrphanAssets(gracePeriod: 0) == 0)
        #expect(try await store.assetData(copied.assetID).0 == bytes)
    }

    @Test func pageOperationsRefuseFileItems() async throws {
        let dir = TempDirectory()
        let store = try store(dir)
        let asset = try store.assets.store(Data("zip".utf8), kind: .file, originalFilename: "Archive.zip")
        let file = try await store.createFileItem(named: "Archive", asset: asset, uti: "public.zip-archive",
                                                  originalFilename: "Archive.zip")
        let pdf = try store.assets.store(Data("%PDF".utf8), kind: .pdf, originalFilename: nil)
        let document = try await store.createItem(kind: .document, name: "Doc", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(pdf.id, index: 0)),
        ], assets: [pdf])
        let before = try await store.items(in: .all)

        await #expect(throws: StoreError.invalidOrder) {
            try await store.mergeItems([document.id, file.id], named: "Mixed", folderID: nil)
        }
        await #expect(throws: StoreError.invalidOrder) {
            try await store.splitItem(file.id) { index, _ in "Part \(index)" }
        }
        await #expect(throws: StoreError.invalidOrder) {
            try await store.extractPages([PageID.make()], from: file.id, named: "Pages")
        }
        #expect(try await store.items(in: .all) == before)
    }

    @Test func storageUsageCountsFilesAndTheirBytes() async throws {
        let dir = TempDirectory()
        let store = try store(dir)
        let before = try await store.storageUsage()
        let asset = try store.assets.store(Data(repeating: 7, count: 40_000), kind: .file, originalFilename: "Clip.mov")
        _ = try await store.createFileItem(named: "Clip", asset: asset, uti: "public.movie", originalFilename: "Clip.mov")
        let after = try await store.storageUsage()
        #expect(after.documents == before.documents + 1)
        #expect(after.pages == before.pages, "a file contributes no pages")
        #expect(after.bytes > before.bytes + 30_000)
    }
}
