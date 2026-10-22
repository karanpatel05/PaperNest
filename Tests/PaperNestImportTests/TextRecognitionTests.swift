import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// F4 first slice: reading printed text off a page, in the page's own
/// coordinate space. Vision runs on device, so these are real recognitions,
/// not stubs.
@Suite struct TextRecognitionTests {
    private func cgImage(_ data: Data) throws -> CGImage {
        try #require(PixelProbe.decode(data))
    }

    @Test func readsThePrintedWordsInReadingOrder() throws {
        let image = try cgImage(SyntheticDocuments.textImage(lines: ["Invoice total", "Paid in full"]))
        let lines = try TextRecognizer().recognize(image)
        let text = lines.map(\.text).joined(separator: " ")
        #expect(text.contains("Invoice"))
        #expect(text.contains("total"))
        #expect(text.contains("Paid"))
        // Reading order: the first printed line comes back first.
        let invoice = try #require(lines.firstIndex { $0.text.contains("Invoice") })
        let paid = try #require(lines.firstIndex { $0.text.contains("Paid") })
        #expect(invoice < paid)
        #expect(lines.allSatisfy { $0.confidence > 0 })
    }

    @Test func boxesUseATopLeftOriginInSourceSpace() throws {
        let image = try cgImage(SyntheticDocuments.textImage(lines: ["Top line", "", "", "", "", "", "", "Bottom line"]))
        let lines = try TextRecognizer().recognize(image)
        let top = try #require(lines.first { $0.text.contains("Top") })
        let bottom = try #require(lines.first { $0.text.contains("Bottom") })
        // Top-left origin: the line printed near the top has the smaller y.
        #expect(top.box.y < bottom.box.y)
        #expect(top.box.y < 0.3, "the first line should sit near the top, got \(top.box.y)")
        #expect(bottom.box.y > 0.4, "the last line should sit lower, got \(bottom.box.y)")
        // A text line is thinner than the minimum crop side; it must not be
        // inflated to it.
        #expect(top.box.height < NormalizedRect.minimumSide * 2)
        #expect(top.box.x > 0, "text starts inside the left margin")
        #expect(top.box.x < 0.5)
    }

    @Test func anEmptyPageYieldsNothingRatherThanNoise() throws {
        let image = try cgImage(SyntheticDocuments.image(width: 800, height: 1000, type: .png))
        #expect(try TextRecognizer().recognize(image).isEmpty)
    }

    @Test func onlySupportedLanguagesAreRequested() throws {
        let supported = TextRecognizer.supportedLanguages(from: TextRecognizer.preferredLanguages)
        #expect(!supported.isEmpty, "the OS must support at least one of en/fr/es")
        #expect(TextRecognizer.supportedLanguages(from: ["xx-XX"]).isEmpty)
        #expect(throws: TextRecognizer.RecognitionError.noSupportedLanguage) {
            let image = try cgImage(SyntheticDocuments.textImage(lines: ["Anything"]))
            _ = try TextRecognizer(languages: ["xx-XX"]).recognize(image)
        }
    }

    /// Recognition reads the paper, not the current view of it: a crop and a
    /// rotation must not change the words or their place in source space.
    @Test func theSourceRenderIgnoresCropRotationAndFilters() async throws {
        let library = try TestLibrary()
        let store = library.store
        let data = SyntheticDocuments.textImage(lines: ["Lease agreement"])
        let asset = try store.assets.store(data, kind: .png, originalFilename: "lease.png")
        let page = LibraryStore.NewPage(sourceSize: CGSize(width: 1000, height: 1400), content: .image(asset.id))
        let item = try await store.createItem(kind: .document, name: "Lease", pages: [page], assets: [asset])
        let renderer = library.renderer
        let stored = try await store.pages(of: item.id)[0]

        let plainImage = try await renderer.renderSourceForRecognition(stored, pixelsPerPoint: 1)
        let plain = try #require(plainImage)
        let before = try TextRecognizer().recognize(plain)

        var transform = stored.transform
        transform.rotation = .clockwise90
        transform.crop = NormalizedRect(x: 0.0, y: 0.0, width: 0.6, height: 0.5)
        transform.filter = .grayscale
        let edited = try await store.updateTransform(stored.id, to: transform)

        let editedImage = try await renderer.renderSourceForRecognition(edited, pixelsPerPoint: 1)
        let afterImage = try #require(editedImage)
        #expect(afterImage.width == plain.width && afterImage.height == plain.height)
        let lines = try TextRecognizer().recognize(afterImage)
        let afterText: [String] = lines.map { $0.text }
        let beforeText: [String] = before.map { $0.text }
        #expect(afterText == beforeText)
        if let a = lines.first, let b = before.first {
            #expect(abs(a.box.y - b.box.y) < 0.01)
            #expect(abs(a.box.x - b.box.x) < 0.01)
        }
    }
}
