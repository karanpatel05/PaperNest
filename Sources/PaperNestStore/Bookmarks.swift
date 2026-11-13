import Foundation
import PaperNestCore

/// The reader's bookmarks (schema v11).
///
/// **Not synced, by decision.** A bookmark is written to this library only;
/// no trigger queues it and iCloud never hears of it. The reasons and what
/// adding it would take are in `docs/ARCHITECTURE.md` under "Sync". The table
/// is shaped so that it can be added later without a rebuild: stable UUID
/// ids, a `modified_at`, and the page referred to by id.
///
/// **Marking a page is not editing it.** None of these calls moves a page's
/// revision or a document's modified date: a ribbon in a book does not
/// change the book, re-render its thumbnail, send its text to be recognised
/// again, or move it to the top of Recent.
extension LibraryStore {
    private static let bookmarkColumns = "b.id, p.item_id, b.page_id, b.name, b.created_at, b.modified_at"

    private static func decodeBookmark(_ row: Statement) -> Bookmark {
        Bookmark(id: BookmarkID(rawValue: row.text(0)), itemID: ItemID(rawValue: row.text(1)),
                 pageID: PageID(rawValue: row.text(2)), name: row.text(3),
                 createdAt: row.date(4), modifiedAt: row.date(5))
    }

    /// A document's bookmarks, in the order of its pages.
    ///
    /// A bookmark whose page is deleted is not listed while the page is gone,
    /// and is back if the deletion is undone.
    public func bookmarks(of itemID: ItemID) throws -> [Bookmark] {
        try db.query("""
            SELECT \(Self.bookmarkColumns) FROM bookmarks b
            JOIN pages p ON p.id = b.page_id
            WHERE p.item_id = ? AND p.deleted_at IS NULL
            ORDER BY p.sort_key, p.id
            """, [.text(itemID.rawValue)], map: Self.decodeBookmark)
    }

    private func bookmark(_ id: BookmarkID) throws -> Bookmark? {
        try db.query("""
            SELECT \(Self.bookmarkColumns) FROM bookmarks b
            JOIN pages p ON p.id = b.page_id
            WHERE b.id = ? AND p.deleted_at IS NULL
            """, [.text(id.rawValue)], map: Self.decodeBookmark).first
    }

    /// Marks a page. A page has one bookmark: marking a page that is already
    /// marked returns the bookmark it has, unchanged.
    @discardableResult
    public func addBookmark(on pageID: PageID, name: String = "") throws -> Bookmark {
        let timestamp = now()
        return try db.transaction {
            guard let page = try page(pageID), let parent = try item(page.itemID), !parent.isDeleted else {
                throw StoreError.pageNotFound
            }
            if let existing = try db.query("""
                SELECT \(Self.bookmarkColumns) FROM bookmarks b JOIN pages p ON p.id = b.page_id WHERE b.page_id = ?
                """, [.text(pageID.rawValue)], map: Self.decodeBookmark).first {
                return existing
            }
            let bookmark = Bookmark(itemID: page.itemID, pageID: pageID, name: name,
                                    createdAt: timestamp, modifiedAt: timestamp)
            try db.run("INSERT INTO bookmarks (id, page_id, name, created_at, modified_at) VALUES (?, ?, ?, ?, ?)",
                       [.text(bookmark.id.rawValue), .text(pageID.rawValue), .text(bookmark.name),
                        .date(timestamp), .date(timestamp)])
            return bookmark
        }
    }

    /// Names a bookmark. An empty name is allowed and means "show it by its
    /// page number again".
    @discardableResult
    public func renameBookmark(_ id: BookmarkID, to name: String) throws -> Bookmark {
        let timestamp = now()
        return try db.transaction {
            guard var bookmark = try bookmark(id) else { throw StoreError.bookmarkNotFound }
            bookmark.name = Bookmark.cleanName(name)
            bookmark.modifiedAt = timestamp
            try db.run("UPDATE bookmarks SET name = ?, modified_at = ? WHERE id = ?",
                       [.text(bookmark.name), .date(timestamp), .text(id.rawValue)])
            return bookmark
        }
    }

    /// Takes a bookmark away. Removing one that is already gone is not an
    /// error: the reader wanted it gone and it is.
    public func removeBookmark(_ id: BookmarkID) throws {
        _ = try db.transaction { try db.run("DELETE FROM bookmarks WHERE id = ?", [.text(id.rawValue)]) }
    }
}
