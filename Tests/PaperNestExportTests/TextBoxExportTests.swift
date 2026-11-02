import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// Text typed onto a page, on the way out.
@Suite struct TextBoxExportTests {
    private let box = CGRect(x: 100, y: 450, width: 400, height: 250)

    private func importedWithText(_ fixture: ExportFixture, _ text: String)
        async throws -> (PaperNestCore.LibraryItem, [Page]) {
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Statement"]), name: "Statement"))
        let pages = try await fixture.store.pages(of: item.id)
        try await fixture.store.saveObject(PageObject(
            pageID: pages[0].id, zKey: "m",
            payload: .text(TextBox(frame: box, text: text, fontSize: 28,
                                   color: .black, alignment: .leading)),
            modifiedAt: Date()))
        return (item, pages)
    }

    /// **Real text, not a picture of text.** Drawing glyphs as paths would look
    /// identical and be useless: nobody could select, copy or search the words
    /// someone typed. This reads them back out of the written file.
    @Test func textInABoxIsRealTextInTheExportedPDF() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importedWithText(fixture, "RENT RECEIPT")

        let output = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(url: output.files[0]))
        let page = try #require(document.page(at: 0))
        let text = try #require(page.string)
        #expect(text.contains("RENT RECEIPT"),
                "the typed words are not selectable text in the export: \(text)")
    }

    /// The same trap placed images had. An unedited PDF page at its original
    /// paper size carrying only a text box would be copied from its source,
    /// and the words would be gone from the export without a sound.
    @Test func aPageCarryingATextBoxIsDrawnRatherThanCopied() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importedWithText(fixture, "PAID IN FULL")

        let output = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(url: output.files[0]))
        let text = try #require(document.page(at: 0)?.string)
        #expect(text.contains("PAID IN FULL"), "the page was copied and the text box lost")
    }
}
