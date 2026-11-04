import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestExport

/// When an export is simply the file that was imported, give back that file.
///
/// Row 24's finding: a page copied through PDFKit keeps its widget
/// annotations and loses the catalog `AcroForm`, because a form lives in the
/// document catalog and PDFKit offers no way to carry one across. Rebuilding
/// a document is the problem; the answer is not to rebuild it when there is
/// nothing to rebuild.
///
/// The predicate is pure and strict: it says yes only when every page of the
/// export is an untouched page of one source file, in that file's own order,
/// and nothing else has been asked for. Each `nil` below is a reason a copy
/// would hand back something other than what was asked.
@Suite struct WholeSourceCopyTests {
    private let asset = AssetID(sha256: String(repeating: "a", count: 64))
    private let other = AssetID(sha256: String(repeating: "b", count: 64))
    private let pdf = ExportOptions(format: .pdf, paperSize: .original)

    private func page(_ index: Int, of source: AssetID? = nil,
                      transform: PageTransform = .identity) -> Page {
        Page(itemID: ItemID(rawValue: "item"), sortKey: "p\(index)",
             sourceSize: CGSize(width: 612, height: 792),
             content: .pdfPage(source ?? asset, index: index),
             transform: transform,
             createdAt: Date(timeIntervalSince1970: 0), modifiedAt: Date(timeIntervalSince1970: 0))
    }

    @Test func oneUntouchedPageOfOneFileIsThatFile() {
        #expect(Exporter.wholeSourceAsset(of: [page(0)], options: pdf,
                                          rasterQuality: nil, password: nil) == asset)
    }

    @Test func soAreAllOfItsPagesInOrder() {
        let pages = (0..<3).map { page($0) }

        #expect(Exporter.wholeSourceAsset(of: pages, options: pdf,
                                          rasterQuality: nil, password: nil) == asset)
    }

    /// A password has to be written, and a copy of an unprotected file would
    /// be unprotected — the silent false promise the engine refuses
    /// everywhere else.
    @Test func aPasswordRulesOutACopy() {
        #expect(Exporter.wholeSourceAsset(of: [page(0)], options: pdf,
                                          rasterQuality: nil, password: "secret") == nil)
    }

    /// A compression preset does **not** rule out a copy, and this is the
    /// surprising one. The caller only asks when no page was re-encoded,
    /// which under a preset means nothing could be made smaller — and the
    /// rebuild was measured coming out *larger* than the source it was built
    /// from, which broke the invariant that compressing is never worse than
    /// not compressing. Three compression tests failed on exactly that the
    /// moment untouched exports started handing the source back.
    @Test func aCompressionPresetStillAllowsACopyWhenNothingCouldBeShrunk() {
        #expect(Exporter.wholeSourceAsset(of: [page(0)], options: pdf,
                                          rasterQuality: .init(maxDPI: 150, jpegQuality: 0.5),
                                          password: nil) == asset)
    }

    @Test func anotherFormatIsNotACopyOfAPDF() {
        for format in ExportFormat.allCases where format != .pdf {
            #expect(Exporter.wholeSourceAsset(of: [page(0)],
                                              options: ExportOptions(format: format, paperSize: .original),
                                              rasterQuality: nil, password: nil) == nil, "\(format)")
        }
    }

    @Test func askingForDifferentPaperIsAskingForADifferentFile() {
        #expect(Exporter.wholeSourceAsset(of: [page(0)],
                                          options: ExportOptions(format: .pdf, paperSize: .a4),
                                          rasterQuality: nil, password: nil) == nil)
    }

    /// Reordered, and so no longer the file that was imported.
    @Test func pagesOutOfTheirSourceOrderAreNotACopy() {
        let reordered = [page(1), page(0)]

        #expect(Exporter.wholeSourceAsset(of: reordered, options: pdf,
                                          rasterQuality: nil, password: nil) == nil)
    }

    /// The case the per-page index check exists for, and the only one it
    /// catches on its own: the **first page and the count both still match**,
    /// and the middle has been shuffled. Nothing else here notices that — the
    /// first-page guard sees index 0 and the caller's page-count guard sees
    /// three of three — so without this the export would hand back the source
    /// in the source's order and quietly undo the reordering.
    @Test func aShuffleThatKeepsTheFirstPageAndTheCountIsStillNotACopy() {
        let shuffled = [page(0), page(2), page(1)]

        #expect(Exporter.wholeSourceAsset(of: shuffled, options: pdf,
                                          rasterQuality: nil, password: nil) == nil)
    }

    /// The first page was deleted, so page 0 of the export is page 1 of the
    /// source. Handing back the whole file would restore a deleted page —
    /// the worst thing this could do.
    @Test func aSubsetThatSkipsThePagesBeforeItIsNotACopy() {
        let withoutTheFirst = [page(1), page(2)]

        #expect(Exporter.wholeSourceAsset(of: withoutTheFirst, options: pdf,
                                          rasterQuality: nil, password: nil) == nil)
    }

    @Test func pagesFromTwoFilesAreNeitherFile() {
        let merged = [page(0), page(1, of: other)]

        #expect(Exporter.wholeSourceAsset(of: merged, options: pdf,
                                          rasterQuality: nil, password: nil) == nil)
    }

    /// Cropped, rotated or filtered is an edit, whatever the rest says.
    @Test func anEditedPageIsNotACopy() {
        let rotated = page(0, transform: PageTransform(rotation: .clockwise90))

        #expect(Exporter.wholeSourceAsset(of: [rotated], options: pdf,
                                          rasterQuality: nil, password: nil) == nil)
    }

    /// A notebook page has no source file to hand back.
    @Test func aPageWithNoSourceFileIsNotACopy() {
        let drawn = Page(itemID: ItemID(rawValue: "item"), sortKey: "p0",
                         sourceSize: CGSize(width: 612, height: 792),
                         content: .template(.blank),
                         createdAt: Date(timeIntervalSince1970: 0),
                         modifiedAt: Date(timeIntervalSince1970: 0))

        #expect(Exporter.wholeSourceAsset(of: [drawn], options: pdf,
                                          rasterQuality: nil, password: nil) == nil)
    }

    @Test func nothingIsNotACopyOfAnything() {
        #expect(Exporter.wholeSourceAsset(of: [], options: pdf,
                                          rasterQuality: nil, password: nil) == nil)
    }
}
