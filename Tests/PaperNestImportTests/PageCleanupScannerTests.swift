import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestRender

/// Blank and repeated pages found in real documents, through the renderer,
/// and which of them are chosen to start with.
@Suite struct PageCleanupScannerTests {
    /// A white page, with an optional small square of `gray` (0 black … 1 white).
    private func scan(mark gray: CGFloat? = nil) -> Data {
        let width = 1000, height = 1400
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if let gray {
            context.setFillColor(CGColor(red: gray, green: gray, blue: gray, alpha: 1))
            context.fill(CGRect(x: 700, y: 200, width: 80, height: 20))     // a pencilled note in the margin
        }
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// What a scanner app saves: a PDF page holding only a picture — here a
    /// white one, so a page with no text and no ink.
    private func pictureOnlyPDF() -> Data {
        let picture = PixelProbe.decode(scan())!
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &box, nil)!
        context.beginPDFPage(nil)
        context.draw(picture, in: box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    private func document(_ lib: TestLibrary, _ pages: [(Data, AssetKind)]) async throws -> ItemID {
        var staged: [AssetFileStore.StagedAsset] = []
        var newPages: [LibraryStore.NewPage] = []
        for (data, kind) in pages {
            let asset = try lib.store.assets.store(data, kind: kind, originalFilename: nil)
            staged.append(asset)
            newPages.append(.init(sourceSize: CGSize(width: 612, height: 792),
                                  content: kind == .pdf ? .pdfPage(asset.id, index: 0) : .image(asset.id)))
        }
        return try await lib.store.createItem(kind: .document, name: "Bundle", pages: newPages, assets: staged).id
    }

    private func scanner(_ lib: TestLibrary) -> PageCleanupScanner {
        PageCleanupScanner(renderer: lib.renderer, store: lib.store)
    }

    @Test func aReadBlankScanIsChosenAnUnreadOneAndAFaintMarkAreOnlyOffered() async throws {
        let lib = try TestLibrary()
        let words = SyntheticDocuments.textPDF(pages: ["Quarterly report sales grew across every region this year"])
        let item = try await document(lib, [(words, .pdf), (scan(), .png), (scan(mark: 0.72), .png)])
        // Read the two scans: completed recognitions with no lines, so only ink can tell them apart.
        let pages = try await lib.store.pages(of: item)
        for page in pages[1...] {
            try await lib.store.saveRecognition(PageRecognition(pageID: page.id, sourceRevision: page.revision,
                                                                engineVersion: "test", status: .completed, languages: ["en-US"], lines: []))
        }

        let suggestions = try await scanner(lib).suggestions(for: item)

        let blank = try #require(suggestions.first { $0.page == 1 })
        #expect(blank.reason == .blank && blank.isPreselected, "read, no words, no ink")
        #expect(!suggestions.contains { $0.page == 0 }, "a page of words is not blank")
        // The faint margin note, light enough to vanish in the small picture: read and
        // wordless like the blank one, it is not chosen, only offered to look at.
        let faint = try #require(suggestions.first { $0.page == 2 })
        #expect(faint.reason == .looksBlank && !faint.isPreselected)
    }

    @Test func anUnreadBlankScanIsOnlyOffered() async throws {
        let lib = try TestLibrary()
        let item = try await document(lib, [(scan(), .png)])
        let suggestions = try await scanner(lib).suggestions(for: item)
        #expect(suggestions.map(\.reason) == [.looksBlank])
        #expect(suggestions.allSatisfy { !$0.isPreselected })
    }

    @Test func theSamePageAgainIsADuplicateAndTheBookmarkedCopyIsKept() async throws {
        let lib = try TestLibrary()
        let statement = SyntheticDocuments.textPDF(pages: ["Account statement for November with three payments listed"])
        let item = try await document(lib, [(statement, .pdf), (statement, .pdf)])
        let pages = try await lib.store.pages(of: item)

        let plain = try await scanner(lib).suggestions(for: item)
        #expect(plain == [CleanupSuggestion(page: 1, reason: .duplicate(of: 0), isPreselected: true, attachments: [])])

        _ = try await lib.store.addBookmark(on: pages[1].id, name: "Keep")
        let bookmarked = try await scanner(lib).suggestions(for: item)
        #expect(bookmarked == [CleanupSuggestion(page: 0, reason: .duplicate(of: 1), isPreselected: true, attachments: [])])
    }

    /// A PDF page without text is a picture nobody has read: only offered,
    /// until a recognition reads it and finds nothing.
    @Test func aPictureOnlyPDFPageIsUnreadUntilRecognized() async throws {
        let lib = try TestLibrary()
        let item = try await document(lib, [(pictureOnlyPDF(), .pdf)])

        let unread = try await scanner(lib).suggestions(for: item)
        #expect(unread.map(\.reason) == [.looksBlank])
        #expect(unread.allSatisfy { !$0.isPreselected })

        let page = try #require(try await lib.store.pages(of: item).first)
        try await lib.store.saveRecognition(PageRecognition(pageID: page.id, sourceRevision: page.revision, engineVersion: "test",
                                                            status: .completed, languages: ["en-US"], lines: []))
        let read = try await scanner(lib).suggestions(for: item)
        #expect(read == [CleanupSuggestion(page: 0, reason: .blank, isPreselected: true, attachments: [])])
    }

    /// Text someone corrected by hand is kept with its page: that copy stays,
    /// and the losses name it when it is the one offered.
    @Test func theCopyWithCorrectedTextIsKept() async throws {
        let lib = try TestLibrary()
        let statement = SyntheticDocuments.textPDF(pages: ["Account statement for November with three payments listed"])
        let item = try await document(lib, [(statement, .pdf), (statement, .pdf)])
        let pages = try await lib.store.pages(of: item)
        try await lib.store.saveRecognition(PageRecognition(pageID: pages[1].id, sourceRevision: pages[1].revision,
                                                            engineVersion: "test", status: .completed, languages: ["en-US"],
                                                            lines: [], correctedAt: Date()))

        let suggestions = try await scanner(lib).suggestions(for: item)

        #expect(suggestions == [CleanupSuggestion(page: 0, reason: .duplicate(of: 1), isPreselected: true, attachments: [])])
    }

    /// Two separate files saying the same thing: similar, to look at, never chosen.
    @Test func theSameWordsInAnotherFileAreSimilarAndDifferentWordsAreNot() async throws {
        let lib = try TestLibrary()
        let text = "Staff meeting minutes for the month of March approved"
        let first = SyntheticDocuments.textPDF(pages: [text]), second = SyntheticDocuments.textPDF(pages: [text])
        let different = SyntheticDocuments.textPDF(pages: ["Quarterly report sales grew across every region this year"])
        let item = try await document(lib, [(first, .pdf), (second, .pdf), (different, .pdf)])
        let pages = try await lib.store.pages(of: item)
        try #require(pages[0].content != pages[1].content, "two files, two originals")

        let suggestions = try await scanner(lib).suggestions(for: item)

        #expect(suggestions == [CleanupSuggestion(page: 1, reason: .similar(to: 0), isPreselected: false, attachments: [])])
    }

    @Test func anIdenticalDocumentIsFoundAndAMarkedOneIsNot() async throws {
        let lib = try TestLibrary()
        let statement = SyntheticDocuments.textPDF(pages: ["Account statement"])
        let original = try await document(lib, [(statement, .pdf)])
        let copy = try await document(lib, [(statement, .pdf)])
        let marked = try await document(lib, [(statement, .pdf)])
        let page = try #require(try await lib.store.pages(of: marked).first)
        try await lib.store.saveObject(PageObject(pageID: page.id, zKey: "V", payload: .ink(InkStroke(
            tool: .pen, color: .black, width: 2, points: [InkPoint(x: 1, y: 1), InkPoint(x: 9, y: 9)])), modifiedAt: Date()))

        #expect(try await lib.store.identicalDocuments(to: original).map(\.id) == [copy])
        try await lib.store.moveToRecentlyDeleted([copy])
        #expect(try await lib.store.identicalDocuments(to: original).isEmpty, "one in Recently Deleted is not offered")
    }
}
