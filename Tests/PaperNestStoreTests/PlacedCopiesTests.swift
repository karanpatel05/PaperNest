import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Copies laid on a page by the lasso's Duplicate and Paste: written above
/// everything the page holds, in their own order, in one write, and refused
/// whole when any copy could not be drawn or would collide with a mark that
/// already exists.
@Suite struct PlacedCopiesTests {
    private func notebook(_ store: LibraryStore, pages: Int = 1) async throws -> (LibraryItem, [Page], [PageObject]) {
        let item = try await store.createItem(kind: .notebook, name: "Journal", pages: Array(repeating:
            .init(sourceSize: CGSize(width: 600, height: 800), content: .template(.blank)), count: pages), assets: [])
        let first = try #require(try await store.pages(of: item.id).first)
        let existing = PageObject(pageID: first.id, zKey: "m", payload: .ink(InkStroke(
            tool: .pen, color: .black, width: 2, points: [InkPoint(x: 10, y: 10), InkPoint(x: 20, y: 20)])),
            modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.saveObject(existing)
        return (item, try await store.pages(of: item.id), [existing])
    }

    private func stroke(on page: PageID, x: Double, z: String = "a") -> PageObject {
        PageObject(pageID: page, zKey: z, payload: .ink(InkStroke(tool: .pen, color: RGBAColor(red: 0.2, green: 0.3, blue: 0.8),
            width: 3, points: [InkPoint(x: x, y: 100, widthScale: 0.7, time: 0), InkPoint(x: x + 30, y: 140, widthScale: 1.2, time: 0.2)])),
            modifiedAt: Date())
    }

    private func box(on page: PageID, z: String = "b") -> PageObject {
        PageObject(pageID: page, zKey: z, payload: .text(TextBox(frame: CGRect(x: 50, y: 300, width: 120, height: 40),
                                                                 text: "Copied words", fontSize: 16)), modifiedAt: Date())
    }

    @Test func copiesLandOnTopInTheirOwnOrderInOneWrite() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages, existing) = try await notebook(store)
        let page = pages[0]
        let copies = [stroke(on: page.id, x: 100, z: "a"), box(on: page.id, z: "b"), stroke(on: page.id, x: 200, z: "c")]

        let result = try await store.placeCopies(copies, on: page.id, expectedPage: page)
        #expect(result.page.revision == page.revision + 1, "one write, one revision")
        #expect(result.objects.map(\.id) == copies.map(\.id))
        #expect(result.objects.map(\.payload) == copies.map(\.payload))
        let stored = try await store.objects(on: page.id)
        #expect(stored.map(\.id) == existing.map(\.id) + copies.map(\.id), "laid over what was there, in order")
        #expect(stored.dropFirst().map(\.zKey) == result.objects.map(\.zKey))
        #expect(Set(stored.map(\.zKey)).count == stored.count)
        // Kept on disk the moment the call returns.
        let reopened = try LibraryStore(directory: dir.url)
        #expect(try await reopened.objects(on: page.id) == stored)
    }

    @Test func aCopyOfAPictureSharesItsOriginalsBytes() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages, _) = try await notebook(store, pages: 2)
        // The store keeps bytes by their hash; what they draw is not its concern here.
        let staged = try store.assets.store(Data("picture bytes \(UUID().uuidString)".utf8),
                                            kind: .png, originalFilename: "picture.png")
        let placed = try await store.placeImage(staged, on: pages[0].id, frame: CGRect(x: 100, y: 100, width: 80, height: 40))
        guard case .image(let picture) = placed.object.payload else { Issue.record("not an image"); return }
        let copy = PageObject(pageID: pages[1].id, zKey: "a", payload: .image(picture), modifiedAt: Date())

        let result = try await store.placeCopies([copy], on: pages[1].id)
        #expect(result.objects.count == 1)
        #expect(try await store.isAssetReferenced(picture.assetID))
        // Taking the original away leaves the copy's picture in the library.
        _ = try await store.applyInkChanges(on: pages[0].id, saving: [], replacing: [], deleting: [placed.object])
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)
        #expect(try await store.isAssetReferenced(picture.assetID))
        let (data, _) = try await store.assetData(picture.assetID)
        #expect(!data.isEmpty, "the copy's picture was swept away with its original")
    }

    @Test func aPictureWhoseBytesAreGoneIsRefused() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages, _) = try await notebook(store)
        let page = pages[0]
        let missing = PageObject(pageID: page.id, zKey: "a",
            payload: .image(PlacedImage(assetID: AssetID(sha256: String(repeating: "0", count: 64)),
                                        frame: CGRect(x: 0, y: 0, width: 10, height: 10))), modifiedAt: Date())
        await #expect(throws: StoreError.assetMissing(String(repeating: "0", count: 64))) {
            try await store.placeCopies([stroke(on: page.id, x: 100), missing], on: page.id)
        }
        #expect(try await store.objects(on: page.id).count == 1, "nothing written")
        #expect(try await store.page(page.id) == page)
    }

    @Test func anIdThatAlreadyExistsAnywhereIsRefused() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages, existing) = try await notebook(store, pages: 2)
        var clash = stroke(on: pages[1].id, x: 100)
        clash.id = existing[0].id
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.placeCopies([clash], on: pages[1].id)
        }
        #expect(try await store.objects(on: pages[0].id) == existing, "another page's mark cannot be moved by a copy")
        #expect(try await store.objects(on: pages[1].id).isEmpty)
        let twice = stroke(on: pages[1].id, x: 100)
        await #expect(throws: StoreError.invalidOrder) {
            try await store.placeCopies([twice, twice], on: pages[1].id)
        }
    }

    @Test func aChangedPageRefusesCopiesLaidOutForItsOldShape() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages, _) = try await notebook(store)
        var transform = pages[0].transform
        transform.rotation = .clockwise90
        _ = try await store.updateTransform(pages[0].id, to: transform)
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.placeCopies([stroke(on: pages[0].id, x: 100)], on: pages[0].id, expectedPage: pages[0])
        }
        #expect(try await store.objects(on: pages[0].id).count == 1)
    }

    @Test func copiesThatCouldNotBeDrawnAreRefusedWhole() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages, _) = try await notebook(store, pages: 2)
        let page = pages[0]
        let good = stroke(on: page.id, x: 100)
        var bad: [PageObject] = []
        var nonFinite = stroke(on: page.id, x: 100)
        if case .ink(var ink) = nonFinite.payload { ink.points[0].x = .nan; nonFinite.payload = .ink(ink) }
        bad.append(nonFinite)
        var invisible = stroke(on: page.id, x: 100)
        if case .ink(var ink) = invisible.payload { ink.color.alpha = 0; invisible.payload = .ink(ink) }
        bad.append(invisible)
        var empty = stroke(on: page.id, x: 100)
        if case .ink(var ink) = empty.payload { ink.points = []; empty.payload = .ink(ink) }
        bad.append(empty)
        var flat = box(on: page.id)
        if case .text(var text) = flat.payload { text.frame.size.height = 0; flat.payload = .text(text) }
        bad.append(flat)
        var blank = box(on: page.id)
        if case .text(var text) = blank.payload { text.text = "  \n"; blank.payload = .text(text) }
        bad.append(blank)
        bad.append(PageObject(pageID: page.id, zKey: "z", payload: .comment("Private"), modifiedAt: Date()))
        bad.append(stroke(on: pages[1].id, x: 100))
        for copy in bad {
            await #expect(throws: StoreError.self) {
                try await store.placeCopies([good, copy], on: page.id)
            }
        }
        await #expect(throws: StoreError.invalidPlacement) { try await store.placeCopies([], on: page.id) }
        #expect(try await store.objects(on: page.id).count == 1)
        #expect(try await store.page(page.id) == page)
    }

    @Test func aPasteTooLargeToBeAMarkIsRefused() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, pages, _) = try await notebook(store)
        let page = pages[0]
        let points = (0...LibraryStore.maximumCopiedPoints).map { InkPoint(x: Double($0 % 500), y: 100) }
        let huge = PageObject(pageID: page.id, zKey: "a",
                              payload: .ink(InkStroke(tool: .pen, color: .black, width: 1, points: points)),
                              modifiedAt: Date())
        await #expect(throws: StoreError.invalidPlacement) { try await store.placeCopies([huge], on: page.id) }
    }

    @Test func aDeletedDocumentTakesNoCopies() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, pages, _) = try await notebook(store)
        try await store.moveToRecentlyDeleted([item.id])
        await #expect(throws: StoreError.pageNotFound) {
            try await store.placeCopies([stroke(on: pages[0].id, x: 100)], on: pages[0].id)
        }
    }
}
