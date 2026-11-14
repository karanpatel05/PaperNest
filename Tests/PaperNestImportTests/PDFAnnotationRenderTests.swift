import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// A PDF keeps some of what a reader sees outside its page content, in
/// **annotations**: the answer typed into a form field, a checkbox's tick, a
/// box or stamp another app drew. Core Graphics' `drawPDFPage` draws page
/// content only, so until these tests every one of them was missing from the
/// page PaperNest showed — a filled-in form opened with empty boxes.
@Suite struct PDFAnnotationRenderTests {
    private struct Seeded {
        let url: URL
        let store: LibraryStore
        let page: Page
        let renderer: PageRenderer
    }

    private func seeded(_ data: Data, name: String = "Marked up") async throws -> Seeded {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestAnnotations-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: url)
        let item = try await DocumentImporter(store: store).importItem(.data(data, name: name))
        let page = try await store.pages(of: item.id)[0]
        return Seeded(url: url, store: store, page: page, renderer: PageRenderer(store: store))
    }

    /// Where a rectangle given in PDF user space on an unrotated, uncropped
    /// 612 × 792 page sits as a fraction of the page, from the top left.
    private func fraction(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / 612, y: (792 - rect.maxY) / 792, width: rect.width / 612, height: rect.height / 792)
    }

    /// The pixels of `image`, decoded once.
    private struct Pixels {
        let width: Int, height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: width * height * 4)
            let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            bytes = buffer
        }

        func at(_ x: Int, _ y: Int) -> PixelProbe.RGB {
            let i = (y * width + x) * 4
            return PixelProbe.RGB(r: bytes[i], g: bytes[i + 1], b: bytes[i + 2])
        }

        func at(fraction x: Double, _ y: Double) -> PixelProbe.RGB {
            at(min(width - 1, Int(Double(width) * x)), min(height - 1, Int(Double(height) * y)))
        }

        /// How many pixels inside `region` (fractions of the image, top left) pass `test`.
        func count(in region: CGRect, where test: (PixelProbe.RGB) -> Bool) -> Int {
            let x0 = max(0, Int(region.minX * Double(width))), x1 = min(width, Int(region.maxX * Double(width)))
            let y0 = max(0, Int(region.minY * Double(height))), y1 = min(height, Int(region.maxY * Double(height)))
            var n = 0
            for y in y0..<max(y0, y1) { for x in x0..<max(x0, x1) where test(at(x, y)) { n += 1 } }
            return n
        }

        /// The centre of the pixels that pass `test`, as fractions, or nil if none do.
        func centroid(where test: (PixelProbe.RGB) -> Bool) -> CGPoint? {
            var sx = 0.0, sy = 0.0, n = 0.0
            for y in 0..<height { for x in 0..<width where test(at(x, y)) { sx += Double(x); sy += Double(y); n += 1 } }
            guard n > 0 else { return nil }
            return CGPoint(x: (sx / n + 0.5) / Double(width), y: (sy / n + 0.5) / Double(height))
        }
    }

    private static func isBlue(_ p: PixelProbe.RGB) -> Bool { p.b > 180 && p.r < 80 && p.g < 80 }
    private static func isGreen(_ p: PixelProbe.RGB) -> Bool { p.g > 150 && p.r < 80 && p.b < 80 }
    private static func isRed(_ p: PixelProbe.RGB) -> Bool { p.isRed }
    private static func isDark(_ p: PixelProbe.RGB) -> Bool { p.isDark }

    // MARK: - Marks another app left

    @Test func marksKeptInAnnotationsAreOnThePage() async throws {
        let s = try await seeded(SyntheticDocuments.markedUpPDF())
        defer { try? FileManager.default.removeItem(at: s.url) }

        let pixels = Pixels(try await s.renderer.renderImage(s.page, pixelsPerPoint: 1))

        let red = fraction(SyntheticDocuments.MarkedUp.shownAndPrinted)
        let blue = fraction(SyntheticDocuments.MarkedUp.shownOnly)
        #expect(Self.isRed(pixels.at(fraction: red.midX, red.midY)), "the red box is missing: \(pixels.at(fraction: red.midX, red.midY))")
        // On screen a mark shows whether or not its author meant it for paper.
        #expect(Self.isBlue(pixels.at(fraction: blue.midX, blue.midY)), "the blue box is missing: \(pixels.at(fraction: blue.midX, blue.midY))")
        // Hidden by its author: not shown, as no reader shows it.
        #expect(pixels.count(in: fraction(SyntheticDocuments.MarkedUp.hidden), where: Self.isGreen) == 0, "a hidden mark was drawn")
        // A link is somewhere to tap, not a mark.
        let link = fraction(SyntheticDocuments.MarkedUp.link)
        #expect(pixels.at(fraction: link.midX, link.midY).isWhite, "the link was drawn")
    }

    /// Page thumbnails come from the same drawing, so they show the marks too.
    @Test func aThumbnailShowsTheMarksToo() async throws {
        let s = try await seeded(SyntheticDocuments.markedUpPDF())
        defer { try? FileManager.default.removeItem(at: s.url) }

        let pixels = Pixels(try await s.renderer.renderThumbnail(s.page, maxPixelSize: 200))
        let red = fraction(SyntheticDocuments.MarkedUp.shownAndPrinted)
        #expect(Self.isRed(pixels.at(fraction: red.midX, red.midY)))
    }

    /// A page turned by its file's `/Rotate` has its marks where PDFKit — what
    /// Preview draws with — puts them. Compared against PDFKit's own drawing of
    /// the same file, so this checks the mapping, not an idea of it.
    @Test(arguments: [0, 90, 180, 270])
    func aTurnedPageHasItsMarksWherePDFKitPutsThem(_ rotation: Int) async throws {
        let data = SyntheticDocuments.markedUpPDF(rotation: rotation)
        let s = try await seeded(data)
        defer { try? FileManager.default.removeItem(at: s.url) }

        let ours = Pixels(try await s.renderer.renderImage(s.page, pixelsPerPoint: 1))
        let theirs = Pixels(try #require(PixelProbe.renderPDFPage(data, index: 0, scale: 1)))
        let mine = try #require(ours.centroid(where: Self.isRed), "no red box at /Rotate \(rotation)")
        let reference = try #require(theirs.centroid(where: Self.isRed))
        #expect(abs(mine.x - reference.x) < 0.02 && abs(mine.y - reference.y) < 0.02,
                "at /Rotate \(rotation) the box is at \(mine), PDFKit puts it at \(reference)")
    }

    /// A crop box that does not start at the media box's corner: the marks
    /// still land where PDFKit puts them.
    @Test func aPageCroppedInItsFileHasItsMarksWherePDFKitPutsThem() async throws {
        let data = SyntheticDocuments.markedUpPDF(cropBox: CGRect(x: 50, y: 40, width: 450, height: 650))
        let s = try await seeded(data)
        defer { try? FileManager.default.removeItem(at: s.url) }

        let ours = Pixels(try await s.renderer.renderImage(s.page, pixelsPerPoint: 1))
        let theirs = Pixels(try #require(PixelProbe.renderPDFPage(data, index: 0, scale: 1)))
        let mine = try #require(ours.centroid(where: Self.isRed), "no red box on a page with an offset crop box")
        let reference = try #require(theirs.centroid(where: Self.isRed))
        #expect(abs(mine.x - reference.x) < 0.02 && abs(mine.y - reference.y) < 0.02,
                "the box is at \(mine), PDFKit puts it at \(reference)")
    }

    /// A crop made in PaperNest moves the marks with the paper; one it cuts
    /// off is gone.
    @Test func aCropMadeInPaperNestCarriesTheMarksWithThePage() async throws {
        let s = try await seeded(SyntheticDocuments.markedUpPDF())
        defer { try? FileManager.default.removeItem(at: s.url) }
        var transform = s.page.transform
        transform.crop = .exact(x: 0.45, y: 0, width: 0.55, height: 1)
        let cropped = try await s.store.updateTransform(s.page.id, to: transform)

        let pixels = Pixels(try await s.renderer.renderImage(cropped, pixelsPerPoint: 1))
        let blue = fraction(SyntheticDocuments.MarkedUp.shownOnly)
        #expect(Self.isBlue(pixels.at(fraction: (blue.midX - 0.45) / 0.55, blue.midY)), "the blue box did not move with the crop")
        #expect(pixels.centroid(where: Self.isRed) == nil, "a box the crop cuts off is still drawn")
    }

    /// A page with a filter on it is drawn as pixels rather than vectors; the
    /// marks must survive that path too.
    @Test func aFilteredPageKeepsItsMarks() async throws {
        let s = try await seeded(SyntheticDocuments.markedUpPDF())
        defer { try? FileManager.default.removeItem(at: s.url) }
        var transform = s.page.transform
        transform.brightness = 0.05
        let filtered = try await s.store.updateTransform(s.page.id, to: transform)
        #expect(filtered.transform.needsPixelProcessing, "precondition: the page is drawn as pixels")

        let pixels = Pixels(try await s.renderer.renderImage(filtered, pixelsPerPoint: 1))
        let red = fraction(SyntheticDocuments.MarkedUp.shownAndPrinted)
        let p = pixels.at(fraction: red.midX, red.midY)
        #expect(p.r > 180 && p.g < 110 && p.b < 110, "the red box is missing from the filtered page: \(p)")
    }

    // MARK: - Form answers

    /// The field the fixture puts first: `acroFormPDF` places it at
    /// [72 600 300 630] in PDF space.
    private var firstField: CGRect { fraction(CGRect(x: 72, y: 600, width: 228, height: 30)) }
    /// The second field, at [72 560 300 590].
    private var secondField: CGRect { fraction(CGRect(x: 72, y: 560, width: 228, height: 30)) }

    @Test func aFilledInFieldShowsItsAnswer() async throws {
        let filled = try await seeded(SyntheticDocuments.acroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer", value: "MMMMMMMM"),
        ]))
        defer { try? FileManager.default.removeItem(at: filled.url) }
        let empty = try await seeded(SyntheticDocuments.acroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer"),
        ]))
        defer { try? FileManager.default.removeItem(at: empty.url) }

        let answered = Pixels(try await filled.renderer.renderImage(filled.page, pixelsPerPoint: 2))
        let blank = Pixels(try await empty.renderer.renderImage(empty.page, pixelsPerPoint: 2))
        let inked = answered.count(in: firstField, where: Self.isDark)
        #expect(inked > 150, "the answer is not on the page: \(inked) dark pixels in its box")
        #expect(blank.count(in: firstField, where: Self.isDark) < 5, "an empty field drew something")
    }

    /// Text recognition reads the paper as a reader sees it, answers included.
    /// A choice: the alternative, reading under the answers, would make the
    /// recognised words disagree with the page on screen.
    @Test func thePictureRecognitionReadsShowsTheAnswer() async throws {
        let s = try await seeded(SyntheticDocuments.acroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer", value: "MMMMMMMM"),
        ]))
        defer { try? FileManager.default.removeItem(at: s.url) }

        let picture = try #require(try await s.renderer.renderSourceForRecognition(s.page, pixelsPerPoint: 2))
        #expect(Pixels(picture).count(in: firstField, where: Self.isDark) > 150)
    }

    /// Building a form field's appearance makes PDFKit look up the field's font
    /// over synchronous XPC, and several of those at once on Swift's
    /// cooperative threads were measured to deadlock (`PDFForm`). Pages are
    /// drawn concurrently — thumbnails, the page, its neighbours — so this is
    /// the case that matters: all of them have to come back.
    @Test(.timeLimit(.minutes(1)))
    func manyPicturesOfAFormDrawnAtOnceAllComeBack() async throws {
        let s = try await seeded(SyntheticDocuments.acroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer", value: "MMMMMMMM"),
            SyntheticDocuments.FormFieldSpec(name: "second", value: "WWWWWWWW"),
        ]))
        defer { try? FileManager.default.removeItem(at: s.url) }
        let renderer = s.renderer, page = s.page

        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<16 {
                group.addTask {
                    let image = try await renderer.renderImage(page, pixelsPerPoint: 1 + CGFloat(index % 4) * 0.25)
                    return Pixels(image).count(in: self.firstField, where: Self.isDark)
                }
            }
            var all: [Int] = []
            for try await count in group { all.append(count) }
            return all
        }
        #expect(counts.count == 16)
        #expect(counts.allSatisfy { $0 > 20 }, "a picture came back without the answer: \(counts)")
    }

    // MARK: - Redaction

    /// Redaction draws the page as the reader sees it and paints out what was
    /// asked: an answer under the rectangle is gone, one beside it stays.
    /// Drawn without its answers, the redacted page would silently lose every
    /// answer on it, not just the one redacted.
    @Test func redactingAnAnswerRemovesThatAnswerAndKeepsTheNext() async throws {
        let s = try await seeded(SyntheticDocuments.acroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer", value: "MMMMMMMM"),
            SyntheticDocuments.FormFieldSpec(name: "second", value: "WWWWWWWW"),
        ]))
        defer { try? FileManager.default.removeItem(at: s.url) }
        let first = firstField
        let rectangle = NormalizedRect.exact(x: first.minX - 0.01, y: first.minY - 0.005,
                                             width: first.width + 0.02, height: first.height + 0.006)

        let png = try await PageRedaction.redactedPNG(for: s.page, rectangles: [rectangle], renderer: s.renderer)
        let pixels = Pixels(try #require(PixelProbe.decode(png)))

        let insideFirst = first.insetBy(dx: first.width * 0.1, dy: first.height * 0.2)
        let total = Int(insideFirst.width * Double(pixels.width)) * Int(insideFirst.height * Double(pixels.height))
        #expect(pixels.count(in: insideFirst, where: Self.isDark) >= total * 9 / 10, "the redacted answer is not painted out")
        // The second answer is text on white, so some of its box is dark and most is not.
        let second = pixels.count(in: secondField, where: Self.isDark)
        #expect(second > 50, "the answer beside the redaction was lost: \(second) dark pixels")
    }

    /// Redacting rewrites a page as a picture with no author's limits on it,
    /// which would hand out the contents of a PDF whose author forbade copying
    /// them. So a page from such a file is not redacted, and is left as it was.
    @Test func aPageWhoseAuthorForbadeCopyingIsNotRedacted() async throws {
        let s = try await seeded(SyntheticDocuments.restrictedPDF(pages: ["Application"]), name: "Form")
        defer { try? FileManager.default.removeItem(at: s.url) }

        await #expect(throws: RedactionError.restrictedByAuthor) {
            _ = try await PageRedactor(store: s.store, renderer: s.renderer)
                .redact(s.page, rectangles: [.exact(x: 0.1, y: 0.1, width: 0.5, height: 0.1)])
        }
        let after = try await s.store.pages(of: s.page.itemID)[0]
        #expect(after.content == s.page.content, "the page was changed anyway")
        #expect(after.revision == s.page.revision)
    }
}
