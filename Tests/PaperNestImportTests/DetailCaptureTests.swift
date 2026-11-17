import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestRender

/// Details read off real pages: a scanned receipt through Vision, a digital
/// PDF through its own text, and a redaction taking kept details with it.
@Suite struct DetailCaptureTests {
    /// A synthetic receipt, read by recognition on this device, then by the
    /// extractor. The words Vision gives back decide what can be checked.
    @Test func aScannedReceiptIsReadAfterRecognition() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.textImage(
            lines: ["CORNER BAKERY", "2026-11-16", "Croissant 3.20", "Coffee 2.80", "TOTAL 6.00"], fontSize: 40),
            name: "Receipt"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        #expect(try await lib.renderer.captureLines(for: page).isEmpty, "nothing is read until text recognition runs")

        _ = try await AutomaticTextRecognizer(store: lib.store, renderer: lib.renderer).recognizeMissing()
        let read = try #require(try await lib.store.pages(of: item.id).first)
        let lines = try await lib.renderer.captureLines(for: read)
        #expect(lines.allSatisfy { $0.confidence > 0 && $0.confidence <= 1 })

        let details = DetailExtractor.extract(DetailExtractor.guessKind(lines), from: lines)
        #expect(details.kind == .receipt)
        #expect(details[.total] == "6.00")
        #expect(details[.date] == "2026-11-16")
        #expect(details[.merchant] == "CORNER BAKERY")
    }

    /// A digital invoice's own text, at full confidence, typed boxes left out.
    @Test func aDigitalInvoiceIsReadFromItsOwnText() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["Invoice No. A-17 Amount due 99.50 EUR"]),
                                                           name: "Invoice"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        try await lib.store.saveObject(PageObject(pageID: page.id, zKey: "V", payload: .text(TextBox(
            frame: CGRect(x: 300, y: 600, width: 200, height: 20), text: "Total 1,000.00 typed note")), modifiedAt: Date()))
        let current = try #require(try await lib.store.pages(of: item.id).first)

        let lines = try await lib.renderer.captureLines(for: current)

        #expect(lines.allSatisfy { $0.confidence == 1 })
        #expect(!lines.contains { $0.text.contains("typed note") }, "a typed box is a mark, not the page's text")
        let details = DetailExtractor.extract(.invoice, from: lines)
        #expect(details[.invoiceNumber] == "A-17")
        #expect(details[.total] == "99.50 EUR")
    }

    /// Kept details are words from the page: redacting it deletes them.
    @Test func redactingAPageDeletesTheDetailsKeptFromIt() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["ACCOUNT 55512345 Total 12.00"]),
                                                           name: "Statement"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        let details = CapturedDetails(kind: .receipt, values: [.total: DetailValue(text: "12.00", confidence: 1)])
        try await lib.store.saveDocumentDetails(details, for: item.id, readFrom: page.id)

        _ = try await PageRedactor(store: lib.store, renderer: lib.renderer)
            .redact(page, rectangles: [.exact(x: 0.05, y: 0.13, width: 0.9, height: 0.07)])

        #expect(try await lib.store.documentDetails(of: item.id) == nil)
    }
}
