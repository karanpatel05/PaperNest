import Foundation
import PaperNestCore

/// Where a search matched: which document, which page, and the words around
/// the match.
///
/// `search(_:)` says which documents match. That is enough to list them, and
/// not enough to find anything in a forty-page scan: the roadmap asks for
/// "search snippets that show the matching page and recognized text context".
/// This is that, read from the same index with the same rules, so a hit is
/// never shown for a document `search(_:)` would not return.
public struct SearchHit: Hashable, Sendable {
    /// Which of the page's words matched. Named for what they are to someone
    /// reading the result, not for the index's field names.
    public enum Source: String, Hashable, Sendable {
        /// The document's name. Has no page.
        case title
        /// Text recognition read it off the page (corrected or not).
        case recognized
        /// A digital PDF page's own text.
        case pageText
        /// Someone typed it on the page, in a text box.
        case typed
    }

    public let itemID: ItemID
    /// Nil for a title.
    public let pageID: PageID?
    /// 1-based, among the document's live pages in their order. Nil for a
    /// title.
    public let pageNumber: Int?
    public let source: Source
    public let snippet: SearchSnippet
}

/// A few words of context around a match, with the matching words marked.
public struct SearchSnippet: Hashable, Sendable {
    public struct Run: Hashable, Sendable {
        public let text: String
        public let isMatch: Bool
    }

    public let runs: [Run]
    public var text: String { runs.map(\.text).joined() }
    public var hasMatch: Bool { runs.contains(where: \.isMatch) }

    /// Marks around each matched token in what FTS5's `snippet()` returns.
    /// Private-use characters, which no recognition, PDF or keyboard puts in
    /// a document's words.
    static let openMark: Character = "\u{E000}"
    static let closeMark: Character = "\u{E001}"

    /// Splits marked text into runs, with every stretch of white space —
    /// line breaks included — made one space: a snippet is one line, and the
    /// page's own line breaks are the layout of paper, not of a result.
    ///
    /// Marks that do not pair up are not guessed at: the text comes back
    /// whole and unmarked, which loses the emphasis and nothing else.
    init(marked: String) {
        var runs: [Run] = []
        var current = ""
        var inMatch = false
        var balanced = true
        for character in marked {
            switch character {
            case Self.openMark where !inMatch, Self.closeMark where inMatch:
                if !current.isEmpty { runs.append(Run(text: current, isMatch: inMatch)) }
                current = ""
                inMatch.toggle()
            case Self.openMark, Self.closeMark:
                balanced = false
            default:
                current.append(character)
            }
        }
        if !current.isEmpty { runs.append(Run(text: current, isMatch: inMatch)) }
        if !balanced || inMatch {
            let plain = marked.filter { $0 != Self.openMark && $0 != Self.closeMark }
            runs = [Run(text: plain, isMatch: false)]
        }
        self.runs = Self.tidied(runs)
    }

    init(runs: [Run]) { self.runs = Self.tidied(runs) }

    private static func tidied(_ runs: [Run]) -> [Run] {
        var result: [Run] = []
        for run in runs {
            var text = collapsed(run.text)
            // Two runs meeting at a space would make it two.
            if let last = result.last, last.text.hasSuffix(" "), text.hasPrefix(" ") { text.removeFirst() }
            guard !text.isEmpty else { continue }
            if let last = result.last, last.isMatch == run.isMatch {
                result[result.count - 1] = Run(text: last.text + text, isMatch: run.isMatch)
            } else {
                result.append(Run(text: text, isMatch: run.isMatch))
            }
        }
        // No space at either end of the whole line.
        if let first = result.first {
            let trimmed = String(first.text.drop(while: \.isWhitespace))
            if trimmed.isEmpty { result.removeFirst() } else { result[0] = Run(text: trimmed, isMatch: first.isMatch) }
        }
        if let last = result.last {
            var trimmed = last.text
            while trimmed.last?.isWhitespace == true { trimmed.removeLast() }
            if trimmed.isEmpty { result.removeLast() } else { result[result.count - 1] = Run(text: trimmed, isMatch: last.isMatch) }
        }
        return result
    }

    /// Every stretch of white space, line breaks included, as one space.
    /// A space at either end is kept: it separates this run from the next.
    private static func collapsed(_ text: String) -> String {
        var result = ""
        var pendingSpace = false
        for character in text {
            if character.isWhitespace { pendingSpace = true; continue }
            if pendingSpace { result.append(" "); pendingSpace = false }
            result.append(character)
        }
        if pendingSpace { result.append(" ") }
        return result
    }
}

extension LibraryStore {
    /// The places `text` matches, document by document.
    ///
    /// The same query and the same rules as `search(_:)` — a live document,
    /// and for words on a page, a live page — so every hit belongs to a
    /// document `search(_:)` returns, in the same order (most recently
    /// changed first). Within a document the title comes first, then pages in
    /// their order.
    ///
    /// **One hit per page.** A page can match more than once: a digital PDF
    /// that was also recognized holds its own text and the recognized text,
    /// and it may carry a typed text box too. The hit shows the words find
    /// will light when the page is opened: the PDF's own text, then the
    /// recognized text, then what was typed.
    ///
    /// - Parameters:
    ///   - items: only these documents — the ones on screen. **Narrowed
    ///     before any cap**, so the hits of a folder or a kind are not
    ///     crowded out by newer documents elsewhere that will not be shown.
    ///     Nil means the whole library.
    ///   - perItem: at most this many page hits per document, so one long
    ///     document cannot fill the list. Its title hit is not counted.
    ///   - limit: at most this many page hits in all.
    public func searchHits(_ text: String, among items: Set<ItemID>? = nil,
                           perItem: Int = 3, limit: Int = 60) throws -> [SearchHit] {
        guard let match = Self.ftsQuery(text), perItem > 0, limit > 0 else { return [] }
        if let items, items.isEmpty { return [] }
        // One parameter however many documents: a JSON array, read back by
        // `json_each`, rather than a variable per document.
        let among = try items.map { String(decoding: try JSONEncoder().encode($0.map(\.rawValue).sorted()), as: UTF8.self) }
        let open = String(SearchSnippet.openMark), close = String(SearchSnippet.closeMark)
        var parameters: [SQLValue] = [.text(open), .text(close), .text(match)]
        if let among { parameters.append(.text(among)) }
        // Every matching row; the page number counts the live pages before
        // this one in `(sort_key, id)`, the order pages are shown in.
        let rows = try db.query("""
            SELECT s.item_id, s.page_id, s.field,
                   snippet(search_index, 3, ?, ?, '…', 12),
                   CASE WHEN s.page_id IS NULL THEN NULL ELSE
                       (SELECT COUNT(*) FROM pages q, pages p
                        WHERE p.id = s.page_id AND q.item_id = p.item_id AND q.deleted_at IS NULL
                          AND (q.sort_key < p.sort_key OR (q.sort_key = p.sort_key AND q.id <= p.id)))
                   END
            FROM search_index s
            JOIN items i ON i.id = s.item_id
            WHERE search_index MATCH ? AND i.deleted_at IS NULL AND \(Self.livePageRow)
              \(among == nil ? "" : "AND s.item_id IN (SELECT value FROM json_each(?))")
            ORDER BY i.modified_at DESC, s.item_id
            LIMIT 2000
            """, parameters) { row in
            (item: ItemID(rawValue: row.text(0)), page: row.optionalText(1).map(PageID.init(rawValue:)),
             field: row.text(2), snippet: row.text(3), number: row.isNull(4) ? nil : row.int(4))
        }

        // Grouped by document, keeping the documents' order.
        var order: [ItemID] = []
        var byItem: [ItemID: [(page: PageID?, field: String, snippet: String, number: Int?)]] = [:]
        for row in rows {
            if byItem[row.item] == nil { order.append(row.item) }
            byItem[row.item, default: []].append((row.page, row.field, row.snippet, row.number))
        }

        var hits: [SearchHit] = []
        var pageHits = 0
        for item in order {
            let found = byItem[item] ?? []
            if let title = found.first(where: { $0.page == nil && Self.source(of: $0.field) == .title }) {
                hits.append(SearchHit(itemID: item, pageID: nil, pageNumber: nil, source: .title,
                                      snippet: SearchSnippet(marked: title.snippet)))
            }
            // One per page: the best source, as find reads the page.
            var best: [PageID: (source: SearchHit.Source, snippet: String, number: Int)] = [:]
            for entry in found {
                guard let page = entry.page, let number = entry.number,
                      let source = Self.source(of: entry.field), source != .title else { continue }
                if let held = best[page], Self.precedence(held.source) <= Self.precedence(source) { continue }
                best[page] = (source, entry.snippet, number)
            }
            for (page, entry) in best.sorted(by: { $0.value.number < $1.value.number }).prefix(perItem) {
                guard pageHits < limit else { break }
                hits.append(SearchHit(itemID: item, pageID: page, pageNumber: entry.number, source: entry.source,
                                      snippet: SearchSnippet(marked: entry.snippet)))
                pageHits += 1
            }
            if pageHits >= limit { break }
        }
        return hits
    }

    private static func source(of field: String) -> SearchHit.Source? {
        switch field {
        case "title": .title
        case "ocr": .recognized
        case embeddedTextField: .pageText
        case typedTextField: .typed
        default: nil
        }
    }

    /// Lower first: the order find reads a page's words in.
    private static func precedence(_ source: SearchHit.Source) -> Int {
        switch source {
        case .pageText: 0
        case .recognized: 1
        case .typed: 2
        case .title: 3
        }
    }
}
