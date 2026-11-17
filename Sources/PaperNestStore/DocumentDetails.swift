import Foundation
import PaperNestCore

/// Details a person reviewed and kept for a document (schema v13,
/// `document_details`): one set per document, read off one of its pages.
///
/// Kept on this device and not synced, like bookmarks. **This is text taken
/// from a page**, so a redaction of that page deletes it in the same
/// operation (`deleteDocumentDetails(readFrom:)`), and the page's revision at
/// reading time is kept so the screen can say when the page has changed
/// since (a rescan, a correction).
extension LibraryStore {
    public struct StoredDetails: Hashable, Sendable {
        public var details: CapturedDetails
        public var pageID: PageID
        public var pageRevision: Int
        public var modifiedAt: Date
        /// The page has changed since these were read.
        public var isStale: Bool
    }

    /// Keeps `details` for `itemID`, replacing any it had, as read from
    /// `pageID` at its current revision.
    public func saveDocumentDetails(_ details: CapturedDetails, for itemID: ItemID, readFrom pageID: PageID) throws {
        try db.transaction {
            guard let page = try page(pageID), page.itemID == itemID else { throw StoreError.pageNotFound }
            try db.run("""
                INSERT OR REPLACE INTO document_details (item_id, page_id, page_revision, kind, details_json, modified_at)
                VALUES (?, ?, ?, ?, ?, ?)
                """, [.text(itemID.rawValue), .text(pageID.rawValue), .int(Int64(page.revision)),
                      .text(details.kind.rawValue), .text(try json(details)), .date(now())])
        }
    }

    public func documentDetails(of itemID: ItemID) throws -> StoredDetails? {
        let rows = try db.query("""
            SELECT d.page_id, d.page_revision, d.details_json, d.modified_at, p.revision
            FROM document_details d JOIN pages p ON p.id = d.page_id WHERE d.item_id = ?
            """, [.text(itemID.rawValue)]) { s in
            StoredDetails(details: try decoder.decode(CapturedDetails.self, from: Data(s.text(2).utf8)),
                          pageID: PageID(rawValue: s.text(0)), pageRevision: s.int(1), modifiedAt: s.date(3),
                          isStale: s.int(4) != s.int(1))
        }
        return rows.first
    }

    public func deleteDocumentDetails(of itemID: ItemID) throws {
        _ = try db.transaction { try db.run("DELETE FROM document_details WHERE item_id = ?", [.text(itemID.rawValue)]) }
    }

    /// Deletes details read from `pageID`. A redaction calls this: the details
    /// are words from the page, and the redacted ones must not survive here.
    @discardableResult
    public func deleteDocumentDetails(readFrom pageID: PageID) throws -> Int {
        try db.transaction { try db.run("DELETE FROM document_details WHERE page_id = ?", [.text(pageID.rawValue)]) }
    }
}
