import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// Marks drawn over a redacted area. They live in rows of their own and are
/// drawn over the flattened picture, in every export, and a text box's words
/// answer searches — so a redaction removes the ones over its areas, in the
/// same operation, and keeps the rest.
@Suite struct PageRedactionMarksTests {
    /// The band `textPDF`'s line of text sits in.
    private let band = NormalizedRect.exact(x: 0.05, y: 0.13, width: 0.9, height: 0.07)

    private func seeded() async throws -> (URL, LibraryStore, Page) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRedactMarks-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: url)
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.textPDF(pages: ["ACCOUNT 55512345"]), name: "Statement"))
        return (url, store, try await store.pages(of: item.id)[0])
    }

    private func textBox(_ page: Page, _ text: String, y: CGFloat) -> PageObject {
        PageObject(pageID: page.id, zKey: "m\(Int(y))",
                   payload: .text(TextBox(frame: CGRect(x: 60, y: y, width: 300, height: 30), text: text)),
                   modifiedAt: Date())
    }

    @Test func aTextBoxOverTheAreaGoesAndOneBesideItStays() async throws {
        let (url, store, page) = try await seeded()
        defer { try? FileManager.default.removeItem(at: url) }
        // 792-point page: the band is about 103…158 points down.
        let over = textBox(page, "PIN 9921", y: 110)
        let beside = textBox(page, "Filed in March", y: 600)
        try await store.saveObject(over)
        try await store.saveObject(beside)
        #expect(try await store.search("9921").count == 1)
        let current = try #require(try await store.page(page.id))
        let objects = try await store.objects(on: page.id)
        let marks = PageRedactionReview.marksOverlapping([band], in: objects, sourceSize: current.sourceSize)
        #expect(marks.map(\.id) == [over.id])

        let renderer = PageRenderer(store: store)
        let outcome = try await PageRedactor(store: store, renderer: renderer)
            .redact(current, rectangles: [band], removingMarks: marks)

        #expect(outcome.removedMarks == 1)
        #expect(try await store.objects(on: page.id).map(\.id) == [beside.id])
        #expect(try await store.search("9921").isEmpty, "the removed box's words still answer a search")
        #expect(try await store.search("March").count == 1, "the box beside the area is kept")

        // Nor is it in what leaves the app.
        let exporter = Exporter(renderer: renderer, temporaryRoot: url)
        let output = try await exporter.export(itemName: "Statement", pages: [outcome.page],
                                               options: ExportOptions(format: .pdf))
        let text = PDFDocument(url: output.files[0])?.string ?? ""
        #expect(!text.contains("9921"))
        #expect(!text.contains("55512345"), "the page's own words are gone too")
    }

    @Test func marksFromAnotherPageAreNeverRemoved() async throws {
        let (url, store, page) = try await seeded()
        defer { try? FileManager.default.removeItem(at: url) }
        let elsewhere = PageObject(pageID: PageID(rawValue: "someone-else"), zKey: "m",
                                   payload: .text(TextBox(frame: CGRect(x: 60, y: 110, width: 300, height: 30), text: "x")),
                                   modifiedAt: Date())

        let outcome = try await PageRedactor(store: store, renderer: PageRenderer(store: store))
            .redact(page, rectangles: [band], removingMarks: [elsewhere])

        #expect(outcome.removedMarks == 0)
    }

    /// Whether the review must say the page's words all go: read from the
    /// page itself, so a page imported a moment ago, before the background
    /// pass has indexed its text, still says so.
    @Test func whetherThePaperHasWordsIsReadFromThePage() async throws {
        let (url, store, page) = try await seeded()
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = PageRenderer(store: store)
        #expect(try await renderer.paperHasWords(page), "a digital page with a line of text")

        let asset = try store.assets.store(SyntheticDocuments.image(width: 300, height: 400, type: .png), kind: .png,
                                           originalFilename: "scan.png")
        let item = try await store.createItem(kind: .document, name: "Scan", pages: [
            .init(sourceSize: CGSize(width: 300, height: 400), content: .image(asset.id)),
        ], assets: [asset])
        let scan = try await store.pages(of: item.id)[0]
        #expect(try await !renderer.paperHasWords(scan), "a scan nobody has read")
        try await store.saveRecognition(PageRecognition(pageID: scan.id, sourceRevision: scan.revision, engineVersion: "test",
                                                        status: .completed, languages: ["en-US"],
                                                        lines: [RecognizedLine(text: "Read", box: .exact(x: 0.1, y: 0.1, width: 0.3, height: 0.05),
                                                                               confidence: 1)]))
        #expect(try await renderer.paperHasWords(scan), "a scan with recognized text")
    }

    /// A drawing that fails removes nothing: the marks go only once the
    /// redacted picture exists.
    @Test func aRedactionThatCannotStartRemovesNoMarks() async throws {
        let (url, store, page) = try await seeded()
        defer { try? FileManager.default.removeItem(at: url) }
        let over = textBox(page, "PIN 9921", y: 110)
        try await store.saveObject(over)
        let current = try #require(try await store.page(page.id))

        await #expect(throws: RedactionError.noRectangles) {
            try await PageRedactor(store: store, renderer: PageRenderer(store: store))
                .redact(current, rectangles: [], removingMarks: [over])
        }
        #expect(try await store.objects(on: page.id).map(\.id) == [over.id])
    }
}
