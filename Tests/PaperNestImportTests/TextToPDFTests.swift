import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import PaperNestImport

/// Row 33: turning a plain text file into pages. The risk is not getting text
/// onto a page, it is losing some of it at a page break or off the right
/// margin — which looks like a clean conversion until someone reads it.
@Suite struct TextToPDFTests {
    private func pdfText(_ data: Data) -> String {
        guard let document = PDFDocument(data: data) else { return "" }
        let indexes = Array(0..<document.pageCount)
        let found = PDFTextExtractor.text(in: data, pageIndexes: indexes)
        return indexes.compactMap { found[$0] }.joined(separator: " ")
    }

    @Test func shortTextBecomesOnePageWhoseWordsReadBack() throws {
        let data = try #require(TextToPDF.render("Quarterly report\nPrepared for review"))

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount == 1)
        let text = pdfText(data)
        #expect(text.contains("Quarterly report"))
        #expect(text.contains("Prepared for review"))
    }

    @Test func textLongerThanAPageBreaksAcrossPagesWithNothingLost() throws {
        // Numbered lines, so a dropped one is obvious rather than plausible.
        let lines = (1...200).map { "Line \($0) of the converted document" }
        let data = try #require(TextToPDF.render(lines.joined(separator: "\n")))

        let document = try #require(PDFDocument(data: data))
        #expect(document.pageCount > 1, "200 lines cannot fit on one page")

        let text = pdfText(data)
        #expect(text.contains("Line 1 of"))
        #expect(text.contains("Line 200 of"), "the last line must not fall off the final page")
        // The page break is where text usually disappears.
        for probe in [50, 99, 100, 101, 150] {
            #expect(text.contains("Line \(probe) of"), "line \(probe) went missing")
        }
    }

    @Test func aLineWiderThanThePageWrapsInsteadOfBeingClipped() throws {
        let long = Array(repeating: "wrapping", count: 80).joined(separator: " ")
        let data = try #require(TextToPDF.render(long))

        let text = pdfText(data)
        // Every occurrence has to survive; clipping would drop the tail.
        #expect(text.components(separatedBy: "wrapping").count - 1 == 80)
    }

    @Test func aSingleUnbrokenWordTooWideForThePageStillAppears() throws {
        let giant = String(repeating: "A", count: 400)
        let data = try #require(TextToPDF.render(giant))

        #expect(pdfText(data).contains("AAAAAAAAAA"), "an unbreakable word must not vanish")
    }

    @Test func accentsAndNonLatinTextSurvive() throws {
        let data = try #require(TextToPDF.render("Café Müller reçu 12,50 €\nкириллица\n日本語"))

        let text = pdfText(data)
        #expect(text.contains("Café Müller reçu 12,50 €"))
        #expect(text.contains("кириллица"))
    }

    @Test func textWithNothingInItIsRefused() throws {
        #expect(TextToPDF.render("") == nil)
        #expect(TextToPDF.render("   \n\t\n  ") == nil, "whitespace is not a document")
    }

    @Test func theResultCarriesRealTextRatherThanAPictureOfIt() throws {
        let data = try #require(TextToPDF.render("Selectable and searchable"))

        // Extractable text is what makes a converted file searchable and
        // annotatable; a rasterized page would look identical and be neither.
        #expect(PDFTextExtractor.text(in: data, pageIndex: 0)?.contains("Selectable") == true)
    }
}
