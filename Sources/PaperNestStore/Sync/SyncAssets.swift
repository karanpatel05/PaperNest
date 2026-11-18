import Foundation
import PaperNestCore

/// Where each original stands with iCloud.
///
/// Originals are immutable and named by their SHA-256, so there is nothing to
/// merge: bytes are either in iCloud or not, and either on this device or
/// not. They travel separately from records so that a device learns a
/// document exists — its name, its pages, its ink — without first having to
/// pull every scan it contains.
extension LibraryStore {
    func syncReconcileAssets() throws {
        let stamp = now().timeIntervalSinceReferenceDate
        // Bytes that are here and unknown to iCloud must be uploaded; a row
        // that only describes bytes elsewhere came from iCloud to begin with.
        try db.run("""
            INSERT OR IGNORE INTO sync_assets (asset_id, state, changed_at)
            SELECT id, CASE availability WHEN 'local' THEN 'pendingUpload' ELSE 'uploaded' END, \(stamp) FROM assets
            """)
        try db.run("""
            UPDATE sync_assets SET state = 'pendingUpload', changed_at = \(stamp)
            WHERE state = 'pendingRemoteDelete' AND asset_id IN (SELECT id FROM assets)
            """)
        try db.run("""
            UPDATE sync_assets SET state = 'pendingRemoteDelete', changed_at = \(stamp)
            WHERE state = 'uploaded' AND asset_id NOT IN (SELECT id FROM assets)
            """)
        try db.run("DELETE FROM sync_assets WHERE state = 'pendingUpload' AND asset_id NOT IN (SELECT id FROM assets)")
    }

    /// A record that points at an original is held back until iCloud has the
    /// bytes, so no other device is ever told about a page it cannot fetch.
    func syncAssetBlocksSending(_ id: AssetID) throws -> Bool {
        try !db.query("SELECT 1 FROM sync_assets WHERE asset_id = ? AND state = 'pendingUpload'",
                      [.text(id.sha256)]) { $0.int(0) }.isEmpty
    }

    public struct SyncAssetUpload: Sendable, Hashable {
        public var record: AssetRecord
        /// Nil when the bytes are not on this device: iCloud is only asked
        /// whether it still has them.
        public var fileURL: URL?
    }

    public func syncAssetsPendingUpload(limit: Int = 8) throws -> [SyncAssetUpload] {
        let ids = try db.query("SELECT asset_id FROM sync_assets WHERE state = 'pendingUpload' ORDER BY attempts, changed_at LIMIT ?",
                               [.int(Int64(limit))]) { AssetID(sha256: $0.text(0)) }
        return try ids.compactMap { id in
            guard let record = try assetRecord(id) else { return nil }
            return SyncAssetUpload(record: record, fileURL: record.availability == .local ? assets.url(for: id, kind: record.kind) : nil)
        }
    }

    public func syncAssetDidUpload(_ id: AssetID) throws {
        _ = try db.transaction {
            try db.run("""
                UPDATE sync_assets SET state = 'uploaded', changed_at = ?, attempts = 0, last_error = NULL
                WHERE asset_id = ? AND state = 'pendingUpload'
                """, [.date(now()), .text(id.sha256)])
        }
    }

    public func syncAssetFailed(_ id: AssetID, message: String) throws {
        _ = try db.transaction {
            try db.run("UPDATE sync_assets SET attempts = attempts + 1, last_error = ?, changed_at = ? WHERE asset_id = ?",
                       [.text(message), .date(now()), .text(id.sha256)])
        }
    }

    /// Originals that nothing here has used for the whole tombstone period.
    /// Only these may be removed from iCloud, and each is checked once more
    /// against the library at the moment of asking.
    public func syncAssetsDueForRemoteDelete(limit: Int = 50) throws -> [AssetID] {
        let cutoff = RetentionPolicy.syncTombstoneCutoff(now: now())
        return try db.query("""
            SELECT asset_id FROM sync_assets
            WHERE state = 'pendingRemoteDelete' AND changed_at < ? AND asset_id NOT IN (SELECT id FROM assets)
            LIMIT ?
            """, [.date(cutoff), .int(Int64(limit))]) { AssetID(sha256: $0.text(0)) }
    }

    public func syncAssetDidRemoteDelete(_ id: AssetID) throws {
        _ = try db.transaction {
            try db.run("DELETE FROM sync_assets WHERE asset_id = ? AND state = 'pendingRemoteDelete'", [.text(id.sha256)])
        }
    }

    /// Originals known only by description. `item` narrows it to one
    /// document, for when someone opens it or asks for it offline.
    public func syncAssetsNeedingDownload(for item: ItemID? = nil, limit: Int = 50) throws -> [AssetRecord] {
        let ids: [AssetID]
        if let item {
            ids = try syncAssetIDs(of: item)
        } else {
            ids = try db.query("SELECT id FROM assets WHERE availability = 'remoteOnly' LIMIT ?", [.int(Int64(limit))]) {
                AssetID(sha256: $0.text(0))
            }
        }
        return try ids.compactMap { try assetRecord($0) }.filter { $0.availability == .remoteOnly }.prefix(limit).map { $0 }
    }

    /// Every original a document uses: its pages, a file item's bytes, and
    /// pictures placed on its pages. Deleted pages count — they can still be
    /// restored.
    func syncAssetIDs(of item: ItemID) throws -> [AssetID] {
        var ids = Set(try db.query("""
            SELECT asset_id FROM pages WHERE item_id = ?1 AND asset_id IS NOT NULL
            UNION SELECT asset_id FROM file_items WHERE item_id = ?1
            UNION SELECT json_extract(o.payload_json, '$.image._0.assetID') FROM page_objects o
                  JOIN pages p ON p.id = o.page_id WHERE p.item_id = ?1 AND o.kind = 'image'
            """, [.text(item.rawValue)]) { $0.optionalText(0) }.compactMap { $0 })
        ids.remove("")
        return ids.sorted().map(AssetID.init(sha256:))
    }

    /// Takes a downloaded file into the library. The bytes are hashed as they
    /// are copied and must be exactly the original asked for; anything else
    /// is refused and the row keeps saying the bytes are not here.
    public func syncInstallDownloadedAsset(_ id: AssetID, from fileURL: URL) throws {
        guard let record = try assetRecord(id) else { throw StoreError.assetMissing(id.sha256) }
        let staged = try assets.store(contentsOf: fileURL, kind: record.kind, originalFilename: record.originalFilename)
        guard staged.id == id else {
            // Stored under its true name, which nothing references; the
            // launch sweep takes it.
            throw StoreError.assetChecksumMismatch(id.sha256)
        }
        _ = try db.transaction {
            try db.run("UPDATE assets SET availability = 'local', byte_count = ? WHERE id = ?",
                       [.int(staged.byteCount), .text(id.sha256)])
            try db.run("UPDATE sync_assets SET last_error = NULL, attempts = 0 WHERE asset_id = ?", [.text(id.sha256)])
            // Pages that showed "not on this device" are cached that way
            // under their revision; moving it is what makes them draw again.
            // (A revision-only change is not a synced edit.)
            try db.run("""
                UPDATE pages SET revision = revision + 1 WHERE asset_id = ?1 OR id IN
                    (SELECT page_id FROM page_objects WHERE kind = 'image' AND json_extract(payload_json, '$.image._0.assetID') = ?1)
                """, [.text(id.sha256)])
        }
    }

    /// Originals of one document that could be removed from this device
    /// without losing anything: iCloud has confirmed each, and no other
    /// document or saved template here uses it.
    public func syncEvictableAssets(of item: ItemID) throws -> [AssetRecord] {
        try syncAssetIDs(of: item).compactMap { id -> AssetRecord? in
            guard let record = try assetRecord(id), record.availability == .local else { return nil }
            let uploaded = try !db.query("SELECT 1 FROM sync_assets WHERE asset_id = ? AND state = 'uploaded'",
                                         [.text(id.sha256)]) { $0.int(0) }.isEmpty
            guard uploaded else { return nil }
            // Templates and picture stamps are not synced, so nothing in
            // iCloud speaks for the ones here: an original either keeps stays
            // on this device.
            guard try !isAssetKeptAside(id) else { return nil }
            let users = try db.query("""
                SELECT item_id FROM pages WHERE asset_id = ?1
                UNION SELECT item_id FROM file_items WHERE asset_id = ?1
                UNION SELECT p.item_id FROM page_objects o JOIN pages p ON p.id = o.page_id
                      WHERE o.kind = 'image' AND json_extract(o.payload_json, '$.image._0.assetID') = ?1
                UNION SELECT p.item_id FROM page_content_history h JOIN pages p ON p.id = h.page_id WHERE h.asset_id = ?1
                """, [.text(id.sha256)]) { $0.text(0) }
            return users.allSatisfy { $0 == item.rawValue } ? record : nil
        }
    }

    /// Removes this device's copy of one original that iCloud holds. The row
    /// is changed first: a crash in between leaves a file the library no
    /// longer counts on, never a row promising bytes that are gone.
    public func syncEvictLocalCopy(_ id: AssetID) throws {
        guard let record = try assetRecord(id), record.availability == .local else { return }
        let changed = try db.transaction {
            try db.run("""
                UPDATE assets SET availability = 'remoteOnly'
                WHERE id = ? AND EXISTS (SELECT 1 FROM sync_assets WHERE asset_id = assets.id AND state = 'uploaded')
                """, [.text(id.sha256)])
        }
        if changed == 1 { try? assets.remove(id, kind: record.kind) }
    }

    /// Whether everything a document shows is on this device.
    public func syncIsAvailableOffline(_ item: ItemID) throws -> Bool {
        try syncAssetIDs(of: item).allSatisfy { try assetRecord($0)?.availability == .local }
    }

    /// Documents with at least one original that is only in iCloud.
    public func syncCloudOnlyItems() throws -> Set<ItemID> {
        Set(try db.query("""
            SELECT p.item_id FROM pages p JOIN assets a ON a.id = p.asset_id WHERE a.availability = 'remoteOnly'
            UNION SELECT f.item_id FROM file_items f JOIN assets a ON a.id = f.asset_id WHERE a.availability = 'remoteOnly'
            """) { ItemID(rawValue: $0.text(0)) })
    }
}
