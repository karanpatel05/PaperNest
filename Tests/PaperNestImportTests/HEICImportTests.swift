import CoreGraphics
import ImageIO
import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestImport

/// F2c: photos from the system library are usually HEIC. Claiming support for
/// a format means proving this platform can read it, so these tests encode a
/// real HEIC and put it through the importer rather than mocking anything.
@Suite struct HEICImportTests {
    @Test func thePlatformReallyEncodesAndDecodesHEIC() throws {
        let data = SyntheticDocuments.image(width: 64, height: 32, type: .heic)
        #expect(!data.isEmpty, "ImageIO refused to write HEIC on this machine")
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.heic.identifier)
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(image.width == 64 && image.height == 32)
    }

    @Test func aHEICPhotoBecomesAPageWithTheSizeItsResolutionImplies() async throws {
        let library = try TestLibrary()
        // 300 dpi over 600×900 pixels is a 2×3 inch page: 144×216 points.
        let data = SyntheticDocuments.image(width: 600, height: 900, type: .heic, dpi: 300)
        let item = try await library.importer.importItem(.data(data, name: "Photo.heic"))
        let pages = try await library.store.pages(of: item.id)
        #expect(pages.count == 1)
        #expect(item.kind == .document, "a photo is something you can crop and export, not an opaque file")
        #expect(abs(pages[0].sourceSize.width - 144) < 1)
        #expect(abs(pages[0].sourceSize.height - 216) < 1)
        let asset = try #require(pages[0].content.assetID)
        #expect(try await library.store.assetRecord(asset)?.kind == .heic)
    }

    @Test func theTypeComesFromTheBytesNotTheName() async throws {
        let library = try TestLibrary()
        let data = SyntheticDocuments.image(width: 100, height: 100, type: .heic)
        #expect(FileTypeSniffer.kind(of: data) == .heic)
        // Misleading name, honest content.
        let item = try await library.importer.importItem(.data(data, name: "notes.txt"))
        let pages = try await library.store.pages(of: item.id)
        let asset = try #require(pages.first?.content.assetID)
        #expect(try await library.store.assetRecord(asset)?.kind == .heic)
    }

    @Test func aTruncatedHEICIsRejectedRatherThanImportedHalfBlank() async throws {
        let library = try TestLibrary()
        let whole = SyntheticDocuments.image(width: 400, height: 400, type: .heic)
        let truncated = whole.prefix(whole.count * 2 / 3)
        // It still sniffs as HEIC: the header is intact, the file is not.
        #expect(FileTypeSniffer.kind(of: Data(truncated)) == .heic)
        await #expect(throws: ImportError.damaged(filename: "cut.heic")) {
            try await library.importer.importItem(.data(Data(truncated), name: "cut.heic"))
        }
        #expect(try await library.store.items(in: .all).isEmpty)
    }

    /// Other ISO-BMFF formats share the container but not the codec. We do not
    /// claim what we have not verified.
    @Test func aNonHEICBrandInTheSameContainerIsNotClaimed() {
        var bytes: [UInt8] = [0, 0, 0, 0x20]
        bytes.append(contentsOf: Array("ftyp".utf8))
        bytes.append(contentsOf: Array("avif".utf8))
        bytes.append(contentsOf: [UInt8](repeating: 0, count: 20))
        #expect(FileTypeSniffer.kind(of: Data(bytes)) == nil)
        #expect(!FileTypeSniffer.isHEIC(bytes))

        var heic = bytes
        heic.replaceSubrange(8..<12, with: Array("heic".utf8))
        #expect(FileTypeSniffer.isHEIC(heic))
    }

    @Test func aHEICPageExportsLikeAnyOther() async throws {
        let library = try TestLibrary()
        let data = SyntheticDocuments.image(width: 300, height: 200, type: .heic, dpi: 150)
        let item = try await library.importer.importItem(.data(data, name: "Wide.heic"))
        let pages = try await library.store.pages(of: item.id)
        // Rendering is what export and thumbnails both go through.
        let rendered = try await library.renderer.renderImage(pages[0], pixelsPerPoint: 2)
        #expect(rendered.width > 0 && rendered.height > 0)
        #expect(rendered.width > rendered.height, "a landscape photo should render landscape")
    }
}
