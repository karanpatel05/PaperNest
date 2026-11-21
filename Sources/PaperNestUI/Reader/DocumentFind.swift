import Foundation
import Observation
import PaperNestCore
import PaperNestRender

/// Find in the open document: what was typed, where it occurs, and which
/// occurrence the reader is on.
///
/// Every page's text is read once and kept — text only, a few kilobytes a
/// page — so each keystroke is answered from memory however long the document
/// is. Where a hit *is* on its page is worked out separately and only for a
/// page on screen (`FindHighlightsOverlay`), because boxes for every character
/// of a thousand-page book would be most of a gigabyte.
@MainActor @Observable
final class DocumentFind {
    /// One occurrence: a page, and a range of that page's search text.
    struct Hit: Hashable, Sendable {
        let pageID: PageID
        let range: Range<Int>
    }

    enum Status: Equatable {
        /// Nothing has been typed.
        case idle
        /// Pages are still being read and nothing has turned up yet.
        case searching
        case hit(Int, of: Int)
        /// The document has text and this is not in it.
        case noResults
        /// The document has no text to look in at all — a scan nobody has
        /// run recognition on. Not the same answer as `noResults`, which
        /// would read as "that word is not in here".
        case noText
    }

    /// The scroll anchor the current hit's first box carries.
    static let anchorID = "find-current-hit"

    var isPresented = false
    /// The find field has the keyboard. On a phone the editor makes room
    /// for the page while it does.
    var isTyping = false

    /// What is typed in the find bar. Setting it searches straight away.
    var query: String {
        get { typed }
        set {
            guard newValue != typed else { return }
            typed = newValue
            search()
        }
    }

    /// The page being read. A new search starts from here rather than from
    /// the top of the document.
    var anchorPageID: PageID?

    private(set) var hits: [Hit] = []
    private(set) var currentIndex: Int?
    private(set) var isIndexing = false
    /// Goes up each time the reader should be shown the current hit: a search
    /// found its first one, or they moved to another.
    private(set) var focusRequest = 0
    /// The `focusRequest` whose hit is laid out on screen and can be scrolled
    /// to. Written by the highlights, read by the page viewer.
    var shownFocus = 0
    /// How many page reads have been recorded; a page read twice counts twice.
    private(set) var pagesRead = 0

    private var typed = ""
    private var order: [PageID] = []
    private var expected: [PageID: Stamp] = [:]
    private var texts: [PageID: (stamp: Stamp, text: PageSearchText)] = [:]
    private var ranges: [PageID: [Range<Int>]] = [:]
    private var hasIndexed = false
    private var generation = 0

    /// What a page's text was read from. Recognition and typed text change
    /// with the revision; the file's own text changes with the content; and
    /// handwriting, read in the background, arrives with a new epoch
    /// (`LibrarySession.handwritingEpoch`) without either changing.
    private struct Stamp: Hashable, Sendable {
        let content: PageContent
        let revision: Int
        let handwritingEpoch: Int
    }

    var current: Hit? { currentIndex.map { hits[$0] } }

    var hasSearchableText: Bool { texts.values.contains { !$0.text.isEmpty } }

    var status: Status {
        guard PageSearchQuery(typed) != nil else { return .idle }
        if let currentIndex { return .hit(currentIndex + 1, of: hits.count) }
        if isIndexing || !hasIndexed { return .searching }
        return hasSearchableText ? .noResults : .noText
    }

    func hits(on pageID: PageID) -> [Hit] {
        (ranges[pageID] ?? []).map { Hit(pageID: pageID, range: $0) }
    }

    /// The handwriting epoch a page's hits were found at. The highlights draw
    /// boxes only from a layout read at the same one, so a reading that lands
    /// between finding and drawing cannot put a box on the wrong word.
    func indexedHandwritingEpoch(of pageID: PageID) -> Int? { texts[pageID]?.stamp.handwritingEpoch }

    func next() { move(by: 1) }
    func previous() { move(by: -1) }

    private func move(by step: Int) {
        guard !hits.isEmpty else { return }
        let from = currentIndex ?? (step > 0 ? -1 : 0)
        currentIndex = (from + step + hits.count) % hits.count
        focusRequest &+= 1
    }

    /// Takes the highlights off the page. What was typed is kept, so opening
    /// the bar again carries on where the reader left off.
    func close() {
        isPresented = false
        isTyping = false
    }

    /// Reads the text of every page that has not been read, or has changed
    /// since it was, and answers the current query as each one arrives.
    ///
    /// Safe to call again while an earlier call is still running: a result
    /// that arrives for a page as it no longer is, is dropped.
    func index(_ pages: [Page], with renderer: PageRenderer, handwritingEpoch: Int = 0) async {
        generation &+= 1
        let pass = generation
        let held = current
        order = pages.map(\.id)
        expected = Dictionary(pages.map { ($0.id, Stamp(content: $0.content, revision: $0.revision,
                                                       handwritingEpoch: handwritingEpoch)) },
                              uniquingKeysWith: { first, _ in first })
        // A page that left the document takes its hits with it. A page that
        // only changed keeps its old ones until it has been read again, so
        // the count does not blink to nothing on every edit.
        texts = texts.filter { expected[$0.key] != nil }
        ranges = ranges.filter { expected[$0.key] != nil }
        rebuild(keeping: held)

        let stale = pages.filter { texts[$0.id]?.stamp != expected[$0.id] }
        if !stale.isEmpty {
            isIndexing = true
            let stamps = expected
            // Cancelled when the bar closes or the pages change again: what
            // was read so far stays, and the next call reads the rest.
            try? await renderer.searchTexts(for: stale, includingHandwriting: true) { [weak self] id, text in
                guard let stamp = stamps[id] else { return }
                await self?.record(text, for: id, stamp: stamp)
            }
        }
        guard pass == generation else { return }
        isIndexing = false
        hasIndexed = true
    }

    private func record(_ text: PageSearchText, for id: PageID, stamp: Stamp) {
        guard expected[id] == stamp else { return }
        let held = current
        texts[id] = (stamp, text)
        pagesRead += 1
        let found = PageSearchQuery(typed).map { text.ranges(of: $0) } ?? []
        ranges[id] = found.isEmpty ? nil : found
        rebuild(keeping: held)
    }

    private func search() {
        ranges = [:]
        if let wanted = PageSearchQuery(typed) {
            for (id, read) in texts {
                let found = read.text.ranges(of: wanted)
                if !found.isEmpty { ranges[id] = found }
            }
        }
        rebuild(keeping: nil)
    }

    /// Lays the hits out in page order. `held` stays the current hit if it
    /// is still there; otherwise the current hit becomes the first one on or
    /// after the page being read, and the reader is shown it.
    private func rebuild(keeping held: Hit?) {
        hits = order.flatMap { hits(on: $0) }
        if let held, let index = hits.firstIndex(of: held) {
            currentIndex = index
            return
        }
        guard !hits.isEmpty else {
            currentIndex = nil
            return
        }
        let start = anchorPageID.flatMap { order.firstIndex(of: $0) } ?? 0
        let later = Set(order[start...])
        currentIndex = hits.firstIndex { later.contains($0.pageID) } ?? 0
        focusRequest &+= 1
    }
}
