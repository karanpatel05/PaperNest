import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// What happens to a PDF's annotations — a form's answers, another app's
/// marks — when PaperNest draws the page rather than copying it.
///
/// A page nobody touched is copied, annotations and all. A page with
/// something drawn on it is rebuilt, and a rebuilt page used to come out with
/// the page content only: draw a line on a filled-in form and every answer on
/// that page was gone from the export and from the print.
@Suite struct AnnotationExportTests {
    private func drawOn(_ page: Page, _ fixture: ExportFixture) async throws {
        try await fixture.store.saveObject(PageObject(
            pageID: page.id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 6,
                                    points: [InkPoint(x: 72, y: 740), InkPoint(x: 300, y: 740)])),
            modifiedAt: Date()))
    }

    /// Page `number` of a written PDF drawn by **Core Graphics alone**, which
    /// draws page content and ignores annotations. Whatever shows here is part
    /// of the page itself, not a field or an annotation riding on top of it.
    private func contentOnly(_ url: URL, page number: Int = 1, scale: CGFloat = 2) throws -> CGImage {
        let document = try #require(CGPDFDocument(url as CFURL))
        let page = try #require(document.page(at: number))
        let box = page.getBoxRect(.mediaBox)
        let width = Int(box.width * scale), height = Int(box.height * scale)
        let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: -box.minX, y: -box.minY)
        ctx.drawPDFPage(page)
        return try #require(ctx.makeImage())
    }

    /// How many pixels inside `region` (fractions of the image, from the top
    /// left) pass `test`.
    private func count(_ image: CGImage, in region: CGRect, where test: (PixelProbe.RGB) -> Bool) -> Int {
        let width = image.width, height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var n = 0
        for y in Int(region.minY * Double(height))..<Int(region.maxY * Double(height)) {
            for x in Int(region.minX * Double(width))..<Int(region.maxX * Double(width)) {
                let i = (y * width + x) * 4
                if test(PixelProbe.RGB(r: buffer[i], g: buffer[i + 1], b: buffer[i + 2])) { n += 1 }
            }
        }
        return n
    }

    /// A rectangle in PDF user space on a 612 × 792 page, as fractions from the top left.
    private func fraction(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX / 612, y: (792 - rect.maxY) / 792, width: rect.width / 612, height: rect.height / 792)
    }

    /// `acroFormPDF`'s first field sits at [72 600 300 630].
    private var firstField: CGRect { fraction(CGRect(x: 72, y: 600, width: 228, height: 30)) }

    private func widgets(in url: URL) throws -> Int {
        let document = try #require(PDFDocument(url: url))
        return (0..<document.pageCount).reduce(0) { total, index in
            total + (document.page(at: index)?.annotations.filter { $0.type == "Widget" }.count ?? 0)
        }
    }

    @Test func anAnswerOnAPageThatWasDrawnOnIsInTheExportedPage() async throws {
        let f = try ExportFixture()
        let item = try await f.importer.importItem(.data(SyntheticDocuments.acroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer", value: "MMMMMMMM"),
        ]), name: "Form.pdf"))
        let page = try await f.store.pages(of: item.id)[0]
        try await drawOn(page, f)

        let output = try await f.exporter.export(itemName: item.name, pages: try await f.store.pages(of: item.id),
                                                 options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }

        let inked = count(try contentOnly(output.files[0]), in: firstField) { $0.isDark }
        #expect(inked > 150, "the answer is not on the exported page: \(inked) dark pixels in its box")
        // Drawn into the page, so no field is left on top of it to draw it twice.
        #expect(try widgets(in: output.files[0]) == 0)
    }

    /// Print takes the same road, and a restricted form — the USCIS case — is
    /// printed with its answers and still closed to copying.
    @Test func aRestrictedFormDrawnOnIsPrintedWithItsAnswers() async throws {
        let f = try ExportFixture()
        let item = try await f.importer.importItem(.data(SyntheticDocuments.restrictedAcroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer", value: "MMMMMMMM"),
        ]), name: "Form.pdf"))
        let page = try await f.store.pages(of: item.id)[0]
        try await drawOn(page, f)

        let output = try await f.exporter.export(itemName: item.name, pages: try await f.store.pages(of: item.id),
                                                 options: ExportOptions(format: .pdf, paperSize: .original),
                                                 purpose: .printing)
        defer { output.removeTemporaryFiles() }

        let written = try #require(CGPDFDocument(output.files[0] as CFURL))
        #expect(written.isUnlocked && !written.allowsCopying, "the printed file is not closed to copying")
        let inked = count(try contentOnly(output.files[0]), in: firstField) { $0.isDark }
        #expect(inked > 150, "the answer is not on the page sent to print: \(inked) dark pixels")
    }

    /// A form filled in PaperNest's own form sheet and opened again shows what
    /// was typed. This is the case people met: fill a form, open the saved
    /// copy, see empty boxes.
    @Test func aFormFilledInPaperNestShowsItsAnswerWhenOpened() async throws {
        let f = try ExportFixture()
        let filled = try PDFForm.filled(SyntheticDocuments.acroFormPDF(), with: ["customer": .text("MMMMMMMM")])
        let item = try await f.importer.importItem(.data(filled, name: "Filled.pdf"))
        let page = try await f.store.pages(of: item.id)[0]

        let picture = try await PageRenderer(store: f.store).renderImage(page, pixelsPerPoint: 2)
        let inked = count(picture, in: firstField) { $0.isDark }
        #expect(inked > 150, "the typed answer is not on the page: \(inked) dark pixels in its box")
    }

    /// A picture exported from a page is paper too: the same marks as a PDF
    /// export of it, so the two formats agree.
    @Test func anImageExportKeepsTheMarksMeantForPaper() async throws {
        let f = try ExportFixture()
        let item = try await f.importer.importItem(.data(SyntheticDocuments.markedUpPDF(), name: "Marked.pdf"))
        let output = try await f.exporter.export(itemName: item.name, pages: try await f.store.pages(of: item.id),
                                                 options: ExportOptions(format: .png))
        defer { output.removeTemporaryFiles() }
        let picture = try #require(PixelProbe.decode(try Data(contentsOf: output.files[0])))

        let red = fraction(SyntheticDocuments.MarkedUp.shownAndPrinted).insetBy(dx: 0.02, dy: 0.02)
        let blue = fraction(SyntheticDocuments.MarkedUp.shownOnly).insetBy(dx: 0.02, dy: 0.02)
        #expect(count(picture, in: red) { $0.isRed } > 500, "the mark meant for paper is missing from the picture")
        #expect(count(picture, in: blue) { $0.b > 180 && $0.r < 80 } == 0, "a mark not meant for paper is in the picture")
    }

    /// Exports read and write a form through PDFKit — the copy of an untouched
    /// page, the pass that writes it into the finished file — while the page
    /// and its thumbnails are being drawn, which also builds the form's fields.
    /// Printing a filled form while its pages render is the everyday case, and
    /// every one of these has to finish.
    @Test(.timeLimit(.minutes(1)))
    func printingAFormWhileItsPicturesAreDrawnFinishes() async throws {
        let f = try ExportFixture()
        let item = try await f.importer.importItem(.data(SyntheticDocuments.restrictedAcroFormPDF(fields: [
            SyntheticDocuments.FormFieldSpec(name: "customer", value: "MMMMMMMM"),
            SyntheticDocuments.FormFieldSpec(name: "second", value: "WWWWWWWW"),
        ]), name: "Form.pdf"))
        let pages = try await f.store.pages(of: item.id)
        let renderer = PageRenderer(store: f.store), exporter = f.exporter

        let finished = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<16 {
                group.addTask {
                    _ = try await renderer.renderImage(pages[0], pixelsPerPoint: 1 + CGFloat(index % 4) * 0.25)
                    return 1
                }
            }
            for index in 0..<4 {
                group.addTask {
                    // A password makes the export copy the untouched page and
                    // write it through PDFKit, rather than hand back the file.
                    let output = try await exporter.export(itemName: "Form \(index)", pages: pages,
                                                           options: ExportOptions(format: .pdf),
                                                           password: "pw\(index)", purpose: .printing)
                    output.removeTemporaryFiles()
                    return 1
                }
            }
            var total = 0
            for try await one in group { total += one }
            return total
        }
        #expect(finished == 20)
    }

    /// A rebuilt page is paper, so it follows the author's print flags: a mark
    /// shown on screen but not meant for printing is left off, one meant for
    /// both is drawn in, a hidden one is in neither.
    @Test func aRebuiltPageKeepsTheMarksMeantForPaper() async throws {
        let f = try ExportFixture()
        let item = try await f.importer.importItem(.data(SyntheticDocuments.markedUpPDF(), name: "Marked.pdf"))
        let page = try await f.store.pages(of: item.id)[0]
        try await drawOn(page, f)

        let output = try await f.exporter.export(itemName: item.name, pages: try await f.store.pages(of: item.id),
                                                 options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }
        let paper = try contentOnly(output.files[0])

        let red = fraction(SyntheticDocuments.MarkedUp.shownAndPrinted).insetBy(dx: 0.02, dy: 0.02)
        let blue = fraction(SyntheticDocuments.MarkedUp.shownOnly).insetBy(dx: 0.02, dy: 0.02)
        let green = fraction(SyntheticDocuments.MarkedUp.hidden)
        #expect(count(paper, in: red) { $0.isRed } > 1_000, "the mark meant for paper is missing")
        #expect(count(paper, in: blue) { $0.b > 180 && $0.r < 80 } == 0, "a mark not meant for paper was printed")
        #expect(count(paper, in: green) { $0.g > 150 && $0.r < 80 } == 0, "a hidden mark was drawn")
    }
}
