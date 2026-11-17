import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestRender

/// Comparing real documents through the renderer: digital PDFs by their
/// words, scans by their pictures until they are read, and marks by the
/// pictures always.
@Suite struct DocumentComparerTests {
    private func pages(_ lib: TestLibrary, _ data: Data, _ name: String) async throws -> [Page] {
        let item = try await lib.importer.importItem(.data(data, name: name))
        return try await lib.store.pages(of: item.id)
    }

    private func compare(_ lib: TestLibrary, _ old: [Page], _ new: [Page]) async throws -> DocumentComparison {
        try await DocumentComparer(renderer: lib.renderer).compare(old: old, new: new)
    }

    @Test func oneChangedWordInADigitalPDFIsOneChangeWhereItIs() async throws {
        let lib = try TestLibrary()
        let old = try await pages(lib, SyntheticDocuments.textPDF(pages: ["Invoice total 42 paid in March"]), "Old")
        let new = try await pages(lib, SyntheticDocuments.textPDF(pages: ["Invoice total 42 paid in April"]), "New")

        let comparison = try await compare(lib, old, new)

        #expect(comparison.pages.count == 1)
        let page = try #require(comparison.pages.first)
        #expect(page.kind == .changed)
        #expect(page.method == .text(.embedded))
        #expect(page.textChanges.map { $0.removed.map(\.text) } == [["March"]])
        #expect(page.textChanges.map { $0.added.map(\.text) } == [["April"]])
        // textPDF draws its line about 0.15 of the way down the page.
        let removed = try #require(page.textChanges.first?.removed.first?.box)
        #expect(removed.y > 0.1 && removed.y < 0.2 && removed.x > 0.3, "\(removed)")
        #expect(page.pictureDifferenceCount == 0, "the pictures differ only under words")
    }

    @Test func aPageInsertedInTheMiddleIsOneAddedPage() async throws {
        let lib = try TestLibrary()
        let old = try await pages(lib, SyntheticDocuments.textPDF(pages: [
            "Chapter one begins with the harbour at dawn", "Chapter two follows the boats out to sea"]), "Old")
        let new = try await pages(lib, SyntheticDocuments.textPDF(pages: [
            "Chapter one begins with the harbour at dawn", "An interlude about the lighthouse keeper alone",
            "Chapter two follows the boats out to sea"]), "New")

        let comparison = try await compare(lib, old, new)

        #expect(comparison.pages.map(\.kind) == [.same, .added, .same])
        #expect(comparison.pages[1].newIndex == 1)
        #expect(comparison.movedPageCount == 0)
    }

    /// The same words, and a stroke drawn on the new page: a change, found
    /// by the picture, where the stroke is.
    @Test func aDrawingOverIdenticalTextIsAChange() async throws {
        let lib = try TestLibrary()
        let statement = SyntheticDocuments.textPDF(pages: ["Invoice total 42 paid in March"])
        let old = try await pages(lib, statement, "Old")
        let new = try await pages(lib, statement, "New")
        let stroke = InkStroke(tool: .pen, color: .black, width: 8,
                               points: [InkPoint(x: 150, y: 500), InkPoint(x: 450, y: 520)])
        try await lib.store.saveObject(PageObject(pageID: new[0].id, zKey: "m", payload: .ink(stroke), modifiedAt: Date()))

        let comparison = try await compare(lib, old, new)

        let page = try #require(comparison.pages.first)
        #expect(page.textChanges.isEmpty)
        #expect(page.kind == .changed, "matching words over a new drawing are not the same page")
        let region = try #require(page.newPictureRegions.first)
        // 500 of 792 points down is about 0.63.
        #expect(region.y < 0.65 && region.y + region.height > 0.63, "\(region)")
    }

    /// Two scans nobody has read are compared by picture and say so; once
    /// read, by their words, and say they were read off the pixels.
    @Test func scansAreComparedByPictureUntilReadThenByTheirWords() async throws {
        let lib = try TestLibrary()
        let old = try await pages(lib, SyntheticDocuments.textImage(lines: ["Invoice total 42"]), "Old scan")
        let new = try await pages(lib, SyntheticDocuments.textImage(lines: ["Invoice total 43"]), "New scan")

        let unread = try await compare(lib, old, new)
        let page = try #require(unread.pages.first)
        #expect(unread.pages.count == 1)
        #expect(page.method == .picture(.noTextOnEither))
        #expect(page.kind == .changed)
        #expect(unread.comparedOnlyByPicture)

        _ = try await AutomaticTextRecognizer(store: lib.store, renderer: lib.renderer).recognizeMissing()
        let read = try await compare(lib, try await lib.store.pages(of: old[0].itemID),
                                     try await lib.store.pages(of: new[0].itemID))
        let readPage = try #require(read.pages.first)
        #expect(readPage.method == .text(.recognized))
        #expect(readPage.textChanges.map { $0.removed.map(\.text) } == [["42"]])
        #expect(readPage.textChanges.map { $0.added.map(\.text) } == [["43"]])
        #expect(read.usesRecognizedText)
    }

    /// One character changed in body-size print on a scan nobody has read.
    /// Compared at the small size pages are matched by, each of these came
    /// back "Same"; the pair is now compared drawn larger.
    @Test(arguments: [("Total 42.10 due", "Total 42.70 due"), ("Paid 3 March", "Paid 8 March"),
                      ("Ref 1234567", "Ref 1234561")])
    func aOneCharacterChangeInBodySizePrintIsFoundByThePicture(_ pair: (String, String)) async throws {
        let lib = try TestLibrary()
        let old = try await pages(lib, SyntheticDocuments.textImage(lines: [pair.0], fontSize: 18), "Old")
        let new = try await pages(lib, SyntheticDocuments.textImage(lines: [pair.1], fontSize: 18), "New")

        let page = try #require(try await compare(lib, old, new).pages.first)

        #expect(page.method == .picture(.noTextOnEither))
        #expect(page.kind == .changed, "\(pair.0) → \(pair.1) was called the same")
        #expect(page.pictureDifferenceCount == 1)
    }

    @Test func aDocumentComparedWithItselfIsIdentical() async throws {
        let lib = try TestLibrary()
        let pagesOf = try await pages(lib, SyntheticDocuments.textPDF(pages: ["First page words here", "Second page words here"]), "Doc")
        #expect(try await compare(lib, pagesOf, pagesOf).isIdentical)
    }

    /// Red where only the old page is dark, green where only the new one is,
    /// dark where both are, white where neither is.
    @Test func theOverlayColoursWhatEachSideAloneHas() throws {
        func picture(darkLeft: Bool, darkRight: Bool) -> CGImage {
            let context = CGContext(data: nil, width: 20, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            context.setFillColor(gray: 1, alpha: 1); context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
            context.setFillColor(gray: 0, alpha: 1)
            if darkLeft { context.fill(CGRect(x: 0, y: 0, width: 5, height: 10)) }
            if darkRight { context.fill(CGRect(x: 5, y: 0, width: 5, height: 10)) }
            return context.makeImage()!
        }
        // Old: dark in columns 0–9; new: dark in columns 5–9.
        let old = picture(darkLeft: true, darkRight: true)
        let new = picture(darkLeft: false, darkRight: true)
        let overlay = try #require(DocumentComparer.overlay(old: old, new: new))
        #expect(PixelProbe.pixel(overlay, x: 0.1, y: 0.5).isRed, "only the old page: red")
        #expect(PixelProbe.pixel(overlay, x: 0.35, y: 0.5).isDark, "both pages: dark")
        #expect(PixelProbe.pixel(overlay, x: 0.8, y: 0.5).isWhite, "neither: white")

        let added = try #require(DocumentComparer.overlay(old: picture(darkLeft: false, darkRight: false), new: new))
        let green = PixelProbe.pixel(added, x: 0.35, y: 0.5)
        #expect(green.g > 180 && green.r < 80 && green.b < 80, "only the new page: green, not \(green)")
    }
}
