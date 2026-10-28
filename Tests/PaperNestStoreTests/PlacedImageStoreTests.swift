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

        let (_, object) = try await store.placeImage(staged, on: page.id, frame: frame)

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

        let (_, object) = try await store.placeImage(try stamp(store), on: page.id, frame: frame)

        let objects = try await store.objects(on: page.id)
        #expect(objects.count == 2)
        #expect(objects.last?.id == object.id, "the image did not land on top")
    }

    /// Two in a row both land, and the second is above the first: the key is
    /// worked out from what the page holds at the time, inside the write.
    @Test func twoImagesInARowBothLandInOrder() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)

        let (_, first) = try await store.placeImage(try stamp(store), on: page.id, frame: frame)
        let (_, second) = try await store.placeImage(
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
        let (_, object) = try await store.placeImage(staged, on: page.id, frame: frame)

        try await store.deleteObject(object.id)
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)

        #expect(try await store.assetRecord(staged.id) == nil, "the bytes outlived the placement")
    }

    /// The common real case, and the one the unique bytes above were hiding:
    /// the same logo or signature put on more than one page. Content
    /// addressing gives both the same `AssetID`, so the row is written twice.
    @Test func theSameImageOnTwoPagesSharesOneCopyOfIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let document = try store.assets.store(Data("a PDF".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Statement",
                                              pages: samplePages(document, count: 2), assets: [document])
        let pages = try await store.pages(of: item.id)
        // Identical bytes staged twice: the same asset by content address.
        let logo = Data("one logo".utf8)
        let first = try store.assets.store(logo, kind: .png, originalFilename: "logo.png")
        let second = try store.assets.store(logo, kind: .png, originalFilename: "logo.png")
        #expect(first.id == second.id, "content addressing should give one id")

        let (_, one) = try await store.placeImage(first, on: pages[0].id, frame: frame)
        let (_, two) = try await store.placeImage(second, on: pages[1].id, frame: frame)

        #expect(try await store.objects(on: pages[0].id).map(\.id) == [one.id])
        #expect(try await store.objects(on: pages[1].id).map(\.id) == [two.id])
        // One placement removed, the bytes stay: the other page still needs them.
        try await store.deleteObject(one.id)
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)
        #expect(try await store.assetRecord(first.id) != nil, "the second page lost its image")
        // Both gone, and only then do the bytes go.
        try await store.deleteObject(two.id)
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)
        #expect(try await store.assetRecord(first.id) == nil)
    }

    /// Placing a picture that is already a page's own content — someone places
    /// a photo the library already holds. One row, two kinds of reference.
    @Test func placingAnImageThatIsAlreadyAPagesContentSharesIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let photo = try store.assets.store(Data("a photo".utf8), kind: .png, originalFilename: "photo.png")
        let item = try await store.createItem(
            kind: .document, name: "Photo",
            pages: [LibraryStore.NewPage(sourceSize: CGSize(width: 400, height: 300),
                                         content: .image(photo.id))],
            assets: [photo])
        let page = try await store.pages(of: item.id)[0]

        let (_, object) = try await store.placeImage(photo, on: page.id, frame: frame)

        // Removing the placement must not take the page's own content with it.
        try await store.deleteObject(object.id)
        _ = try await store.sweepOrphanAssets(gracePeriod: 0)
        #expect(try await store.assetRecord(photo.id) != nil, "the page's own content was swept")
    }

    /// Writing an object bumps the page's revision, so the `Page` a caller
    /// started with is stale and the next guarded edit refuses it. The page
    /// that comes back has to be usable instead, or placing an image would
    /// break the very next thing someone did.
    @Test func thePageThatComesBackIsGoodForTheNextEdit() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)

        let (updated, _) = try await store.placeImage(try stamp(store), on: page.id, frame: frame)

        // The page from before the placement is refused, which is why the call
        // returns a fresh one.
        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.addShape(to: page, kind: .rectangle,
                                     start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.4),
                                     color: .black, width: 2)
        }
        _ = try await store.addShape(to: updated, kind: .rectangle,
                                     start: CGPoint(x: 0.1, y: 0.1), end: CGPoint(x: 0.4, y: 0.4),
                                     color: .black, width: 2)
        #expect(try await store.objects(on: page.id).count == 2)
    }

    /// Placing something on a page does not change the paper, so words already
    /// read off it must stay current — otherwise putting a signature on a scan
    /// would drop its searchable text. `bumpRevision` carries a current
    /// completed result forward with the page; this is that, from outside.
    @Test func placingAnImageDoesNotStaleWhatWasReadOffThePage() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        try await store.saveRecognition(PageRecognition(
            pageID: page.id, sourceRevision: page.revision, engineVersion: "test",
            status: .completed, languages: ["en"],
            lines: [RecognizedLine(text: "ACCOUNT 1234",
                                   box: NormalizedRect.exact(x: 0.1, y: 0.1, width: 0.5, height: 0.05),
                                   confidence: 0.9)]))

        let (updated, _) = try await store.placeImage(try stamp(store), on: page.id, frame: frame)

        let recognition = try #require(try await store.recognition(for: page.id))
        #expect(recognition.status == .completed)
        #expect(recognition.sourceRevision == updated.revision,
                "the page's words went stale because something was placed on it")
    }
}
