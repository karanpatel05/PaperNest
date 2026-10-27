import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// Row 26: redaction that removes content rather than covering it.
///
/// A black rectangle drawn over a word is the classic fake — the word stays in
/// the file, selectable, searchable and recoverable. Every test here is meant
/// to fail for a redaction that merely looks right.
@Suite struct PageRedactionTests {
    private func seeded(_ text: String) async throws -> (URL, LibraryStore, Page, PageRenderer) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRedaction-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: url)
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.textPDF(pages: [text]), name: "Statement"))
        let pages = try await store.pages(of: item.id)
        return (url, store, pages[0], PageRenderer(store: store))
    }

    /// The band the fixture's line of text sits in. `textPDF` draws at
    /// (72, height − 140) at 18pt, so with a top-left origin on a 792pt page
    /// the line lands around y = 0.15.
    private let textBand = NormalizedRect.exact(x: 0.05, y: 0.13, width: 0.9, height: 0.07)

    @Test func theRedactedWordsAreNotInTheBytesAtAll() async throws {
        let (url, _, page, renderer) = try await seeded("ACCOUNT 55512345 SECRET")
        defer { try? FileManager.default.removeItem(at: url) }

        let redacted = try await PageRedaction.redactedPNG(for: page, rectangles: [textBand],
                                                           renderer: renderer)

        #expect(PixelProbe.decode(redacted) != nil, "not a decodable image")
        // Not "is it covered" — is it gone. The word must not survive anywhere
        // in the new bytes, in any form a reader could pull back out.
        #expect(String(decoding: redacted, as: UTF8.self).contains("SECRET") == false,
                "the word is still in the bytes")
        #expect(String(decoding: redacted, as: UTF8.self).contains("55512345") == false)
    }

    @Test func thePixelsWhereTheWordsWereAreBlack() async throws {
        let (url, _, page, renderer) = try await seeded("ACCOUNT 55512345 SECRET")
        defer { try? FileManager.default.removeItem(at: url) }

        let redacted = try await PageRedaction.redactedPNG(for: page, rectangles: [textBand],
                                                           renderer: renderer)
        let image = try #require(PixelProbe.decode(redacted))

        for x in [0.1, 0.3, 0.5, 0.7, 0.85] {
            #expect(PixelProbe.pixel(image, x: x, y: 0.16).isDark, "not black at x=\(x)")
        }
        // The rest of the page survives: redaction removes a region, it does
        // not blank the sheet.
        #expect(PixelProbe.pixel(image, x: 0.5, y: 0.6).isWhite)
    }

    @Test func redactingNothingIsRefusedRatherThanQuietlyRewritingThePage() async throws {
        let (url, _, page, renderer) = try await seeded("Nothing to hide")
        defer { try? FileManager.default.removeItem(at: url) }

        await #expect(throws: RedactionError.noRectangles) {
            try await PageRedaction.redactedPNG(for: page, rectangles: [], renderer: renderer)
        }
    }

    /// A scan is already pixels, so there is no text layer to lose — the only
    /// cost is the painted region itself.
    @Test func aScannedPageIsRedactedToo() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRedaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LibraryStore(directory: url)
        let item = try await DocumentImporter(store: store).importItem(
            .data(SyntheticDocuments.textImage(lines: ["ACCOUNT 55512345"], width: 1000, height: 1400), name: "Scan"))
        let pages = try await store.pages(of: item.id)

        let redacted = try await PageRedaction.redactedPNG(
            for: pages[0], rectangles: [.exact(x: 0, y: 0, width: 1, height: 0.3)],
            renderer: PageRenderer(store: store))
        let image = try #require(PixelProbe.decode(redacted))

        #expect(PixelProbe.pixel(image, x: 0.5, y: 0.15).isDark)
    }

    /// The whole operation, which is the point: rendering alone leaves the
    /// original in the library, replacing alone leaves the words in
    /// `page_recognition`, forgetting alone leaves the file on disk. All four
    /// or the promise is false.
    @Test func redactingLeavesNothingToFindAnywhere() async throws {
        let (url, store, page, renderer) = try await seeded("ACCOUNT 55512345 SECRET")
        defer { try? FileManager.default.removeItem(at: url) }
        try await store.saveRecognition(PageRecognition(
            pageID: page.id, sourceRevision: page.revision, engineVersion: "test",
            status: .completed, languages: ["en-US"],
            lines: [RecognizedLine(text: "ACCOUNT 55512345 SECRET",
                                   box: .exact(x: 0.1, y: 0.14, width: 0.8, height: 0.03), confidence: 0.9)]))
        #expect(try await store.search("55512345").isEmpty == false, "precondition: it was findable")
        guard case .pdfPage(let originalID, _) = page.content else {
            Issue.record("expected a PDF page"); return
        }
        let originalFile = store.assets.url(for: originalID, kind: .pdf)

        let outcome = try await PageRedactor(store: store, renderer: renderer)
            .redact(page, rectangles: [textBand])

        // The page now shows the redacted picture, not the paper.
        guard case .image = outcome.page.content else {
            Issue.record("the page still shows \(outcome.page.content)"); return
        }
        #expect(try await store.search("55512345").isEmpty, "the words still answer searches")
        #expect(try await store.recognition(for: page.id) == nil, "the words are still stored")
        #expect(outcome.originalStillInLibrary == false)
        #expect(!FileManager.default.fileExists(atPath: originalFile.path), "the original is still on disk")
    }

    /// Content addressing means identical paper is stored once. Redacting one
    /// page cannot delete it, and the words stay reachable through the other —
    /// so the outcome has to say so rather than report a removal.
    @Test func aSharedOriginalSurvivesAndTheOutcomeSaysSo() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRedaction-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let store = try LibraryStore(directory: url)
        let importer = DocumentImporter(store: store)
        let data = SyntheticDocuments.textPDF(pages: ["ACCOUNT 55512345"])
        let first = try await importer.importItem(.data(data, name: "One"))
        _ = try await importer.importItem(.data(data, name: "Two"))
        let page = try await store.pages(of: first.id)[0]
        guard case .pdfPage(let originalID, _) = page.content else {
            Issue.record("expected a PDF page"); return
        }
        let originalFile = store.assets.url(for: originalID, kind: .pdf)

        let outcome = try await PageRedactor(store: store, renderer: PageRenderer(store: store))
            .redact(page, rectangles: [textBand])

        #expect(outcome.originalStillInLibrary, "a shared original was reported as removed")
        #expect(FileManager.default.fileExists(atPath: originalFile.path),
                "the second document's paper was deleted from under it")
    }

    /// Redaction is not a reshuffle: the page stays where it was and keeps the
    /// edits the user had made to it.
    @Test func theRedactedPageKeepsItsPlaceAndItsTransform() async throws {
        let (url, store, page, renderer) = try await seeded("ACCOUNT 55512345")
        defer { try? FileManager.default.removeItem(at: url) }
        var cropped = page.transform
        cropped.crop = .exact(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
        let edited = try await store.updateTransform(page.id, to: cropped)

        let outcome = try await PageRedactor(store: store, renderer: renderer)
            .redact(edited, rectangles: [textBand])

        #expect(outcome.page.id == page.id)
        #expect(outcome.page.sortKey == page.sortKey)
        #expect(outcome.page.transform.crop == cropped.crop, "the crop was lost")
        #expect(outcome.page.sourceSize == page.sourceSize)
    }
}
