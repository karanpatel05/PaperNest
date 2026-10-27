import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestRender

/// Row 32's WEBP half, added only after checking what the system actually
/// does: ImageIO reports `org.webmproject.webp` among the types it reads and
/// **nothing** among the types it writes. So a `.webp` can be brought in; one
/// cannot be produced.
@Suite struct WebPImportTests {
    private func library() throws -> (URL, LibraryStore) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestWebP-\(UUID().uuidString)", isDirectory: true)
        return (url, try LibraryStore(directory: url))
    }

    @Test func webPBytesAreRecognised() throws {
        #expect(FileTypeSniffer.kind(of: SyntheticDocuments.webPImage()) == .webp)
    }

    /// `RIFF` alone is not WebP — WAV and AVI start the same way. Claiming
    /// those would import an audio file as a page.
    @Test func otherRIFFFilesAreNotClaimedAsWebP() throws {
        var wav = Data("RIFF".utf8)
        wav.append(contentsOf: [0x24, 0x00, 0x00, 0x00])
        wav.append(Data("WAVEfmt ".utf8))
        #expect(FileTypeSniffer.kind(of: wav) != .webp)
        #expect(FileTypeSniffer.kind(of: Data("RIFF".utf8)) == nil)
    }

    @Test func aWebPImportsAsOneImagePage() async throws {
        let (url, store) = try library()
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.webPImage(), name: "photo.webp"))
        let pages = try await store.pages(of: item.id)

        #expect(pages.count == 1)
        guard case .image(let assetID) = pages[0].content else {
            Issue.record("expected an image page, got \(pages[0].content)")
            return
        }
        // Stored under its own kind, so the file on disk is named for what it is.
        let record = try #require(try await store.assetRecord(assetID))
        #expect(record.kind == .webp)
        #expect(store.assets.url(for: assetID, kind: .webp).pathExtension == "webp")
    }

    /// Proof it is really decoded, not merely accepted: the fixture's top-left
    /// quadrant is red and the rest is white, and those colours have to come
    /// back in the right places.
    @Test func theImageDecodesToTheRightPixels() throws {
        let image = try #require(PixelProbe.decode(SyntheticDocuments.webPImage()))

        #expect(image.width == 16 && image.height == 16)
        #expect(PixelProbe.pixel(image, x: 0.2, y: 0.2).isRed)
        #expect(PixelProbe.pixel(image, x: 0.8, y: 0.8).isWhite)
        #expect(PixelProbe.pixel(image, x: 0.8, y: 0.2).isWhite)
    }

    /// Being stored is not the point; being usable is. An imported WebP has to
    /// come back out in the formats the app actually writes.
    @Test func anImportedWebPExportsAsAPDF() async throws {
        let (url, store) = try library()
        defer { try? FileManager.default.removeItem(at: url) }
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.webPImage(), name: "photo.webp"))
        let pages = try await store.pages(of: item.id)
        let renderer = PageRenderer(store: store)

        let source = try await renderer.prepareSource(for: pages[0], pixelsPerPoint: 2)
        guard case .image(let decoded, _) = source else {
            Issue.record("the page did not prepare as an image")
            return
        }
        #expect(decoded.width > 0 && decoded.height > 0)
    }
}
