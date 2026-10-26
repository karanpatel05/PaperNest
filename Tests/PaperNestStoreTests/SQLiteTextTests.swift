import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// Text has to come back out of the database as it went in. `sqlite3_bind_text`
/// with length -1 and `String(cString:)` both stop at the first NUL, so a
/// single unprintable character used to take the rest of the string with it —
/// silently, which is the part that matters.
@Suite struct SQLiteTextTests {
    private func seedPDFPage(_ store: LibraryStore) async throws -> (LibraryItem, Page) {
        let asset = try store.assets.store(Data("%PDF-1.7 synthetic".utf8), kind: .pdf, originalFilename: "doc.pdf")
        let item = try await store.createItem(kind: .document, name: "Statement", pages: [
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: 0)),
        ], assets: [asset])
        return (item, try await store.pages(of: item.id)[0])
    }

    @Test func textSurvivesANULInsteadOfLosingEverythingAfterIt() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedPDFPage(store)

        // A PDF's own text, or recognition of a noisy scan, can carry one.
        try await store.indexEmbeddedText("Before\u{0}After", for: page.id, expecting: page.content)

        let read = try await store.embeddedText(for: page.id)
        #expect(read == "Before\u{0}After", "got \(String(describing: read))")
    }

    @Test func wordsAfterANULAreStillFindable() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seedPDFPage(store)

        try await store.indexEmbeddedText("Invoice\u{0}Rotterdam", for: page.id, expecting: page.content)

        // The user-visible cost of truncation: half the page stops existing.
        #expect(try await store.search("invoice") == [item.id])
        #expect(try await store.search("rotterdam") == [item.id],
                "a word after the NUL has to stay searchable")
    }

    @Test func ordinaryTextIsUnaffected() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seedPDFPage(store)

        try await store.indexEmbeddedText("Café Müller reçu 12,50 € — plain text",
                                          for: page.id, expecting: page.content)

        #expect(try await store.embeddedText(for: page.id) == "Café Müller reçu 12,50 € — plain text")
        #expect(try await store.search("muller") == [item.id])
    }

    @Test func textRoundTripsThroughAReopenedLibrary() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seedPDFPage(store)
        try await store.indexEmbeddedText("Kept\u{0}Across\u{0}Launches", for: page.id, expecting: page.content)

        let reopened = try LibraryStore(directory: dir.url)

        #expect(try await reopened.embeddedText(for: page.id) == "Kept\u{0}Across\u{0}Launches")
    }
}
