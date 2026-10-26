import Foundation
import PaperNestCore

/// How much room an item's originals take up, which is what compression has
/// to compare its output against.
extension LibraryStore {
    /// The bytes the item is made of: the originals behind its live pages, or,
    /// for a general file item, the file it keeps.
    ///
    /// Deliberately the paper rather than the size of some previous export,
    /// whose size would depend on the settings it was made with. An original
    /// shared by several pages is counted once, because immutable originals
    /// are shared by hash and the paper only exists once.
    ///
    /// Pages that have been deleted do not count, and an item in Recently
    /// Deleted reports zero: there is nothing there to compress. A document of
    /// template pages also reports zero, because those pages are drawn rather
    /// than stored.
    public func originalByteCount(of id: ItemID) throws -> Int64 {
        guard let item = try item(id), !item.isDeleted else { return 0 }

        let pageBytes = try db.query("""
            SELECT COALESCE(SUM(a.byte_count), 0) FROM assets a
            WHERE a.id IN (
                SELECT DISTINCT p.asset_id FROM pages p
                WHERE p.item_id = ? AND p.deleted_at IS NULL AND p.asset_id IS NOT NULL
            )
            """, [.text(item.id.rawValue)]) { $0.int64(0) }.first ?? 0

        let fileBytes = try db.query("SELECT byte_count FROM file_items WHERE item_id = ?",
                                     [.text(item.id.rawValue)]) { $0.int64(0) }.first ?? 0

        return pageBytes + fileBytes
    }
}
