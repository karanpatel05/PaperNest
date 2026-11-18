import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestExport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// The export sheet's preview: the first chosen page read back from a real
/// one-page export, so the paper, a watermark and a text format's words are
/// what the writer wrote.
@Suite struct ExportPreviewTests {
    private struct Fixture {
        let root: URL
        let store: LibraryStore
        let exporter: Exporter
        let pages: [Page]
    }

    private func fixture(_ text: [String] = ["Quarterly report: sales grew in every region"]) async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestPreview-\(UUID())")
        let store = try LibraryStore(directory: root)
        let asset = try store.assets.store(SyntheticDocuments.textPDF(pages: text), kind: .pdf, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Report", pages: text.indices.map {
            .init(sourceSize: CGSize(width: 612, height: 792), content: .pdfPage(asset.id, index: $0))
        }, assets: [asset])
        let exports = root.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        return Fixture(root: root, store: store, exporter: Exporter(renderer: PageRenderer(store: store), temporaryRoot: exports),
                       pages: try await store.pages(of: item.id))
    }

    /// The preview a sample gives, its files removed as the sheet removes them.
    private func preview(_ fixture: Fixture, _ options: ExportOptions) async throws -> ExportPreview? {
        let sample = try await fixture.exporter.sample(itemName: "Report", pages: fixture.pages, options: options)
        defer { sample.firstPage.removeTemporaryFiles() }
        return ExportPreview.read(sample.firstPage)
    }

    private func picture(_ preview: ExportPreview?) -> CGImage? {
        if case .picture(let image)? = preview { image } else { nil }
    }

    private func words(_ preview: ExportPreview?) -> String? {
        if case .words(let words)? = preview { words } else { nil }
    }

    /// Letter and A4 are different shapes, and the preview is the paper's.
    @Test func aPDFPreviewIsTheExportedPaper() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let letter = try #require(picture(try await preview(fixture, ExportOptions(format: .pdf, paperSize: .usLetter))))
        let a4 = try #require(picture(try await preview(fixture, ExportOptions(format: .pdf, paperSize: .a4))))

        #expect(abs(Double(letter.width) / Double(letter.height) - 612.0 / 792) < 0.01)
        #expect(abs(Double(a4.width) / Double(a4.height) - 595.28 / 841.89) < 0.01)
        #expect(max(letter.width, letter.height) == 720)
    }

    /// A watermark the export draws is in the preview: red in the middle of
    /// the page that the unmarked preview does not have.
    @Test func aWatermarkIsInThePreview() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var marked = ExportOptions(format: .pdf, paperSize: .original)
        marked.watermark = Watermark(preset: .confidential, text: "CONFIDENTIAL", opacity: 0.6)

        let plain = try #require(picture(try await preview(fixture, ExportOptions(format: .pdf, paperSize: .original))))
        let withMark = try #require(picture(try await preview(fixture, marked)))

        #expect(reddish(withMark) > reddish(plain) + 200, "no watermark in the preview: \(reddish(withMark)) vs \(reddish(plain))")
    }

    /// Pixels clearly redder than they are green or blue.
    private func reddish(_ image: CGImage) -> Int {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var count = 0
        for i in stride(from: 0, to: buffer.count, by: 4) where Int(buffer[i]) > Int(buffer[i + 1]) + 40
            && Int(buffer[i]) > Int(buffer[i + 2]) + 40 {
            count += 1
        }
        return count
    }

    @Test func aPicturePreviewIsTheExportedImage() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        for format in [ExportFormat.jpeg, .png] {
            let image = try #require(picture(try await preview(fixture, ExportOptions(format: format))), "\(format)")
            #expect(abs(Double(image.width) / Double(image.height) - 612.0 / 792) < 0.02, "\(format)")
        }
    }

    /// A text file and an editable Word file preview as their words.
    @Test func textAndEditableWordPreviewAsTheirWords() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let text = try #require(words(try await preview(fixture, ExportOptions(format: .txt))))
        let word = try #require(words(try await preview(fixture, ExportOptions(format: .docx, docxLayout: .editableText))))

        #expect(text.contains("Quarterly report: sales grew in every region"))
        #expect(word.contains("Quarterly report: sales grew in every region"))
    }

    /// A Word file of page pictures previews as its page picture.
    @Test func aWordFileOfPagePicturesPreviewsAsThePicture() async throws {
        let fixture = try await fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let image = try #require(picture(try await preview(fixture, ExportOptions(format: .docx, docxLayout: .pageImages))))
        #expect(abs(Double(image.width) / Double(image.height) - 612.0 / 792) < 0.02)
    }

    /// Only the first chosen page is previewed, and nothing is left behind.
    @Test func theFirstPageIsPreviewedAndNothingIsLeft() async throws {
        let fixture = try await fixture(["First page words", "Second page words", "Third page words",
                                         "Fourth page words", "Fifth page words", "Sixth page words"])
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let text = try #require(words(try await preview(fixture, ExportOptions(format: .txt))))
        #expect(text.contains("First page words") && !text.contains("Second page words"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.exporter.temporaryRoot.path).isEmpty)
    }

    @Test func wordParagraphsReadEachParagraphAsALine() {
        let xml = Data("""
            <w:document xmlns:w="w"><w:body><w:p><w:r><w:t xml:space="preserve">Fish &amp; chips</w:t></w:r></w:p>\
            <w:p><w:r><w:br w:type="page"/></w:r></w:p><w:p><w:r><w:t>Line </w:t></w:r><w:r><w:t>two</w:t></w:r></w:p></w:body></w:document>
            """.utf8)
        #expect(WordParagraphs.text(of: xml) == "Fish & chips\nLine two")
    }
}
