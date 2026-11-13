import CoreGraphics
import Foundation
import Testing
@testable import PaperNestCore

/// Selecting text on a page: which letters a finger or a pointer means, what
/// a word is, and what gets copied.
@Suite struct PageTextSelectionTests {
    private typealias Fragment = PageTextLayout.Fragment
    private typealias Line = PageTextLayout.Line

    /// One fragment per character, 0.02 wide, on a row 0.03 tall.
    private func characters(_ text: String, y: Double, origin: PageTextLayout.Origin = .embedded) -> Line {
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
        return Line(fragments: fragments, origin: origin)
    }

    /// "cat hat" on one row and "big dog" on the next.
    private var page: PageTextLayout {
        PageTextLayout(lines: [characters("cat hat", y: 0.10), characters("big dog", y: 0.20)])
    }

    /// The middle of the character in `column` of the row at `y`.
    private func point(column: Int, y: Double) -> CGPoint {
        CGPoint(x: 0.1 + Double(column) * 0.02 + 0.01, y: y + 0.015)
    }

    // MARK: - Which fragment a point means

    @Test func aPointOnALetterMeansThatLetter() throws {
        let index = try #require(page.fragmentIndex(nearest: point(column: 4, y: 0.10)))

        #expect(page.text(in: index...index) == "h")
    }

    /// Dragging into the margin past the end of a line still means that line.
    @Test func aPointBesideALineMeansTheNearestEndOfIt() throws {
        let right = try #require(page.fragmentIndex(nearest: CGPoint(x: 0.9, y: 0.115)))
        let left = try #require(page.fragmentIndex(nearest: CGPoint(x: 0.01, y: 0.215)))

        #expect(page.text(in: right...right) == "t")
        #expect(page.text(in: left...left) == "b")
    }

    /// A touch has to land near text to start a selection; one in the middle
    /// of an empty margin is not asking for the nearest word half a page away.
    @Test func aPointFarFromAnyTextMeansNothingWhenAReachIsGiven() {
        #expect(page.fragmentIndex(nearest: CGPoint(x: 0.5, y: 0.8), within: 0.05) == nil)
        #expect(page.fragmentIndex(nearest: CGPoint(x: 0.5, y: 0.8)) != nil)
        #expect(page.fragmentIndex(nearest: point(column: 0, y: 0.10), within: 0.05) == 0)
        #expect(PageTextLayout.empty.fragmentIndex(nearest: .zero) == nil)
    }

    // MARK: - Words and lines

    @Test func aWordIsTheLettersBetweenTwoSpaces() throws {
        let inHat = try #require(page.fragmentIndex(nearest: point(column: 5, y: 0.10)))

        let word = page.wordRange(around: inHat)

        #expect(page.text(in: word) == "hat")
    }

    /// A word does not run on into the next line just because no space was
    /// typed at the end of this one.
    @Test func aWordStopsAtTheEndOfItsLine() throws {
        let inHat = try #require(page.fragmentIndex(nearest: point(column: 6, y: 0.10)))
        let inBig = try #require(page.fragmentIndex(nearest: point(column: 0, y: 0.20)))

        #expect(page.text(in: page.wordRange(around: inHat)) == "hat")
        #expect(page.text(in: page.wordRange(around: inBig)) == "big")
    }

    /// Recognition gives a fragment per word, so the word is the fragment.
    @Test func aRecognisedWordIsItsOwnFragment() {
        let layout = PageTextLayout(lines: [Line(fragments: [
            Fragment(text: "Amount", box: .exact(x: 0.1, y: 0.1, width: 0.15, height: 0.03), spaceAfter: true),
            Fragment(text: "due", box: .exact(x: 0.27, y: 0.1, width: 0.08, height: 0.03), spaceAfter: true),
        ], origin: .recognized)])

        #expect(layout.wordRange(around: 1) == 1...1)
        #expect(layout.text(in: layout.wordRange(around: 0)) == "Amount")
    }

    @Test func aLineIsEverythingOnItsRow() throws {
        let inDog = try #require(page.fragmentIndex(nearest: point(column: 5, y: 0.20)))

        #expect(page.text(in: page.lineRange(around: inDog)) == "big dog")
    }

    // MARK: - What is copied, and what is lit

    @Test func aSelectionAcrossLinesCopiesWithItsSpacesAndLineBreak() throws {
        let from = try #require(page.fragmentIndex(nearest: point(column: 4, y: 0.10)))
        let to = try #require(page.fragmentIndex(nearest: point(column: 2, y: 0.20)))

        #expect(page.text(in: from...to) == "hat\nbig")
        #expect(page.text(in: 0...(page.fragmentCount - 1)) == "cat hat\nbig dog")
    }

    /// The space after the last selected letter is not part of the selection.
    @Test func aSelectionDoesNotEndInTheSpaceThatFollowsIt() {
        #expect(page.text(in: 0...2) == "cat")
        #expect(page.text(in: 2...3) == "t h")
    }

    @Test func aSelectionHasOneBoxPerLine() throws {
        let from = try #require(page.fragmentIndex(nearest: point(column: 4, y: 0.10)))
        let to = try #require(page.fragmentIndex(nearest: point(column: 2, y: 0.20)))

        let boxes = page.boxes(in: from...to)

        #expect(boxes.count == 2)
        // "hat": columns 4–6 of the first row.
        #expect(abs(boxes[0].x - 0.18) < 1e-9 && abs(boxes[0].width - 0.06) < 1e-9 && abs(boxes[0].y - 0.10) < 1e-9)
        // "big": columns 0–2 of the second.
        #expect(abs(boxes[1].x - 0.10) < 1e-9 && abs(boxes[1].width - 0.06) < 1e-9 && abs(boxes[1].y - 0.20) < 1e-9)
    }

    /// Dragging backwards selects the same text as dragging forwards.
    @Test func aDragSelectsBetweenItsEndsWhicheverWayItWent() throws {
        let a = point(column: 1, y: 0.10), b = point(column: 5, y: 0.20)

        let forwards = try #require(page.selection(from: a, to: b))
        let backwards = try #require(page.selection(from: b, to: a))

        #expect(forwards == backwards)
        #expect(page.text(in: forwards) == "at hat\nbig do")
    }

    @Test func rangesOutsideThePageAreClampedRatherThanTrapping() {
        #expect(page.text(in: 10...400) == "og")
        #expect(page.boxes(in: 300...400).isEmpty)
        // Past the end means the last word, "dog".
        #expect(page.wordRange(around: 999) == 9...11)
    }

    // MARK: - What can be selected

    /// A typed text box is edited in its own way; selecting page text must
    /// not reach into it.
    @Test func typedTextIsLeftOutOfWhatCanBeSelected() {
        let layout = PageTextLayout(lines: [
            characters("cat", y: 0.10),
            Line(fragments: [Fragment(text: "a note", box: .exact(x: 0.1, y: 0.5, width: 0.3, height: 0.1))],
                 origin: .typed),
        ])

        let selectable = layout.excluding(.typed)

        #expect(selectable.text == "cat")
        #expect(selectable.fragmentCount == 3)
        #expect(layout.excluding(.recognized) == layout)
    }
}
