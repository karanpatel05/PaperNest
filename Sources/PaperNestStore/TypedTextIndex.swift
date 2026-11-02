import Foundation
import PaperNestCore

/// Making what someone typed on a page findable.
extension LibraryStore {
    /// The `search_index` field typed text has always used — not a new one.
    ///
    /// Worth saying why, because a fifth field was written first and was wrong.
    /// `LibraryComposition` already gathered text boxes into a `text` row, but
    /// **only while duplicating, extracting or merging**: typing a box onto an
    /// existing page indexed nothing at all, which is the gap this closes. A
    /// new field name would have left a composed item carrying the same words
    /// twice under two names.
    static let typedTextField = "text"

    /// Rebuilds the index of what someone typed on a page.
    ///
    /// **Recomputed from the page's objects rather than patched**, so it cannot
    /// drift: a box edited, deleted, undone or redone leaves whatever the page
    /// now holds, and nothing has to remember what the previous text was.
    ///
    /// There is no empty-marker row, unlike `pdfText`. A marker there means
    /// "this page was looked at and carries no text layer", which stops a
    /// backfill reading the same scan forever. Here the objects *are* the
    /// truth and there is nothing to look at later, so no row means no typing.
    ///
    /// **A page comment is private and is never indexed.** That is a promise,
    /// not a side effect of how this is written: only `.text` payloads — what
    /// someone typed *onto* the page — are gathered. The one path that writes
    /// comments, `persistCommentChange`, deliberately leaves the page revision
    /// alone, which is also why it never reaches here;
    /// `aPrivateCommentIsNeverFindable` says so out loud in case either of
    /// those facts changes.
    func reindexTypedText(on page: Page) throws {
        try db.run("DELETE FROM search_index WHERE page_id = ? AND field = ?",
                   [.text(page.id.rawValue), .text(Self.typedTextField)])
        // Only the text rows, found by `kind`, rather than every object on the
        // page. This runs on **every** object write, an ink stroke included, so
        // decoding a page's whole ink to discover it holds no text boxes would
        // cost one decode of everything per stroke through a drawing session.
        let sql = "SELECT payload_json FROM page_objects WHERE page_id = ? AND kind = 'text' ORDER BY z_key, id"
        let typed = try db.query(sql, [.text(page.id.rawValue)]) {
            try decoder.decode(PageObject.Payload.self, from: Data($0.text(0).utf8))
        }.compactMap { payload -> String? in
            guard case .text(let box) = payload else { return nil }
            let words = box.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return words.isEmpty ? nil : words
        }
        guard !typed.isEmpty else { return }
        try db.run("INSERT INTO search_index (item_id, page_id, field, content) VALUES (?, ?, ?, ?)",
                   [.text(page.itemID.rawValue), .text(page.id.rawValue),
                    .text(Self.typedTextField), .text(typed.joined(separator: " "))])
    }
}
