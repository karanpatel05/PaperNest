import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// Find in a document, at the level where it can be wrong without anyone
/// noticing: which characters count as the same, where a phrase is allowed to
/// break, and which boxes a hit lights up.
///
/// A layout comes at two grains. A digital PDF gives a box per character, so a
/// hit covers exactly its letters. Recognition gives a box per word, so a hit
/// inside a word lights the whole word — the alternative, dividing the word's
/// box by its letters, drifts on any proportional font.
@Suite struct PageTextLayoutTests {
    private typealias Fragment = PageTextLayout.Fragment
    private typealias Line = PageTextLayout.Line

    /// Words on one row, each 0.1 wide with a gap after it.
    private func words(_ texts: [String], y: Double = 0.1, origin: PageTextLayout.Origin = .recognized) -> Line {
        Line(fragments: texts.enumerated().map { index, text in
            Fragment(text: text, box: .exact(x: 0.1 + Double(index) * 0.15, y: y, width: 0.1, height: 0.03),
                     spaceAfter: true)
        }, origin: origin)
    }

    /// One fragment per character, as a digital PDF reports them. A space is
    /// not a fragment: it is `spaceAfter` on the character before it.
    private func characters(_ text: String, y: Double = 0.1) -> Line {
        var fragments: [Fragment] = []
        var column = 0
        for character in text {
            if character == " " {
                if !fragments.isEmpty { fragments[fragments.count - 1].spaceAfter = true }
            } else {
                fragments.append(Fragment(text: String(character),
                                          box: .exact(x: 0.1 + Double(column) * 0.02, y: y, width: 0.02, height: 0.03)))
            }
            column += 1
        }
        return Line(fragments: fragments, origin: .embedded)
    }

    private func hits(_ query: String, in layout: PageTextLayout) throws -> [Range<Int>] {
        layout.searchText.ranges(of: try #require(PageSearchQuery(query)))
    }

    // MARK: - What counts as the same text

    @Test func findIsBlindToCaseAndAccents() throws {
        let layout = PageTextLayout(lines: [words(["Résumé", "TOTAL", "ñandú"])])

        #expect(try hits("resume", in: layout).count == 1)
        #expect(try hits("RÉSUMÉ", in: layout).count == 1)
        #expect(try hits("total", in: layout).count == 1)
        #expect(try hits("nandu", in: layout).count == 1)
    }

    /// Folding changes how long a string is — ß becomes ss, the ﬁ ligature
    /// becomes fi — so a hit after one of those has to be traced back to the
    /// right word rather than counted off by position.
    @Test func aHitAfterAFoldThatChangedLengthStillLandsOnItsOwnWord() throws {
        let layout = PageTextLayout(lines: [words(["Straße", "ﬁnal", "invoice"])])

        let found = try hits("invoice", in: layout)

        #expect(found.count == 1)
        #expect(layout.boxes(for: try #require(found.first)) == [layout.lines[0].fragments[2].box])
        #expect(try hits("strasse", in: layout).count == 1)
        #expect(try hits("final", in: layout).count == 1)
    }

    @Test func extraSpacingInTheQueryIsForgiven() throws {
        let layout = PageTextLayout(lines: [words(["Invoice", "total"])])

        #expect(try hits("  invoice \t  total ", in: layout).count == 1)
    }

    @Test func nothingToLookForIsNotAQuery() {
        #expect(PageSearchQuery("") == nil)
        #expect(PageSearchQuery("  \n\t ") == nil)
    }

    @Test func hitsDoNotOverlap() throws {
        let layout = PageTextLayout(lines: [characters("aaaa")])

        #expect(try hits("aa", in: layout).count == 2)
    }

    // MARK: - Where a phrase may break

    /// A sentence does not stop being a sentence where the paper ran out.
    @Test func aPhraseIsFoundAcrossALineBreakWithABoxOnEachLine() throws {
        let layout = PageTextLayout(lines: [words(["Invoice", "total"], y: 0.1), words(["1234", "EUR"], y: 0.2)])

        let found = try hits("total 1234", in: layout)

        #expect(found.count == 1)
        let boxes = layout.boxes(for: try #require(found.first))
        #expect(boxes == [layout.lines[0].fragments[1].box, layout.lines[1].fragments[0].box])
    }

    /// The end of one word and the start of the next are not a word.
    @Test func wordsAreNotRunTogether() throws {
        let layout = PageTextLayout(lines: [words(["Invoice", "total"])])

        #expect(try hits("invoicetotal", in: layout).isEmpty)
    }

    // MARK: - Which boxes a hit covers

    @Test func aHitInsideARecognisedWordCoversTheWholeWord() throws {
        let layout = PageTextLayout(lines: [words(["Quarterly", "report"])])

        let found = try hits("repo", in: layout)

        #expect(layout.boxes(for: try #require(found.first)) == [layout.lines[0].fragments[1].box])
    }

    @Test func aHitInCharacterBoxesCoversOnlyItsLetters() throws {
        let layout = PageTextLayout(lines: [characters("cat hat")])

        let found = try hits("at", in: layout)

        #expect(found.count == 2)
        let first = try #require(layout.boxes(for: found[0]).first)
        // "a" and "t" of "cat": columns 1 and 2.
        #expect(abs(first.x - 0.12) < 1e-9)
        #expect(abs(first.width - 0.04) < 1e-9)
        let second = try #require(layout.boxes(for: found[1]).first)
        // "a" and "t" of "hat": columns 5 and 6.
        #expect(abs(second.x - 0.20) < 1e-9)
        #expect(abs(second.width - 0.04) < 1e-9)
    }

    /// A phrase across characters and a space is one box from its first
    /// letter to its last, not two with a hole where the space is.
    @Test func aPhraseOnOneLineIsOneBox() throws {
        let layout = PageTextLayout(lines: [characters("cat hat")])

        let found = try hits("cat hat", in: layout)

        let boxes = layout.boxes(for: try #require(found.first))
        #expect(boxes.count == 1)
        #expect(abs(boxes[0].x - 0.10) < 1e-9)
        #expect(abs(boxes[0].width - 0.14) < 1e-9)
    }

    /// A typed text box is one fragment holding several words, on several
    /// lines of its own.
    @Test func aFragmentHoldingSeveralWordsIsSearchedAsWords() throws {
        let box = NormalizedRect.exact(x: 0.2, y: 0.4, width: 0.5, height: 0.2)
        let layout = PageTextLayout(lines: [
            Line(fragments: [Fragment(text: "Meeting   notes\nfor Monday", box: box)], origin: .typed)])

        let found = try hits("notes for", in: layout)

        #expect(found.count == 1)
        #expect(layout.boxes(for: try #require(found.first)) == [box])
    }

    /// A character PDFKit could not place has no box. It still has to be
    /// counted, or every hit after it would point one letter along.
    @Test func aCharacterWithNoBoxIsSkippedWithoutShiftingTheRest() throws {
        var line = characters("abc")
        line.fragments[1].box = .exact(x: 0, y: 0, width: 0, height: 0)
        let layout = PageTextLayout(lines: [line])

        let boxes = layout.boxes(for: try #require(try hits("abc", in: layout).first))

        #expect(boxes.count == 1)
        #expect(abs(boxes[0].x - 0.10) < 1e-9)
        #expect(abs(boxes[0].width - 0.06) < 1e-9)
        let last = layout.boxes(for: try #require(try hits("c", in: layout).first))
        #expect(last == [line.fragments[2].box])
    }

    @Test func aRangeThatTouchesNoTextHasNoBoxes() {
        let layout = PageTextLayout(lines: [words(["Invoice", "total"])])

        #expect(layout.boxes(for: 400..<410).isEmpty)
        #expect(PageTextLayout.empty.boxes(for: 0..<3).isEmpty)
    }

    // MARK: - A raw page string

    /// Find reads every page of a long document as plain text first, and
    /// works out boxes only for the page on screen. Both have to agree on
    /// what the text *is*, or a hit counted on page 40 lights the wrong
    /// letters when page 40 is shown.
    @Test func aRawPageStringSearchesExactlyLikeTheLayoutBuiltFromIt() {
        let raw = "Invoice\ttotal  \r\n  Stra\u{DF}e  e\u{301}cole\n\n\u{FB01}nal   line \n"

        let layout = PageTextLayout(lines: PageTextTokenizer.lines(of: raw).map { tokens in
            PageTextLayout.Line(fragments: tokens.map {
                PageTextLayout.Fragment(text: $0.text, box: .exact(x: 0, y: 0, width: 0.01, height: 0.01),
                                        spaceAfter: $0.spaceAfter)
            }, origin: .embedded)
        })

        #expect(PageSearchText(pageString: raw) == layout.searchText)
        #expect(layout.searchText.folded == "invoice total strasse ecole final line")
    }

    /// A token's range is where it sits in the raw string, in the UTF-16
    /// units PDFKit counts characters in.
    @Test func tokensRememberWhereTheyCameFrom() {
        let raw = "a \u{1F600}b\ne\u{301}"

        let lines = PageTextTokenizer.lines(of: raw)

        #expect(lines.map { $0.map(\.text) } == [["a", "\u{1F600}", "b"], ["e\u{301}"]])
        #expect(lines[0].map(\.range) == [NSRange(location: 0, length: 1), NSRange(location: 2, length: 2),
                                         NSRange(location: 4, length: 1)])
        #expect(lines[1].map(\.range) == [NSRange(location: 6, length: 2)])
        #expect(lines[0].map(\.spaceAfter) == [true, false, false])
    }

    // MARK: - Reading and cropping

    @Test func textReadsALinePerLine() {
        let layout = PageTextLayout(lines: [characters("cat hat"), words(["Invoice", "total"])])

        #expect(layout.text == "cat hat\nInvoice total")
    }

    /// What a crop hides is not on the page as far as a reader can tell, so
    /// find must not count it and then have nothing to show.
    @Test func aCropLeavesOnlyTheTextThatStillShows() throws {
        let layout = PageTextLayout(lines: [words(["Kept", "words"], y: 0.1), words(["Hidden", "words"], y: 0.8)])

        let cropped = layout.cropped(to: NormalizedRect(x: 0, y: 0, width: 1, height: 0.5))

        #expect(cropped.text == "Kept words")
        #expect(try hits("words", in: cropped).count == 1)
        #expect(layout.cropped(to: .full) == layout)
    }

    @Test func anEmptyLayoutSaysSo() {
        #expect(PageTextLayout.empty.isEmpty)
        #expect(PageTextLayout(lines: [PageTextLayout.Line(fragments: [], origin: .typed)]).isEmpty)
        #expect(PageTextLayout.empty.searchText.isEmpty)
        #expect(!PageTextLayout(lines: [words(["a"])]).isEmpty)
    }
}
