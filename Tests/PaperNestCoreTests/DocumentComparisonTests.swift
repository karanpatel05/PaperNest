import CoreGraphics
import Testing
@testable import PaperNestCore

/// Comparing pages: words from a page's text, pictures always, and every
/// highlight in each page's own source space.
@Suite struct DocumentComparisonTests {
    // MARK: - Words from a page's text

    @Test func aPDFsCharactersBecomeWordsWithOneBoxEach() {
        // "Pay 42": characters, a space after "y".
        let layout = PageTextLayout(lines: [PageTextLayout.Line(fragments: [
            .init(text: "P", box: .exact(x: 0.1, y: 0.1, width: 0.02, height: 0.03)),
            .init(text: "a", box: .exact(x: 0.12, y: 0.1, width: 0.02, height: 0.03)),
            .init(text: "y", box: .exact(x: 0.14, y: 0.1, width: 0.02, height: 0.03), spaceAfter: true),
            .init(text: "4", box: .exact(x: 0.2, y: 0.1, width: 0.02, height: 0.03)),
            .init(text: "2", box: .exact(x: 0.22, y: 0.1, width: 0.02, height: 0.03)),
        ], origin: .embedded)])

        let text = layout.comparisonText

        #expect(text.words.map(\.text) == ["Pay", "42"])
        #expect(text.source == .embedded)
        let pay = text.words[0].box
        #expect(abs(pay.x - 0.1) < 1e-9 && abs(pay.width - 0.06) < 1e-9)
    }

    @Test func typedTextBoxesAreLeftOutAndRecognizedLinesSplit() {
        let layout = PageTextLayout(lines: [
            PageTextLayout.Line(fragments: [.init(text: "Total due", box: .exact(x: 0.1, y: 0.5, width: 0.3, height: 0.04),
                                                  spaceAfter: true)], origin: .recognized),
            PageTextLayout.Line(fragments: [.init(text: "My note", box: .exact(x: 0.1, y: 0.8, width: 0.3, height: 0.04),
                                                  spaceAfter: true)], origin: .typed),
        ])

        let text = layout.comparisonText

        #expect(text.words.map(\.text) == ["Total", "due"], "a typed box is a mark, not the document's text")
        #expect(text.source == .recognized)
        #expect(text.words.allSatisfy { $0.box == .exact(x: 0.1, y: 0.5, width: 0.3, height: 0.04) })
        #expect(PageTextLayout(lines: [layout.lines[1]]).comparisonText == .none)
    }

    // MARK: - Pictures

    private func picture(_ width: Int = 80, _ height: Int = 100, dark: [(x: Range<Int>, y: Range<Int>)] = []) -> GrayPicture {
        var pixels = [UInt8](repeating: 255, count: width * height)
        for block in dark { for y in block.y { for x in block.x { pixels[y * width + x] = 0 } } }
        return GrayPicture(width: width, height: height, pixels: pixels)
    }

    @Test func identicalPicturesHaveNoDifference() {
        let page = picture(dark: [(10..<30, 10..<20)])
        #expect(PictureDifference.regions(page, page).isEmpty)
    }

    @Test func aMarkOnOneSideIsOneRegionWhereItIs() {
        let old = picture()
        let new = picture(dark: [(40..<60, 70..<80)])   // lower right
        let regions = PictureDifference.regions(old, new)
        #expect(regions.count == 1)
        let region = regions[0]
        #expect(region.x <= 0.5 + 1e-9 && region.x + region.width >= 0.75 - 1e-9)
        #expect(region.y <= 0.7 + 1e-9 && region.y + region.height >= 0.8 - 1e-9)
    }

    @Test func aDifferenceUnderIgnoredAreasIsNotCounted() {
        let new = picture(dark: [(40..<60, 70..<80)])
        #expect(PictureDifference.regions(picture(), new, ignoring: [.exact(x: 0.4, y: 0.6, width: 0.5, height: 0.3)]).isEmpty)
    }

    /// A one-pixel fringe — a letter drawn half a pixel over — is not a difference.
    @Test func faintFringesAreNotDifferences() {
        var new = picture().pixels
        for y in 0..<100 { new[y * 80 + 40] = 200 }
        #expect(PictureDifference.regions(picture(), GrayPicture(width: 80, height: 100, pixels: new)).isEmpty)
    }

    // MARK: - Pages

    private let size = CGSize(width: 600, height: 800)
    private func words(_ text: String) -> ComparisonPageText {
        ComparisonPageText(words: text.split(separator: " ").enumerated().map { index, word in
            ComparisonWord(text: String(word), box: .exact(x: 0.1 + Double(index) * 0.1, y: 0.1, width: 0.08, height: 0.03))
        }, source: .embedded)
    }
    /// The picture of a page with its line of words drawn as a dark band.
    private func withWords(_ extra: [(x: Range<Int>, y: Range<Int>)] = []) -> GrayPicture {
        picture(60, 80, dark: [(6..<54, 8..<10)] + extra)
    }

    @Test func aChangedWordIsAChangeWithBothWordsAndTheirBoxes() {
        let geometry = PageGeometry(sourceSize: size)
        let old = ComparedPage(text: words("Paid on 3 March"), picture: withWords(), geometry: geometry)
        let new = ComparedPage(text: words("Paid on 3 April"), picture: withWords(), geometry: geometry)

        let page = PageComparison.compare(old, new, oldIndex: 0, newIndex: 0, moved: false)

        #expect(page.kind == .changed)
        #expect(page.method == .text(.embedded))
        #expect(page.textChanges.map { $0.removed.map(\.text) } == [["March"]])
        #expect(page.textChanges.map { $0.added.map(\.text) } == [["April"]])
        #expect(page.oldPictureRegions.isEmpty, "the pictures differ only under words, which the words account for")
    }

    /// The same words over a changed drawing, stamp or photo: not "Same".
    @Test func matchingWordsOverAChangedPictureAreAChange() {
        let geometry = PageGeometry(sourceSize: size)
        let old = ComparedPage(text: words("Invoice total 42"), picture: withWords(), geometry: geometry)
        let new = ComparedPage(text: words("Invoice total 42"), picture: withWords([(10..<30, 50..<70)]), geometry: geometry)

        let page = PageComparison.compare(old, new, oldIndex: 0, newIndex: 0, moved: false)

        #expect(page.textChanges.isEmpty)
        #expect(page.kind == .changed)
        #expect(page.pictureDifferenceCount == 1)
    }

    @Test func aPageWithoutWordsIsComparedAsAPictureAndSaysWhy() {
        let geometry = PageGeometry(sourceSize: size)
        let digital = ComparedPage(text: words("Invoice total 42"), picture: withWords(), geometry: geometry)
        let scan = ComparedPage(text: .none, picture: withWords(), geometry: geometry)

        #expect(PageComparison.compare(digital, scan, oldIndex: 0, newIndex: 0, moved: false).method == .picture(.noTextOnNew))
        #expect(PageComparison.compare(scan, digital, oldIndex: 0, newIndex: 0, moved: false).method == .picture(.noTextOnOld))
        let same = PageComparison.compare(scan, scan, oldIndex: 0, newIndex: 0, moved: false)
        #expect(same.method == .picture(.noTextOnEither))
        #expect(same.kind == .same)
    }

    @Test func recognizedWordsOnEitherSideAreSaid() {
        let geometry = PageGeometry(sourceSize: size)
        var read = words("Invoice total 42"); read.source = .recognized
        let page = PageComparison.compare(ComparedPage(text: words("Invoice total 42"), picture: withWords(), geometry: geometry),
                                          ComparedPage(text: read, picture: withWords(), geometry: geometry),
                                          oldIndex: 0, newIndex: 0, moved: false)
        #expect(page.method == .text(.recognized))
    }

    /// A picture difference found on a rotated, cropped page comes back in
    /// its source space and lands where it was seen.
    @Test(arguments: [QuarterTurns.none, .clockwise90, .half, .clockwise270])
    func pictureRegionsAreInEachPagesSourceSpace(_ rotation: QuarterTurns) throws {
        let geometry = PageGeometry(sourceSize: size, crop: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.7),
                                    rotation: rotation)
        let shown = geometry.pageSize
        let width = 60, height = max(1, Int((60 * shown.height / shown.width).rounded()))
        let old = ComparedPage(text: .none, picture: picture(width, height), geometry: geometry)
        // Dark in the picture's top-left quarter.
        let new = ComparedPage(text: .none, picture: picture(width, height, dark: [(0..<(width / 2), 0..<(height / 2))]),
                               geometry: geometry)

        let page = PageComparison.compare(old, new, oldIndex: 0, newIndex: 0, moved: false)

        let region = try #require(page.newPictureRegions.first)
        let onPage = geometry.pageRect(forNormalizedSourceRect: region)
        #expect(onPage.minX < shown.width * 0.05 && onPage.minY < shown.height * 0.05, "\(rotation): \(onPage)")
        #expect(onPage.maxX > shown.width * 0.45 && onPage.maxX < shown.width * 0.6, "\(rotation): \(onPage)")
        #expect(onPage.maxY > shown.height * 0.45 && onPage.maxY < shown.height * 0.6, "\(rotation): \(onPage)")
    }

    // MARK: - Documents

    @Test func aDocumentComparedWithItselfIsIdentical() {
        let geometry = PageGeometry(sourceSize: size)
        let pages = [ComparedPage(text: words("one two three four"), picture: withWords(), geometry: geometry),
                     ComparedPage(text: words("five six seven eight"), picture: withWords(), geometry: geometry)]
        let comparison = DocumentComparison.compare(old: pages, new: pages)
        #expect(comparison.isIdentical)
        #expect(comparison.textChangeCount == 0 && comparison.pictureDifferenceCount == 0)
        #expect(!comparison.comparedOnlyByPicture)
    }

    @Test func countsAreKeptApart() {
        let geometry = PageGeometry(sourceSize: size)
        let old = [ComparedPage(text: words("Paid on 3 March"), picture: withWords(), geometry: geometry)]
        let new = [ComparedPage(text: words("Paid on 3 April"), picture: withWords([(10..<30, 50..<70)]), geometry: geometry),
                   ComparedPage(text: words("an added page here"), picture: withWords(), geometry: geometry)]
        let comparison = DocumentComparison.compare(old: old, new: new)
        #expect(comparison.textChangeCount == 1)
        #expect(comparison.pictureDifferenceCount == 1)
        #expect(comparison.addedPageCount == 1 && comparison.removedPageCount == 0)
    }
}
