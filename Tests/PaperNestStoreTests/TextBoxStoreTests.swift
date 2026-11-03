import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Row 21's text boxes, on the way in. Drawing and exporting them works; this
/// is a screen being able to put one on a page at all, with the same guards
/// `placeImage` has.
@Suite struct TextBoxStoreTests {
    private func seeded(at url: URL) async throws -> (LibraryStore, Page) {
        let store = try LibraryStore(directory: url)
        let asset = try store.assets.store(Data("a PDF".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Statement",
                                              pages: samplePages(asset, count: 1), assets: [asset])
        return (store, try await store.pages(of: item.id)[0])
    }

    private let frame = CGRect(x: 72, y: 72, width: 300, height: 120)

    @Test func writingATextBoxPutsItOnThePage() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)

        let (updated, object) = try await store.placeText(
            "Paid in full", on: page.id, frame: frame, fontSize: 24,
            color: .black, alignment: .leading)

        let objects = try await store.objects(on: page.id)
        #expect(objects.map(\.id) == [object.id])
        guard case .text(let box) = try #require(objects.first).payload else {
            Issue.record("what was written is not a text box")
            return
        }
        #expect(box.text == "Paid in full")
        #expect(box.frame == frame)
        #expect(box.fontSize == 24)
        // The page that comes back is usable for the next guarded edit, as
        // `placeImage` learned the hard way.
        #expect(updated.revision > page.revision)
    }

    /// Typed words are findable the moment they are written — the index is
    /// rebuilt by the same write.
    @Test func theWordsAreFindableImmediately() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let item = try #require(try await store.page(page.id)).itemID

        _ = try await store.placeText("ZEBRAFISH clause", on: page.id, frame: frame,
                                      fontSize: 18, color: .black, alignment: .leading)

        #expect(try await store.search("zebrafish") == [item])
    }

    @Test func anEmptyTextBoxIsRefused() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)

        await #expect(throws: StoreError.invalidPlacement) {
            try await store.placeText("   ", on: page.id, frame: frame, fontSize: 18,
                                      color: .black, alignment: .leading)
        }
        #expect(try await store.objects(on: page.id).isEmpty)
    }

    @Test func aFrameWithNoAreaIsRefused() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)

        await #expect(throws: StoreError.invalidPlacement) {
            try await store.placeText("Paid", on: page.id,
                                      frame: CGRect(x: 10, y: 10, width: 0, height: 80),
                                      fontSize: 18, color: .black, alignment: .leading)
        }
        #expect(try await store.objects(on: page.id).isEmpty)
    }

    /// A size that cannot be drawn is refused rather than stored: the renderer
    /// would skip the box and the page would simply be missing it.
    @Test func aFontSizeThatCannotBeDrawnIsRefused() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)

        await #expect(throws: StoreError.invalidPlacement) {
            try await store.placeText("Paid", on: page.id, frame: frame, fontSize: 0,
                                      color: .black, alignment: .leading)
        }
    }

    @Test func writingOnAPageThatIsNotThereIsRefused() async throws {
        let dir = TempDirectory()
        let (store, _) = try await seeded(at: dir.url)

        await #expect(throws: StoreError.pageNotFound) {
            try await store.placeText("Paid", on: PageID(rawValue: "no-such-page"),
                                      frame: frame, fontSize: 18, color: .black,
                                      alignment: .leading)
        }
    }

    @Test func aNewTextBoxLandsOnTopOfWhatIsThere() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        try await store.saveObject(PageObject(
            pageID: page.id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 3,
                                    points: [InkPoint(x: 1, y: 1), InkPoint(x: 9, y: 9)])),
            modifiedAt: Date()))

        let (_, object) = try await store.placeText("On top", on: page.id, frame: frame,
                                                    fontSize: 18, color: .black,
                                                    alignment: .leading)

        #expect(try await store.objects(on: page.id).last?.id == object.id)
    }

    /// **Undo has to actually remove it.** The editor registers undo for a
    /// text box through the same machinery ink uses, and that machinery ends
    /// at `applyInkChanges` — so if it refuses anything that is not ink, the
    /// Undo button lights up and then does nothing but show an error. This is
    /// exactly the inverse change the undo path applies.
    @Test func undoingATextBoxRemovesIt() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let (_, object) = try await store.placeText("Paid in full", on: page.id, frame: frame,
                                                    fontSize: 18, color: .black, alignment: .leading)

        _ = try await store.applyInkChanges(on: page.id, saving: [], replacing: [], deleting: [object])

        #expect(try await store.objects(on: page.id).isEmpty, "undo left the text box on the page")
    }
}
