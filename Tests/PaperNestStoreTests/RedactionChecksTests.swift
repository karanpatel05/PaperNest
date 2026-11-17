import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Before a redaction: does anything but this page still use its original?
/// A duplicated document is the usual case, and redacting one copy cannot
/// remove what the other shows.
@Suite struct RedactionChecksTests {
    private func page(_ store: LibraryStore, bytes: String) async throws -> (LibraryItem, Page) {
        let asset = try store.assets.store(Data(bytes.utf8), kind: .png, originalFilename: "scan.png")
        let item = try await store.createItem(kind: .document, name: "Scan", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(asset.id)),
        ], assets: [asset])
        return (item, try await store.pages(of: item.id)[0])
    }

    @Test func anOriginalOnlyThisPageUsesIsNotUsedElsewhere() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, only) = try await page(store, bytes: "only")
        let asset = try #require(only.content.assetID)

        #expect(try await !store.isAssetUsedElsewhere(asset, besides: only.id))
    }

    @Test func aSecondPageShowingTheSameOriginalIsFound() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, first) = try await page(store, bytes: "same paper")
        let (_, second) = try await page(store, bytes: "same paper")
        let asset = try #require(first.content.assetID)
        #expect(second.content.assetID == asset, "content addressing shares the file")

        #expect(try await store.isAssetUsedElsewhere(asset, besides: first.id))
        #expect(try await store.isAssetUsedElsewhere(asset, besides: second.id))
    }

    /// In the trash, the other page still holds its original until it is
    /// purged, and can be put back with it.
    @Test func aPageInTheTrashStillCounts() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, first) = try await page(store, bytes: "same paper")
        let (other, _) = try await page(store, bytes: "same paper")
        try await store.moveToRecentlyDeleted([other.id])

        #expect(try await store.isAssetUsedElsewhere(try #require(first.content.assetID), besides: first.id))
    }
}
