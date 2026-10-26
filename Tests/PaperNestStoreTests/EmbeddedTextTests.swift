import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// F4: text that a digital PDF already carries has to be findable, must stop
/// being findable when the page stops showing that content, and must never
/// look like an edit to the document.
@Suite struct EmbeddedTextTests {
    private func seedPDFPage(_ store: LibraryStore, name: String = "Statement") async throws -> (LibraryItem, Page, AssetID) {
        let asset = try store.assets.store(Data("%PDF-1.7 synthetic".utf8), kind: .pdf, originalFilename: "statement.pdf")
        let item = try await store.createItem(kind: .document, name: name, pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        return (item, try await store.pages(of: item.id)[0], asset.id)
    }

    @Test func wordsInsideADigitalPDFAreFoundEvenWhenTheTitleDoesNotMatch() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, _) = try await seedPDFPage(store)
        #expect(try await store.search("rent").isEmpty)

        try await store.indexEmbeddedText("Monthly rent 1200 EUR", for: page.id, expecting: page.content)

        #expect(try await store.search("rent") == [item.id])
        #expect(try await store.search("1200") == [item.id])
        #expect(try await store.search("mortgage").isEmpty)
    }

    @Test func aPageWithNoTextLayerIsRecordedAsCheckedAndContributesNothingToSearch() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, _) = try await seedPDFPage(store, name: "Receipt")
        try await store.indexEmbeddedText("Earlier words", for: page.id, expecting: page.content)
        #expect(try await store.search("earlier") == [item.id])

        // Looked at, found nothing: the marker replaces the old words, and is
        // itself unfindable.
        try await store.indexEmbeddedText(nil, for: page.id, expecting: page.content)

        #expect(try await store.pagesMissingEmbeddedText().isEmpty, "a page already checked must not be read again")
        #expect(try await store.search("earlier").isEmpty)
        #expect(try await store.search("receipt") == [item.id], "the title is indexed separately and still matches")
    }

    @Test func textIsNotIndexedWhenThePageNoLongerShowsTheContentItCameFrom() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page, _) = try await seedPDFPage(store)
        let other = try store.assets.store(Data("%PDF-1.7 different".utf8), kind: .pdf, originalFilename: "other.pdf")

        // The page was rescanned while the text was being read off the old PDF.
        let wrote = try await store.indexEmbeddedText("Words from the old paper", for: page.id,
                                                     expecting: .pdfPage(other.id, index: 0))

        #expect(wrote == false)
        #expect(try await store.search("old").isEmpty, "words from content the page no longer shows must not be findable")
    }

    @Test func reindexingReplacesTheOldWordsInsteadOfAddingToThem() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, _) = try await seedPDFPage(store)
        try await store.indexEmbeddedText("Draft agreement", for: page.id, expecting: page.content)
        #expect(try await store.search("draft") == [item.id])

        try await store.indexEmbeddedText("Final agreement", for: page.id, expecting: page.content)

        #expect(try await store.search("final") == [item.id])
        #expect(try await store.search("draft").isEmpty)
        #expect(try await store.search("agreement") == [item.id], "one hit per item, not one per indexing pass")
    }

    @Test func indexingDoesNotCountAsAnEditToTheDocument() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, _) = try await seedPDFPage(store)

        try await store.indexEmbeddedText("Some words", for: page.id, expecting: page.content)

        // A backfill over an existing library must not reorder it by date or
        // make every page's thumbnail and OCR look out of date.
        #expect(try await store.item(item.id)?.modifiedAt == item.modifiedAt)
        #expect(try await store.pages(of: item.id)[0].revision == page.revision)
    }

    @Test func indexingAPageThatIsGoneIsRejected() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, _, assetID) = try await seedPDFPage(store)

        await #expect(throws: StoreError.pageNotFound) {
            try await store.indexEmbeddedText("Nowhere", for: PageID.make(), expecting: .pdfPage(assetID, index: 0))
        }
        #expect(try await store.search("nowhere").isEmpty)
    }

    @Test func rescanningAPageStopsItsOldWordsFromBeingFoundAndQueuesItAgain() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, _) = try await seedPDFPage(store)
        try await store.indexEmbeddedText("Original lease terms", for: page.id, expecting: page.content)
        #expect(try await store.search("lease") == [item.id])

        let fresh = try store.assets.store(Data("%PDF-1.7 rescanned".utf8), kind: .pdf, originalFilename: "rescan.pdf")
        _ = try await store.replacePageContent(page.id, with: .init(sourceSize: page.sourceSize,
                                                                    content: .pdfPage(fresh.id, index: 0),
                                                                    transform: page.transform),
                                               assets: [fresh])

        #expect(try await store.search("lease").isEmpty, "the page shows different paper now")
        #expect(try await store.pagesMissingEmbeddedText().map(\.id) == [page.id], "the new content has not been read yet")
    }

    /// Guard on behavior this slice relies on: the words come from the
    /// immutable original, so an edit that only changes how the page is shown
    /// must leave them findable, even though it bumps the revision.
    @Test func editingHowThePageLooksKeepsItsWordsFindable() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, _) = try await seedPDFPage(store)
        try await store.indexEmbeddedText("Utility bill total", for: page.id, expecting: page.content)

        var brighter = page.transform
        brighter.brightness = 0.2
        let edited = try await store.updateTransform(page.id, to: brighter)

        #expect(edited.revision > page.revision)
        #expect(try await store.search("utility") == [item.id])
        #expect(try await store.pagesMissingEmbeddedText().isEmpty, "nothing needs re-reading")
    }

    @Test func duplicatingADocumentCarriesItsFindableWords() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, _) = try await seedPDFPage(store)
        try await store.indexEmbeddedText("Insurance policy number", for: page.id, expecting: page.content)

        let copies = try await store.duplicateItems([item.id])

        let copy = try #require(copies.first)
        #expect(try await Set(store.search("insurance")) == Set([item.id, copy.id]),
                "a copy of a digital PDF must be findable by the same words")
        #expect(try await store.pagesMissingEmbeddedText().isEmpty, "the copy's text was carried, not re-read")
    }

    @Test func deletingTheDocumentTakesItsIndexedWordsWithIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page, _) = try await seedPDFPage(store)
        try await store.indexEmbeddedText("Mortgage statement", for: page.id, expecting: page.content)

        try await store.moveToRecentlyDeleted([item.id])
        #expect(try await store.search("mortgage").isEmpty)
        #expect(try await store.pagesMissingEmbeddedText().isEmpty, "a deleted document is not worth reading")

        try await store.deletePermanently([item.id])
        #expect(try await store.search("mortgage").isEmpty)
        #expect(try await store.integrityCheck().isEmpty)
    }
}
