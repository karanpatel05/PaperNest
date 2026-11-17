import Foundation
import PaperNestCore

extension LibraryStore {
    /// Whether anything other than this page still uses `asset`: another page
    /// (in the trash too, until it is purged), another page's undo history, a
    /// file item, a placed picture or a saved template.
    ///
    /// Asked before a redaction, so the review can say it up front. Assets are
    /// shared by content, and a duplicated document shares its pages'
    /// originals: redacting one copy cannot remove the original the other
    /// copy still shows. `PageRedactor`'s outcome reports the same thing after
    /// the fact; this lets nobody be told the content is gone when it is not.
    public func isAssetUsedElsewhere(_ asset: AssetID, besides pageID: PageID) throws -> Bool {
        let direct = try db.query("""
            SELECT 1 FROM pages p WHERE p.asset_id = ?1 AND p.id <> ?2
            UNION ALL SELECT 1 FROM page_content_history h WHERE h.asset_id = ?1 AND h.page_id <> ?2
            UNION ALL SELECT 1 FROM file_items f WHERE f.asset_id = ?1
            LIMIT 1
            """, [.text(asset.sha256), .text(pageID.rawValue)]) { $0.int(0) }
        if !direct.isEmpty { return true }
        // A template saved from a page keeps its own copy of what it showed.
        if try isAssetKeptBySavedTemplate(asset) { return true }
        return try db.query("SELECT payload_json FROM page_objects WHERE kind = 'image'") {
            try decoder.decode(PageObject.Payload.self, from: Data($0.text(0).utf8))
        }.contains { payload in
            if case .image(let image) = payload { return image.assetID == asset }
            return false
        }
    }
}
