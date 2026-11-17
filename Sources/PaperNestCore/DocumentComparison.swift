import CoreGraphics
import Foundation

/// A word on a page and where it is, in the page's upright, uncropped source
/// space (top-left origin, 0…1), like every other box on a page.
public struct ComparisonWord: Hashable, Sendable {
    public var text: String
    public var box: NormalizedRect

    public init(text: String, box: NormalizedRect) {
        self.text = text
        self.box = box
    }
}

/// Where a page's compared words came from.
public enum ComparisonTextSource: String, Hashable, Sendable {
    /// The page's own PDF text.
    case embedded
    /// Read off the page's pixels, so a misread word is a "change" too.
    case recognized
}

/// The words a comparison reads from one page.
public struct ComparisonPageText: Hashable, Sendable {
    public var words: [ComparisonWord]
    /// Nil when the page has no words. `recognized` when any were read off
    /// its pixels.
    public var source: ComparisonTextSource?

    public init(words: [ComparisonWord], source: ComparisonTextSource?) {
        self.words = words
        self.source = source
    }

    public static let none = ComparisonPageText(words: [], source: nil)
}

extension PageTextLayout {
    /// The paper's words, one per word, for comparing.
    ///
    /// **Typed text boxes are left out**: they are marks someone added, not
    /// the document's text, and the picture comparison sees them. A digital
    /// PDF's characters are joined into words, their boxes into one; a
    /// fragment holding several words (a recognized line whose words were not
    /// all boxed) gives each of them its box.
    public var comparisonText: ComparisonPageText {
        var words: [ComparisonWord] = []
        var recognized = false, embedded = false
        for line in lines where line.origin != .typed {
            var text = ""
            var box: NormalizedRect?
            func flush() {
                if !text.isEmpty, let box { words.append(ComparisonWord(text: text, box: box)) }
                text = ""; box = nil
            }
            func extend(_ fragmentBox: NormalizedRect) {
                guard fragmentBox.width > 0, fragmentBox.height > 0 else { return }
                box = box.map { $0.union(fragmentBox) } ?? fragmentBox
            }
            for fragment in line.fragments {
                if fragment.text.contains(where: \.isWhitespace) {
                    flush()
                    for part in fragment.text.split(whereSeparator: \.isWhitespace) {
                        text = String(part); extend(fragment.box); flush()
                    }
                    continue
                }
                text += fragment.text
                extend(fragment.box)
                if fragment.spaceAfter { flush() }
            }
            flush()
            if line.origin == .recognized { recognized = true } else { embedded = true }
        }
        guard !words.isEmpty else { return .none }
        return ComparisonPageText(words: words, source: recognized ? .recognized : (embedded ? .embedded : nil))
    }
}

/// One page as the comparison sees it: its words, a small picture of it as
/// shown (crop, rotation and marks applied) and its geometry.
public struct ComparedPage: Sendable {
    public var text: ComparisonPageText
    /// The page as seen, in page space, row by row from the top.
    public var picture: GrayPicture
    public var geometry: PageGeometry

    public init(text: ComparisonPageText, picture: GrayPicture, geometry: PageGeometry) {
        self.text = text
        self.picture = picture
        self.geometry = geometry
    }

    public var signature: PageSignature {
        PageSignature(foldedWords: text.words.map {
            $0.text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        }, fingerprint: picture.fingerprint())
    }
}

/// What the comparison found for one page of either document.
public struct PageComparison: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case same, changed, added, removed
    }

    /// Why a pair of pages was compared only as pictures.
    public enum PictureReason: String, Hashable, Sendable {
        case noTextOnEither, noTextOnOld, noTextOnNew
    }

    public enum Method: Hashable, Sendable {
        /// Word by word, and the pictures for anything not under words.
        case text(ComparisonTextSource)
        /// Pixels only: nothing here knows what the page says.
        case picture(PictureReason)
    }

    /// One place the words differ. Either side may be empty, never both.
    public struct TextChange: Hashable, Sendable {
        public var removed: [ComparisonWord]
        public var added: [ComparisonWord]

        public init(removed: [ComparisonWord], added: [ComparisonWord]) {
            self.removed = removed
            self.added = added
        }
    }

    public var oldIndex: Int?
    public var newIndex: Int?
    /// Matched, but out of order with the other pages.
    public var moved: Bool
    /// Nil for a page only one document has.
    public var method: Method?
    public var textChanges: [TextChange]
    /// Where the pictures differ, in each page's own upright, uncropped
    /// source space (the same rectangles, mapped through each page's
    /// geometry). On a page compared by text, only away from its words.
    public var oldPictureRegions: [NormalizedRect]
    public var newPictureRegions: [NormalizedRect]
    /// The two pages are different shapes, so one was stretched onto the
    /// other to compare their pictures.
    public var sizesDiffer: Bool

    public init(oldIndex: Int?, newIndex: Int?, moved: Bool = false, method: Method? = nil,
                textChanges: [TextChange] = [], oldPictureRegions: [NormalizedRect] = [],
                newPictureRegions: [NormalizedRect] = [], sizesDiffer: Bool = false) {
        self.oldIndex = oldIndex
        self.newIndex = newIndex
        self.moved = moved
        self.method = method
        self.textChanges = textChanges
        self.oldPictureRegions = oldPictureRegions
        self.newPictureRegions = newPictureRegions
        self.sizesDiffer = sizesDiffer
    }

    public var kind: Kind {
        if oldIndex == nil { return .added }
        if newIndex == nil { return .removed }
        return textChanges.isEmpty && oldPictureRegions.isEmpty ? .same : .changed
    }

    /// How many picture differences were found: the rectangles are the same
    /// on both sides, mapped to each.
    public var pictureDifferenceCount: Int { oldPictureRegions.count }

    /// Compares two matched pages.
    ///
    /// Words when both pages have them; the pictures always. **A page is the
    /// same only when both agree**: matching words over a changed stamp,
    /// photo or drawing is a change. On a page compared by words, picture
    /// differences under any word on either page are left to the words —
    /// two files can draw the same letters slightly differently.
    ///
    /// `detail`, when given, is the two pages drawn larger for comparing
    /// their pictures (the pages' own pictures, drawn small, are for matching
    /// them), divided into `columns` cells across. A picture too small for
    /// its print misses a changed digit: at 400 pixels on Letter, body text
    /// is five pixels tall.
    public static func compare(_ old: ComparedPage, _ new: ComparedPage,
                               oldIndex: Int, newIndex: Int, moved: Bool,
                               detail: (old: GrayPicture, new: GrayPicture)? = nil,
                               columns: Int = PictureDifference.columns) -> PageComparison {
        var method: Method
        var changes: [TextChange] = []
        var ignoring: [NormalizedRect] = []
        if let oldSource = old.text.source, let newSource = new.text.source {
            method = .text(oldSource == .recognized || newSource == .recognized ? .recognized : .embedded)
            changes = WordDiff.changes(old.text.words.map(\.text), new.text.words.map(\.text)).map {
                TextChange(removed: Array(old.text.words[$0.removed]), added: Array(new.text.words[$0.added]))
            }
            // Word boxes in each page's picture, normalized to it; the new
            // picture is stretched onto the old one's frame, so the two agree.
            // With a margin: a word's box may not quite reach its letters' ink.
            ignoring = (old.text.words.map { normalizedPageRect($0.box, old.geometry) }
                + new.text.words.map { normalizedPageRect($0.box, new.geometry) }).map(widened)
        } else {
            method = .picture(old.text.source == nil && new.text.source == nil ? .noTextOnEither
                              : (old.text.source == nil ? .noTextOnOld : .noTextOnNew))
        }
        let regions = PictureDifference.regions(detail?.old ?? old.picture, detail?.new ?? new.picture,
                                                columns: columns, ignoring: ignoring)
        let oldSize = old.geometry.pageSize, newSize = new.geometry.pageSize
        let sizesDiffer = oldSize.height > 0 && newSize.height > 0
            && abs(oldSize.width / oldSize.height - newSize.width / newSize.height) > 0.02 * (oldSize.width / oldSize.height)
        return PageComparison(
            oldIndex: oldIndex, newIndex: newIndex, moved: moved, method: method, textChanges: changes,
            oldPictureRegions: regions.map { old.geometry.normalizedSourceRect(forPageRect: $0.denormalized(in: oldSize)) },
            newPictureRegions: regions.map { new.geometry.normalizedSourceRect(forPageRect: $0.denormalized(in: newSize)) },
            sizesDiffer: sizesDiffer)
    }

    private static func widened(_ box: NormalizedRect) -> NormalizedRect {
        let margin = max(box.height * 0.3, 0.003)
        return .exact(x: box.x - margin, y: box.y - margin, width: box.width + 2 * margin, height: box.height + 2 * margin)
    }

    private static func normalizedPageRect(_ source: NormalizedRect, _ geometry: PageGeometry) -> NormalizedRect {
        let size = geometry.pageSize
        guard size.width > 0, size.height > 0 else { return source }
        let rect = geometry.pageRect(forNormalizedSourceRect: source)
        return .exact(x: rect.minX / size.width, y: rect.minY / size.height,
                      width: rect.width / size.width, height: rect.height / size.height)
    }
}

/// Two documents compared, page by page, in the order to show them.
public struct DocumentComparison: Hashable, Sendable {
    public var pages: [PageComparison]

    public init(pages: [PageComparison]) {
        self.pages = pages
    }

    /// Aligns the pages (`PageAlignment`) and compares each matched pair.
    public static func compare(old: [ComparedPage], new: [ComparedPage]) -> DocumentComparison {
        let entries = PageAlignment.align(old: old.map(\.signature), new: new.map(\.signature))
        return DocumentComparison(pages: entries.map { entry in
            switch entry {
            case .matched(let i, let j, let moved):
                PageComparison.compare(old[i], new[j], oldIndex: i, newIndex: j, moved: moved)
            case .removed(let i): PageComparison(oldIndex: i, newIndex: nil)
            case .added(let j): PageComparison(oldIndex: nil, newIndex: j)
            }
        })
    }

    public var textChangeCount: Int { pages.reduce(0) { $0 + $1.textChanges.count } }
    public var pictureDifferenceCount: Int { pages.reduce(0) { $0 + $1.pictureDifferenceCount } }
    public var addedPageCount: Int { pages.filter { $0.kind == .added }.count }
    public var removedPageCount: Int { pages.filter { $0.kind == .removed }.count }
    public var movedPageCount: Int { pages.filter(\.moved).count }
    public var isIdentical: Bool { pages.allSatisfy { $0.kind == .same && !$0.moved } }

    /// Whether any compared words were read off pixels.
    public var usesRecognizedText: Bool {
        pages.contains { $0.method == .text(.recognized) }
    }

    /// Whether any matched pair was compared only as pictures.
    public var anyComparedOnlyByPicture: Bool {
        pages.contains { if case .picture = $0.method { true } else { false } }
    }

    /// Whether every matched pair was compared only as pictures.
    public var comparedOnlyByPicture: Bool {
        let methods = pages.compactMap(\.method)
        return !methods.isEmpty && methods.allSatisfy { if case .picture = $0 { true } else { false } }
    }
}
