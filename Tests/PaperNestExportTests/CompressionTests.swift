import CoreGraphics
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
}
