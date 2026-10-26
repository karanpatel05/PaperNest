import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// F2d: compression has to compare against something real. The "before" is
/// the originals a document's live pages are made of — not the size of some
/// previous export, and not a shared original counted twice.
@Suite struct ItemSizeTests {
    private func asset(_ store: LibraryStore, _ bytes: String, name: String) throws -> AssetFileStore.StagedAsset {
        try store.assets.store(Data(bytes.utf8), kind: .png, originalFilename: name)
    }

    @Test func aDocumentIsAsBigAsTheOriginalItIsMadeOf() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let scan = try asset(store, String(repeating: "scan bytes ", count: 40), name: "scan.png")
        let item = try await store.createItem(kind: .document, name: "Receipt", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(scan.id)),
        ], assets: [scan])

        #expect(try await store.originalByteCount(of: item.id) == scan.byteCount)
        #expect(scan.byteCount > 0)
    }

    @Test func anOriginalSharedByTwoPagesIsCountedOnce() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let shared = try asset(store, String(repeating: "shared ", count: 60), name: "shared.png")
        let item = try await store.createItem(kind: .document, name: "Twice", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(shared.id)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(shared.id)),
        ], assets: [shared])

        // Originals are immutable and shared by hash: the paper exists once.
        #expect(try await store.originalByteCount(of: item.id) == shared.byteCount)
    }

    @Test func twoDifferentOriginalsAddUp() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let first = try asset(store, String(repeating: "one ", count: 50), name: "one.png")
        let second = try asset(store, String(repeating: "two different ", count: 50), name: "two.png")
        let item = try await store.createItem(kind: .document, name: "Pair", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(first.id)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(second.id)),
        ], assets: [first, second])

        #expect(try await store.originalByteCount(of: item.id) == first.byteCount + second.byteCount)
    }

    @Test func paperThatIsNoLongerThereDoesNotCount() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let kept = try asset(store, String(repeating: "kept ", count: 50), name: "kept.png")
        let dropped = try asset(store, String(repeating: "dropped ", count: 50), name: "dropped.png")
        let item = try await store.createItem(kind: .document, name: "Trimmed", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(kept.id)),
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(dropped.id)),
        ], assets: [kept, dropped])
        let pages = try await store.pages(of: item.id)

        try await store.deletePages([pages[1].id])

        #expect(try await store.originalByteCount(of: item.id) == kept.byteCount)
    }

    @Test func aDeletedDocumentHasNothingToCompress() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let scan = try asset(store, String(repeating: "gone ", count: 50), name: "gone.png")
        let item = try await store.createItem(kind: .document, name: "Gone", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(scan.id)),
        ], assets: [scan])

        try await store.moveToRecentlyDeleted([item.id])

        #expect(try await store.originalByteCount(of: item.id) == 0)
    }

    @Test func aNotebookOfBlankPagesHasNoOriginals() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let item = try await store.createItem(kind: .notebook, name: "Notes", pages: [
            .init(sourceSize: CGSize(width: 595, height: 842), content: .template(.blank)),
        ], assets: [])

        // Template pages are drawn, not stored, so there is nothing to shrink.
        #expect(try await store.originalByteCount(of: item.id) == 0)
    }
}

/// A general file item keeps its bytes as themselves, so its size is on its
/// own payload rather than behind a page.
@Suite struct FileItemSizeTests {
    @Test func aFileItemIsAsBigAsTheBytesItKeeps() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let bytes = Data(String(repeating: "photo bytes ", count: 500).utf8)
        let staged = try store.assets.store(bytes, kind: .file, originalFilename: "holiday.jpg")
        let item = try await store.createFileItem(named: "Holiday", asset: staged,
                                                 uti: "public.jpeg", originalFilename: "holiday.jpg")

        #expect(try await store.originalByteCount(of: item.id) == Int64(bytes.count))
    }

    @Test func aDeletedFileItemHasNothingToCompress() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let staged = try store.assets.store(Data(String(repeating: "gone ", count: 100).utf8),
                                            kind: .file, originalFilename: "gone.jpg")
        let item = try await store.createFileItem(named: "Gone", asset: staged,
                                                 uti: "public.jpeg", originalFilename: "gone.jpg")

        try await store.moveToRecentlyDeleted([item.id])

        #expect(try await store.originalByteCount(of: item.id) == 0)
    }
}
