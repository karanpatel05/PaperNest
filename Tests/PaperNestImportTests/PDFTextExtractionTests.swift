import Foundation
import Testing
import PaperNestTestSupport
@testable import PaperNestImport

/// F4: a digital PDF already carries its own words. Reading them is what lets
/// a text PDF be found by its contents instead of only by its title.
@Suite struct PDFTextExtractionTests {
    @Test func readsEachPagesOwnTextFromAVectorPDF() throws {
        let data = SyntheticDocuments.textPDF(pages: ["Quarterly invoice total", "Terms and conditions"])

        #expect(PDFTextExtractor.text(in: data, pageIndex: 0)?.contains("Quarterly invoice total") == true)
        #expect(PDFTextExtractor.text(in: data, pageIndex: 1)?.contains("Terms and conditions") == true)
        // Each page answers for itself; page 0 must not carry page 1's words.
        #expect(PDFTextExtractor.text(in: data, pageIndex: 0)?.contains("Terms") == false)
    }

    @Test func findsNoTextOnAScannedPage() throws {
        // A scan is pixels. There is nothing to extract, and saying otherwise
        // would claim recognition this does not do.
        #expect(PDFTextExtractor.text(in: SyntheticDocuments.scannedPDF(), pageIndex: 0) == nil)
    }

    @Test func findsNoTextOutsideThePageRange() throws {
        let data = SyntheticDocuments.textPDF(pages: ["Only page"])

        #expect(PDFTextExtractor.text(in: data, pageIndex: 1) == nil)
        #expect(PDFTextExtractor.text(in: data, pageIndex: -1) == nil)
    }

    @Test func findsNoTextInBytesThatAreNotAPDF() throws {
        #expect(PDFTextExtractor.text(in: Data("this is not a PDF".utf8), pageIndex: 0) == nil)
    }

    @Test func readsSeveralPagesOfOnePDFInOneParse() throws {
        // A 100-page PDF must not be opened and parsed 100 times, so the
        // indexer asks for the pages it needs together.
        let data = SyntheticDocuments.textPDF(pages: ["First words", "Second words", "Third words"])

        let found = PDFTextExtractor.text(in: data, pageIndexes: [0, 2])

        #expect(found[0]?.contains("First words") == true)
        #expect(found[2]?.contains("Third words") == true)
        #expect(found[1] == nil, "a page that was not asked for is not read")
    }

    @Test func leavesOutPagesWithNoTextAndIndexesOutsideTheDocument() throws {
        let scanned = SyntheticDocuments.scannedPDF(pages: 2)

        #expect(PDFTextExtractor.text(in: scanned, pageIndexes: [0, 1]).isEmpty)
        #expect(PDFTextExtractor.text(in: scanned, pageIndexes: [5]).isEmpty)
        #expect(PDFTextExtractor.text(in: Data("nope".utf8), pageIndexes: [0]).isEmpty)
    }

    @Test func readsTextFromAPDFOnDiskWithoutHoldingItAllInMemory() throws {
        // Indexing reads originals straight off disk, so a large PDF is
        // memory-mapped by PDFKit rather than loaded whole. On a phone,
        // loading a few hundred megabytes at launch risks being killed.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestExtract-\(UUID().uuidString).pdf")
        try SyntheticDocuments.textPDF(pages: ["Ground rent demand", "Service charge"]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let found = try #require(PDFTextExtractor.text(at: url, pageIndexes: [0, 1]))

        #expect(found[0]?.contains("Ground rent demand") == true)
        #expect(found[1]?.contains("Service charge") == true)
    }

    @Test func saysNothingAtAllWhenTheFileCannotBeOpened() throws {
        // Distinct from "opened it, found no text": a page whose original is
        // unreadable must be left for a later pass, not marked as checked.
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestMissing-\(UUID().uuidString).pdf")

        #expect(PDFTextExtractor.text(at: missing, pageIndexes: [0]) == nil)
    }
}
