import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Text boxes paint and export; this is them becoming findable.
///
/// The search words are deliberately odd — ZEBRAFISH, WALRUS, PANGOLIN — so a
/// hit cannot be the item's own title or anything else already in the index.
@Suite struct TypedTextIndexTests {
    private func seeded(at url: URL) async throws -> (LibraryStore, LibraryItem, Page) {
        let store = try LibraryStore(directory: url)
        let asset = try store.assets.store(Data("a PDF".utf8), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Statement",
                                              pages: samplePages(asset, count: 1), assets: [asset])
        return (store, item, try await store.pages(of: item.id)[0])
    }

    private func typed(_ text: String, on page: Page, id: PageObjectID = .make()) -> PageObject {
        PageObject(id: id, pageID: page.id, zKey: "m",
                   payload: .text(TextBox(frame: CGRect(x: 10, y: 10, width: 200, height: 100),
                                          text: text)),
                   modifiedAt: Date())
    }

    @Test func typedWordsAreFindable() async throws {
        let dir = TempDirectory()
        let (store, item, page) = try await seeded(at: dir.url)

        try await store.saveObject(typed("ZEBRAFISH INVOICE", on: page))

        #expect(try await store.search("zebrafish") == [item.id])
        // A word nobody typed is still not found.
        #expect(try await store.search("walrus").isEmpty)
    }

    @Test func changingTheTextChangesWhatIsFound() async throws {
        let dir = TempDirectory()
        let (store, item, page) = try await seeded(at: dir.url)
        let object = typed("ZEBRAFISH", on: page)
        try await store.saveObject(object)

        try await store.saveObject(typed("WALRUS", on: page, id: object.id))

        #expect(try await store.search("walrus") == [item.id])
        #expect(try await store.search("zebrafish").isEmpty, "the old words are still findable")
    }

    @Test func deletingTheBoxTakesItsWordsOutOfSearch() async throws {
        let dir = TempDirectory()
        let (store, _, page) = try await seeded(at: dir.url)
        let object = typed("ZEBRAFISH", on: page)
        try await store.saveObject(object)

        try await store.deleteObject(object.id)

        #expect(try await store.search("zebrafish").isEmpty)
    }

    @Test func clearingTheTextTakesItOutToo() async throws {
        let dir = TempDirectory()
        let (store, item, page) = try await seeded(at: dir.url)
        let object = typed("ZEBRAFISH", on: page)
        try await store.saveObject(object)
        #expect(try await store.search("zebrafish") == [item.id])

        try await store.saveObject(typed("   ", on: page, id: object.id))

        #expect(try await store.search("zebrafish").isEmpty)
    }

    @Test func everyBoxOnThePageIsFindable() async throws {
        let dir = TempDirectory()
        let (store, item, page) = try await seeded(at: dir.url)

        try await store.saveObject(typed("ZEBRAFISH", on: page))
        try await store.saveObject(typed("WALRUS", on: page))

        #expect(try await store.search("zebrafish") == [item.id])
        #expect(try await store.search("walrus") == [item.id])
    }

    /// **A page comment is private, and that has to stay true.** It is typed on
    /// the same page, by the same person, into the same objects table; the only
    /// thing keeping it out of search is that it is deliberately left out.
    ///
    /// The ink stroke is the point of this test. Writing a comment does not
    /// bump the page's revision — on purpose, so an undone comment does not
    /// invalidate page history — so no reindex runs and the comment is safe by
    /// accident. **Checked:** without the stroke, this test passes even when
    /// the reindex is changed to gather comments, which makes it worthless. The
    /// stroke forces a reindex while the comment is sitting there, so the
    /// question actually asked is "does the reindex pick up comments", and
    /// making it do so fails this.
    @Test func aPrivateCommentIsNeverFindable() async throws {
        let dir = TempDirectory()
        let (store, _, page) = try await seeded(at: dir.url)
        _ = try await store.setPageComment(on: page.id, replacing: nil, text: "PANGOLIN remember this")

        // Any other object write bumps the revision, which rebuilds the index
        // with the comment already on the page.
        try await store.saveObject(PageObject(
            pageID: page.id, zKey: "n",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 3,
                                    points: [InkPoint(x: 10, y: 10), InkPoint(x: 20, y: 20)])),
            modifiedAt: Date()))

        #expect(try await store.search("pangolin").isEmpty, "a private comment became searchable")
    }

    /// Ink is not words, so a page full of strokes adds nothing — and the
    /// reindex running on every object write must not break that.
    @Test func inkAddsNothingToSearch() async throws {
        let dir = TempDirectory()
        let (store, _, page) = try await seeded(at: dir.url)

        try await store.saveObject(PageObject(
            pageID: page.id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 3,
                                    points: [InkPoint(x: 10, y: 10), InkPoint(x: 20, y: 20)])),
            modifiedAt: Date()))

        #expect(try await store.search("zebrafish").isEmpty)
    }
}
