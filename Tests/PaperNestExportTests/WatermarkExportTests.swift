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

/// A watermark through the real exporter: in the file, over the page, never
/// in its text, never in the library.
@Suite struct WatermarkExportTests {
    private let confidential = Watermark(preset: .confidential, text: "CONFIDENTIAL")

    private func pdf(_ output: ExportOutput) throws -> PDFDocument {
        try #require(PDFDocument(url: output.files[0]))
    }

    /// The colour of what is drawn in the middle of page `index`.
    private func middle(of data: Data, page index: Int = 0) throws -> (count: Int, red: Double, green: Double, blue: Double) {
        let image = try #require(PixelProbe.renderPDFPage(data, index: index, scale: 1))
        let bitmap = WatermarkBitmap(image)
        let w = CGFloat(bitmap.width), h = CGFloat(bitmap.height)
        return bitmap.marked(in: CGRect(x: w * 0.3, y: h * 0.35, width: w * 0.4, height: h * 0.3))
    }

    @Test func aPDFCarriesTheMarkAndKeepsItsOwnText() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["Payment terms net thirty", "Second page alpha"])
        let output = try await f.exporter.export(itemName: item.name, pages: pages,
                                                 options: ExportOptions(format: .pdf, watermark: confidential))
        defer { output.removeTemporaryFiles() }
        let document = try pdf(output)
        #expect(document.pageCount == 2)
        // The page's own words are still text a reader can select and search…
        #expect(document.page(at: 0)?.string?.contains("Payment terms net thirty") == true)
        #expect(document.page(at: 1)?.string?.contains("Second page alpha") == true)
        // …and the watermark's are not: they are shapes.
        #expect(document.string?.contains("CONFIDENTIAL") != true)
        // Red, faint, in the middle of every page.
        let data = try Data(contentsOf: output.files[0])
        for index in 0..<2 {
            let drawn = try middle(of: data, page: index)
            #expect(drawn.count > 1_000, "page \(index + 1) carries no mark")
            #expect(drawn.red > drawn.green + 10, "page \(index + 1)'s mark is not red")
        }
    }

    /// An imported PDF nobody edited is handed back byte for byte without a
    /// watermark. With one, it cannot be: the mark has to be drawn on it.
    @Test func aWatermarkStopsAnUntouchedPDFBeingHandedBackAsItCame() async throws {
        let f = try ExportFixture()
        let source = SyntheticDocuments.textPDF(pages: ["Untouched page"])
        let item = try await f.importer.importItem(.data(source, name: "Plain"))
        let pages = try await f.store.pages(of: item.id)

        let plain = try await f.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .pdf))
        defer { plain.removeTemporaryFiles() }
        #expect(try Data(contentsOf: plain.files[0]) == source, "no watermark: the import comes back as it was")

        let marked = try await f.exporter.export(itemName: item.name, pages: pages,
                                                 options: ExportOptions(format: .pdf, watermark: confidential))
        defer { marked.removeTemporaryFiles() }
        let data = try Data(contentsOf: marked.files[0])
        #expect(data != source)
        #expect(try middle(of: data).count > 1_000)
        #expect(try pdf(marked).page(at: 0)?.string?.contains("Untouched page") == true)
    }

    /// None, and a Custom watermark with no text, write exactly what an export
    /// with no watermark writes.
    @Test func noVisibleWatermarkChangesNothing() async throws {
        let f = try ExportFixture()
        let source = SyntheticDocuments.textPDF(pages: ["Same bytes"])
        let item = try await f.importer.importItem(.data(source, name: "Plain"))
        let pages = try await f.store.pages(of: item.id)
        let empty = try await f.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, watermark: Watermark(preset: .custom, text: "  ")))
        defer { empty.removeTemporaryFiles() }
        #expect(try Data(contentsOf: empty.files[0]) == source)
        #expect(ExportOptions().watermark == nil, "an export starts with no watermark")
    }

    /// A scan's recognized words stay an invisible, searchable layer, and the
    /// watermark adds nothing to what a search finds.
    @Test func searchableScanStaysSearchableUnderTheMark() async throws {
        let f = try ExportFixture()
        let data = SyntheticDocuments.image(width: 600, height: 800, type: .png)
        let item = try await f.importer.importItem(.data(data, name: "Scan"))
        let page = try #require(try await f.store.pages(of: item.id).first)
        try await f.store.saveRecognition(PageRecognition(
            pageID: page.id, sourceRevision: page.revision, engineVersion: "test", status: .completed,
            languages: ["en-US"],
            lines: [RecognizedLine(text: "Quarterly statement", box: .exact(x: 0.1, y: 0.1, width: 0.6, height: 0.04),
                                   confidence: 0.9)]))
        let output = try await f.exporter.export(
            itemName: item.name, pages: [page],
            options: ExportOptions(format: .pdf, watermark: Watermark(preset: .approved, text: "APPROVED",
                                                                      dateLine: "Nov 16, 2026")))
        defer { output.removeTemporaryFiles() }
        let text = try #require(try pdf(output).page(at: 0)?.string)
        #expect(text.contains("Quarterly statement"))
        #expect(!text.contains("APPROVED"))
        #expect(!text.contains("2026"))
    }

    /// On Letter paper a corner mark sits in the corner of the paper, which
    /// is what the reader holds — not of the page fitted inside it.
    @Test func cornersFollowThePaper() async throws {
        let f = try ExportFixture()
        // A square page on portrait Letter fills the width and leaves a band
        // of 90 points above it and below it.
        let (item, pages) = try await f.importPDF(["Receipt"], size: CGSize(width: 600, height: 600))
        let output = try await f.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .usLetter, watermark: Watermark(preset: .draft, text: "DRAFT")))
        defer { output.removeTemporaryFiles() }
        let document = try pdf(output)
        #expect(document.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        let image = try #require(PixelProbe.renderPDFPage(try Data(contentsOf: output.files[0]), index: 0, scale: 1))
        let bitmap = WatermarkBitmap(image)
        let w = CGFloat(bitmap.width), h = CGFloat(bitmap.height)
        // The capsule is in the band above the page, in the paper's corner.
        let band = bitmap.marked(in: CGRect(x: w * 0.6, y: 0, width: w * 0.4, height: h * 0.1))
        #expect(band.count > 300, "the capsule is not in the paper's top-right corner")
        #expect(band.blue > band.green + 10)
    }

    @Test func picturesCarryTheMarkOnEveryPage() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["One", "Two"])
        for format in [ExportFormat.jpeg, .png, .heic] {
            let output = try await f.exporter.export(
                itemName: item.name, pages: pages,
                options: ExportOptions(format: format, imageDPI: 72, packaging: .separateFiles,
                                       watermark: Watermark(preset: .draft, text: "DRAFT")))
            defer { output.removeTemporaryFiles() }
            #expect(output.files.count == 2)
            for file in output.files {
                let image = try #require(PixelProbe.decode(try Data(contentsOf: file)))
                let bitmap = WatermarkBitmap(image)
                let corner = bitmap.marked(in: CGRect(x: 412, y: 0, width: 200, height: 120))
                #expect(corner.count > 300, "\(format) \(file.lastPathComponent) has no capsule")
                #expect(corner.blue > corner.green + 10)
                #expect(bitmap.marked(in: CGRect(x: 0, y: 650, width: 300, height: 142)).count < 50)
            }
        }
    }

    @Test func aTextFileRefusesAWatermarkInsteadOfDroppingIt() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["Words only"])
        for format in [ExportFormat.txt, .docx] {
            await #expect(throws: ExportError.watermarkNotSupported) {
                _ = try await f.exporter.export(itemName: item.name, pages: pages,
                                                options: ExportOptions(format: format, watermark: confidential))
            }
        }
        // Word's page pictures could carry one, but drawing on them is not
        // built, so that layout refuses too rather than leaving it off.
        await #expect(throws: ExportError.watermarkNotSupported) {
            _ = try await f.exporter.export(
                itemName: item.name, pages: pages,
                options: ExportOptions(format: .docx, docxLayout: .pageImages, watermark: confidential))
        }
        // With nothing to draw there is nothing to refuse.
        let output = try await f.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .txt, watermark: Watermark(preset: .custom, text: "")))
        output.removeTemporaryFiles()
    }

    /// One export draws the mark once. At 18% the muted red comes out at a
    /// green level of about 216 on white; drawn twice it would be about 185.
    /// The page has no text, and the fixture's black orientation square sits
    /// in its top-left corner, so only the middle of the page is read: there
    /// every coloured pixel is the mark's.
    @Test func oneExportDrawsTheMarkOnce() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF([""])
        let options = ExportOptions(format: .png, imageDPI: 72, watermark: confidential)
        let first = try await f.exporter.export(itemName: item.name, pages: pages, options: options)
        defer { first.removeTemporaryFiles() }
        let image = try #require(PixelProbe.decode(try Data(contentsOf: first.files[0])))
        let bitmap = WatermarkBitmap(image)
        #expect(bitmap.marked(in: CGRect(x: 184, y: 296, width: 244, height: 200)).count > 1_000, "no mark in the middle")
        var lowestGreen: UInt8 = 255
        for y in 296..<496 {
            for x in 184..<428 { lowestGreen = min(lowestGreen, bitmap.bytes[(y * bitmap.width + x) * 4 + 1]) }
        }
        #expect((205...225).contains(lowestGreen), "the mark's strongest green level is \(lowestGreen)")
        // And the same again, byte for byte, when the export is made again.
        let second = try await f.exporter.export(itemName: item.name, pages: pages, options: options)
        defer { second.removeTemporaryFiles() }
        #expect(try Data(contentsOf: first.files[0]) == Data(contentsOf: second.files[0]))
    }

    /// A PDF whose author switched copying off is redrawn to carry the mark,
    /// and leaves still closed: the exporter checks the written file holds
    /// the author's limits and fails the export if it does not.
    @Test func aRestrictedPDFKeepsItsLimitsUnderTheMark() async throws {
        let f = try ExportFixture()
        let item = try await f.importer.importItem(
            .data(SyntheticDocuments.restrictedPDF(pages: ["Closed words"], allowsCopying: false), name: "Closed"))
        let pages = try await f.store.pages(of: item.id)
        let output = try await f.exporter.export(itemName: item.name, pages: pages,
                                                 options: ExportOptions(format: .pdf, watermark: confidential))
        defer { output.removeTemporaryFiles() }
        let document = try pdf(output)
        #expect(!document.allowsCopying, "the watermark wrote the author's limit away")
        #expect(try middle(of: Data(contentsOf: output.files[0])).count > 1_000, "the closed PDF carries no mark")
    }

    /// The editable original and its pages are exactly as they were.
    @Test func theLibraryIsUntouched() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["Keep me"])
        let before = try await f.store.pages(of: item.id)
        let output = try await f.exporter.export(itemName: item.name, pages: pages,
                                                 options: ExportOptions(format: .pdf, watermark: confidential))
        output.removeTemporaryFiles()
        let after = try await f.store.pages(of: item.id)
        #expect(after == before)
        let plain = try await f.exporter.export(itemName: item.name, pages: after, options: ExportOptions(format: .pdf))
        defer { plain.removeTemporaryFiles() }
        #expect(try pdf(plain).string?.contains("CONFIDENTIAL") != true)
        #expect(try middle(of: Data(contentsOf: plain.files[0])).count < 50, "the mark stayed behind in the library")
    }
}
