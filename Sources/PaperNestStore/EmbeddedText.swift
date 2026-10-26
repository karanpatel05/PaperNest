import Foundation
import PaperNestCore

/// The text a digital PDF already carries, kept in the search index beside
/// recognized text and titles.
///
/// Unlike OCR this is deliberately **not** keyed to the page's revision: the
/// words come from the immutable original, so a crop, a rotation or an ink
/// stroke leaves them true. Only replacing what the page shows invalidates
/// them, which `replacePage` does.
extension LibraryStore {
    /// A fourth `search_index` field, beside `title`, `ocr` and `text`. The
    /// index is derived and rebuildable, and the column is unconstrained, so
    /// this needs no migration.
    static let embeddedTextField = "pdfText"

    /// Records the text read off the page's current content.
    ///
    /// `expecting` is the content the text was read from. Extraction runs off
    /// this actor, so the page may have been rescanned in between; when it no
    /// longer shows that content, nothing is written and this returns false.
    /// Nil or blank text records an empty marker, which answers no search but
    /// does say the page was looked at, so a scan is not read again on every
    /// pass.
    ///
    /// This is not an edit: no revision bump and no modification date, so a
    /// backfill over an existing library cannot reorder it.
    @discardableResult
    public func indexEmbeddedText(_ text: String?, for pageID: PageID, expecting content: PageContent) throws -> Bool {
        try db.transaction {
            guard let page = try page(pageID) else { throw StoreError.pageNotFound }
            guard page.content == content else { return false }
            try db.run("DELETE FROM search_index WHERE page_id = ? AND field = ?",
                       [.text(pageID.rawValue), .text(Self.embeddedTextField)])
            let words = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            try db.run("INSERT INTO search_index (item_id, page_id, field, content) VALUES (?, ?, ?, ?)",
                       [.text(page.itemID.rawValue), .text(pageID.rawValue), .text(Self.embeddedTextField), .text(words)])
            return true
        }
    }

    /// The text this page's own PDF carries, or nil when it has none.
    ///
    /// An empty marker row means "looked, found no text layer", which is not
    /// text and so reads back as nil. The text is stored normalized for the
    /// search index, so its whitespace is collapsed and a page comes back as
    /// one paragraph rather than its original lines — good enough to export,
    /// but not the page's layout.
    public func embeddedText(for pageID: PageID) throws -> String? {
        let found = try db.query("SELECT content FROM search_index WHERE page_id = ? AND field = ?",
                                 [.text(pageID.rawValue), .text(Self.embeddedTextField)]) { $0.text(0) }
        guard let words = found.first, !words.isEmpty else { return nil }
        return words
    }

    /// Live PDF pages whose text has not been looked for yet, newest document
    /// first. Pages of deleted documents, and deleted pages, are left alone,
    /// as are pages whose original is not on this device: fetching those
    /// would park unreadable pages at the front of every pass forever.
    ///
    /// The "already looked at" set is read **once** rather than per page.
    /// `search_index` is an FTS5 table whose `page_id` is `UNINDEXED`, so a
    /// correlated check scans the whole index for every page: on a 2,000-page
    /// library that cost 0.30 s on the store actor, blocking edits, on every
    /// library change. `page_id IS NOT NULL` matters because title rows carry
    /// a NULL page id, and one NULL inside `NOT IN` makes it match nothing.
    public func pagesMissingEmbeddedText(limit: Int = 200) throws -> [Page] {
        let ids = try db.query("""
            SELECT p.id FROM pages p
            JOIN items i ON i.id = p.item_id
            JOIN assets a ON a.id = p.asset_id AND a.availability = 'local'
            WHERE p.content_kind = 'pdfPage' AND p.deleted_at IS NULL AND i.deleted_at IS NULL
              AND p.id NOT IN (SELECT page_id FROM search_index WHERE field = ? AND page_id IS NOT NULL)
            ORDER BY i.modified_at DESC, p.sort_key
            LIMIT ?
            """, [.text(Self.embeddedTextField), .int(Int64(limit))]) { PageID(rawValue: $0.text(0)) }
        return try ids.compactMap { try page($0) }
    }
}

extension LibraryStore {
    /// Carries a duplicated, merged or extracted page's embedded text to the
    /// copy. The copy shares the same immutable original, so the words are
    /// identical and re-reading the PDF would only repeat work.
    ///
    /// An empty marker is copied too: the copy has been looked at just as much
    /// as its source, and leaving it out would send every copied scan back
    /// through the indexer.
    func copyEmbeddedText(from source: Page, to destination: Page) throws {
        let found = try db.query("SELECT content FROM search_index WHERE page_id = ? AND field = ?",
                                 [.text(source.id.rawValue), .text(Self.embeddedTextField)]) { $0.text(0) }
        guard let words = found.first else { return }
        try db.run("DELETE FROM search_index WHERE page_id = ? AND field = ?",
                   [.text(destination.id.rawValue), .text(Self.embeddedTextField)])
        try db.run("INSERT INTO search_index (item_id, page_id, field, content) VALUES (?, ?, ?, ?)",
                   [.text(destination.itemID.rawValue), .text(destination.id.rawValue),
                    .text(Self.embeddedTextField), .text(words)])
    }
}
