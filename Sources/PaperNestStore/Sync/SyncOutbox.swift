import Foundation
import PaperNestCore

/// The sending half of sync: what is waiting to go to iCloud, handing it
/// over, and taking the server's answer.
///
/// The outbox is the durable journal. A change is in it from the moment it
/// commits locally until the server confirms it, across crashes, relaunches
/// and months offline. Nothing here talks to a network; whoever does calls
/// these methods, which is what lets the whole protocol be tested against a
/// pretend server.
extension LibraryStore {
    // MARK: - Switch and small facts

    public func syncIsEnabled() throws -> Bool {
        try db.query("SELECT enabled FROM sync_control") { $0.bool(0) }.first ?? false
    }

    /// Turning sync on reconciles the whole library against what was last
    /// confirmed, so everything that exists is queued exactly once however
    /// many times this is called. Turning it off stops recording; it deletes
    /// nothing here and nothing in iCloud.
    public func syncSetEnabled(_ enabled: Bool) throws {
        try db.transaction {
            try db.run("UPDATE sync_control SET enabled = ?", [.bool(enabled)])
            if enabled { try syncReconcileAll() }
        }
    }

    public func syncMeta(_ key: String) throws -> Data? {
        try db.query("SELECT value FROM sync_meta WHERE key = ?", [.text(key)]) { $0.blob(0) }.first
    }

    public func syncSetMeta(_ key: String, _ value: Data?) throws {
        _ = try db.transaction {
            if let value {
                try db.run("INSERT OR REPLACE INTO sync_meta (key, value) VALUES (?, ?)", [.text(key), .blob(value)])
            } else {
                try db.run("DELETE FROM sync_meta WHERE key = ?", [.text(key)])
            }
        }
    }

    public func syncMetaString(_ key: String) throws -> String? {
        try syncMeta(key).map { String(decoding: $0, as: UTF8.self) }
    }

    public func syncSetMetaString(_ key: String, _ value: String?) throws {
        try syncSetMeta(key, value.map { Data($0.utf8) })
    }

    // MARK: - Queueing

    func syncEnqueue(_ key: SyncRecordKey, change: String, parent: String?) throws {
        try db.run("UPDATE sync_control SET seq = seq + 1")
        try db.run("""
            INSERT OR REPLACE INTO sync_outbox (record_type, record_id, change, parent_id, seq, queued_at)
            VALUES (?, ?, ?, ?, (SELECT seq FROM sync_control), ?)
            """, [.text(key.type.rawValue), .text(key.id), .text(change), .optionalText(parent), .date(now())])
    }

    struct SyncOutboxEntry {
        var change: String
        var seq: Int64
        var sentSeq: Int64?
        var isSave: Bool { change == "save" }
    }

    func syncOutboxEntry(_ key: SyncRecordKey) throws -> SyncOutboxEntry? {
        try db.query("SELECT change, seq, sent_seq FROM sync_outbox WHERE record_type = ? AND record_id = ?",
                     [.text(key.type.rawValue), .text(key.id)]) {
            SyncOutboxEntry(change: $0.text(0), seq: $0.int64(1), sentSeq: $0.isNull(2) ? nil : $0.int64(2))
        }.first
    }

    func syncDropOutbox(_ key: SyncRecordKey) throws {
        try db.run("DELETE FROM sync_outbox WHERE record_type = ? AND record_id = ?", [.text(key.type.rawValue), .text(key.id)])
    }

    struct SyncKnown {
        var systemFields: Data?
        var base: SyncFields
    }

    func syncKnown(_ key: SyncRecordKey) throws -> SyncKnown? {
        try db.query("SELECT system_fields, base_json FROM sync_records WHERE record_type = ? AND record_id = ?",
                     [.text(key.type.rawValue), .text(key.id)]) {
            SyncKnown(systemFields: $0.isNull(0) ? nil : $0.blob(0),
                      base: try decoder.decode(SyncFields.self, from: Data($0.text(1).utf8)))
        }.first
    }

    func syncSetKnown(_ key: SyncRecordKey, systemFields: Data?, base: SyncFields) throws {
        try db.run("INSERT OR REPLACE INTO sync_records (record_type, record_id, system_fields, base_json) VALUES (?, ?, ?, ?)",
                   [.text(key.type.rawValue), .text(key.id), systemFields.map(SQLValue.blob) ?? .null,
                    .text(try json(Self.syncCore(base)))])
    }

    func syncForget(_ key: SyncRecordKey) throws {
        try db.run("DELETE FROM sync_records WHERE record_type = ? AND record_id = ?", [.text(key.type.rawValue), .text(key.id)])
    }

    /// One statement queues every row a `SELECT` names; they share a `seq`,
    /// which only ever has to say "changed since it was handed over".
    func syncEnqueueRows(_ type: SyncRecordType, select: String, _ values: [SQLValue] = []) throws {
        try db.run("UPDATE sync_control SET seq = seq + 1")
        try db.run("""
            INSERT OR REPLACE INTO sync_outbox (record_type, record_id, change, parent_id, seq, queued_at)
            SELECT '\(type.rawValue)', src.id, 'save', src.parent, (SELECT seq FROM sync_control), \(now().timeIntervalSinceReferenceDate)
            FROM (\(select)) AS src
            """, values)
    }

    /// Brings the outbox in line with the library as it stands: every row the
    /// server has not confirmed in its current form is queued, and every
    /// record the server has whose row is gone is queued for deletion.
    ///
    /// This is the first-time migration, the resume after sync was off, and
    /// the repair after a reset — the same idempotent pass each time. A row
    /// already confirmed as it is costs a comparison and queues nothing.
    func syncReconcileAll() throws {
        let tables: [(SyncRecordType, String, String)] = [
            (.folder, "folders", "parent_id"), (.item, "items", "NULL"), (.page, "pages", "item_id"),
            (.object, "page_objects", "page_id"), (.signature, "signatures", "NULL"),
        ]
        for (type, table, parent) in tables {
            let unknown = """
                NOT EXISTS (SELECT 1 FROM sync_records r WHERE r.record_type = '\(type.rawValue)' AND r.record_id = t.id)
                AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.record_type = '\(type.rawValue)' AND o.record_id = t.id)
                """
            try syncEnqueueRows(type, select: "SELECT t.id AS id, \(parent) AS parent FROM \(table) t WHERE \(unknown)")

            // Rows the server knows: queue only those that differ from what
            // it confirmed.
            let known = try db.query("""
                SELECT r.record_id, t.id IS NOT NULL FROM sync_records r LEFT JOIN \(table) t ON t.id = r.record_id
                WHERE r.record_type = '\(type.rawValue)'
                  AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.record_type = r.record_type AND o.record_id = r.record_id)
                """) { ($0.text(0), $0.bool(1)) }
            for (id, exists) in known {
                let key = SyncRecordKey(type, id)
                if !exists {
                    try syncEnqueue(key, change: "delete", parent: nil)
                } else if let snapshot = try syncSnapshot(key), let base = try syncKnown(key)?.base,
                          Self.syncCore(snapshot.fields) != base {
                    try syncEnqueue(key, change: "save", parent: nil)
                }
            }
        }
        // Parents recorded for the bulk rows above are right; the single-row
        // paths pass nil, which only costs a slower "does this page have
        // pending edits" answer, so fill them in.
        try db.run("""
            UPDATE sync_outbox SET parent_id = (SELECT page_id FROM page_objects WHERE id = record_id)
            WHERE record_type = 'object' AND parent_id IS NULL AND change = 'save'
            """)
        try db.run("""
            UPDATE sync_outbox SET parent_id = (SELECT item_id FROM pages WHERE id = record_id)
            WHERE record_type = 'page' AND parent_id IS NULL AND change = 'save'
            """)
        try syncReconcileAssets()
    }

    // MARK: - Handing changes over

    public struct SyncBatch: Sendable {
        public var changes: [SyncOutgoing] = []
        /// Records held back because the original they point at has not
        /// reached iCloud yet. They go once it has.
        public var waitingForUploads = 0
        /// Queue entries that turned out to need no sending at all.
        public var dropped: [SyncRecordKey] = []
        /// The records behind `waitingForUploads`.
        public var blocked: [SyncRecordKey] = []
    }

    /// A record never confirmed by the server is being queued, so everything
    /// under it has to go as well. This is what makes "restore" work for a
    /// document another device deleted for good: the item is saved again, and
    /// its pages and their marks follow.
    private func syncQueueUnconfirmedChildren() throws {
        let unknown = { (type: String) in
            """
            NOT EXISTS (SELECT 1 FROM sync_records r WHERE r.record_type = '\(type)' AND r.record_id = c.id)
            AND NOT EXISTS (SELECT 1 FROM sync_outbox o WHERE o.record_type = '\(type)' AND o.record_id = c.id)
            """
        }
        let orphanParent = { (type: String, column: String) in
            """
            c.\(column) IN (SELECT o.record_id FROM sync_outbox o WHERE o.record_type = '\(type)' AND o.change = 'save'
                AND NOT EXISTS (SELECT 1 FROM sync_records r WHERE r.record_type = '\(type)' AND r.record_id = o.record_id))
            """
        }
        let pages = "SELECT c.id AS id, c.item_id AS parent FROM pages c WHERE \(orphanParent("item", "item_id")) AND \(unknown("page"))"
        if try !db.query("SELECT 1 FROM (\(pages)) LIMIT 1", map: { $0.int(0) }).isEmpty {
            try syncEnqueueRows(.page, select: pages)
        }
        let objects = "SELECT c.id AS id, c.page_id AS parent FROM page_objects c WHERE \(orphanParent("page", "page_id")) AND \(unknown("object"))"
        if try !db.query("SELECT 1 FROM (\(objects)) LIMIT 1", map: { $0.int(0) }).isEmpty {
            try syncEnqueueRows(.object, select: objects)
        }
    }

    /// The next changes to send, oldest first with parents ahead of children.
    /// Each is marked as handed over; `syncConfirm…` clears it only if it has
    /// not changed again since.
    public func syncNextBatch(limit: Int = 200, byteLimit: Int = 900_000,
                              only keys: Set<SyncRecordKey>? = nil) throws -> SyncBatch {
        try db.transaction {
            try syncQueueUnconfirmedChildren()
            var batch = SyncBatch()
            var bytes = 0
            let rows = try db.query("""
                SELECT record_type, record_id, change, seq FROM sync_outbox
                ORDER BY CASE record_type WHEN 'folder' THEN 0 WHEN 'item' THEN 1 WHEN 'page' THEN 2
                                          WHEN 'object' THEN 3 ELSE 4 END, seq
                """) { ($0.text(0), $0.text(1), $0.text(2), $0.int64(3)) }
            for (typeName, id, change, seq) in rows {
                guard batch.changes.count < limit, bytes < byteLimit else { break }
                guard let type = SyncRecordType(rawValue: typeName) else { continue }
                let key = SyncRecordKey(type, id)
                if let keys, !keys.contains(key) { continue }
                let known = try syncKnown(key)
                if change == "delete" {
                    // Nothing on the server to delete.
                    guard known != nil else { try syncDropOutbox(key); batch.dropped.append(key); continue }
                    batch.changes.append(.delete(key))
                } else {
                    guard let snapshot = try syncSnapshot(key) else { try syncDropOutbox(key); batch.dropped.append(key); continue }
                    // Already what the server holds: changed and changed back.
                    if let known, known.base == Self.syncCore(snapshot.fields) {
                        try syncDropOutbox(key)
                        batch.dropped.append(key)
                        continue
                    }
                    if let asset = Self.syncAssetReference(snapshot), try syncAssetBlocksSending(asset) {
                        batch.waitingForUploads += 1
                        batch.blocked.append(key)
                        continue
                    }
                    bytes += snapshot.fields.values.reduce(0) { total, value in
                        if case .string(let s) = value { return total + s.utf8.count }
                        return total + 8
                    }
                    batch.changes.append(.save(snapshot, systemFields: known?.systemFields))
                }
                try db.run("UPDATE sync_outbox SET sent_seq = ? WHERE record_type = ? AND record_id = ?",
                           [.int(seq), .text(typeName), .text(id)])
            }
            return batch
        }
    }

    /// Every record still waiting, for whoever schedules sending.
    public func syncPendingKeys() throws -> [(key: SyncRecordKey, isDelete: Bool)] {
        try db.query("SELECT record_type, record_id, change FROM sync_outbox ORDER BY seq") {
            (SyncRecordType(rawValue: $0.text(0)), $0.text(1), $0.text(2) == "delete")
        }.compactMap { type, id, isDelete in type.map { (SyncRecordKey($0, id), isDelete) } }
    }

    // MARK: - The server's answer

    /// The server accepted these saves. `record` is what it now holds.
    public func syncConfirmSaved(_ saved: [SyncIncoming]) throws {
        try db.transaction {
            for incoming in saved {
                let key = incoming.record.key
                try syncSetKnown(key, systemFields: incoming.systemFields, base: incoming.record.fields)
                try db.run("""
                    DELETE FROM sync_outbox WHERE record_type = ? AND record_id = ? AND change = 'save' AND sent_seq = seq
                    """, [.text(key.type.rawValue), .text(key.id)])
                try db.run("UPDATE sync_outbox SET sent_seq = NULL, attempts = 0, last_error = NULL WHERE record_type = ? AND record_id = ?",
                           [.text(key.type.rawValue), .text(key.id)])
            }
        }
    }

    /// The server deleted these, or reports they were already gone — the same
    /// outcome.
    public func syncConfirmDeleted(_ keys: [SyncRecordKey]) throws {
        try db.transaction {
            for key in keys {
                try db.run("""
                    DELETE FROM sync_outbox WHERE record_type = ? AND record_id = ? AND change = 'delete'
                    """, [.text(key.type.rawValue), .text(key.id)])
                // Re-created under the same id while the delete was in
                // flight: it is a new record now and must be saved as one.
                try syncForget(key)
            }
        }
    }

    /// Everything the server said about one send, taken in together.
    public struct SyncSendResult: Sendable {
        public var saved: [SyncIncoming] = []
        public var deleted: [SyncRecordKey] = []
        /// Refused because the server's copy had moved on; this is its copy.
        public var conflicts: [SyncIncoming] = []
        /// Refused because the server no longer has the record at all.
        public var missing: [SyncRecordKey] = []
        public var failed: [(key: SyncRecordKey, message: String)] = []

        public init() {}
    }

    /// Clears what was confirmed, merges what was refused, and keeps the rest
    /// queued with the reason. One transaction: a crash leaves either all of
    /// the server's answer taken in or none of it, and the outbox is right
    /// both ways.
    @discardableResult
    public func syncHandleSendResult(_ result: SyncSendResult) throws -> SyncApplyReport {
        try db.transaction {
            try syncConfirmSaved(result.saved)
            try syncConfirmDeleted(result.deleted)
            for failure in result.failed { try syncRecordFailure([failure.key], message: failure.message) }
            guard !result.conflicts.isEmpty || !result.missing.isEmpty else { return SyncApplyReport() }
            return try syncApply(modifications: result.conflicts, deletions: result.missing)
        }
    }

    /// Which of these are still waiting — changed again while their upload
    /// was in flight, or refused and merged.
    public func syncStillPending(_ keys: [SyncRecordKey]) throws -> [(key: SyncRecordKey, isDelete: Bool)] {
        try keys.compactMap { key in
            try syncOutboxEntry(key).map { (key, !$0.isSave) }
        }
    }

    /// A send that failed for a reason worth keeping: it stays queued and the
    /// reason is shown under Settings.
    public func syncRecordFailure(_ keys: [SyncRecordKey], message: String) throws {
        try db.transaction {
            for key in keys {
                try db.run("""
                    UPDATE sync_outbox SET attempts = attempts + 1, last_error = ?, sent_seq = NULL
                    WHERE record_type = ? AND record_id = ?
                    """, [.text(message), .text(key.type.rawValue), .text(key.id)])
            }
        }
    }

    /// Nothing was sent after all (cancelled, offline): the hand-over marks
    /// come off and everything is simply still waiting.
    public func syncAbandonBatch() throws {
        _ = try db.transaction { try db.run("UPDATE sync_outbox SET sent_seq = NULL WHERE sent_seq IS NOT NULL") }
    }

    // MARK: - Counts for the status line

    public struct SyncCounts: Sendable, Equatable {
        public var pendingChanges = 0
        public var pendingUploads = 0
        public var pendingDownloads = 0
        public var failedChanges = 0
        public var deferred = 0
        public var unresolvedConflicts = 0
        public var lastError: String?

        public init() {}
    }

    public func syncCounts() throws -> SyncCounts {
        var c = SyncCounts()
        let one = { (sql: String) in try self.db.query(sql) { $0.int(0) }.first ?? 0 }
        c.pendingChanges = try one("SELECT count(*) FROM sync_outbox")
        c.failedChanges = try one("SELECT count(*) FROM sync_outbox WHERE last_error IS NOT NULL")
        c.pendingUploads = try one("SELECT count(*) FROM sync_assets WHERE state = 'pendingUpload'")
        c.pendingDownloads = try one("SELECT count(*) FROM assets WHERE availability = 'remoteOnly'")
        c.deferred = try one("SELECT count(*) FROM sync_deferred")
        c.unresolvedConflicts = try one("SELECT count(*) FROM sync_conflicts WHERE resolved_at IS NULL")
        c.lastError = try db.query("""
            SELECT last_error FROM (
                SELECT last_error, queued_at AS at FROM sync_outbox WHERE last_error IS NOT NULL
                UNION ALL SELECT last_error, changed_at FROM sync_assets WHERE last_error IS NOT NULL)
            ORDER BY at DESC LIMIT 1
            """) { $0.optionalText(0) }.first ?? nil
        return c
    }

    // MARK: - Starting over with the server

    /// Forgets everything the server confirmed — tokens, ancestors, queue —
    /// without touching a single document, then queues the library afresh if
    /// sync is on. Used when the iCloud account changed and the person chose
    /// to sync this library with the new one, and when iCloud's copy was
    /// deleted.
    public func syncResetCloudKnowledge() throws {
        try db.transaction {
            for table in ["sync_records", "sync_outbox", "sync_deferred", "sync_assets"] {
                try db.run("DELETE FROM \(table)")
            }
            try db.run("DELETE FROM sync_meta WHERE key = ?", [.text(SyncMetaKey.engineState)])
            if try syncIsEnabled() { try syncReconcileAll() }
        }
    }

    /// Writes a copy of the database beside the library before sync is first
    /// turned on, so the library as it was can always be looked at again.
    /// Originals are immutable files and are not copied; see docs.
    public func syncWriteRecoveryCopy() throws -> URL {
        let folder = directoryURL.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = Int(now().timeIntervalSince1970)
        let url = folder.appendingPathComponent("before-icloud-sync-\(stamp).sqlite")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let stmt = try db.prepare("VACUUM INTO ?")
        try stmt.bind([.text(url.path)])
        while try stmt.step() {}
        return url
    }
}

public enum SyncMetaKey {
    public static let engineState = "engineState"
    public static let account = "account"
    public static let lastSynced = "lastSynced"
    public static let recoveryCopy = "recoveryCopy"
    public static let downloadOnDemand = "downloadOnDemand"
}
