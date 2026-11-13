import CoreGraphics
import Foundation

/// The words on a page and where each one is, so they can be found, selected
/// and read out.
///
/// Boxes are normalized to the page's **upright, uncropped source** with a
/// top-left origin — the space `PageGeometry` maps from, and the one
/// recognised text already lives in — so a box stays on its word through a
/// crop or a rotation.
///
/// A layout comes at one of two grains, and nothing here needs to know which.
/// A digital PDF gives a fragment per character, so a hit covers exactly its
/// letters. Recognition gives a fragment per word, and a typed text box is a
/// single fragment holding everything in it; a hit inside either lights the
/// whole fragment. That is deliberate: the only way to do better would be to
/// divide a box by its letters, which drifts on any proportional font.
public struct PageTextLayout: Hashable, Sendable {
    /// Where a line's words came from.
    public enum Origin: String, Hashable, Sendable {
        /// Text the page's own PDF carries.
        case embedded
        /// Read off the page's pixels by recognition.
        case recognized
        /// Typed onto the page in a text box.
        case typed
    }

    public struct Fragment: Hashable, Sendable {
        public var text: String
        public var box: NormalizedRect
        /// Whether a space separates this from the next fragment on its line.
        /// A space is never a fragment of its own.
        public var spaceAfter: Bool

        public init(text: String, box: NormalizedRect, spaceAfter: Bool = false) {
            self.text = text
            self.box = box
            self.spaceAfter = spaceAfter
        }
    }

    public struct Line: Hashable, Sendable {
        public var fragments: [Fragment]
        public var origin: Origin

        public init(fragments: [Fragment], origin: Origin) {
            self.fragments = fragments
            self.origin = origin
        }
    }

    public var lines: [Line]

    public init(lines: [Line]) {
        self.lines = lines
    }

    public static let empty = PageTextLayout(lines: [])

    public var isEmpty: Bool { lines.allSatisfy(\.fragments.isEmpty) }

    /// The page's words as a reader would copy them, a line per line.
    public var text: String {
        lines.filter { !$0.fragments.isEmpty }.map { line in
            var text = ""
            for (index, fragment) in line.fragments.enumerated() {
                text += fragment.text
                if fragment.spaceAfter, index < line.fragments.count - 1 { text += " " }
            }
            return text
        }.joined(separator: "\n")
    }

    /// What find matches against.
    public var searchText: PageSearchText {
        var assembler = SearchTextAssembler(tracksOwners: false)
        feed(&assembler)
        return PageSearchText(folded: assembler.string)
    }

    /// One box per line that `range` of the search text touches: the union of
    /// the fragments it covers there.
    public func boxes(for range: Range<Int>) -> [NormalizedRect] {
        boxes(for: [range])[0]
    }

    /// The same, for several ranges at once. The search text is assembled a
    /// single time however many hits the page has.
    public func boxes(for ranges: [Range<Int>]) -> [[NormalizedRect]] {
        var assembler = SearchTextAssembler(tracksOwners: true)
        feed(&assembler)
        let owners = assembler.owners
        // Which line each fragment is on, counted across the page.
        var lineOf: [Int] = []
        var boxOf: [NormalizedRect] = []
        for (lineIndex, line) in lines.enumerated() {
            for fragment in line.fragments {
                lineOf.append(lineIndex)
                boxOf.append(fragment.box)
            }
        }
        return ranges.map { range in
            let clamped = range.clamped(to: 0..<owners.count)
            var result: [NormalizedRect] = []
            var currentLine: Int?
            var seen: Int?
            for owner in owners[clamped] where owner >= 0 && owner != seen {
                seen = owner
                let box = boxOf[owner]
                // A character nobody could place has no box to show.
                guard box.width > 0, box.height > 0 else { continue }
                if currentLine == lineOf[owner], let last = result.indices.last {
                    result[last] = result[last].union(box)
                } else {
                    result.append(box)
                    currentLine = lineOf[owner]
                }
            }
            return result
        }
    }

    /// Only the text a crop leaves showing.
    ///
    /// What a crop hides is not on the page as far as a reader can tell, so
    /// find must not count a word there and then have nothing to light up. A
    /// fragment is kept when its centre is inside the crop.
    public func cropped(to crop: NormalizedRect) -> PageTextLayout {
        guard !crop.isApproximately(.full) else { return self }
        let minX = crop.x, maxX = crop.x + crop.width
        let minY = crop.y, maxY = crop.y + crop.height
        return PageTextLayout(lines: lines.compactMap { line in
            let kept = line.fragments.filter { fragment in
                let x = fragment.box.x + fragment.box.width / 2
                let y = fragment.box.y + fragment.box.height / 2
                return x >= minX && x <= maxX && y >= minY && y <= maxY
            }
            return kept.isEmpty ? nil : Line(fragments: kept, origin: line.origin)
        })
    }

    private func feed(_ assembler: inout SearchTextAssembler) {
        var index = 0
        for line in lines {
            for (position, fragment) in line.fragments.enumerated() {
                assembler.append(fragment.text, owner: index,
                                 breaksAfter: fragment.spaceAfter || position == line.fragments.count - 1)
                index += 1
            }
        }
    }
}

/// A page's text, folded for matching: case, accents and letter width
/// removed, and every run of spacing — including a line break — made a single
/// space, so a phrase is found whether or not the paper ran out in the middle
/// of it.
///
/// Small enough to keep for every page of a long document, which the boxes
/// are not.
public struct PageSearchText: Hashable, Sendable {
    public let folded: String

    /// A page with nothing to find on it.
    public static let empty = PageSearchText(folded: "")

    init(folded: String) {
        self.folded = folded
    }

    /// From the string a PDF page reports for itself.
    ///
    /// Reads exactly as the search text of a layout built from the same
    /// string's tokens does — they share one assembler — which is what lets
    /// find count hits from the text alone and work out boxes later, only for
    /// the page on screen.
    public init(pageString: String) {
        var assembler = SearchTextAssembler(tracksOwners: false)
        for line in PageTextTokenizer.lines(of: pageString) {
            for (position, token) in line.enumerated() {
                assembler.append(token.text, owner: 0, breaksAfter: token.spaceAfter || position == line.count - 1)
            }
        }
        folded = assembler.string
    }

    public var isEmpty: Bool { folded.isEmpty }

    /// Where `query` occurs, as UTF-16 ranges of `folded`, in reading order
    /// and never overlapping.
    public func ranges(of query: PageSearchQuery) -> [Range<Int>] {
        let haystack = folded as NSString
        let needle = query.folded as NSString
        var found: [Range<Int>] = []
        var start = 0
        while start < haystack.length {
            // Both sides are already folded, so the comparison is literal.
            let hit = haystack.range(of: needle as String, options: .literal,
                                     range: NSRange(location: start, length: haystack.length - start))
            guard hit.location != NSNotFound, hit.length > 0 else { break }
            found.append(hit.location..<(hit.location + hit.length))
            start = hit.location + hit.length
        }
        return found
    }
}

/// What someone typed into find, folded the way a page's text is.
public struct PageSearchQuery: Hashable, Sendable {
    public let folded: String

    /// Nil when there is nothing to look for.
    public init?(_ text: String) {
        let words = PageTextFolding.fold(text).split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }
        folded = words.joined(separator: " ")
    }
}

/// Splits the string a PDF page reports into lines of visible characters.
public enum PageTextTokenizer {
    public struct Token: Hashable, Sendable {
        /// One character as a reader sees it, which may be several code units.
        public let text: String
        /// Where it sits in the raw string, in UTF-16 units — the units PDFKit
        /// counts a page's characters in.
        public let range: NSRange
        public var spaceAfter: Bool
    }

    public static func lines(of raw: String) -> [[Token]] {
        var lines: [[Token]] = []
        var current: [Token] = []
        var offset = 0
        for character in raw {
            let length = character.utf16.count
            if character.isNewline {
                if !current.isEmpty { lines.append(current) }
                current = []
            } else if character.isWhitespace {
                if !current.isEmpty { current[current.count - 1].spaceAfter = true }
            } else {
                current.append(Token(text: String(character), range: NSRange(location: offset, length: length),
                                     spaceAfter: false))
            }
            offset += length
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }
}

enum PageTextFolding {
    /// Case, accents and width removed. No locale: a document's language is
    /// not the device's, and find should not change with a setting.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

/// Builds a page's search text one fragment at a time, and — when asked —
/// remembers which fragment each UTF-16 unit came from.
///
/// The one place the rules live. Folding changes a string's length (ß becomes
/// ss, the ﬁ ligature becomes fi), so a hit cannot be traced back to a
/// fragment by counting characters; it is traced through `owners`.
private struct SearchTextAssembler {
    private(set) var string = ""
    /// The fragment each UTF-16 unit of `string` belongs to, or -1 for the
    /// space between two.
    private(set) var owners: [Int] = []
    private let tracksOwners: Bool
    /// A space is owed before whatever comes next. Owed rather than written,
    /// so a page never starts or ends in one and two breaks in a row are one.
    private var owesSpace = false

    init(tracksOwners: Bool) {
        self.tracksOwners = tracksOwners
    }

    /// `breaksAfter` is true when a space or the end of a line follows the
    /// fragment. Without it the next fragment continues the same word, which
    /// is how a word arrives when it comes a character at a time.
    mutating func append(_ text: String, owner: Int, breaksAfter: Bool) {
        // A fragment may hold several words and line breaks of its own.
        var isFirstWord = true
        for word in PageTextFolding.fold(text).split(whereSeparator: \.isWhitespace) {
            if (owesSpace || !isFirstWord), !string.isEmpty {
                string += " "
                if tracksOwners { owners.append(-1) }
            }
            string += word
            if tracksOwners { owners.append(contentsOf: repeatElement(owner, count: word.utf16.count)) }
            isFirstWord = false
            owesSpace = false
        }
        if breaksAfter { owesSpace = true }
    }
}
