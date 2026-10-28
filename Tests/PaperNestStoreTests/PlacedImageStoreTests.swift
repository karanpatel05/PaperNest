import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Row 21: what a screen needs before it can place an image at all.
///
/// Drawing one already works. Writing one safely did not. The bytes and the
/// row that points at them have to land together — `AssetFileStore.store`
/// stages the file, but until a row references it `sweepOrphanAssets` is
/// entitled to take it away.
///
/// The bytes here are not real images, deliberately: nothing in this path
/// decodes them, only the asset's declared kind and the frame matter, and the
/// store's business is rows and files. Real images are what
/// `PlacedImageRenderTests` draws.
@Suite struct PlacedImageStoreTests {
    private func seeded(at url: URL) async throws -> (LibraryStore, Page) {
        let store = try LibraryStore(directory: url)
        let asset = try store.assets.store(Data("a PDF".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Statement",
                                              pages: samplePages(asset, count: 1), assets: [asset])
        return (store, try await store.pages(of: item.id)[0])
    }

    private func stamp(_ store: LibraryStore) throws -> AssetFileStore.StagedAsset {
        try store.assets.store(Data("stamp bytes \(UUID().uuidString)".utf8),
                               kind: .png, originalFilename: "stamp.png")
    }

    private let frame = CGRect(x: 100, y: 100, width: 200, height: 200)

    @Test func placingAnImageWritesTheBytesAndTheRowTogether() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let staged = try stamp(store)

        let object = try await store.placeImage(staged, on: page.id, frame: frame)

        let objects = try await store.objects(on: page.id)
        #expect(objects.map(\.id) == [object.id])
        guard case .image(let placed) = try #require(objects.first).payload else {
            Issue.record("the object that was written is not a placed image")
            return
        }
        #expect(placed.assetID == staged.id)
        #expect(placed.frame == frame)
        #expect(try await store.assetRecord(staged.id) != nil, "no asset row was written")
        #expect(try await store.isAssetReferenced(staged.id))
    }

    /// The point of the whole call. A staged file with no row is rubbish as far
    /// as housekeeping is concerned, so if the two are not written together a
    /// sweep between them leaves a page pointing at nothing.
    @Test func aPlacedImageIsNotSweptAway() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let staged = try stamp(store)
        _ = try await store.placeImage(staged, on: page.id, frame: frame)

        _ = try await store.sweepOrphanAssets(gracePeriod: 0)

        let (data, kind) = try await store.assetData(staged.id)
        #expect(kind == .png)
        #expect(!data.isEmpty, "the bytes were swept out from under the page")
    }

    /// A new image goes on top of what is already on the page, as putting
    /// something down does.
    @Test func aPlacedImageLandsOnTopOfWhatIsAlreadyThere() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        try await store.saveObject(PageObject(
            pageID: page.id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 3,
                                    points: [InkPoint(x: 10, y: 10), InkPoint(x: 20, y: 20)])),
            modifiedAt: Date()))

        let object = try await store.placeImage(try stamp(store), on: page.id, frame: frame)

        let objects = try await store.objects(on: page.id)
        #expect(objects.count == 2)
        #expect(objects.last?.id == object.id, "the image did not land on top")
    }

    /// Two in a row both land, and the second is above the first: the key is
    /// worked out from what the page holds at the time, inside the write.
    @Test func twoImagesInARowBothLandInOrder() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)

        let first = try await store.placeImage(try stamp(store), on: page.id, frame: frame)
        let second = try await store.placeImage(
            try store.assets.store(Data("other stamp bytes".utf8),
                                   kind: .png, originalFilename: "other.png"),
            on: page.id, frame: frame.offsetBy(dx: 20, dy: 20))

        let objects = try await store.objects(on: page.id)
        #expect(objects.map(\.id) == [first.id, second.id])
    }

    @Test func placingOnAPageThatIsNotThereIsRefused() async throws {
        let dir = TempDirectory()
        let (store, _) = try await seeded(at: dir.url)
        let staged = try stamp(store)

        await #expect(throws: StoreError.pageNotFound) {
            try await store.placeImage(staged, on: PageID(rawValue: "no-such-page"), frame: frame)
        }
        // A refusal writes nothing at all, so the bytes stay unreferenced
        // rubbish for the sweeper rather than a half-written placement.
        #expect(try await store.assetRecord(staged.id) == nil)
    }

    /// A PDF is not something this can draw, and the renderer would only find
    /// that out at drawing time — by then the object is saved and the page is
    /// broken. Refused at the write instead.
    @Test func placingSomethingThatIsNotAnImageIsRefused() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let notAnImage = try store.assets.store(Data("not a picture".utf8),
                                                kind: .pdf, originalFilename: "doc.pdf")

        await #expect(throws: StoreError.invalidPlacement) {
            try await store.placeImage(notAnImage, on: page.id, frame: frame)
        }
        #expect(try await store.objects(on: page.id).isEmpty)
    }

    @Test func aFrameWithNoAreaIsRefused() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let staged = try stamp(store)

        await #expect(throws: StoreError.invalidPlacement) {
            try await store.placeImage(staged, on: page.id,
                                       frame: CGRect(x: 10, y: 10, width: 0, height: 200))
        }
        #expect(try await store.objects(on: page.id).isEmpty)
    }

    /// Removing the image lets its bytes go, which is the other half of
    /// writing them: `isAssetReferenced` already counted placed images, and
    /// this is that counting seen from the outside.
    @Test func deletingAPlacedImageLetsItsBytesGo() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let staged = try stamp(store)
        let object = try await store.placeImage(staged, on: page.id, frame: frame)

        try await store.deleteObject(object.id)
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)

        #expect(try await store.assetRecord(staged.id) == nil, "the bytes outlived the placement")
    }
}
