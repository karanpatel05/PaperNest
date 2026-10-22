import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
@testable import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestRender

/// A fresh library in a temporary directory, removed afterwards.
final class TestLibrary: @unchecked Sendable {
    let url: URL
    let store: LibraryStore
    let importer: DocumentImporter
    let renderer: PageRenderer

    init() throws {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestImportTests-\(UUID().uuidString)", isDirectory: true)
        store = try LibraryStore(directory: url)
        importer = DocumentImporter(store: store)
        renderer = PageRenderer(store: store)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func writeFile(_ data: Data, named name: String) throws -> URL {
        let dir = url.appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try data.write(to: file)
        return file
    }
}

@Suite struct PDFImportTests {
    @Test func importsEveryPageAsVectorPDFWithoutRasterizing() async throws {
        let lib = try TestLibrary()
        let data = SyntheticDocuments.textPDF(pages: ["One", "Deux", "Tres"], size: CGSize(width: 595, height: 842))
        let item = try await lib.importer.importItem(.file(try lib.writeFile(data, named: "Contract.pdf")))
        #expect(item.name == "Contract")
        let pages = try await lib.store.pages(of: item.id)
        #expect(pages.count == 3)
        #expect(pages.map(\.sourceSize) == Array(repeating: CGSize(width: 595, height: 842), count: 3))
        guard case .pdfPage(let asset, index: 0) = pages[0].content else {
            Issue.record("expected a PDF page, got \(pages[0].content)")
            return
        }
        // The stored original is byte-identical to the imported file.
        #expect(try await lib.store.assetData(asset).0 == data)
        #expect(pages.map(\.content) == [0, 1, 2].map { PageContent.pdfPage(asset, index: $0) })
    }

    @Test func rotatedPDFPagesAreStoredUpright() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.rotatedPDF(degrees: 90), name: "Rotated"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        #expect(page.sourceSize == CGSize(width: 792, height: 612))
        // Content drawn top-left on the unrotated page appears top-right once
        // the /Rotate 90 is honored.
        let image = try await lib.renderer.renderThumbnail(page, maxPixelSize: 400)
        #expect(PixelProbe.pixel(image, x: 0.95, y: 0.08).isDark)
        #expect(PixelProbe.pixel(image, x: 0.05, y: 0.08).isWhite)
    }

    @Test func passwordProtectedPDFNeedsTheRightPasswordAndIsStoredUnlocked() async throws {
        let lib = try TestLibrary()
        let data = SyntheticDocuments.encryptedPDF(text: "Confidential synthetic text", password: "s3cret")
        let source = DocumentImporter.Source.data(data, name: "Locked.pdf")
        await #expect(throws: ImportError.passwordRequired(filename: "Locked.pdf")) { try await lib.importer.importItem(source) }
        await #expect(throws: ImportError.incorrectPassword(filename: "Locked.pdf")) { try await lib.importer.importItem(source, password: "wrong") }
        #expect(try await lib.store.items(in: .all).isEmpty)

        let item = try await lib.importer.importItem(source, password: "s3cret")
        let page = try #require(try await lib.store.pages(of: item.id).first)
        let stored = try await lib.store.assetData(page.content.assetID!).0
        let document = try #require(CGDataProvider(data: stored as CFData).flatMap(CGPDFDocument.init))
        #expect(document.isUnlocked)
        // Nothing in the library holds the password.
        #expect(stored.range(of: Data("s3cret".utf8)) == nil)
    }

    @Test func pdfsWithAuthorRestrictionsAreDeclined() async throws {
        let lib = try TestLibrary()
        await #expect(throws: ImportError.restrictedPDF(filename: "Restricted.pdf")) {
            try await lib.importer.importItem(.data(SyntheticDocuments.restrictedPDF(), name: "Restricted.pdf"))
        }
        #expect(try await lib.store.items(in: .all).isEmpty)
    }

    @Test func damagedEmptyAndUnsupportedFilesAreRejectedWithoutSideEffects() async throws {
        let lib = try TestLibrary()
        let truncated = SyntheticDocuments.textPDF(pages: ["x"]).prefix(40)
        await #expect(throws: ImportError.damaged(filename: "Broken.pdf")) {
            try await lib.importer.importItem(.data(Data(truncated), name: "Broken.pdf"))
        }
        await #expect(throws: ImportError.empty(filename: "Empty.pdf")) {
            try await lib.importer.importItem(.data(Data(), name: "Empty.pdf"))
        }
        await #expect(throws: ImportError.unsupportedType(filename: "notes.txt")) {
            try await lib.importer.importItem(.file(try lib.writeFile(Data("plain text".utf8), named: "notes.txt")))
        }
        await #expect(throws: ImportError.unreadable(filename: "missing.pdf")) {
            try await lib.importer.importItem(.file(lib.url.appendingPathComponent("missing.pdf")))
        }
        #expect(try await lib.store.items(in: .all).isEmpty)
        #expect(try lib.store.assets.allFiles().isEmpty)
    }

    @Test func typeComesFromContentNotExtension() async throws {
        let lib = try TestLibrary()
        let png = SyntheticDocuments.image(width: 200, height: 300, type: .png)
        let item = try await lib.importer.importItem(.file(try lib.writeFile(png, named: "actually-png.pdf")))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        #expect(try await lib.store.assetRecord(page.content.assetID!)?.kind == .png)
    }

    @Test func duplicateFilenamesBecomeNumberedNames() async throws {
        let lib = try TestLibrary()
        let data = SyntheticDocuments.textPDF(pages: ["A"])
        let first = try await lib.importer.importItem(.file(try lib.writeFile(data, named: "Report.pdf")))
        let second = try await lib.importer.importItem(.file(try lib.writeFile(data, named: "Report.pdf")))
        #expect([first.name, second.name] == ["Report", "Report 2"])
        // Identical bytes are stored once.
        #expect(try lib.store.assets.allFiles().count == 1)
    }
}

@Suite struct ImageImportTests {
    @Test func exifOrientationIsAppliedSoPagesAreUpright() async throws {
        let lib = try TestLibrary()
        let jpeg = SyntheticDocuments.image(width: 600, height: 900, type: .jpeg, exifOrientation: 6)
        let item = try await lib.importer.importItem(.data(jpeg, name: "Receipt"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        // Upright is portrait 600×900 px → long edge normalized to 792 pt.
        #expect(abs(page.sourceSize.height - 792) < 0.01)
        #expect(abs(page.sourceSize.width - 528) < 0.01)
        let image = try await lib.renderer.renderThumbnail(page, maxPixelSize: 300)
        #expect(PixelProbe.pixel(image, x: 0.05, y: 0.05).isRed)
        #expect(PixelProbe.pixel(image, x: 0.95, y: 0.05).isWhite)
        #expect(PixelProbe.pixel(image, x: 0.05, y: 0.95).isWhite)
    }

    @Test func trustedResolutionSetsPhysicalSize() async throws {
        let lib = try TestLibrary()
        let png = SyntheticDocuments.image(width: 2550, height: 3300, type: .png, dpi: 300)
        let item = try await lib.importer.importItem(.data(png, name: "Letter scan"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        #expect(abs(page.sourceSize.width - 612) < 0.01 && abs(page.sourceSize.height - 792) < 0.01)
    }

    @Test func truncatedImagesAreRejected() async throws {
        let lib = try TestLibrary()
        let jpeg = SyntheticDocuments.image(width: 400, height: 400, type: .jpeg)
        await #expect(throws: ImportError.damaged(filename: "cut.jpg")) {
            try await lib.importer.importItem(.data(Data(jpeg.prefix(jpeg.count / 3)), name: "cut.jpg"))
        }
        let png = SyntheticDocuments.image(width: 400, height: 400, type: .png)
        await #expect(throws: ImportError.damaged(filename: "cut.png")) {
            try await lib.importer.importItem(.data(Data(png.prefix(png.count - 20)), name: "cut.png"))
        }
        // The intact files import fine.
        _ = try await lib.importer.importItem(.data(jpeg, name: "whole.jpg"))
        _ = try await lib.importer.importItem(.data(png, name: "whole.png"))
    }

    @Test func scanSessionBecomesOneDocumentInCaptureOrder() async throws {
        let lib = try TestLibrary()
        let shots = [
            SyntheticDocuments.image(width: 300, height: 400, type: .jpeg),
            SyntheticDocuments.image(width: 400, height: 300, type: .jpeg),
            SyntheticDocuments.image(width: 300, height: 300, type: .jpeg),
        ]
        let item = try await lib.importer.importScan(images: shots, name: "Scan")
        let pages = try await lib.store.pages(of: item.id)
        #expect(pages.count == 3)
        #expect(pages.map { $0.sourceSize.width > $0.sourceSize.height } == [false, true, false])
    }

    @Test func pagesCanBeAddedToAnExistingDocument() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["1", "2"]), name: "Doc"))
        let firstPage = try await lib.store.pages(of: item.id)[0]
        let added = try await lib.importer.insertPages(from: .data(SyntheticDocuments.image(width: 100, height: 100, type: .png), name: "photo"),
                                                       into: item.id, after: firstPage.id)
        let order = try await lib.store.pages(of: item.id).map(\.id)
        #expect(order.count == 3)
        #expect(order[1] == added[0].id)
    }
}

@Suite struct RenderTests {
    @Test func rotationAndCropMoveTheMarkerAsExpected() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.image(width: 500, height: 500, type: .png), name: "Square"))
        let page = try #require(try await lib.store.pages(of: item.id).first)

        let turned = try await lib.store.updateTransform(page.id, to: PageTransform(rotation: .clockwise90))
        let rotated = try await lib.renderer.renderThumbnail(turned, maxPixelSize: 200)
        #expect(PixelProbe.pixel(rotated, x: 0.95, y: 0.05).isRed)
        #expect(PixelProbe.pixel(rotated, x: 0.05, y: 0.05).isWhite)

        // Crop to the top-left quarter: the marker fills the page's corner.
        let cropped = try await lib.store.updateTransform(page.id, to: PageTransform(crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        #expect(cropped.geometry.pageSize.width == page.sourceSize.width / 2)
        let image = try await lib.renderer.renderThumbnail(cropped, maxPixelSize: 200)
        #expect(PixelProbe.pixel(image, x: 0.1, y: 0.1).isRed)
        #expect(PixelProbe.pixel(image, x: 0.9, y: 0.9).isWhite)
    }

    @Test func filtersProduceGrayAndPureBlackAndWhite() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.image(width: 300, height: 300, type: .jpeg), name: "Color"))
        let page = try #require(try await lib.store.pages(of: item.id).first)

        let gray = try await lib.store.updateTransform(page.id, to: PageTransform(filter: .grayscale))
        let grayImage = try await lib.renderer.renderThumbnail(gray, maxPixelSize: 150)
        #expect(PixelProbe.pixel(grayImage, x: 0.05, y: 0.05).isGray)

        // The filter output itself is strictly two-level; a scaled thumbnail
        // would add interpolated edge pixels, so check before scaling.
        let decoded = try #require(PixelProbe.decode(SyntheticDocuments.image(width: 300, height: 300, type: .jpeg)))
        let bwImage = ImageAdjustments.apply(PageTransform(filter: .blackAndWhite), to: decoded)
        #expect(PixelProbe.grayLevels(bwImage).isSubset(of: [0, 255]))
        #expect(PixelProbe.pixel(bwImage, x: 0.5, y: 0.5).isDark)
        #expect(PixelProbe.pixel(bwImage, x: 0.7, y: 0.2).isWhite)

        // Reverting restores the untouched original rendering.
        let original = try await lib.store.updateTransform(page.id, to: .identity)
        #expect(PixelProbe.pixel(try await lib.renderer.renderThumbnail(original, maxPixelSize: 150), x: 0.05, y: 0.05).isRed)
    }

    @Test func pdfPageWithFilterIsRasterizedButUnfilteredStaysVector() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["Vector"]), name: "V"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        guard case .pdf = try await lib.renderer.prepareSource(for: page, pixelsPerPoint: 1) else {
            Issue.record("unfiltered PDF page should draw as vector")
            return
        }
        let filtered = try await lib.store.updateTransform(page.id, to: PageTransform(filter: .grayscale))
        guard case .image = try await lib.renderer.prepareSource(for: filtered, pixelsPerPoint: 1) else {
            Issue.record("filtered PDF page should be rasterized")
            return
        }
    }

    /// A filter forces a PDF page to be rasterized; with a tight crop that
    /// raster must cover only the crop, or large renders exceed the pixel cap.
    @Test func tightlyCroppedFilteredPDFPageRendersAtLargeSizes() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["Crop me"]), name: "P"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        let edited = try await lib.store.updateTransform(page.id, to: PageTransform(
            crop: NormalizedRect(x: 0, y: 0, width: 0.25, height: 0.25), filter: .grayscale))
        let image = try await lib.renderer.renderThumbnail(edited, maxPixelSize: 3072)
        #expect(max(image.width, image.height) == 3072)
        // The source's top-left marker fills the crop's top-left, in gray.
        let marker = PixelProbe.pixel(image, x: 0.3, y: 0.3)
        #expect(marker.isDark && marker.isGray)
        #expect(PixelProbe.pixel(image, x: 0.9, y: 0.9).isWhite)
    }

    @Test func missingOriginalIsReportedNotDrawnBlank() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.image(width: 100, height: 100, type: .png), name: "Gone"))
        let page = try #require(try await lib.store.pages(of: item.id).first)
        let record = try #require(try await lib.store.assetRecord(page.content.assetID!))
        try FileManager.default.removeItem(at: lib.store.assets.url(for: record.id, kind: record.kind))
        await #expect(throws: RenderError.sourceUnavailable) { try await lib.renderer.renderThumbnail(page, maxPixelSize: 100) }
    }
}

/// Pass 7, step 1: ink drawn by the renderer that every display and export
/// path uses.
@Suite struct InkRenderTests {
    func stroke(_ tool: InkStroke.Tool = .pen, color: RGBAColor = .black, width: Double, _ points: [(Double, Double)]) -> InkStroke {
        InkStroke(tool: tool, color: color, width: width, points: points.map { InkPoint(x: $0.0, y: $0.1) })
    }

    func add(_ stroke: InkStroke, to page: Page, _ lib: TestLibrary) async throws -> Page {
        try await lib.store.saveObject(PageObject(pageID: page.id, zKey: "m", payload: .ink(stroke), modifiedAt: Date()))
        return try #require(try await lib.store.page(page.id))
    }

    func squarePage(_ lib: TestLibrary) async throws -> Page {
        let item = try await lib.importer.importItem(.data(SyntheticDocuments.image(width: 500, height: 500, type: .png), name: "Square"))
        return try #require(try await lib.store.pages(of: item.id).first)
    }

    @Test func penInkFollowsRotationAndCropAndRefreshesTheRevision() async throws {
        let lib = try TestLibrary()
        let page = try await squarePage(lib)
        // Near the source's top-right corner; the red marker is top-left.
        // Coordinates are fractions of the page: image point size follows DPI.
        let side = page.sourceSize.width
        let inked = try await add(stroke(width: 0.06 * side, [(0.76 * side, 0.12 * side), (0.92 * side, 0.12 * side)]), to: page, lib)
        #expect(inked.revision == page.revision + 1, "thumbnails are keyed by revision")

        let plain = try await lib.renderer.renderThumbnail(inked, maxPixelSize: 200)
        #expect(PixelProbe.pixel(plain, x: 0.84, y: 0.12).isDark)
        // The ink editor asks for the page without its ink.
        let contentOnly = try await lib.renderer.renderThumbnail(inked, maxPixelSize: 200, includingInk: false)
        #expect(PixelProbe.pixel(contentOnly, x: 0.84, y: 0.12).isWhite)

        // Clockwise: the source's top-right lands at the page's bottom-right.
        let turned = try await lib.store.updateTransform(page.id, to: PageTransform(rotation: .clockwise90))
        let rotated = try await lib.renderer.renderThumbnail(turned, maxPixelSize: 200)
        #expect(PixelProbe.pixel(rotated, x: 0.88, y: 0.84).isDark)
        #expect(PixelProbe.pixel(rotated, x: 0.6, y: 0.84).isWhite)

        // A crop that leaves the stroke out hides it.
        let cropped = try await lib.store.updateTransform(page.id, to: PageTransform(crop: NormalizedRect(x: 0, y: 0, width: 0.6, height: 0.5)))
        let croppedImage = try await lib.renderer.renderThumbnail(cropped, maxPixelSize: 200)
        #expect(PixelProbe.pixel(croppedImage, x: 0.95, y: 0.24).isWhite)
        #expect(PixelProbe.pixel(croppedImage, x: 0.1, y: 0.1).isRed)
    }

    @Test func highlighterLetsThePageShowThrough() async throws {
        let lib = try TestLibrary()
        let page = try await squarePage(lib)
        let yellow = RGBAColor(red: 1, green: 1, blue: 0)
        let side = page.sourceSize.width
        let inked = try await add(stroke(.highlighter, color: yellow, width: 0.08 * side, [(0.04 * side, 0.1 * side), (0.6 * side, 0.1 * side)]),
                                  to: page, lib)
        let image = try await lib.renderer.renderThumbnail(inked, maxPixelSize: 250)
        // Multiplied over the red marker it stays red; painted normally the
        // green channel would rise to about 90.
        #expect(PixelProbe.pixel(image, x: 0.1, y: 0.1).isRed)
        // Over white paper: a light yellow tint, not opaque yellow.
        let tint = PixelProbe.pixel(image, x: 0.4, y: 0.1)
        #expect(!tint.isWhite && tint.r > 230 && tint.g > 230 && tint.b > 120 && tint.b < 200, "\(tint)")
    }

    @Test func penWidthFollowsEachPointWithinLimits() {
        let pen = InkStroke(tool: .pen, color: .black, width: 4, points: [])
        #expect(pen.width(at: InkPoint(x: 0, y: 0)) == 4)
        #expect(pen.width(at: InkPoint(x: 0, y: 0, widthScale: 0.5)) == 2)
        #expect(pen.width(at: InkPoint(x: 0, y: 0, widthScale: 0)) == 0.2)
        #expect(pen.width(at: InkPoint(x: 0, y: 0, widthScale: 10)) == 16)
    }
}
