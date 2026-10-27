import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// Row 32's export half. Added after measuring, not after assuming: unlike
/// WebP, ImageIO's HEIC support is symmetric — `public.heic` appears among the
/// types it writes as well as the ones it reads.
@Suite struct HEICExportTests {
    private func photoPage(_ fixture: ExportFixture) async throws -> (PaperNestCore.LibraryItem, [Page]) {
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textImage(lines: Array(repeating: "Invoice total 1234 EUR", count: 20),
                                               width: 1600, height: 2000), name: "Scan"))
        return (item, try await fixture.store.pages(of: item.id))
    }

    private func export(_ fixture: ExportFixture, _ item: PaperNestCore.LibraryItem, _ pages: [Page],
                        _ format: ExportFormat) async throws -> ExportOutput {
        try await fixture.exporter.export(itemName: item.name, pages: pages,
                                          options: ExportOptions(format: format, imageDPI: 200, jpegQuality: 0.85))
    }

    /// The trap this slice had to avoid: `writeImages` chose
    /// `format == .jpeg ? .jpeg : .png`, so a new case would have written PNG
    /// bytes into a file named `.heic`. The name is not the evidence — the
    /// bytes are.
    @Test func theFileIsReallyHEICAndNotPNGWearingTheExtension() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await photoPage(fixture)

        let output = try await export(fixture, item, pages, .heic)
        defer { output.removeTemporaryFiles() }

        #expect(output.files[0].pathExtension == "heic")
        let data = try Data(contentsOf: output.files[0])
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let type = try #require(CGImageSourceGetType(source) as String?)
        #expect(type == UTType.heic.identifier, "the bytes are \\(type)")
    }

    @Test func itDecodesBackToThePageAtTheRequestedResolution() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await photoPage(fixture)

        let output = try await export(fixture, item, pages, .heic)
        defer { output.removeTemporaryFiles() }

        let data = try Data(contentsOf: output.files[0])
        let image = try #require(PixelProbe.decode(data))
        #expect(image.width > 100 && image.height > 100)
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect((props[kCGImagePropertyDPIWidth] as? NSNumber)?.intValue == 200, "the dpi asked for was lost")
    }

    /// The reason to offer it at all. Measured on this fixture: HEIC 94,742
    /// bytes against PNG 209,699 and JPEG 284,377.
    @Test func itIsMateriallySmallerThanPNGForTheSamePage() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await photoPage(fixture)

        let heic = try await export(fixture, item, pages, .heic)
        defer { heic.removeTemporaryFiles() }
        let png = try await export(fixture, item, pages, .png)
        defer { png.removeTemporaryFiles() }

        #expect(heic.totalByteCount < png.totalByteCount / 2,
                "heic \\(heic.totalByteCount) vs png \\(png.totalByteCount)")
    }

    /// Adding a format must not disturb the ones already shipped.
    @Test(arguments: [ExportFormat.pdf, .jpeg, .png])
    func theExistingFormatsAreUnchanged(_ format: ExportFormat) async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await photoPage(fixture)

        let output = try await export(fixture, item, pages, format)
        defer { output.removeTemporaryFiles() }

        #expect(output.files[0].pathExtension == format.fileExtension)
        #expect(output.totalByteCount > 0)
    }

    @Test func severalPagesStillPackageAsAZip() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["One", "Two", "Three"])

        let output = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .heic, packaging: .zip))
        defer { output.removeTemporaryFiles() }

        #expect(output.files.count == 1)
        #expect(output.files[0].pathExtension == "zip")
        let listed = try unzip(["-Z1", output.files[0].path])
        #expect(listed.output.contains(".heic"), "the archive holds \\(listed.output)")
    }
}
