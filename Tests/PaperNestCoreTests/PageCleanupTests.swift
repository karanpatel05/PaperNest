import Foundation
import Testing
@testable import PaperNestCore

/// Which pages to offer for removal, and which to choose to start with.
@Suite struct PageCleanupTests {
    private let scan = PageContent.image(AssetID(sha256: String(repeating: "a", count: 64)))
    private let other = PageContent.image(AssetID(sha256: String(repeating: "b", count: 64)))
    private let flat = [Double](repeating: 1, count: 256)

    private func page(_ index: Int, _ content: PageContent? = nil, words: [String]? = [], ink: Double = 0,
                      marks: [PageObject.Payload] = [], attachments: Set<CleanupAttachment> = [],
                      fingerprint: [Double]? = nil) -> CleanupPage {
        CleanupPage(index: index, content: content ?? scan, transform: .identity, marks: marks, words: words,
                    inkRatio: ink, fingerprint: fingerprint ?? flat, attachments: attachments)
    }

    private let note = PageObject.Payload.text(TextBox(frame: CGRect(x: 10, y: 10, width: 100, height: 20), text: "note"))

    // MARK: - Blank

    @Test func aReadPageWithNoWordsMarksOrInkIsBlankAndChosen() {
        let pages = [page(0, other, words: ["Invoice", "total"], ink: 0.08), page(1, words: [], ink: 0.0001)]
        #expect(PageCleanup.blankCandidates(pages) == [1])
        let blank = PageCleanup.blankSuggestions(pages, detailInk: [1: 0.0001])
        #expect(blank == [CleanupSuggestion(page: 1, reason: .blank, isPreselected: true, attachments: [])])
    }

    /// A faint pencil mark the small picture averaged away shows at the large size.
    @Test func faintInkAtTheLargeSizeIsNotBlankAndNotChosen() {
        let pages = [page(0, words: [], ink: 0.0002)]
        let blank = PageCleanup.blankSuggestions(pages, detailInk: [0: 0.002])
        #expect(blank.map(\.reason) == [.looksBlank])
        #expect(blank.allSatisfy { !$0.isPreselected })
    }

    /// A scan nobody has read has no words, which says nothing about it.
    @Test func anUnreadScanIsNeverChosenAsBlank() {
        let blank = PageCleanup.blankSuggestions([page(0, words: nil, ink: 0.0001)], detailInk: [0: 0.0001])
        #expect(blank.map(\.reason) == [.looksBlank])
        #expect(!blank[0].isPreselected)
    }

    @Test func anEmptyNotebookPageIsOfferedButNotChosen() {
        let lined = page(0, .template(.lined), ink: 0.05)
        #expect(PageCleanup.blankCandidates([lined]) == [0], "its rules are ink, not writing")
        let blank = PageCleanup.blankSuggestions([lined], detailInk: [:])
        #expect(blank == [CleanupSuggestion(page: 0, reason: .blank, isPreselected: false, attachments: [])])
    }

    @Test func aPageWithMarksOrSomethingAttachedIsNotChosen() {
        #expect(PageCleanup.blankCandidates([page(0, marks: [note])]).isEmpty)
        let commented = PageCleanup.blankSuggestions([page(0, attachments: [.comment])], detailInk: [0: 0])
        #expect(commented.map(\.isPreselected) == [false])
        #expect(commented.first?.attachments == [.comment])
    }

    // MARK: - Duplicates

    @Test func theSameOriginalAndMarksAgainIsADuplicateOfTheFirst() {
        let pages = [page(0, words: ["a", "b"], ink: 0.1, marks: [note]), page(1, other, ink: 0.1),
                     page(2, words: ["a", "b"], ink: 0.1, marks: [note])]
        #expect(PageCleanup.exactDuplicates(pages) == [
            CleanupSuggestion(page: 2, reason: .duplicate(of: 0), isPreselected: true, attachments: [])])
    }

    /// The copy carrying a bookmark is the one kept, even when it comes later.
    @Test func theCopyWithABookmarkIsKept() {
        let pages = [page(0, ink: 0.1), page(1, ink: 0.1, attachments: [.bookmark])]
        #expect(PageCleanup.exactDuplicates(pages) == [
            CleanupSuggestion(page: 0, reason: .duplicate(of: 1), isPreselected: true, attachments: [])])
    }

    @Test func differentMarksOrCropAreNotDuplicates() {
        var cropped = page(1, ink: 0.1)
        cropped.transform = PageTransform(crop: NormalizedRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
        #expect(PageCleanup.exactDuplicates([page(0, ink: 0.1), page(1, ink: 0.1, marks: [note])]).isEmpty)
        #expect(PageCleanup.exactDuplicates([page(0, ink: 0.1), cropped]).isEmpty)
    }

    /// Five empty lined pages are blank pages, not four duplicates.
    @Test func emptyNotebookPagesAreNotDuplicatesOfEachOther() {
        let pages = (0..<5).map { page($0, .template(.lined)) }
        #expect(PageCleanup.exactDuplicates(pages).isEmpty)
    }

    // MARK: - Similar

    private let wordsA = "Quarterly report sales grew across every region".split(separator: " ").map(String.init)
    private let wordsB = "Staff meeting minutes for the month of March".split(separator: " ").map(String.init)

    @Test func theSameWordsFromAnotherOriginalAreSimilar() {
        let pairs = PageCleanup.similarCandidates([page(0, words: wordsA, ink: 0.1), page(1, other, words: wordsA, ink: 0.1)],
                                                  excluding: [])
        #expect(pairs == [PageCleanup.SimilarPair(page: 1, of: 0, needsPictureCheck: false)])
    }

    /// Every page of a text document shares a layout: that is no evidence.
    @Test func differentWordsWithTheSameLookAreNotSimilar() {
        let pairs = PageCleanup.similarCandidates([page(0, words: wordsA, ink: 0.1), page(1, other, words: wordsB, ink: 0.1)],
                                                  excluding: [])
        #expect(pairs.isEmpty)
    }

    /// Without words, the same look is only a candidate for the pictures to settle.
    @Test func theSameLookWithoutWordsNeedsThePicturesToConfirm() {
        let pairs = PageCleanup.similarCandidates([page(0, words: nil, ink: 0.1), page(1, other, words: nil, ink: 0.1)],
                                                  excluding: [])
        #expect(pairs == [PageCleanup.SimilarPair(page: 1, of: 0, needsPictureCheck: true)])
    }

    /// A signed copy is not "similar" to the unsigned one, by words or by look.
    @Test func theSameWordsOrLookWithDifferentMarksAreNotSimilar() {
        let byWords = PageCleanup.similarCandidates([page(0, words: wordsA, ink: 0.1),
                                                     page(1, other, words: wordsA, ink: 0.1, marks: [note])], excluding: [])
        let byLook = PageCleanup.similarCandidates([page(0, words: nil, ink: 0.1),
                                                    page(1, other, words: nil, ink: 0.1, marks: [note])], excluding: [])
        #expect(byWords.isEmpty)
        #expect(byLook.isEmpty)
    }

    /// One page's "é" typed as one character, another's as e and an accent: the same word.
    @Test func wordsCompareInOneNormalForm() {
        let composed = ["Caf\u{E9}", "menu", "for", "the", "week", "ahead"]
        let decomposed = ["Cafe\u{301}", "menu", "for", "the", "week", "ahead"]
        let pairs = PageCleanup.similarCandidates([page(0, words: composed, ink: 0.1), page(1, other, words: decomposed, ink: 0.1)],
                                                  excluding: [])
        #expect(pairs == [PageCleanup.SimilarPair(page: 1, of: 0, needsPictureCheck: false)])
    }

    /// Three pages with the same words: both later ones are similar to the first.
    @Test func severalPagesWithTheSameWordsPointAtTheFirst() {
        let pages = [page(0, words: wordsA, ink: 0.1), page(1, words: wordsB, ink: 0.1),
                     page(2, other, words: wordsA, ink: 0.1),
                     page(3, .image(AssetID(sha256: String(repeating: "c", count: 64))), words: wordsA, ink: 0.1)]
        #expect(PageCleanup.similarCandidates(pages, excluding: []).map { [$0.page, $0.of] } == [[2, 0], [3, 0]])
    }

    /// Hand-corrected recognized text goes with its page: that copy is kept.
    @Test func theCopyWithCorrectedTextIsKept() {
        let pages = [page(0, ink: 0.1), page(1, ink: 0.1, attachments: [.correctedText])]
        #expect(PageCleanup.exactDuplicates(pages) == [
            CleanupSuggestion(page: 0, reason: .duplicate(of: 1), isPreselected: true, attachments: [])])
        let blank = PageCleanup.blankSuggestions([page(0, attachments: [.correctedText])], detailInk: [0: 0])
        #expect(blank.map(\.isPreselected) == [false], "a blank page with corrected text is offered, not chosen")
    }

    @Test func onePageGetsOneSuggestion() {
        let all = PageCleanup.suggestions(
            blank: [CleanupSuggestion(page: 2, reason: .blank, isPreselected: true, attachments: [])],
            duplicates: [CleanupSuggestion(page: 2, reason: .duplicate(of: 0), isPreselected: true, attachments: []),
                         CleanupSuggestion(page: 1, reason: .duplicate(of: 0), isPreselected: true, attachments: [])],
            similar: [])
        #expect(all.map(\.page) == [1, 2])
        #expect(all.last?.reason == .blank)
    }

    @Test func inkIsWhatIsClearlyDarkerThanPaper() {
        var pixels = [UInt8](repeating: 255, count: 100)
        pixels[0] = 190      // pencil
        pixels[1] = 230      // scanner grey
        #expect(GrayPicture(width: 10, height: 10, pixels: pixels).inkRatio() == 0.01)
    }
}
