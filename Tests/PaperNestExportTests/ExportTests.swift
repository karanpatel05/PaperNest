import CoreGraphics
import Foundation
import PDFKit
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

final class ExportFixture: @unchecked Sendable {
    let url: URL
    let store: LibraryStore
    let importer: DocumentImporter
    let exporter: Exporter

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestExportTests-\(UUID().uuidString)", isDirectory: true)
        store = try LibraryStore(directory: url)
        importer = DocumentImporter(store: store)
        exporter = Exporter(renderer: PageRenderer(store: store))
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func importPDF(_ pages: [String], size: CGSize = CGSize(width: 612, height: 792)) async throws -> (PaperNestCore.LibraryItem, [Page]) {
        let item = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: pages, size: size), name: "Doc"))
        return (item, try await store.pages(of: item.id))
    }
}

/// Runs `/usr/bin/unzip` as an independent check of archive validity.
func unzip(_ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return (process.terminationStatus, output)
}

@Suite struct PDFExportTests {
    @Test func preservesPageOrderSizesAndSelectableText() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["First page alpha", "Deuxième page — été", "Tercera página año"])
        let output = try await f.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        #expect(output.files.map(\.lastPathComponent) == ["Doc.pdf"])

        let pdf = try #require(PDFDocument(url: output.files[0]))
        #expect(pdf.pageCount == 3)
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 612, height: 792))
        // Vector content is copied, so text stays selectable, accented
        // characters included, and in the original order.
        #expect(pdf.page(at: 0)?.string?.contains("First page alpha") == true)
        #expect(pdf.page(at: 1)?.string?.contains("Deuxième page — été") == true)
        #expect(pdf.page(at: 2)?.string?.contains("Tercera página año") == true)
        #expect(pdf.documentAttributes?[PDFDocumentAttribute.creatorAttribute] as? String == Brand.pdfCreator)
    }

    @Test func rotatedAndReorderedPagesExportUprightInTheNewOrder() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["Page A", "Page B"])
        try await f.store.updateTransform(pages[1].id, to: PageTransform(rotation: .clockwise90))
        try await f.store.movePage(pages[1].id, toIndex: 0)
        let current = try await f.store.pages(of: item.id)
        let output = try await f.exporter.export(itemName: item.name, pages: current, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        let data = try Data(contentsOf: output.files[0])
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.page(at: 0)?.string?.contains("Page B") == true)
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).size == CGSize(width: 792, height: 612))
        #expect(pdf.page(at: 1)?.string?.contains("Page A") == true)
        // The source's top-left marker sits top-right after a clockwise turn.
        let rendered = try #require(PixelProbe.renderPDFPage(data, index: 0))
        #expect(PixelProbe.pixel(rendered, x: 0.95, y: 0.08).isDark)
        #expect(PixelProbe.pixel(rendered, x: 0.05, y: 0.08).isWhite)
    }

    @Test(arguments: [PaperSize.usLetter, .a4])
    func fittingToPaperNeverCropsContent(paper: PaperSize) async throws {
        let f = try ExportFixture()
        // A long receipt-shaped page.
        let (item, pages) = try await f.importPDF(["Receipt"], size: CGSize(width: 300, height: 1200))
        let output = try await f.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .pdf, paperSize: paper))
        defer { output.removeTemporaryFiles() }
        let data = try Data(contentsOf: output.files[0])
        let pdf = try #require(PDFDocument(data: data))
        #expect(pdf.page(at: 0)?.bounds(for: .mediaBox).size == paper.portraitSize)
        #expect(pdf.page(at: 0)?.string?.contains("Receipt") == true)
        // The marker (top-left of the content) is still on the sheet,
        // horizontally centred content leaves white margins at the sides.
        let rendered = try #require(PixelProbe.renderPDFPage(data, index: 0, scale: 1))
        let layout = PaperLayout(pageSize: CGSize(width: 300, height: 1200), paper: paper)
        let markerX = (layout.contentRect.minX + 50 * layout.contentRect.width / 300) / layout.paperSize.width
        let markerY = (50 * layout.contentRect.height / 1200) / layout.paperSize.height
        #expect(PixelProbe.pixel(rendered, x: markerX, y: markerY).isDark)
        #expect(PixelProbe.pixel(rendered, x: 0.02, y: 0.5).isWhite)
    }

    @Test func lossyQualityEmbedsJPEGAndBestStaysLossless() async throws {
        let f = try ExportFixture()
        let item = try await f.importer.importItem(.data(SyntheticDocuments.image(width: 1200, height: 1600, type: .png), name: "Scan"))
        let pages = try await f.store.pages(of: item.id)
        var sizes: [PDFImageQuality: Int] = [:]
        for quality in PDFImageQuality.allCases {
            let output = try await f.exporter.export(itemName: "Scan", pages: pages, options: ExportOptions(format: .pdf, pdfImageQuality: quality))
            let data = try Data(contentsOf: output.files[0])
            sizes[quality] = data.count
            let usesDCT = data.range(of: Data("/DCTDecode".utf8)) != nil
            #expect(usesDCT == (quality != .best), "quality \(quality)")
            #expect(PDFDocument(data: data)?.pageCount == 1)
            output.removeTemporaryFiles()
        }
        #expect(sizes[.compact]! < sizes[.balanced]!)
    }

    @Test func tightlyCroppedFilteredPDFPageExportsToPaper() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["Crop me"])
        try await f.store.updateTransform(pages[0].id, to: PageTransform(
            crop: NormalizedRect(x: 0, y: 0, width: 0.25, height: 0.25), filter: .grayscale))
        let current = try await f.store.pages(of: item.id)
        for paper in [PaperSize.usLetter, .a4] {
            let output = try await f.exporter.export(itemName: item.name, pages: current,
                                                     options: ExportOptions(format: .pdf, paperSize: paper, pdfImageQuality: .balanced))
            defer { output.removeTemporaryFiles() }
            let data = try Data(contentsOf: output.files[0])
            let rendered = try #require(PixelProbe.renderPDFPage(data, index: 0, scale: 1))
            // The crop (a square) is fitted to the paper's width; its top-left
            // quarter-ish holds the gray marker.
            let marker = PixelProbe.pixel(rendered, x: 0.2, y: 0.3)
            #expect(marker.isDark && marker.isGray, "\(paper): \(marker)")
        }
    }

    @Test func cancellationStopsAndRemovesPartialOutput() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(Array(repeating: "Page", count: 40))
        let root = f.url.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let exporter = Exporter(renderer: f.exporter.renderer, temporaryRoot: root)
        let started = AsyncStream<Void>.makeStream()
        let task = Task {
            try await exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .png, imageDPI: 150)) { progress in
                if progress.completedPages == 2 { started.continuation.yield() }
            }
        }
        for await _ in started.stream { break }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }
}

@Suite(.serialized) struct ImageExportTests {
    @Test func multiplePagesGoIntoAValidNumberedZip() async throws {
        let f = try ExportFixture()
        let (_, pages) = try await f.importPDF(["1", "2", "3"])
        let output = try await f.exporter.export(itemName: "Relevé: mars/avril", pages: pages,
                                                 options: ExportOptions(format: .jpeg, imageDPI: 72, packaging: .zip))
        defer { output.removeTemporaryFiles() }
        #expect(output.files.map(\.lastPathComponent) == ["Relevé- mars-avril.zip"])
        let test = try unzip(["-t", output.files[0].path])
        #expect(test.status == 0, "\(test.output)")
        // `unzip -Z1` prints non-ASCII names as "??", so extract and list.
        let extracted = f.url.appendingPathComponent("unzipped", isDirectory: true)
        #expect(try unzip(["-q", output.files[0].path, "-d", extracted.path]).status == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: extracted.path).sorted() ==
                ["Relevé- mars-avril-001.jpg", "Relevé- mars-avril-002.jpg", "Relevé- mars-avril-003.jpg"])
        #expect(output.totalByteCount > 0)
    }

    @Test func separateFilesHavePageSizedPixelsAndResolution() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["1", "2"])
        let output = try await f.exporter.export(itemName: item.name, pages: pages,
                                                 options: ExportOptions(format: .png, imageDPI: 150, packaging: .separateFiles))
        defer { output.removeTemporaryFiles() }
        #expect(output.files.map(\.lastPathComponent) == ["Doc-001.png", "Doc-002.png"])
        let source = try #require(CGImageSourceCreateWithURL(output.files[0] as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 1275)  // 8.5 in × 150 dpi
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 1650)
        #expect((props[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue == 150)
    }

    @Test func singlePageUsesThePlainName() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["only"])
        let output = try await f.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .jpeg, imageDPI: 72))
        defer { output.removeTemporaryFiles() }
        #expect(output.files.map(\.lastPathComponent) == ["Doc.jpg"])
    }

    @Test func transparentOriginalsKeepDarkInkInJPEG() async throws {
        let f = try ExportFixture()
        let png = SyntheticDocuments.image(width: 400, height: 300, type: .png, transparentBackground: true)
        let item = try await f.importer.importItem(.data(png, name: "Ink"))
        let pages = try await f.store.pages(of: item.id)
        let output = try await f.exporter.export(itemName: "Ink", pages: pages, options: ExportOptions(format: .jpeg, imageDPI: 72))
        defer { output.removeTemporaryFiles() }
        let image = try #require(PixelProbe.decode(try Data(contentsOf: output.files[0])))
        #expect(PixelProbe.pixel(image, x: 0.8, y: 0.2).isWhite)   // background flattened to white
        #expect(PixelProbe.pixel(image, x: 0.5, y: 0.5).isDark)    // the ink stroke survives
        #expect(PixelProbe.pixel(image, x: 0.05, y: 0.05).isRed)
    }

    @Test func exportLeavesTheLibraryUnchanged() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["x", "y"])
        let before = try await f.store.pages(of: item.id)
        let output = try await f.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .png, imageDPI: 72))
        output.removeTemporaryFiles()
        #expect(try await f.store.pages(of: item.id) == before)
        #expect(try await f.store.item(item.id)?.modifiedAt == item.modifiedAt)
    }
}

@Suite struct NamingAndZipTests {
    @Test func unsafeCharactersAreReplacedAndEmptyNamesFallBack() {
        #expect(ExportNaming.baseName("Q3/Q4: \"budget\"?") == "Q3-Q4- -budget--")
        #expect(ExportNaming.baseName("...") == "Document")
        #expect(ExportNaming.baseName("Año fiscal") == "Año fiscal")
        #expect(ExportNaming.numbered("Doc", index: 7, total: 12, ext: "png") == "Doc-007.png")
        #expect(ExportNaming.numbered("Doc", index: 42, total: 1500, ext: "png") == "Doc-0042.png")
    }

    @Test func crc32MatchesTheStandardCheckValue() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    @Test func zipWithUnicodeNamesExtractsByteForByte() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let archive = dir.appendingPathComponent("t.zip")
        let writer = try ZipWriter(url: archive)
        let payloads = ["été-001.txt": Data("bonjour".utf8), "año-002.bin": Data((0..<1000).map { UInt8($0 % 251) })]
        for name in payloads.keys.sorted() { try writer.addFile(named: name, data: payloads[name]!) }
        try writer.finish()
        let out = dir.appendingPathComponent("out", isDirectory: true)
        let result = try unzip(["-q", archive.path, "-d", out.path])
        #expect(result.status == 0, "\(result.output)")
        for (name, data) in payloads {
            #expect(try Data(contentsOf: out.appendingPathComponent(name)) == data)
        }
    }
}
