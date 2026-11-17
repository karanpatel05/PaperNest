import Foundation

/// What a page carries that deleting it would lose beyond the page itself.
public enum CleanupAttachment: String, Hashable, Sendable, CaseIterable {
    case comment, bookmark, keptDetails
    /// Recognized text someone corrected by hand.
    case correctedText
}

/// One page, as the cleanup sees it.
public struct CleanupPage: Sendable {
    /// Position in the document, from 0.
    public var index: Int
    public var content: PageContent
    public var transform: PageTransform
    /// Ink, text boxes and placed pictures, in paint order; never comments.
    public var marks: [PageObject.Payload]
    /// The page's words: empty when it was read and has none (a digital
    /// page without text, a scan whose recognition found nothing), nil when
    /// nobody has read it — and then no words is no evidence of anything.
    public var words: [String]?
    /// Share of the small picture darker than paper.
    public var inkRatio: Double
    public var fingerprint: [Double]
    public var attachments: Set<CleanupAttachment>

    public init(index: Int, content: PageContent, transform: PageTransform, marks: [PageObject.Payload],
                words: [String]?, inkRatio: Double, fingerprint: [Double], attachments: Set<CleanupAttachment>) {
        self.index = index
        self.content = content
        self.transform = transform
        self.marks = marks
        self.words = words
        self.inkRatio = inkRatio
        self.fingerprint = fingerprint
        self.attachments = attachments
    }

    var isNotebookPaper: Bool { if case .template = content { true } else { false } }
}

/// A page offered for removal, and why. Only a suggestion: nothing is
/// deleted until someone chooses it and confirms.
public struct CleanupSuggestion: Hashable, Sendable {
    public enum Reason: Hashable, Sendable {
        /// Read, no words, no marks, no ink at the large size.
        case blank
        /// Nearly no ink, or no words because it was never read: to look at.
        case looksBlank
        /// The same original, crop and rotation, and the same marks.
        case duplicate(of: Int)
        /// The same words, or the same look at the large size, from another original: to look at.
        case similar(to: Int)
    }

    public var page: Int
    public var reason: Reason
    /// Chosen to start with only on strong evidence, and never when the page
    /// carries something that would go with it.
    public var isPreselected: Bool
    public var attachments: Set<CleanupAttachment>

    public init(page: Int, reason: Reason, isPreselected: Bool, attachments: Set<CleanupAttachment>) {
        self.page = page
        self.reason = reason
        self.isPreselected = isPreselected
        self.attachments = attachments
    }
}

/// Finds blank and repeated pages in a document, cheaply first and then
/// confirmed. A missed suggestion costs nothing; a wrong one chosen for
/// someone costs a page, so the rules lean towards asking.
public enum PageCleanup {
    /// Below this share of ink at the large size, a read page is blank.
    public static let blankInk = 0.0004
    /// Below this at the small size, a page is worth looking at closely.
    public static let candidateInk = 0.004
    /// Pages with at least this many words compare by them.
    public static let minimumWords = 5

    /// Pages to look at closely for being blank: no marks and little ink.
    /// Notebook paper is judged by its marks alone (its rules are ink).
    public static func blankCandidates(_ pages: [CleanupPage]) -> [Int] {
        pages.filter { $0.marks.isEmpty && ($0.isNotebookPaper || $0.inkRatio < candidateInk) }.map(\.index)
    }

    /// `detailInk`: each candidate's share of ink at the large size.
    public static func blankSuggestions(_ pages: [CleanupPage], detailInk: [Int: Double]) -> [CleanupSuggestion] {
        pages.compactMap { page -> CleanupSuggestion? in
            guard page.marks.isEmpty else { return nil }
            if page.isNotebookPaper {
                // An empty notebook page is often left on purpose: offered, not chosen.
                return CleanupSuggestion(page: page.index, reason: .blank, isPreselected: false, attachments: page.attachments)
            }
            guard let ink = detailInk[page.index] else { return nil }
            let read = page.words?.isEmpty == true
            if read && ink < blankInk {
                return CleanupSuggestion(page: page.index, reason: .blank, isPreselected: page.attachments.isEmpty,
                                         attachments: page.attachments)
            }
            if page.words == nil || page.words?.isEmpty == true, ink < candidateInk {
                return CleanupSuggestion(page: page.index, reason: .looksBlank, isPreselected: false, attachments: page.attachments)
            }
            return nil
        }
    }

    /// Pages showing the same original with the same crop, rotation and marks
    /// as an earlier one. The copy kept is the one carrying a comment, a
    /// bookmark or kept details, else the first. Empty notebook pages are
    /// left to the blank rule: every one would otherwise be a "duplicate".
    public static func exactDuplicates(_ pages: [CleanupPage]) -> [CleanupSuggestion] {
        var groups: [[CleanupPage]] = []
        for page in pages where !(page.isNotebookPaper && page.marks.isEmpty) {
            if let index = groups.firstIndex(where: {
                $0[0].content == page.content && $0[0].transform == page.transform && $0[0].marks == page.marks
            }) {
                groups[index].append(page)
            } else {
                groups.append([page])
            }
        }
        return groups.filter { $0.count > 1 }.flatMap { group -> [CleanupSuggestion] in
            let kept = group.first { !$0.attachments.isEmpty } ?? group[0]
            return group.filter { $0.index != kept.index }.map {
                CleanupSuggestion(page: $0.index, reason: .duplicate(of: kept.index), isPreselected: $0.attachments.isEmpty,
                                  attachments: $0.attachments)
            }
        }
    }

    public struct SimilarPair: Hashable, Sendable {
        public var page: Int
        public var of: Int
        /// Found by words, which settles it; otherwise by look, to be
        /// confirmed by comparing the pictures at the large size.
        public var needsPictureCheck: Bool
    }

    /// Pairs worth calling similar, always with the same marks (a signed
    /// copy is not "similar" to the unsigned one). With words on both, the
    /// same words — grouped by them, so a long document is not compared page
    /// against page (a layout shared by every page is no evidence anyway);
    /// without, a near-identical small picture, which the pictures must then
    /// confirm.
    public static func similarCandidates(_ pages: [CleanupPage], excluding: Set<Int>) -> [SimilarPair] {
        var pairs: [SimilarPair] = []
        var claimed = excluding
        let considered = pages.filter { !($0.isNotebookPaper && $0.marks.isEmpty) }
        // By words: the same words, normalized, in the same order.
        var byWords: [String: [CleanupPage]] = [:]
        for page in considered where !claimed.contains(page.index) {
            guard let words = page.words, words.count >= minimumWords else { continue }
            let key = words.map(\.precomposedStringWithCanonicalMapping).joined(separator: "\u{1F}")
            if let earlier = byWords[key]?.first(where: { $0.marks == page.marks && !isSamePage($0, page) }) {
                pairs.append(SimilarPair(page: page.index, of: earlier.index, needsPictureCheck: false))
                claimed.insert(page.index)
            } else {
                byWords[key, default: []].append(page)
            }
        }
        // By look, for pages without words to go on.
        for (i, a) in considered.enumerated() where !claimed.contains(a.index) && !hasWords(a) {
            for b in considered[(i + 1)...] where !claimed.contains(b.index) && !hasWords(b) {
                guard a.marks == b.marks, !isSamePage(a, b),
                      GrayPicture.similarity(a.fingerprint, b.fingerprint) >= 0.985 else { continue }
                pairs.append(SimilarPair(page: b.index, of: a.index, needsPictureCheck: true))
            }
        }
        return pairs.sorted { $0.page < $1.page }
    }

    private static func hasWords(_ page: CleanupPage) -> Bool { (page.words?.count ?? 0) >= minimumWords }

    private static func isSamePage(_ a: CleanupPage, _ b: CleanupPage) -> Bool {
        a.content == b.content && a.transform == b.transform && a.marks == b.marks
    }

    /// Everything to offer, one suggestion per page, in page order: blank
    /// before duplicate before similar when a page qualifies twice.
    public static func suggestions(blank: [CleanupSuggestion], duplicates: [CleanupSuggestion],
                                   similar: [CleanupSuggestion]) -> [CleanupSuggestion] {
        var byPage: [Int: CleanupSuggestion] = [:]
        for suggestion in blank + duplicates + similar where byPage[suggestion.page] == nil {
            byPage[suggestion.page] = suggestion
        }
        return byPage.values.sorted { $0.page < $1.page }
    }
}

extension GrayPicture {
    /// Share of pixels clearly darker than paper (luminance below 200 of
    /// 255), so faint pencil counts and scanner grey does not.
    public func inkRatio(threshold: UInt8 = 200) -> Double {
        guard !pixels.isEmpty else { return 0 }
        return Double(pixels.lazy.filter { $0 < threshold }.count) / Double(pixels.count)
    }
}
