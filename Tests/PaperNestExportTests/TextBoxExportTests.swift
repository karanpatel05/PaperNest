import AppKit
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
    @Test(arguments: TextBox.FontFamily.allCases, [(false, false), (true, false), (false, true), (true, true)])
    func exportedTextRetainsRequestedFontTraits(_ family: TextBox.FontFamily, traits requested: (Bool, Bool)) async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Statement"]), name: "Styled"))
        let page = try await fixture.store.pages(of: item.id)[0]
        let (updated, _) = try await fixture.store.placeText("STYLED", on: page.id, frame: box,
            fontSize: 28, color: RGBAColor(red: 0.8, green: 0.1, blue: 0.2), alignment: .center, fontFamily: family, isBold: requested.0, isItalic: requested.1)
        let output = try await fixture.exporter.export(itemName: item.name, pages: [updated],
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { output.removeTemporaryFiles() }
        let pdf = try #require(PDFDocument(url: output.files[0]))
        let exportedPage = try #require(pdf.page(at: 0))
        let text = try #require(exportedPage.attributedString)
        let range = (text.string as NSString).range(of: "STYLED")
        #expect(range.location != NSNotFound)
        guard range.location != NSNotFound else { return }
        let font = try #require(text.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        let traits = NSFontManager.shared.traits(of: font)
        #expect(traits.contains(.boldFontMask) == requested.0)
        #expect(traits.contains(.italicFontMask) == requested.1)
        let familyName = try #require(font.familyName).lowercased()
        switch family {
        case .sans: #expect(familyName.contains("helvetica"))
        case .serif: #expect(familyName.contains("times"))
        case .monospaced: #expect(familyName.contains("courier"))
        }
        #expect(abs(font.pointSize - 28) < 0.1)
        let color = try #require((text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor)?.usingColorSpace(.sRGB))
        #expect(abs(color.redComponent - 0.8) < 0.02)
        #expect(abs(color.greenComponent - 0.1) < 0.02)
        #expect(abs(color.blueComponent - 0.2) < 0.02)
        let selection = try #require(exportedPage.selection(for: range))
        #expect(abs(selection.bounds(for: exportedPage).midX - box.midX) < 3)

    }

}
