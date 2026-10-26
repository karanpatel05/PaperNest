import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Getting the indexed text of a digital PDF back out, so it can be exported
/// as text rather than only answering searches.
@Suite struct EmbeddedTextReadbackTests {
    private func seedPDFPage(_ store: LibraryStore) async throws -> (LibraryItem, Page) {
        let asset = try store.assets.store(Data("%PDF-1.7 synthetic".utf8), kind: .pdf, originalFilename: "doc.pdf")
        let item = try await store.createItem(kind: .document, name: "Statement", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        return (item, try await store.pages(of: item.id)[0])
    }

    @Test func theTextADigitalPDFCarriesReadsBack() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedPDFPage(store)

        try await store.indexEmbeddedText("Monthly rent 1200 EUR", for: page.id, expecting: page.content)

        #expect(try await store.embeddedText(for: page.id) == "Monthly rent 1200 EUR")
    }

    @Test func aPageLookedAtWithNoTextLayerReadsBackAsNothing() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedPDFPage(store)

        // An empty marker records "looked, found none" — not text.
        try await store.indexEmbeddedText(nil, for: page.id, expecting: page.content)

        #expect(try await store.embeddedText(for: page.id) == nil)
    }

    @Test func aPageNobodyHasLookedAtReadsBackAsNothing() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedPDFPage(store)

        #expect(try await store.embeddedText(for: page.id) == nil)
    }

    @Test func rescanningAPageTakesItsOldTextAway() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedPDFPage(store)
        try await store.indexEmbeddedText("Original lease terms", for: page.id, expecting: page.content)

        let fresh = try store.assets.store(Data("%PDF-1.7 rescanned".utf8), kind: .pdf, originalFilename: "new.pdf")
        _ = try await store.replacePageContent(page.id, with: .init(sourceSize: page.sourceSize,
                                                                    content: .pdfPage(fresh.id, index: 0),
                                                                    transform: page.transform),
                                               assets: [fresh])

        // Exporting words that describe paper the page no longer shows would
        // be worse than exporting nothing.
        #expect(try await store.embeddedText(for: page.id) == nil)
    }
}
