import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// F4: a scan exported as a PDF carries its recognized text invisibly, so it
/// can be searched and selected in any reader. The words come from what was
/// actually recognized; nothing is invented, and nothing becomes visible.
@Suite struct SearchablePDFTests {
    private let size = CGSize(width: 600, height: 800)

    /// An imported scan with a recognition result over the top-left quarter.
    private func scan(_ f: ExportFixture, text: [String] = ["Quarterly statement"],
                      status: PageRecognition.Status = .completed,
                      revisionOffset: Int = 0) async throws -> [Page] {
        let data = SyntheticDocuments.image(width: 600, height: 800, type: .png)
        let item = try await f.importer.importItem(.data(data, name: "Scan"))
        let pages = try await f.store.pages(of: item.id)
        let page = pages[0]
        let lines = text.enumerated().map { index, line in
            RecognizedLine(text: line,
                           box: .exact(x: 0.1, y: 0.08 + Double(index) * 0.06, width: 0.6, height: 0.04),
                           confidence: 0.9)
        }
        try await f.store.saveRecognition(PageRecognition(pageID: page.id, sourceRevision: page.revision + revisionOffset,
                                                          engineVersion: "test", status: status,
                                                          languages: ["en-US"], lines: lines))
        return pages
    }

    private func exported(_ f: ExportFixture, _ pages: [Page], options: ExportOptions) async throws -> (ExportOutput, PDFDocument) {
        let output = try await f.exporter.export(itemName: "Scan", pages: pages, options: options)
        let pdf = try #require(PDFDocument(url: output.files[0]))
        return (output, pdf)
    }

    @Test func recognizedWordsAreSelectableAndSitWhereTheyWereRead() async throws {
        let f = try ExportFixture()
        let pages = try await scan(f, text: ["Quarterly statement", "Amount due"])
        let (output, pdf) = try await exported(f, pages, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }

        let page = try #require(pdf.page(at: 0))
        let text = try #require(page.string)
        #expect(text.contains("Quarterly statement"))
        #expect(text.contains("Amount due"))

        // Found where it was read. The line was stored at x 0.1, y 0.08,
        // width 0.6 of the page, and must land there in the exported paper.
        let pageBounds = page.bounds(for: .mediaBox)
        let word = try #require(pdf.findString("Quarterly", withOptions: []).first).bounds(for: page)
        // PDF user space is y-up, so the top of the page is a high y.
        let fromTop = (pageBounds.height - word.maxY) / pageBounds.height
        #expect(abs(fromTop - 0.08) < 0.03, "expected the line 8% from the top, got \(fromTop)")
        #expect(abs(word.minX / pageBounds.width - 0.1) < 0.02, "expected the line to start at 10%, got \(word)")

        let whole = try #require(pdf.findString("Quarterly statement", withOptions: []).first).bounds(for: page)
        #expect(abs(whole.width / pageBounds.width - 0.6) < 0.05,
                "the line should span the 60% it was read at, got \(whole.width / pageBounds.width)")
    }

    @Test func theTextLayerIsInvisible() async throws {
        let f = try ExportFixture()
        let pages = try await scan(f)
        let (withText, _) = try await exported(f, pages, options: ExportOptions(format: .pdf))
        defer { withText.removeTemporaryFiles() }
        let (without, _) = try await exported(f, pages, options: ExportOptions(format: .pdf, includesRecognizedText: false))
        defer { without.removeTemporaryFiles() }

        let withData = try Data(contentsOf: withText.files[0])
        let withoutData = try Data(contentsOf: without.files[0])
        let a = try #require(PixelProbe.renderPDFPage(withData, index: 0))
        let b = try #require(PixelProbe.renderPDFPage(withoutData, index: 0))
        #expect(a.width == b.width)
        #expect(a.height == b.height)
        // Sample across the band the text covers: nothing may be painted.
        for x in stride(from: 0.12, through: 0.65, by: 0.05) {
            let inked = PixelProbe.pixel(a, x: x, y: 0.10)
            let plain = PixelProbe.pixel(b, x: x, y: 0.10)
            #expect(inked == plain, "the text layer painted something at x=\(x): \(inked) vs \(plain)")
        }
    }

    @Test func turningTheOptionOffWritesNoText() async throws {
        let f = try ExportFixture()
        let pages = try await scan(f)
        let (output, pdf) = try await exported(f, pages, options: ExportOptions(format: .pdf, includesRecognizedText: false))
        defer { output.removeTemporaryFiles() }
        let text = pdf.page(at: 0)?.string ?? ""
        #expect(!text.contains("Quarterly"))
    }

    @Test(arguments: [PageRecognition.Status.pending, .failed])
    func unfinishedRecognitionIsNotExported(_ status: PageRecognition.Status) async throws {
        let f = try ExportFixture()
        let pages = try await scan(f, status: status)
        let (output, pdf) = try await exported(f, pages, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        // Bound outside #expect: a nil inside the macro's expression is
        // itself reported as a failure.
        let text = pdf.page(at: 0)?.string ?? ""
        #expect(!text.contains("Quarterly"))
    }

    @Test func textFromAnOlderRevisionIsNotExported() async throws {
        let f = try ExportFixture()
        let pages = try await scan(f, revisionOffset: -1)
        let (output, pdf) = try await exported(f, pages, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        let text = pdf.page(at: 0)?.string ?? ""
        #expect(!text.contains("Quarterly"), "text read from an older version of the page must not be exported")
    }

    /// A vector PDF already carries its own text; recognition must not be
    /// needed for it, and export must not lose it.
    @Test func aVectorPageKeepsItsOwnTextWithoutRecognition() async throws {
        let f = try ExportFixture()
        let (_, pages) = try await f.importPDF(["Original selectable text"])
        let (output, pdf) = try await exported(f, pages, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        #expect(pdf.page(at: 0)?.string?.contains("Original selectable text") == true)
    }

    @Test func aCroppedAndRotatedPageStillPlacesItsTextOnThePaper() async throws {
        let f = try ExportFixture()
        let pages = try await scan(f)
        var transform = pages[0].transform
        transform.rotation = .clockwise90
        transform.crop = NormalizedRect(x: 0.0, y: 0.0, width: 0.8, height: 0.6)
        let edited = try await f.store.updateTransform(pages[0].id, to: transform)
        // The edit bumped the revision, so the page is read again.
        let lines = [RecognizedLine(text: "Rotated words", box: .exact(x: 0.1, y: 0.1, width: 0.5, height: 0.05), confidence: 0.9)]
        try await f.store.saveRecognition(PageRecognition(pageID: edited.id, sourceRevision: edited.revision,
                                                          engineVersion: "test", status: .completed,
                                                          languages: ["en-US"], lines: lines))

        let (output, pdf) = try await exported(f, [edited], options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        let page = try #require(pdf.page(at: 0))
        let text = page.string ?? ""
        #expect(text.contains("Rotated words"), "extracted: [\(text)]")
        let selection = try #require(pdf.findString("Rotated", withOptions: []).first)
        let bounds = selection.bounds(for: page)
        let paper = page.bounds(for: .mediaBox)
        #expect(paper.insetBy(dx: -1, dy: -1).contains(bounds), "the text must land on the paper, got \(bounds) in \(paper)")
    }
}
