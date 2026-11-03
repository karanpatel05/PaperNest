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

    // MARK: - Changing one that is already on the page

    /// A text box was write-once: its words, size, colour and alignment were
    /// fixed the moment it was added, and a typo meant deleting it and typing
    /// it again. This is the way back in, with the same guards as placing one.
    @Test func changingATextBoxKeepsItsIdentityAndItsPlace() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let (placed, original) = try await store.placeText(
            "Pian in full", on: page.id, frame: frame, fontSize: 24,
            color: .black, alignment: .leading)
        let red = RGBAColor(red: 0.8, green: 0, blue: 0, alpha: 1)

        let (updated, edited) = try await store.updateText(
            original, text: "Paid in full", frame: frame, fontSize: 30,
            color: red, alignment: .center)

        // The same object, changed: undo treats it as one box edited rather
        // than one deleted and another added.
        #expect(edited.id == original.id)
        #expect(edited.zKey == original.zKey)
        #expect(try await store.objects(on: page.id).map(\.id) == [original.id])
        guard case .text(let box) = edited.payload else { Issue.record("not text any more"); return }
        #expect(box.text == "Paid in full")
        #expect(box.fontSize == 30)
        #expect(box.color == red)
        #expect(box.alignment == .center)
        #expect(box.frame == frame)
        #expect(updated.revision > placed.revision)
    }

    /// The words are indexed on the way in; changing them has to replace what
    /// is findable, or search answers with text the page no longer carries.
    @Test func theOldWordsStopBeingFindable() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let (_, original) = try await store.placeText(
            "Aubergine", on: page.id, frame: frame, fontSize: 24, color: .black, alignment: .leading)
        #expect(try await store.search("Aubergine").contains(page.itemID))

        _ = try await store.updateText(original, text: "Courgette", frame: frame,
                                       fontSize: 24, color: .black, alignment: .leading)

        #expect(try await store.search("Courgette").contains(page.itemID))
        #expect(try await store.search("Aubergine").isEmpty, "the old words are still findable")
    }

    /// The box can be given more room as its text or its type grows, which is
    /// what the editor does when the font size changes.
    @Test func theFrameCanGrowWithTheText() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let (_, original) = try await store.placeText(
            "Short", on: page.id, frame: frame, fontSize: 12, color: .black, alignment: .leading)
        let taller = frame.insetBy(dx: 0, dy: -40)

        let (_, edited) = try await store.updateText(original, text: "Short", frame: taller,
                                                     fontSize: 40, color: .black, alignment: .leading)

        guard case .text(let box) = edited.payload else { Issue.record("not text"); return }
        #expect(box.frame == taller)
    }

    /// The same refusals as placing one. An empty box would be a mark nobody
    /// can see and nobody can select.
    @Test func theSameThingsAreRefusedAsWhenPlacingOne() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let (_, original) = try await store.placeText(
            "Keep me", on: page.id, frame: frame, fontSize: 24, color: .black, alignment: .leading)

        for bad in ["", "   \n  "] {
            await #expect(throws: StoreError.invalidPlacement) {
                try await store.updateText(original, text: bad, frame: frame, fontSize: 24,
                                           color: .black, alignment: .leading)
            }
        }
        for size in [0.0, -4.0, Double.nan] {
            await #expect(throws: StoreError.invalidPlacement) {
                try await store.updateText(original, text: "Fine", frame: frame, fontSize: size,
                                           color: .black, alignment: .leading)
            }
        }
        await #expect(throws: StoreError.invalidPlacement) {
            try await store.updateText(original, text: "Fine", frame: .zero, fontSize: 24,
                                       color: .black, alignment: .leading)
        }
        // Nothing was half written by any of those.
        let objects = try await store.objects(on: page.id)
        #expect(objects == [original])
    }

    /// Only a text box can be edited this way; a stroke under the same call
    /// would be silently turned into text.
    @Test func onlyATextBoxCanBeChangedThisWay() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let ink = PageObject(pageID: page.id, zKey: "A",
                             payload: .ink(InkStroke(tool: .pen, color: .black, width: 2,
                                                     points: [InkPoint(x: 10, y: 10)])),
                             modifiedAt: Date())
        _ = try await store.applyObjectChanges(on: page.id, saving: [ink], deleting: [])
        let saved = try #require(try await store.objects(on: page.id).first)

        await #expect(throws: StoreError.invalidPlacement) {
            try await store.updateText(saved, text: "Nope", frame: frame, fontSize: 24,
                                       color: .black, alignment: .leading)
        }
    }

    /// A box someone else changed first must not be written over.
    @Test func aBoxThatChangedUnderneathIsRefused() async throws {
        let dir = TempDirectory()
        let (store, page) = try await seeded(at: dir.url)
        let (_, original) = try await store.placeText(
            "First", on: page.id, frame: frame, fontSize: 24, color: .black, alignment: .leading)
        _ = try await store.updateText(original, text: "Second", frame: frame, fontSize: 24,
                                       color: .black, alignment: .leading)

        await #expect(throws: StoreError.pageObjectsChanged) {
            try await store.updateText(original, text: "Third", frame: frame, fontSize: 24,
                                       color: .black, alignment: .leading)
        }
    }
}
