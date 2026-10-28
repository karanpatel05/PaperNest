import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// Row 21's placed images, on the way out of the app.
///
/// The fixture image is white with a **red square across its top-left fifth**,
/// so a probe just inside the placed frame's corner says whether the image
/// reached the exported file, and where.
@Suite struct PlacedImageExportTests {
    /// Where the image goes, in upright source points on a 612×792 page.
    private let frame = CGRect(x: 306, y: 396, width: 200, height: 200)
    /// Inside the frame's red corner — source (318, 408).
    private let inRedCorner = (x: 0.52, y: 0.515)

    private func importedWithAPlacedImage(_ fixture: ExportFixture)
        async throws -> (PaperNestCore.LibraryItem, [Page]) {
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Statement"]), name: "Statement"))
        let stampItem = try await fixture.importer.importItem(
            .data(SyntheticDocuments.image(width: 200, height: 200, type: .png), name: "Stamp"))
        let stamp = try #require(try await fixture.store.pages(of: stampItem.id)[0].content.assetID)
        let pages = try await fixture.store.pages(of: item.id)
        try await fixture.store.saveObject(PageObject(
            pageID: pages[0].id, zKey: "m",
            payload: .image(PlacedImage(assetID: stamp, frame: frame)),
            modifiedAt: Date()))
        return (item, pages)
    }

    /// **The trap this closes.** The page is an unedited PDF page at its
    /// original paper size with no ink and no text layer, so pass-through
    /// would copy it straight from its source file — and the placed image,
    /// which exists nowhere in that source, would be gone from the export
    /// without a word. Anything painted over a page has to stand pass-through
    /// down.
    @Test func aPageCarryingAPlacedImageIsDrawnRatherThanCopied() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importedWithAPlacedImage(fixture)

        let output = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original))
        defer { output.removeTemporaryFiles() }

        let rendered = try #require(PixelProbe.renderPDFPage(
            try Data(contentsOf: output.files[0]), index: 0, scale: 1))
        let pixel = PixelProbe.pixel(rendered, x: inRedCorner.x, y: inRedCorner.y)
        #expect(pixel.r > 200 && pixel.g < 80 && pixel.b < 80,
                "the placed image is not in the exported PDF: \(pixel)")
    }

    /// The same page exported as an image goes through the renderer, so this
    /// would only fail if the two paths disagreed.
    @Test func aPlacedImageIsInAnExportedImageToo() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importedWithAPlacedImage(fixture)

        let output = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .png, paperSize: .original))
        defer { output.removeTemporaryFiles() }

        let rendered = try #require(PixelProbe.decode(try Data(contentsOf: output.files[0])))
        let pixel = PixelProbe.pixel(rendered, x: inRedCorner.x, y: inRedCorner.y)
        #expect(pixel.r > 200 && pixel.g < 80 && pixel.b < 80,
                "the placed image is not in the exported image: \(pixel)")
    }
}
