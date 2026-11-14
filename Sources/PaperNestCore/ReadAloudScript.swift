import CoreGraphics
import Foundation

/// What reading a page aloud says, and where on the page each part of it is.
///
/// Built from the page's `PageTextLayout` — the words find and selection use —
/// but **not** from its search text. That one is folded (case, accents and
/// spacing removed), while a speech synthesizer reports what it is saying as a
/// range of UTF-16 units of the string it was given. Lighting a word means
/// mapping that range back to boxes, so the string spoken and the string
/// mapped have to be the same string, unfolded.
///
/// Lines are joined into running text. A line ending in a hyphen that splits
/// a word ("docu-" / "ment") is joined without it, so the word is said whole.
/// A line ending in a full stop, question mark and the like is followed by a
/// line break, which a synthesizer pauses on; any other line runs on with a
/// space, so a sentence broken across lines is read as one sentence.
public struct ReadAloudScript: Hashable, Sendable {
    /// What is said.
    public let text: String
    /// For each UTF-16 unit of `text`, the fragment it was read from, or -1
    /// for the spaces and line breaks that join lines.
    private let owners: [Int32]
    /// Each fragment's box, in the layout's space.
    private let fragmentBoxes: [NormalizedRect]
    /// Which line each fragment is on.
    private let fragmentLines: [Int32]

    public init(_ layout: PageTextLayout) {
        var text = ""
        var owners: [Int32] = []
        var boxes: [NormalizedRect] = []
        var lineOf: [Int32] = []
        var fragmentIndex: Int32 = 0

        func append(_ piece: String, owner: Int32) {
            text += piece
            owners.append(contentsOf: repeatElement(owner, count: piece.utf16.count))
        }

        let lines = layout.lines.filter { !$0.fragments.isEmpty }
        for (lineIndex, line) in lines.enumerated() {
            for (position, fragment) in line.fragments.enumerated() {
                append(fragment.text, owner: fragmentIndex)
                boxes.append(fragment.box)
                lineOf.append(Int32(lineIndex))
                if fragment.spaceAfter, position < line.fragments.count - 1 { append(" ", owner: -1) }
                fragmentIndex += 1
            }
            guard lineIndex < lines.count - 1 else { break }
            let next = lines[lineIndex + 1].fragments.first?.text ?? ""
            if Self.splitsAWord(endingWith: text, nextLineStartsWith: next) {
                // The hyphen goes: the word is said whole.
                let hyphen = text.removeLast()
                owners.removeLast(String(hyphen).utf16.count)
            } else if Self.endsASentence(text) || line.origin != lines[lineIndex + 1].origin {
                append("\n", owner: -1)
            } else {
                append(" ", owner: -1)
            }
        }
        self.text = text
        self.owners = owners
        fragmentBoxes = boxes
        fragmentLines = lineOf
    }

    public var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The boxes of the words `range` (UTF-16 units of `text`) touches: one per
    /// line, the union of the fragments on it. A digital PDF gives a fragment
    /// per character, so a word is many fragments and one box.
    public func boxes(for range: NSRange) -> [NormalizedRect] {
        guard range.location != NSNotFound, range.length > 0 else { return [] }
        let lower = max(0, range.location), upper = min(owners.count, range.location + range.length)
        guard lower < upper else { return [] }
        var result: [NormalizedRect] = []
        var currentLine: Int32?
        var seen: Int32?
        for owner in owners[lower..<upper] where owner >= 0 && owner != seen {
            seen = owner
            let box = fragmentBoxes[Int(owner)]
            // A character nobody could place has no box to show.
            guard box.width > 0, box.height > 0 else { continue }
            if currentLine == fragmentLines[Int(owner)], let last = result.indices.last {
                result[last] = result[last].union(box)
            } else {
                result.append(box)
                currentLine = fragmentLines[Int(owner)]
            }
        }
        return result
    }

    /// The part of `text` that `range` covers, as said.
    public func words(for range: NSRange) -> String {
        guard range.location != NSNotFound, range.location >= 0,
              range.location + range.length <= owners.count else { return "" }
        return (text as NSString).substring(with: range)
    }

    /// Where to start again so as to say the word at `offset` from its
    /// beginning: `offset` moved back to the start of its word.
    public func wordStart(atOrBefore offset: Int) -> Int {
        let units = Array(text.utf16)
        var start = min(max(0, offset), units.count)
        while start > 0, let scalar = Unicode.Scalar(units[start - 1]),
              !CharacterSet.whitespacesAndNewlines.contains(scalar) {
            start -= 1
        }
        return start
    }

    /// `text` from `offset` (UTF-16 units) to the end: what a synthesizer is
    /// given to start part-way through. A range it reports for that string is
    /// a range of this one moved by `offset`.
    public func suffix(from offset: Int) -> String {
        let start = min(max(0, offset), owners.count)
        return (text as NSString).substring(from: start)
    }

    /// A line ending "letters-" followed by one starting with a lower-case
    /// letter: a word the paper ran out in the middle of. An upper-case start
    /// ("Jean-" / "Paul") is more likely a hyphenated name, and is left alone.
    static func splitsAWord(endingWith text: String, nextLineStartsWith next: String) -> Bool {
        guard let last = text.last, last == "-" || last == "\u{00AD}",
              let before = text.dropLast().last, before.isLetter,
              let first = next.first, first.isLetter, first.isLowercase else { return false }
        return true
    }

    static func endsASentence(_ text: String) -> Bool {
        guard let last = text.last(where: { !$0.isWhitespace && $0 != "\"" && $0 != "”" && $0 != "»" && $0 != ")" })
        else { return false }
        return ".!?:;…".contains(last)
    }
}
