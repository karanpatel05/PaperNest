import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestRender

/// Reading a real page into a `PageTextLayout`.
///
/// The claim worth testing is not that a word is *found* — a string search
/// does that — but that the box it comes back with sits on the word. So the
/// PDF tests render the page and look at the pixels under the box: ink inside
/// it, and none in the gap either side, which is what an index that had
/// slipped by one character would fail.
@Suite struct PageTextReaderTests {
    private func library() -> (URL, LibraryStore)? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestPageText-\(UUID().uuidString)", isDirectory: true)
        return (try? LibraryStore(directory: url)).map { (url, $0) }
    }

    private func importing(_ data: Data, into store: LibraryStore) async throws -> [Page] {
        let item = try await DocumentImporter(store: store).importItem(.data(data, name: "Fixture"))
        return try await store.pages(of: item.id)
    }

    private func firstHit(_ query: String, in layout: PageTextLayout) throws -> NormalizedRect {
        let wanted = try #require(PageSearchQuery(query))
        let range = try #require(layout.searchText.ranges(of: wanted).first,
                                 "\(query) was not found in: \(layout.text)")
        return try #require(layout.boxes(for: range).first, "\(query) was found but has no box")
    }

    /// The page as pixels, decoded once.
    private struct Ink {
        let width: Int, height: Int
        var buffer: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            buffer = [UInt8](repeating: 0, count: width * height * 4)
            let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        /// How many pixels in `rect` (fractions of the image, top-left
        /// origin) are darker than paper.
        func darkPixels(in rect: CGRect) -> Int {
            let minX = max(0, Int((rect.minX * CGFloat(width)).rounded(.up)))
            let maxX = min(width, Int((rect.maxX * CGFloat(width)).rounded(.down)))
            let minY = max(0, Int((rect.minY * CGFloat(height)).rounded(.up)))
            let maxY = min(height, Int((rect.maxY * CGFloat(height)).rounded(.down)))
            guard minX < maxX, minY < maxY else { return 0 }
            var count = 0
            for y in minY..<maxY {
                for x in minX..<maxX where buffer[(y * width + x) * 4] < 128 { count += 1 }
            }
            return count
        }
    }

    /// Ink under `box`, and clean paper in a strip just before it and just
    /// after it along the line. `box` is a fraction of the rendered image.
    private func expectInkExactlyUnder(_ box: CGRect, in image: CGImage, alongX: Bool = true,
                                       sourceLocation: SourceLocation = #_sourceLocation) {
        let ink = Ink(image)
        #expect(ink.darkPixels(in: box) > 20, "no ink under the box \(box)", sourceLocation: sourceLocation)
        // A sliver of the word-space either side: a third of the line's
        // height is well inside the gap a space leaves at this size.
        let gap = (alongX ? box.height * CGFloat(image.height) / CGFloat(image.width) : box.width
            * CGFloat(image.width) / CGFloat(image.height)) * 0.12
        let before = alongX ? CGRect(x: box.minX - gap, y: box.minY, width: gap * 0.8, height: box.height)
            : CGRect(x: box.minX, y: box.minY - gap, width: box.width, height: gap * 0.8)
        let after = alongX ? CGRect(x: box.maxX + gap * 0.2, y: box.minY, width: gap * 0.8, height: box.height)
            : CGRect(x: box.minX, y: box.maxY + gap * 0.2, width: box.width, height: gap * 0.8)
        #expect(ink.darkPixels(in: before) == 0, "the box starts inside a letter", sourceLocation: sourceLocation)
        #expect(ink.darkPixels(in: after) == 0, "the box stops inside a letter", sourceLocation: sourceLocation)
    }

    private func unit(_ rect: NormalizedRect) -> CGRect {
        CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
    }

    // MARK: - A digital PDF

    @Test func aWordInADigitalPDFIsBoxedWhereItIsDrawn() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.textPDF(pages: ["Invoice total 1234"]), into: store)
        let renderer = PageRenderer(store: store)

        let layout = try await renderer.textLayout(for: pages[0])

        #expect(layout.text == "Invoice total 1234")
        #expect(layout.lines.map(\.origin) == [.embedded])
        let box = try firstHit("total", in: layout)
        let image = try await renderer.renderImage(pages[0], pixelsPerPoint: 3)
        expectInkExactlyUnder(unit(box), in: image)
    }

    /// A hit inside a word covers its letters and not the rest of the word:
    /// "voi" of "Invoice" is narrower than the word, and starts after "In".
    @Test func aHitInsideAWordCoversOnlyItsLetters() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.textPDF(pages: ["Invoice total 1234"]), into: store)

        let layout = try await PageRenderer(store: store).textLayout(for: pages[0])

        let word = try firstHit("invoice", in: layout)
        let part = try firstHit("voi", in: layout)
        #expect(part.x > word.x + 0.005)
        #expect(part.x + part.width < word.x + word.width - 0.005)
        #expect(part.width < word.width * 0.6)
    }

    /// `/Rotate 90`: the file's text runs up the sheet, and the page is shown
    /// turned so that it reads normally. The box has to turn with it.
    @Test(arguments: [90, 180, 270])
    func aRotatedPDFsWordsAreBoxedOnTheUprightPage(degrees: Int) async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.rotatedPDF(degrees: degrees, text: "Rotated invoice total"),
                                        into: store)
        let renderer = PageRenderer(store: store)

        let layout = try await renderer.textLayout(for: pages[0])

        let box = try firstHit("invoice", in: layout)
        let image = try await renderer.renderImage(pages[0], pixelsPerPoint: 3)
        // Text drawn along the file's x axis runs along the page's y axis
        // after a quarter turn.
        expectInkExactlyUnder(unit(box), in: image, alongX: degrees == 180)
    }

    /// A crop box that does not start at the sheet's corner: the page shown
    /// is a window onto the file, and boxes are measured from the window.
    @Test func aPDFWhoseCropBoxIsOffsetStillBoxesItsWords() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let document = try #require(PDFDocument(data: SyntheticDocuments.textPDF(pages: ["Invoice total 1234"])))
        try #require(document.page(at: 0)).setBounds(CGRect(x: 40, y: 560, width: 420, height: 180), for: .cropBox)
        let pages = try await importing(try #require(document.dataRepresentation()), into: store)
        let renderer = PageRenderer(store: store)
        #expect(pages[0].sourceSize == CGSize(width: 420, height: 180))

        let layout = try await renderer.textLayout(for: pages[0])

        let box = try firstHit("total", in: layout)
        let image = try await renderer.renderImage(pages[0], pixelsPerPoint: 3)
        expectInkExactlyUnder(unit(box), in: image)
    }

    /// The reader turned the page in PaperNest. Boxes stay in source space;
    /// `PageGeometry` is what puts them on the turned page, and this is the
    /// mapping the screen uses.
    @Test func aBoxFollowsThePageThroughARotation() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        var pages = try await importing(SyntheticDocuments.textPDF(pages: ["Invoice total 1234"]), into: store)
        let renderer = PageRenderer(store: store)
        let before = try firstHit("total", in: try await renderer.textLayout(for: pages[0]))
        pages[0] = try await store.updateTransform(pages[0].id, to: PageTransform(rotation: .clockwise90))

        let after = try firstHit("total", in: try await renderer.textLayout(for: pages[0]))

        #expect(after == before, "a rotation moved the text in source space")
        let geometry = pages[0].geometry
        let onPage = geometry.pageRect(forNormalizedSourceRect: after)
        let image = try await renderer.renderImage(pages[0], pixelsPerPoint: 3)
        let fraction = CGRect(x: onPage.minX / geometry.pageSize.width, y: onPage.minY / geometry.pageSize.height,
                              width: onPage.width / geometry.pageSize.width,
                              height: onPage.height / geometry.pageSize.height)
        expectInkExactlyUnder(fraction, in: image, alongX: false)
    }

    /// What a crop hides is not found, and the page's search text agrees.
    @Test func textOutsideACropIsNotOnThePage() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        var pages = try await importing(SyntheticDocuments.textPDF(pages: ["Invoice total 1234"]), into: store)
        let renderer = PageRenderer(store: store)
        // The words sit about a sixth of the way down; keep the lower half.
        pages[0] = try await store.updateTransform(
            pages[0].id, to: PageTransform(crop: NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5)))

        let layout = try await renderer.textLayout(for: pages[0])

        #expect(layout.isEmpty)
        #expect(try await searchTexts(renderer, pages) == [PageSearchText(pageString: "")])
    }

    // MARK: - A scan

    private func recognition(for page: Page, lines: [RecognizedLine]) -> PageRecognition {
        PageRecognition(pageID: page.id, sourceRevision: page.revision, engineVersion: "test",
                        status: .completed, languages: ["en-US"], lines: lines)
    }

    @Test func aScanIsReadFromItsRecognisedWords() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.image(width: 800, height: 1000, type: .png), into: store)
        let renderer = PageRenderer(store: store)
        #expect(try await renderer.textLayout(for: pages[0]).isEmpty, "a scan nobody has read has no text")
        let amount = NormalizedRect.exact(x: 0.10, y: 0.20, width: 0.15, height: 0.03)
        let due = NormalizedRect.exact(x: 0.27, y: 0.20, width: 0.08, height: 0.03)
        try await store.saveRecognition(recognition(for: pages[0], lines: [
            RecognizedLine(text: "Amount due", box: .exact(x: 0.10, y: 0.20, width: 0.25, height: 0.03),
                           confidence: 0.9, words: [RecognizedWord(text: "Amount", box: amount),
                                                    RecognizedWord(text: "due", box: due)])]))

        let layout = try await renderer.textLayout(for: pages[0])

        #expect(layout.text == "Amount due")
        #expect(layout.lines.map(\.origin) == [.recognized])
        #expect(try firstHit("due", in: layout) == due)
    }

    /// Recognition from before words had boxes, and a line where Vision
    /// boxed only some of its words: the line is all there is to point at,
    /// and pointing at the line is still true.
    @Test func aLineWithoutAllItsWordBoxesIsFoundAsAWholeLine() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.image(width: 800, height: 1000, type: .png), into: store)
        let old = NormalizedRect.exact(x: 0.1, y: 0.2, width: 0.5, height: 0.03)
        let partial = NormalizedRect.exact(x: 0.1, y: 0.3, width: 0.5, height: 0.03)
        try await store.saveRecognition(recognition(for: pages[0], lines: [
            RecognizedLine(text: "Older words here", box: old, confidence: 0.9),
            RecognizedLine(text: "Three words total", box: partial, confidence: 0.9, words: [
                RecognizedWord(text: "Three", box: .exact(x: 0.1, y: 0.3, width: 0.1, height: 0.03))])]))

        let layout = try await PageRenderer(store: store).textLayout(for: pages[0])

        #expect(try firstHit("words here", in: layout) == old)
        #expect(try firstHit("total", in: layout) == partial, "a word Vision did not box became unfindable")
    }

    /// A digital PDF that was also run through recognition says each word
    /// once, from the file.
    @Test func aPDFsOwnTextWinsOverRecognitionOfTheSamePage() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.textPDF(pages: ["Invoice total 1234"]), into: store)
        try await store.saveRecognition(recognition(for: pages[0], lines: [
            RecognizedLine(text: "Invoice total 1234", box: .exact(x: 0.1, y: 0.15, width: 0.4, height: 0.03),
                           confidence: 0.9)]))

        let layout = try await PageRenderer(store: store).textLayout(for: pages[0])

        #expect(layout.searchText.ranges(of: try #require(PageSearchQuery("total"))).count == 1)
        #expect(layout.lines.map(\.origin) == [.embedded])
    }

    // MARK: - Typed text

    @Test func wordsTypedOntoAPageAreFoundInTheirBox() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        var pages = try await importing(SyntheticDocuments.textPDF(pages: ["Invoice total 1234"]), into: store)
        let frame = CGRect(x: 100, y: 300, width: 200, height: 40)
        pages[0] = try await store.placeText("Call the bank\non Monday", on: pages[0].id, frame: frame, fontSize: 14,
                                             color: .black, alignment: .leading).page

        let layout = try await PageRenderer(store: store).textLayout(for: pages[0])

        #expect(layout.lines.map(\.origin) == [.embedded, .typed])
        let box = try firstHit("bank on monday", in: layout)
        #expect(abs(box.x - 100.0 / 612) < 1e-9 && abs(box.y - 300.0 / 792) < 1e-9)
        #expect(abs(box.width - 200.0 / 612) < 1e-9 && abs(box.height - 40.0 / 792) < 1e-9)
        // The file's own words are still there, in front.
        #expect(layout.text.hasPrefix("Invoice total 1234\n"))
    }

    // MARK: - A whole document

    private func searchTexts(_ renderer: PageRenderer, _ pages: [Page]) async throws -> [PageSearchText] {
        let collected = Collector()
        try await renderer.searchTexts(for: pages) { id, text in await collected.add(id, text) }
        let found = await collected.entries
        #expect(found.map(\.0) == pages.map(\.id), "pages were skipped, repeated or reordered")
        return found.map(\.1)
    }

    private actor Collector {
        var entries: [(PageID, PageSearchText)] = []
        func add(_ id: PageID, _ text: PageSearchText) { entries.append((id, text)) }
    }

    /// Find counts hits from each page's text alone and works out boxes only
    /// for the page on screen. If the two disagreed about what a page says,
    /// a hit counted on one page would light the wrong letters when shown.
    @Test func everyPagesSearchTextIsTheSearchTextOfItsLayout() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let importer = DocumentImporter(store: store)
        let item = try await importer.importItem(.data(SyntheticDocuments.textPDF(
            pages: ["First page\nStra\u{DF}e  two   spaces", "Second page", "Third page", "Fourth page"]), name: "Mixed"))
        var pages = try await store.pages(of: item.id)
        // One page typed on, one cropped, one left alone, one with nothing
        // but a scan's recognised words.
        pages[1] = try await store.placeText("A typed note", on: pages[1].id,
                                             frame: CGRect(x: 80, y: 400, width: 200, height: 30), fontSize: 14,
                                             color: .black, alignment: .leading).page
        pages[2] = try await store.updateTransform(
            pages[2].id, to: PageTransform(crop: NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        let scan = try await importer.importItem(
            .data(SyntheticDocuments.image(width: 800, height: 1000, type: .png), name: "Scan"))
        let scanned = try await store.pages(of: scan.id)
        try await store.saveRecognition(recognition(for: scanned[0], lines: [
            RecognizedLine(text: "Recognised words", box: .exact(x: 0.1, y: 0.1, width: 0.4, height: 0.03),
                           confidence: 0.9)]))
        let all = pages + scanned
        let renderer = PageRenderer(store: store)

        let texts = try await searchTexts(renderer, all)

        for (page, text) in zip(all, texts) {
            #expect(try await renderer.textLayout(for: page).searchText == text)
        }
        #expect(texts[0].folded == "first page strasse two spaces")
        #expect(texts[1].folded == "second page a typed note")
        #expect(texts[4].folded == "recognised words")
    }

    /// A notebook page is a template with nothing on it.
    @Test func aPageWithNoTextAnswersEmptyRatherThanFailing() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let pages = try await importing(SyntheticDocuments.scannedPDF(), into: store)
        let renderer = PageRenderer(store: store)

        #expect(try await renderer.textLayout(for: pages[0]).isEmpty)
        #expect(try await searchTexts(renderer, pages).allSatisfy(\.isEmpty))
    }

    /// Character boxes are asked for one at a time. That has to stay cheap
    /// for a full page, because it is paid when a page with hits is shown.
    @Test func aDensePageIsLaidOutQuickly() async throws {
        let (url, store) = try #require(library())
        defer { try? FileManager.default.removeItem(at: url) }
        let line = String(repeating: "lorem ipsum dolor sit amet ", count: 3)
        let pages = try await importing(SyntheticDocuments.textPDF(
            pages: [Array(repeating: line, count: 24).joined(separator: "\n")]), into: store)
        let renderer = PageRenderer(store: store)

        var layout = PageTextLayout.empty
        let elapsed = try await ContinuousClock().measure { layout = try await renderer.textLayout(for: pages[0]) }

        let characters = layout.lines.reduce(0) { $0 + $1.fragments.count }
        #expect(characters > 1000, "the fixture is not dense: \(characters) characters")
        #expect(elapsed < .seconds(1), "\(characters) characters took \(elapsed)")
        print("PageTextReader: \(characters) characters laid out in \(elapsed)")
    }
}
