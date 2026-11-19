import Foundation
import PaperNestCore

/// A presenter's private notes, one per page (schema v16), shown while
/// presenting and nowhere else.
///
/// **Private, like a page comment:** never rendered, exported, indexed for
/// search or sent to iCloud (no trigger queues it; see "Sync" in
/// `docs/ARCHITECTURE.md`). **Writing one is not editing the page:** no
/// page revision or document date moves, as with bookmarks. A note goes with
/// its page: hidden while the page is deleted and back if that is undone,
/// gone when the page is deleted for good. A copy of the document starts
/// without notes.
extension LibraryStore {
    /// The notes of a document's pages, by page, for the pages not deleted.
    public func speakerNotes(of itemID: ItemID) throws -> [PageID: String] {
        let rows = try db.query("""
            SELECT n.page_id, n.text FROM speaker_notes n JOIN pages p ON p.id = n.page_id
            WHERE p.item_id = ? AND p.deleted_at IS NULL
            """, [.text(itemID.rawValue)]) { (PageID(rawValue: $0.text(0)), $0.text(1)) }
        return Dictionary(rows, uniquingKeysWith: { first, _ in first })
    }

    /// A page's note, or nil when it has none or the page is deleted.
    public func speakerNote(on pageID: PageID) throws -> String? {
        try db.query("""
            SELECT n.text FROM speaker_notes n JOIN pages p ON p.id = n.page_id
            WHERE n.page_id = ? AND p.deleted_at IS NULL
            """, [.text(pageID.rawValue)]) { $0.text(0) }.first
    }

    /// Sets a page's note, replacing any it had. Text that is only white
    /// space removes the note. Committed when the call returns.
    public func setSpeakerNote(_ text: String, on pageID: PageID) throws {
        let timestamp = now()
        try db.transaction {
            guard let page = try page(pageID), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try db.run("DELETE FROM speaker_notes WHERE page_id = ?", [.text(pageID.rawValue)])
            } else {
                try db.run("""
                    INSERT INTO speaker_notes (page_id, text, modified_at) VALUES (?, ?, ?)
                    ON CONFLICT(page_id) DO UPDATE SET text = excluded.text, modified_at = excluded.modified_at
                    """, [.text(pageID.rawValue), .text(text), .date(timestamp)])
            }
        }
    }
}
