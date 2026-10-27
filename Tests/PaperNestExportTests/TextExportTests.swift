import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// F4: getting a document's words out as plain text. The text has to come
/// from what the page really has — recognized lines, or the text a digital
/// PDF already carries — and never be invented for a page that has neither.
@Suite struct TextExportTests {
    private let formFeed = "\u{0C}"

    private func completed(_ page: Page, _ lines: [String]) -> PageRecognition {
        PageRecognition(pageID: page.id, sourceRevision: page.revision,
                        engineVersion: "test", status: .completed, languages: ["en-US"],
                        lines: lines.enumerated().map { index, text in
                            RecognizedLine(text: text,
                                           box: .exact(x: 0.1, y: 0.1 + Double(index) * 0.05, width: 0.5, height: 0.02),
                                           confidence: 0.9)
                        })
    }

    private func exportText(_ fixture: ExportFixture, _ name: String, _ pages: [Page]) async throws -> (String, ExportOutput) {
        let output = try await fixture.exporter.export(itemName: name, pages: pages,
                                                      options: ExportOptions(format: .txt))
        let text = try String(decoding: Data(contentsOf: output.files[0]), as: UTF8.self)
        return (text, output)
    }

    @Test func aScannedDocumentExportsItsRecognizedWords() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.image(width: 600, height: 800, type: .png), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)
        try await fixture.store.saveRecognition(completed(pages[0], ["Invoice total", "Paid in full"]))

        let (text, output) = try await exportText(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(text.contains("Invoice total"))
        #expect(text.contains("Paid in full"))
        // Recognized lines keep their structure.
        #expect(text.contains("Invoice total\nPaid in full"))
        #expect(output.files[0].pathExtension == "txt")
    }

    @Test func aDigitalPDFExportsItsOwnTextWithNoRecognitionAtAll() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Council tax notice for 2026"])

        let (text, output) = try await exportText(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(text.contains("Council tax notice for 2026"))
        #expect(try await fixture.store.recognition(for: pages[0].id) == nil, "no OCR was involved")
    }

    @Test func recognizedLinesWinWhenAPageHasBoth() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["The page's own paragraph"])
        try await fixture.store.saveRecognition(completed(pages[0], ["Recognized first line", "Recognized second line"]))

        let (text, output) = try await exportText(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        // Recognition keeps line structure, so it is the better source.
        #expect(text.contains("Recognized first line\nRecognized second line"))
        #expect(!text.contains("The page's own paragraph"))
    }

    @Test func pagesAreSeparatedByAFormFeedInPageOrder() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["First page words", "Second page words", "Third page words"])

        let (text, output) = try await exportText(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let sections = text.components(separatedBy: formFeed)
        #expect(sections.count == 3)
        #expect(sections[0].contains("First"))
        #expect(sections[1].contains("Second"))
        #expect(sections[2].contains("Third"))
    }

    @Test func aPageWithNoTextDoesNotBreakItsNeighbours() async throws {
        let fixture = try ExportFixture()
        // A scan carries no text of its own, so only the second page has
        // anything to export. The first page used to be a text page nobody had
        // indexed, which tested the index rather than the document.
        let scan = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(), name: "Scan"))
        let scanPages = try await fixture.store.pages(of: scan.id)
        let (item, textPages) = try await fixture.importPDF(["Only these words"])
        let pages = [scanPages[0], textPages[0]]

        let (text, output) = try await exportText(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(text.contains("Only these words"))
        // The empty page still holds its place, so page order stays readable.
        let sections = text.components(separatedBy: formFeed)
        #expect(sections.count == 2)
        #expect(sections[0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test func aDocumentWithNoTextAnywhereIsRefusedRatherThanWritingAnEmptyFile() async throws {
        let fixture = try ExportFixture()
        // A scan: no recognition, and no text of its own either.
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)

        await #expect(throws: ExportError.noTextToExport) {
            try await fixture.exporter.export(itemName: item.name, pages: pages,
                                              options: ExportOptions(format: .txt))
        }
    }

    @Test func theFileIsValidUTF8IncludingAccents() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Café Müller reçu 12,50 €"])

        let (text, output) = try await exportText(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(text.contains("Café Müller reçu 12,50 €"))
    }

    /// The limitation this closes. A digital PDF's text used to come from the
    /// search index, which normalizes it for matching, so a page of lines
    /// arrived as one run-on paragraph. The lines are now read from the page's
    /// own PDF, where they are separate.
    @Test func aDigitalPDFKeepsItsLinesInsteadOfBecomingOneParagraph() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Invoice 2026-114\nDue 30 November\nTotal 1234 EUR"])

        let (text, output) = try await exportText(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        #expect(lines.count == 3, "got \(lines.count) line(s): \(lines)")
        #expect(lines.first?.contains("Invoice 2026-114") == true)
        #expect(lines.last?.contains("Total 1234 EUR") == true)
    }

}
