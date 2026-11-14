import Foundation
import Testing
@testable import PaperNestCore

/// What read aloud says for a page, and how a range the synthesizer reports
/// finds its way back to boxes on the page.
@Suite struct ReadAloudScriptTests {
    /// A line of fragments, one per word, laid left to right on row `row`.
    private func line(_ words: [String], row: Int, origin: PageTextLayout.Origin = .recognized) -> PageTextLayout.Line {
        PageTextLayout.Line(fragments: words.enumerated().map { index, word in
            PageTextLayout.Fragment(text: word, box: .exact(x: 0.1 + Double(index) * 0.15, y: 0.1 + Double(row) * 0.05,
                                                            width: 0.12, height: 0.03),
                                    spaceAfter: index < words.count - 1)
        }, origin: origin)
    }

    /// A line the way a digital PDF gives it: a fragment per character.
    private func characters(_ text: String, row: Int) -> PageTextLayout.Line {
        var fragments: [PageTextLayout.Fragment] = []
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == " " { index += 1; continue }
            let spaceAfter = index + 1 < characters.count && characters[index + 1] == " "
            fragments.append(PageTextLayout.Fragment(
                text: String(character), box: .exact(x: 0.05 + Double(index) * 0.01, y: 0.1 + Double(row) * 0.05,
                                                     width: 0.01, height: 0.03),
                spaceAfter: spaceAfter))
            index += 1
        }
        return PageTextLayout.Line(fragments: fragments, origin: .embedded)
    }

    private func range(of word: String, in script: ReadAloudScript) -> NSRange {
        (script.text as NSString).range(of: word)
    }

    @Test func linesRunOnAsOneSentenceAndPauseAfterAFullStop() {
        let script = ReadAloudScript(PageTextLayout(lines: [
            line(["The", "budget"], row: 0),
            line(["grew."], row: 1),
            line(["Costs", "fell"], row: 2),
        ]))
        #expect(script.text == "The budget grew.\nCosts fell")
    }

    @Test func aWordSplitAcrossLinesIsSaidWhole() {
        let script = ReadAloudScript(PageTextLayout(lines: [line(["the", "docu-"], row: 0), line(["ment", "says"], row: 1)]))
        #expect(script.text == "the document says")
        // Both halves light up, each on its own line.
        #expect(script.boxes(for: range(of: "document", in: script)).count == 2)
    }

    @Test func aHyphenatedNameIsLeftAlone() {
        let script = ReadAloudScript(PageTextLayout(lines: [line(["Jean-"], row: 0), line(["Paul"], row: 1)]))
        #expect(script.text == "Jean- Paul")
    }

    /// A digital PDF's word is many fragments and comes back as one box per line.
    @Test func aWordMadeOfCharactersIsOneBox() throws {
        let script = ReadAloudScript(PageTextLayout(lines: [characters("Quarterly budget", row: 0)]))
        #expect(script.text == "Quarterly budget")
        let boxes = script.boxes(for: range(of: "budget", in: script))
        #expect(boxes.count == 1)
        let box = try #require(boxes.first)
        #expect(abs(box.x - 0.15) < 0.0001)
        #expect(abs(box.width - 0.06) < 0.0001)
    }

    /// The reason the search text is not used: it is folded. Here the range
    /// the synthesizer reports for "réunion" is in UTF-16 units of the real,
    /// accented string, composed or decomposed, and has to land on that word.
    @Test(arguments: ["r\u{E9}union", "re\u{301}union"])
    func anAccentedWordLightsItself(_ word: String) throws {
        let layout = PageTextLayout(lines: [line(["Une", word, "mardi"], row: 0)])
        let script = ReadAloudScript(layout)
        let spoken = range(of: word, in: script)
        #expect(spoken.location != NSNotFound)
        let box = try #require(script.boxes(for: spoken).first)
        #expect(abs(box.x - 0.25) < 0.0001, "lit \(box), not the second word")
        let after = try #require(script.boxes(for: range(of: "mardi", in: script)).first)
        #expect(abs(after.x - 0.4) < 0.0001, "the word after an accent is lit at \(after)")
    }

    /// A ligature arrives as one fragment of two letters; it lights as one.
    @Test func aLigatureFragmentLightsAsOne() throws {
        let layout = PageTextLayout(lines: [PageTextLayout.Line(fragments: [
            .init(text: "o", box: .exact(x: 0.1, y: 0.1, width: 0.01, height: 0.03)),
            .init(text: "ffi", box: .exact(x: 0.11, y: 0.1, width: 0.02, height: 0.03)),
            .init(text: "ce", box: .exact(x: 0.13, y: 0.1, width: 0.02, height: 0.03)),
        ], origin: .embedded)])
        let script = ReadAloudScript(layout)
        #expect(script.text == "office")
        let middle = script.boxes(for: NSRange(location: 2, length: 1))
        #expect(middle == [.exact(x: 0.11, y: 0.1, width: 0.02, height: 0.03)])
    }

    /// Text typed onto the page comes after the page's own words, on a line of its own.
    @Test func typedTextIsReadAfterThePageAndApart() {
        let script = ReadAloudScript(PageTextLayout(lines: [
            line(["Invoice", "total"], row: 0, origin: .embedded),
            line(["Paid", "in", "cash"], row: 5, origin: .typed),
        ]))
        #expect(script.text == "Invoice total\nPaid in cash")
    }

    @Test func anEmptyPageSaysNothing() {
        #expect(ReadAloudScript(.empty).isEmpty)
        #expect(ReadAloudScript(PageTextLayout(lines: [line([" "], row: 0)])).isEmpty)
        #expect(ReadAloudScript(.empty).boxes(for: NSRange(location: 0, length: 3)).isEmpty)
    }

    /// Restarting part-way through — a new speed, say — speaks the rest of
    /// the text; what the synthesizer then reports is moved back by the offset.
    @Test func startingPartWayMapsBackToTheSamePlace() throws {
        let script = ReadAloudScript(PageTextLayout(lines: [line(["One", "two", "three", "four"], row: 0)]))
        let offset = script.wordStart(atOrBefore: range(of: "three", in: script).location + 2)
        #expect(offset == range(of: "three", in: script).location)
        let rest = script.suffix(from: offset)
        #expect(rest == "three four")
        let reported = (rest as NSString).range(of: "four")
        let shifted = NSRange(location: reported.location + offset, length: reported.length)
        #expect(script.words(for: shifted) == "four")
        let box = try #require(script.boxes(for: shifted).first)
        #expect(abs(box.x - 0.55) < 0.0001)
    }

    @Test func aRangeOutsideTheTextLightsNothing() {
        let script = ReadAloudScript(PageTextLayout(lines: [line(["Short"], row: 0)]))
        #expect(script.boxes(for: NSRange(location: 40, length: 3)).isEmpty)
        #expect(script.boxes(for: NSRange(location: NSNotFound, length: 0)).isEmpty)
        #expect(script.words(for: NSRange(location: 40, length: 3)).isEmpty)
    }
}
