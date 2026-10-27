import CoreGraphics
import ImageIO
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// F2d: reducing a document's size on purpose, and saying by how much. The
/// behaviour that matters most here is honesty — a compressor that reports a
/// saving it did not make is worse than no compressor at all.
@Suite struct CompressionTests {
    private func scannedDocument(_ fixture: ExportFixture, width: Int = 1600, height: Int = 2000)
        async throws -> (PaperNestCore.LibraryItem, [Page], Int64) {
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textImage(lines: Array(repeating: "Invoice total 1234 EUR", count: 20),
                                               width: width, height: height), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)
        return (item, pages, try await fixture.store.originalByteCount(of: item.id))
    }

    /// What a scanner actually produces: a large, detailed raster of a page.
    private static let scanRaster = SyntheticDocuments.textImage(
        lines: Array(repeating: "Invoice total 1234 EUR", count: 20), width: 1600, height: 2000)

    private func compress(_ fixture: ExportFixture, _ item: PaperNestCore.LibraryItem, _ pages: [Page],
                          _ original: Int64, _ preset: CompressionPreset) async throws -> CompressionResult {
        try await fixture.exporter.compress(itemName: item.name, pages: pages,
                                            originalByteCount: original, preset: preset)
    }

    @Test func aStrongerPresetProducesASmallerFile() async throws {
        let fixture = try ExportFixture()
        let (item, pages, original) = try await scannedDocument(fixture)

        let light = try await compress(fixture, item, pages, original, .light)
        defer { light.output.removeTemporaryFiles() }
        let strong = try await compress(fixture, item, pages, original, .strong)
        defer { strong.output.removeTemporaryFiles() }
        let smallest = try await compress(fixture, item, pages, original, .smallest)
        defer { smallest.output.removeTemporaryFiles() }

        #expect(strong.compressedByteCount < light.compressedByteCount,
                "strong \(strong.compressedByteCount) should beat light \(light.compressedByteCount)")
        #expect(smallest.compressedByteCount < strong.compressedByteCount,
                "smallest \(smallest.compressedByteCount) should beat strong \(strong.compressedByteCount)")
    }

    @Test func theOutputIsAValidPDFKeepingEveryPage() async throws {
        let fixture = try ExportFixture()
        let (item, pages, original) = try await scannedDocument(fixture)

        let result = try await compress(fixture, item, pages, original, .strong)
        defer { result.output.removeTemporaryFiles() }

        #expect(result.output.files.count == 1)
        let document = try #require(PDFDocument(url: result.output.files[0]))
        #expect(document.pageCount == pages.count)
    }

    @Test func anAlreadyCompactOriginalReportsNoSavingRatherThanAFakeOne() async throws {
        let fixture = try ExportFixture()
        // A flat synthetic page stores as a tiny PNG; re-encoding it as JPEG
        // makes it bigger, which must never be dressed up as a reduction.
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.image(width: 1200, height: 1600, type: .png), name: "Flat"))
        let pages = try await fixture.store.pages(of: item.id)
        let original = try await fixture.store.originalByteCount(of: item.id)

        let result = try await compress(fixture, item, pages, original, .light)
        defer { result.output.removeTemporaryFiles() }

        #expect(result.compressedByteCount > original, "precondition: this source does not compress")
        #expect(result.isSmaller == false)
        #expect(result.savedByteCount == 0, "never a negative saving dressed up as a positive one")
    }

    @Test func aVectorPDFKeepsItsTextInsteadOfBeingRasterizedToSaveBytes() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Council tax notice", "Terms and conditions"])
        let original = try await fixture.store.originalByteCount(of: item.id)

        let result = try await compress(fixture, item, pages, original, .smallest)
        defer { result.output.removeTemporaryFiles() }

        // Shrinking a digital PDF by rasterizing its text would destroy both
        // the quality and the selectable text. Vector pages pass through.
        let document = try #require(PDFDocument(url: result.output.files[0]))
        #expect(document.page(at: 0)?.string?.contains("Council") == true)
        #expect(document.page(at: 1)?.string?.contains("Terms") == true)
    }

    /// A PDF from another scanner app is `.pdfPage` content whose marks are a
    /// photograph. Before this, a preset never reached it: `prepareSource`
    /// handed back `.pdf` and `pdfSource` returned early, so Smallest returned
    /// the page exactly as it arrived.
    @Test func aScannedPDFGetsSmallerAtTheStrongestPreset() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(raster: Self.scanRaster), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)
        let original = try await fixture.store.originalByteCount(of: item.id)

        let result = try await compress(fixture, item, pages, original, .smallest)
        defer { result.output.removeTemporaryFiles() }

        #expect(result.isSmaller,
                "\(result.compressedByteCount) is not smaller than \(original)")
    }

    @Test func aStrongerPresetShrinksAScannedPDFFurther() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(pages: 2, raster: Self.scanRaster), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)
        let original = try await fixture.store.originalByteCount(of: item.id)

        let light = try await compress(fixture, item, pages, original, .light)
        defer { light.output.removeTemporaryFiles() }
        let smallest = try await compress(fixture, item, pages, original, .smallest)
        defer { smallest.output.removeTemporaryFiles() }

        #expect(smallest.compressedByteCount < light.compressedByteCount,
                "smallest \(smallest.compressedByteCount) did not beat light \(light.compressedByteCount)")
        // Re-encoding is not licence to lose pages.
        let document = try #require(PDFDocument(url: smallest.output.files[0]))
        #expect(document.pageCount == 2)
    }

    /// The page is re-encoded, not copied from the source. A copy would ignore
    /// the preset, so pass-through has to stand down for a page being
    /// rasterized — and the way to see that from outside is that the bytes
    /// differ between presets, which `aStrongerPresetShrinksAScannedPDFFurther`
    /// pins, and that the result differs from a plain export of the same page.
    @Test func compressingAScannedPDFDiffersFromJustExportingIt() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(raster: Self.scanRaster), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)
        let original = try await fixture.store.originalByteCount(of: item.id)

        let plain = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { plain.removeTemporaryFiles() }
        let compressed = try await compress(fixture, item, pages, original, .smallest)
        defer { compressed.output.removeTemporaryFiles() }

        #expect(compressed.compressedByteCount < plain.totalByteCount,
                "compressed \(compressed.compressedByteCount) vs plain export \(plain.totalByteCount)")
    }

    /// Light is 300 dpi, which *upsamples* a scan of lower resolution: the
    /// re-encode measured 416,360 bytes against a 193,043-byte page. A
    /// compression that doubled the file would be worse than none, so a
    /// re-encode that is not smaller than the page it would replace is thrown
    /// away and the page is left as it is.
    @Test func aPresetThatWouldEnlargeAScannedPageLeavesItAlone() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(raster: Self.scanRaster), name: "Scan"))
        let pages = try await fixture.store.pages(of: item.id)
        let original = try await fixture.store.originalByteCount(of: item.id)

        let plain = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { plain.removeTemporaryFiles() }
        let light = try await compress(fixture, item, pages, original, .light)
        defer { light.output.removeTemporaryFiles() }

        #expect(light.compressedByteCount <= plain.totalByteCount,
                "light \(light.compressedByteCount) exceeded a plain export at \(plain.totalByteCount)")
    }

    /// A blank page has no text, so it qualifies as "a scan" — and rasterizing
    /// it turns about a kilobyte into a JPEG of white. The budget is therefore
    /// measured per page, from the page itself, not as a share of the file: a
    /// document of one photograph and nine blank pages has no useful average.
    @Test func aBlankPageIsNotRasterizedIntoSomethingLarger() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: [""]), name: "Blank"))
        let pages = try await fixture.store.pages(of: item.id)
        let original = try await fixture.store.originalByteCount(of: item.id)

        let plain = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { plain.removeTemporaryFiles() }
        let result = try await compress(fixture, item, pages, original, .smallest)
        defer { result.output.removeTemporaryFiles() }

        // Without this, the test cannot tell the size rule working from the
        // fixture never qualifying as a scan in the first place: both look
        // like "every preset returned the plain export".
        let blank = try #require(PDFDocument(data: SyntheticDocuments.textPDF(pages: [""])))
        #expect(!Exporter.carriesText(blank, at: 0),
                "precondition: the blank page must be text-free, or this tests nothing")
        #expect(result.compressedByteCount <= plain.totalByteCount,
                "blank page grew: \(result.compressedByteCount) against \(plain.totalByteCount)")
    }

    /// The one geometry path this opens: an *edited* text-free page is now
    /// re-encoded, where before it was drawn as vector. The crop still has to
    /// be applied — a smaller file that quietly ignored the edit would be the
    /// pass-through bug all over again.
    @Test func aCroppedScannedPageIsReEncodedAndKeepsItsCrop() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(raster: Self.scanRaster), name: "Scan"))
        var pages = try await fixture.store.pages(of: item.id)
        let original = try await fixture.store.originalByteCount(of: item.id)
        var cropped = pages[0].transform
        cropped.crop = .exact(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        pages[0] = try await fixture.store.updateTransform(pages[0].id, to: cropped)

        let plain = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { plain.removeTemporaryFiles() }
        let result = try await compress(fixture, item, pages, original, .strong)
        defer { result.output.removeTemporaryFiles() }

        #expect(result.compressedByteCount < plain.totalByteCount,
                "compressed \(result.compressedByteCount) vs plain \(plain.totalByteCount)")
        let document = try #require(PDFDocument(url: result.output.files[0]))
        #expect(try #require(document.page(at: 0)).bounds(for: .mediaBox).width < 612,
                "the crop was lost")
    }

    /// A page too large to rasterize must be left alone, not fail the whole
    /// export: it used to compress by being copied, and that has to keep
    /// working. 8000pt square at Light's 300 dpi is about 1.1 billion pixels,
    /// well past the 100M cap `rasterizePDFPage` enforces.
    @Test func aPageTooLargeToRasterizeIsLeftAloneRatherThanFailing() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.scannedPDF(size: CGSize(width: 8000, height: 8000)), name: "Huge"))
        let pages = try await fixture.store.pages(of: item.id)
        let original = try await fixture.store.originalByteCount(of: item.id)

        let plain = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { plain.removeTemporaryFiles() }
        let result = try await compress(fixture, item, pages, original, .light)
        defer { result.output.removeTemporaryFiles() }

        #expect(result.compressedByteCount <= plain.totalByteCount)
        #expect(try #require(PDFDocument(url: result.output.files[0])).pageCount == 1)
    }

    @Test func compressingChangesNothingInTheLibrary() async throws {
        let fixture = try ExportFixture()
        let (item, pages, original) = try await scannedDocument(fixture)
        let revisions = pages.map(\.revision)

        let result = try await compress(fixture, item, pages, original, .strong)
        defer { result.output.removeTemporaryFiles() }

        // Compression is an export, not an edit: originals are immutable.
        #expect(try await fixture.store.item(item.id)?.modifiedAt == item.modifiedAt)
        #expect(try await fixture.store.pages(of: item.id).map(\.revision) == revisions)
        #expect(try await fixture.store.originalByteCount(of: item.id) == original)
    }

    @Test func theOutputLeavesNothingBehindOnceRemoved() async throws {
        let fixture = try ExportFixture()
        let (item, pages, original) = try await scannedDocument(fixture)

        let result = try await compress(fixture, item, pages, original, .strong)
        let directory = result.output.directory
        #expect(FileManager.default.fileExists(atPath: directory.path))

        result.output.removeTemporaryFiles()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func reportsTheSavingItActuallyMade() async throws {
        let fixture = try ExportFixture()
        let (item, pages, original) = try await scannedDocument(fixture)

        let result = try await compress(fixture, item, pages, original, .smallest)
        defer { result.output.removeTemporaryFiles() }

        #expect(result.originalByteCount == original)
        #expect(result.preset == .smallest)
        if result.isSmaller {
            #expect(result.savedByteCount == original - result.compressedByteCount)
        } else {
            #expect(result.savedByteCount == 0)
        }
    }
}

/// F2d, continued: reducing a photo that is kept as a file rather than as a
/// document page. This is the everyday case — getting a picture under a size
/// limit — and the one where "already compressed" is the normal input.
@Suite struct FileCompressionTests {
    private func compress(_ data: Data, _ preset: CompressionPreset,
                          named name: String = "photo.png") async throws -> CompressionResult {
        let fixture = try ExportFixture()
        return try await fixture.exporter.compress(fileNamed: name, data: data, preset: preset)
    }

    @Test func aStrongerPresetProducesASmallerFile() async throws {
        let photo = SyntheticDocuments.textImage(lines: Array(repeating: "Receipt 1234", count: 30),
                                                 width: 3000, height: 2000)

        let light = try await compress(photo, .light)
        defer { light.output.removeTemporaryFiles() }
        let strong = try await compress(photo, .strong)
        defer { strong.output.removeTemporaryFiles() }
        let smallest = try await compress(photo, .smallest)
        defer { smallest.output.removeTemporaryFiles() }

        #expect(strong.compressedByteCount < light.compressedByteCount,
                "strong \(strong.compressedByteCount) should beat light \(light.compressedByteCount)")
        #expect(smallest.compressedByteCount < strong.compressedByteCount,
                "smallest \(smallest.compressedByteCount) should beat strong \(strong.compressedByteCount)")
    }

    @Test func theOutputIsAnImageWithFewerPixelsThanItStartedWith() async throws {
        let photo = SyntheticDocuments.textImage(lines: ["Receipt"], width: 3000, height: 2000)

        let result = try await compress(photo, .smallest)
        defer { result.output.removeTemporaryFiles() }

        let written = try Data(contentsOf: result.output.files[0])
        let image = try #require(PixelProbe.decode(written))
        #expect(image.width < 3000, "a stronger preset has to actually reduce the resolution")
        #expect(image.width > 0)
        // Aspect ratio is kept; nothing is cropped to hit a size.
        #expect(abs(Double(image.width) / Double(image.height) - 1.5) < 0.02)
    }

    @Test func theSavingReportedIsNeverNegativeAndAlwaysMatchesTheBytes() async throws {
        // Most photos arrive already compressed, so re-encoding often makes
        // them bigger. Whatever happens, the numbers have to agree.
        let flat = SyntheticDocuments.image(width: 1200, height: 1600, type: .png)

        let result = try await compress(flat, .light)
        defer { result.output.removeTemporaryFiles() }

        #expect(result.originalByteCount == Int64(flat.count))
        #expect(result.savedByteCount >= 0)
        #expect(result.isSmaller == (result.compressedByteCount < result.originalByteCount))
        if !result.isSmaller { #expect(result.savedByteCount == 0) }
    }

    /// What a scanner produces, as a loose file rather than a document.
    private static let scanRaster = SyntheticDocuments.textImage(
        lines: Array(repeating: "Invoice total 1234 EUR", count: 20), width: 1600, height: 2000)

    /// A PDF kept as a file used to be refused outright, on the grounds that
    /// shrinking one destroys selectable text. That is only true of pages that
    /// *have* text.
    @Test func aScannedPDFFileIsReducedRatherThanRefused() async throws {
        let data = SyntheticDocuments.scannedPDF(pages: 2, raster: Self.scanRaster)

        let result = try await compress(data, .smallest, named: "scan.pdf")
        defer { result.output.removeTemporaryFiles() }

        #expect(result.isSmaller,
                "\(result.compressedByteCount) is not smaller than \(data.count)")
        #expect(result.output.files[0].pathExtension == "pdf")
        let document = try #require(PDFDocument(url: result.output.files[0]))
        #expect(document.pageCount == 2)

        // A blank page is the smallest file of all, and `isSmaller` alone
        // cannot tell a reduction from a page that lost its content — this
        // test passed at 869 bytes from a 193 KB scan before the rebuilt
        // page's document was kept alive long enough to be serialized.
        let rendered = try #require(PixelProbe.renderPDFPage(try Data(contentsOf: result.output.files[0]), index: 0))
        #expect(PixelProbe.grayLevels(rendered).count > 8,
                "the page came back blank, not compressed")
        #expect(result.compressedByteCount > Int64(Double(data.count) * 0.1),
                "\(result.compressedByteCount) from \(data.count) is too good to be a re-encode")
    }

    /// The refusal's reasoning, kept where it is true: a digital PDF's pages
    /// carry real text, so they are copied rather than rasterized. It comes
    /// back readable, and reports no saving rather than a fake one.
    @Test func aDigitalPDFFileKeepsItsTextAndReportsNoSaving() async throws {
        let data = SyntheticDocuments.textPDF(pages: ["Council tax notice"])

        let result = try await compress(data, .smallest, named: "notice.pdf")
        defer { result.output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(url: result.output.files[0]))
        #expect(document.page(at: 0)?.string?.contains("Council") == true)
        #expect(result.isSmaller == false)
        #expect(result.savedByteCount == 0)
    }

    @Test func aPDFFileKeepsItsPagesInOrder() async throws {
        let data = SyntheticDocuments.textPDF(pages: ["First page", "Second page", "Third page"])

        let result = try await compress(data, .strong, named: "notes.pdf")
        defer { result.output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(url: result.output.files[0]))
        #expect(document.pageCount == 3)
        #expect(document.page(at: 0)?.string?.contains("First") == true)
        #expect(document.page(at: 1)?.string?.contains("Second") == true)
        #expect(document.page(at: 2)?.string?.contains("Third") == true)
    }

    /// Light is 300 dpi and upsamples most scans. On the document path, before
    /// the size rule existed, that turned a 193 KB page into 416 KB. The same
    /// rule applies here, so Light declines and the page is kept as it is.
    @Test func aPresetThatWouldEnlargeAPDFFileLeavesItsPagesAlone() async throws {
        let data = SyntheticDocuments.scannedPDF(raster: Self.scanRaster)

        let result = try await compress(data, .light, named: "scan.pdf")
        defer { result.output.removeTemporaryFiles() }

        #expect(result.compressedByteCount <= Int64(Double(data.count) * 1.1),
                "light ballooned the file: \(result.compressedByteCount) from \(data.count)")
    }

    /// Measured, not assumed: a locked document hands back no text, so every
    /// page looked like a scan, the locked `CGPDFDocument` drew nothing, and
    /// the white page beat the budget — 845 bytes from 8,110, one grey level.
    /// A blank sheet reported as a 99% saving.
    @Test func anEncryptedPDFIsRefusedRatherThanReturnedBlank() async throws {
        let fixture = try ExportFixture()
        let data = SyntheticDocuments.encryptedPDF(text: "Secret memo", password: "hunter2")

        await #expect(throws: CompressionError.unsupportedFormat) {
            try await fixture.exporter.compress(fileNamed: "secret.pdf", data: data, preset: .smallest)
        }
    }

    /// An owner password restricts copying while the document still opens.
    /// Assembling the output fresh drops that restriction, so compressing one
    /// would hand back an unrestricted copy of a document whose author asked
    /// for the opposite. Refused until it can be preserved.
    @Test func aRestrictedPDFIsRefusedRatherThanStrippedOfItsRestrictions() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRestricted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try ExportFixture()
        let exporter = Exporter(renderer: PageRenderer(store: fixture.store), temporaryRoot: root)

        await #expect(throws: CompressionError.unsupportedFormat) {
            try await exporter.compress(fileNamed: "restricted.pdf",
                                        data: SyntheticDocuments.restrictedPDF(), preset: .smallest)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty,
                "a refusal must not leave a directory behind")
    }

    /// A landscape phone scan is a portrait media box with `/Rotate 90`.
    /// Sizing the re-encoded page from PDFKit's media box ignores that and
    /// squeezes 792×612 of content into a portrait page: the input rendered
    /// 396×306 and the output came back 306×396.
    @Test func aRotatedScannedPageKeepsItsOrientation() async throws {
        let data = SyntheticDocuments.scannedPDF(raster: Self.scanRaster)
        let document = try #require(PDFDocument(data: data))
        try #require(document.page(at: 0)).rotation = 90
        let rotated = try #require(document.dataRepresentation())
        let before = try #require(PixelProbe.renderPDFPage(rotated, index: 0))
        #expect(before.width > before.height, "precondition: the input must render landscape")

        let result = try await compress(rotated, .strong, named: "rotated.pdf")
        defer { result.output.removeTemporaryFiles() }

        let after = try #require(PixelProbe.renderPDFPage(try Data(contentsOf: result.output.files[0]), index: 0))
        #expect(after.width > after.height,
                "the page came back portrait: \(after.width)x\(after.height)")
        #expect(PixelProbe.grayLevels(after).count > 8, "the page came back blank")
    }

    @Test func bytesThatAreNotAnImageAreRefusedRatherThanMangled() async throws {
        let fixture = try ExportFixture()

        await #expect(throws: CompressionError.unsupportedFormat) {
            try await fixture.exporter.compress(fileNamed: "notes.txt",
                                                data: Data("just some text".utf8), preset: .strong)
        }
    }

    @Test func aRefusedFileLeavesNoTemporaryDirectoryBehind() async throws {
        // An exporter with a temporary root of its own, because the shared one
        // is the process-wide temporary directory and sibling tests create and
        // remove their own directories in it while this runs. Counting entries
        // there would measure them, not this.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRefusal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fixture = try ExportFixture()
        let exporter = Exporter(renderer: PageRenderer(store: fixture.store), temporaryRoot: root)

        await #expect(throws: CompressionError.unsupportedFormat) {
            try await exporter.compress(fileNamed: "clip.mov", data: Data("not a movie either".utf8), preset: .strong)
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty,
                "a refusal must not leave a directory behind")
    }

    @Test func theOutputLeavesNothingBehindOnceRemoved() async throws {
        let photo = SyntheticDocuments.textImage(lines: ["Receipt"], width: 1200, height: 900)

        let result = try await compress(photo, .strong)
        let directory = result.output.directory
        #expect(FileManager.default.fileExists(atPath: directory.path))

        result.output.removeTemporaryFiles()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    /// Row 35's image-format remainder. JPEG stays the default because
    /// compression exists to make a file easier to send, and a HEIC the
    /// recipient cannot open is a worse outcome than a larger JPEG.
    @Test func theDefaultOutputIsStillJPEG() async throws {
        let photo = SyntheticDocuments.textImage(lines: Array(repeating: "Receipt 1234", count: 30),
                                                 width: 3000, height: 2000)

        let result = try await compress(photo, .strong)
        defer { result.output.removeTemporaryFiles() }

        #expect(result.output.files[0].pathExtension == "jpg")
        let data = try Data(contentsOf: result.output.files[0])
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    /// The point of offering it: the same photo, the same preset, a third of
    /// the bytes. The name is not the evidence — the bytes are, the same trap
    /// `writeImages` had.
    @Test func askingForHEICGivesARealHEICAndASmallerFile() async throws {
        let photo = SyntheticDocuments.textImage(lines: Array(repeating: "Receipt 1234", count: 30),
                                                 width: 3000, height: 2000)
        let fixture = try ExportFixture()

        let asJPEG = try await fixture.exporter.compress(fileNamed: "photo.png", data: photo, preset: .strong)
        defer { asJPEG.output.removeTemporaryFiles() }
        let asHEIC = try await fixture.exporter.compress(fileNamed: "photo.png", data: photo,
                                                         preset: .strong, format: .heic)
        defer { asHEIC.output.removeTemporaryFiles() }

        #expect(asHEIC.output.files[0].pathExtension == "heic")
        let data = try Data(contentsOf: asHEIC.output.files[0])
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier,
                "the bytes are not HEIC")
        #expect(asHEIC.compressedByteCount < asJPEG.compressedByteCount,
                "heic \(asHEIC.compressedByteCount) vs jpeg \(asJPEG.compressedByteCount)")
    }

    /// Choosing a format changes the output, not the honesty rules.
    @Test func bytesThatAreNotAnImageAreStillRefusedWhateverTheFormat() async throws {
        let fixture = try ExportFixture()

        await #expect(throws: CompressionError.unsupportedFormat) {
            try await fixture.exporter.compress(fileNamed: "notes.txt", data: Data("just some text".utf8),
                                                preset: .strong, format: .heic)
        }
    }
}
