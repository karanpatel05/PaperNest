import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// F4: the words in a real Word file. A `.docx` is a ZIP of XML parts, so the
/// risk here is not whether text lands in the file but whether the file stays
/// openable: one unescaped `&` from a scan would make it unreadable.
@Suite struct DocxExportTests {
    private func completed(_ page: Page, _ lines: [String]) -> PageRecognition {
        PageRecognition(pageID: page.id, sourceRevision: page.revision,
                        engineVersion: "test", status: .completed, languages: ["en-US"],
                        lines: lines.enumerated().map { index, text in
                            RecognizedLine(text: text,
                                           box: .exact(x: 0.1, y: 0.1 + Double(index) * 0.05, width: 0.5, height: 0.02),
                                           confidence: 0.9)
                        })
    }

    /// Exports, extracts, and hands back the entry list and `word/document.xml`.
    private func exportDocx(_ fixture: ExportFixture, _ name: String, _ pages: [Page])
        async throws -> (entries: [String], documentXML: Data, output: ExportOutput) {
        let output = try await fixture.exporter.export(itemName: name, pages: pages,
                                                      options: ExportOptions(format: .docx))
        let listed = try unzip(["-Z1", output.files[0].path])
        #expect(listed.status == 0)
        let extracted = output.directory.appendingPathComponent("unpacked", isDirectory: true)
        let result = try unzip(["-q", output.files[0].path, "-d", extracted.path])
        #expect(result.status == 0, "the file has to be a readable ZIP: \(result.output)")
        let xml = try Data(contentsOf: extracted.appendingPathComponent("word/document.xml"))
        return (listed.output.split(separator: "\n").map(String.init), xml, output)
    }

    private func isWellFormed(_ xml: Data) -> Bool {
        XMLParser(data: xml).parse()
    }

    /// The text goes in the PDF, which is where a digital PDF's text lives.
    /// This used to import pages reading "page" and then index the wanted text
    /// against them, which tested the search index rather than the document.
    private func seeded(_ fixture: ExportFixture, _ texts: [String]) async throws
        -> (PaperNestCore.LibraryItem, [Page]) {
        try await fixture.importPDF(texts)
    }

    @Test func theFileIsAZipHoldingThePartsAWordProcessorNeeds() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await seeded(fixture, ["Council tax notice"])

        let (entries, _, output) = try await exportDocx(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(output.files[0].pathExtension == "docx")
        #expect(entries.contains("[Content_Types].xml"))
        #expect(entries.contains("_rels/.rels"))
        #expect(entries.contains("word/document.xml"))
    }

    @Test func everyPartIsWellFormedXML() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await seeded(fixture, ["Statement of account"])

        let (_, documentXML, output) = try await exportDocx(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(isWellFormed(documentXML))
        let extracted = output.directory.appendingPathComponent("unpacked", isDirectory: true)
        #expect(isWellFormed(try Data(contentsOf: extracted.appendingPathComponent("[Content_Types].xml"))))
        #expect(isWellFormed(try Data(contentsOf: extracted.appendingPathComponent("_rels/.rels"))))
    }

    @Test func recognizedLinesBecomeSeparateParagraphs() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Anything"])
        try await fixture.store.saveRecognition(completed(pages[0], ["Invoice total", "Paid in full"]))

        let (_, documentXML, output) = try await exportDocx(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let text = String(decoding: documentXML, as: UTF8.self)
        #expect(text.contains("Invoice total"))
        #expect(text.contains("Paid in full"))
        // Two lines, two paragraphs: a Word file of one run would lose the layout.
        #expect(text.components(separatedBy: "<w:p>").count - 1 >= 2)
    }

    @Test func ampersandsAndAnglesAreEscapedSoTheFileStillParses() async throws {
        let fixture = try ExportFixture()
        // Ordinary text off a scanned page, not an exotic input.
        let (item, pages) = try await seeded(fixture, ["Tom & Jerry <b> \"quoted\" 5 > 3"])

        let (_, documentXML, output) = try await exportDocx(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(isWellFormed(documentXML), "an unescaped & or < makes the file unopenable")
        let text = String(decoding: documentXML, as: UTF8.self)
        #expect(text.contains("Tom &amp; Jerry"))
        #expect(text.contains("&lt;b&gt;"))
    }

    @Test func aControlCharacterIsDroppedRatherThanBreakingTheFile() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Anything"])
        // Recognition of a noisy scan can return characters XML 1.0 forbids,
        // and they really do reach here: a recognition result travels as JSON
        // in `page_recognition`, where a NUL is the escape `\u0000` and
        // survives, decoding back to the real character.
        //
        // Deliberately not fed through `indexEmbeddedText`: that binds text to
        // SQLite with length -1, so the C API stops at the NUL and the string
        // is truncated before it could ever get here. See the TEST_MATRIX note.
        try await fixture.store.saveRecognition(completed(pages[0], ["Before\u{0}After\u{1}End"]))

        let (_, documentXML, output) = try await exportDocx(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(isWellFormed(documentXML))
        let text = String(decoding: documentXML, as: UTF8.self)
        #expect(text.contains("BeforeAfterEnd"))
    }

    @Test func pagesAreSeparatedByAPageBreak() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await seeded(fixture, ["First page words", "Second page words"])

        let (_, documentXML, output) = try await exportDocx(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let text = String(decoding: documentXML, as: UTF8.self)
        #expect(text.contains("w:type=\"page\""))
        let first = try #require(text.range(of: "First page words"))
        let breakAt = try #require(text.range(of: "w:type=\"page\""))
        let second = try #require(text.range(of: "Second page words"))
        #expect(first.upperBound < breakAt.lowerBound)
        #expect(breakAt.upperBound < second.lowerBound)
    }

    @Test func accentsSurviveAsUTF8() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await seeded(fixture, ["Café Müller reçu 12,50 €"])

        let (_, documentXML, output) = try await exportDocx(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(isWellFormed(documentXML))
        #expect(String(decoding: documentXML, as: UTF8.self).contains("Café Müller reçu 12,50 €"))
    }

    @Test func aDocumentWithNoTextIsRefusedRatherThanWritingAnEmptyWordFile() async throws {
        let fixture = try ExportFixture()
        // A scan: no recognition, and no text of its own either. This used to
        // be a text page nobody had indexed, which only looked textless.
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)

        await #expect(throws: ExportError.noTextToExport) {
            try await fixture.exporter.export(itemName: item.name, pages: pages,
                                              options: ExportOptions(format: .docx))
        }
    }

    /// The same limitation on the Word side: a digital PDF's text arrived as a
    /// single paragraph, which is exactly the layout a Word export exists to
    /// keep.
    @Test func aDigitalPDFBecomesOneParagraphPerLine() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Invoice 2026-114\nDue 30 November\nTotal 1234 EUR"])

        let (_, documentXML, output) = try await exportDocx(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let text = String(decoding: documentXML, as: UTF8.self)
        #expect(text.contains("Invoice 2026-114"))
        #expect(text.contains("Total 1234 EUR"))
        #expect(text.components(separatedBy: "<w:p>").count - 1 >= 3,
                "three lines should be three paragraphs")
    }
}
