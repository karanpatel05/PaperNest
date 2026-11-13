import Foundation
import PaperNestCore

/// The receiving half of sync: taking what the server says and making the
/// library agree with it without losing anything this device has not sent.
///
/// The rules, in the order they matter:
///
/// 1. **A change this device has not sent is never overwritten.** It is
///    merged with what arrived (`SyncMerge`), and where the two cannot both
///    stand, this device's version is kept as a copy and a conflict is noted.
/// 2. **An edit beats a deletion.** Whoever still holds the content sends it
///    again; whoever deleted it takes it back.
/// 3. **A deletion from elsewhere never erases at once.** A page goes to the
///    same thirty-day limbo a locally deleted page does; a document that was
///    live here goes to Recently Deleted. Only something already in the bin
///    on this device is removed for good.
///
/// Everything in one call happens in one transaction, with the outbox
/// triggers standing down so a downloaded change is not queued to go back.
extension LibraryStore {
    /// Applies one batch from the server. Also the answer to a rejected save:
    /// the server's version of the record is a modification like any other,
    /// and "that record no longer exists" is a deletion.
    @discardableResult
    public func syncApply(modifications: [SyncIncoming], deletions: [SyncRecordKey]) throws -> SyncApplyReport {
        try db.transaction {
            try db.run("UPDATE sync_control SET applying_remote = 1")
            var report = SyncApplyReport()
            var touchedPages = Set<PageID>()

            var queue: [SyncRecordKey: SyncIncoming] = [:]
            for deferred in try syncLoadDeferred() { queue[deferred.record.key] = deferred }
            for incoming in modifications { queue[incoming.record.key] = incoming }
            for key in deletions { queue[key] = nil }
            try db.run("DELETE FROM sync_deferred")

            var remaining = queue.values.sorted {
                ($0.record.key.type.applyOrder, $0.record.key.id) < ($1.record.key.type.applyOrder, $1.record.key.id)
            }
            // More than one pass only when a folder arrived ahead of the
            // folder it sits in.
            var progressed = true
            while progressed, !remaining.isEmpty {
                progressed = false
                var waiting: [SyncIncoming] = []
                for incoming in remaining {
                    // What a refused record counted is rolled back with it.
                    let before = (report, touchedPages)
                    do {
                        // A savepoint, so a record refused halfway leaves
                        // nothing of itself behind.
                        try db.transaction { try syncApplyOne(incoming, report: &report, touchedPages: &touchedPages) }
                        progressed = true
                    } catch SyncWriteRefusal.missingParent {
                        (report, touchedPages) = before
                        waiting.append(incoming)
                    } catch SyncWriteRefusal.notUnderstood(let what) {
                        (report, touchedPages) = before
                        try syncDefer(incoming, reason: "newer:\(what)")
                        report.deferred += 1
                    } catch let error as StoreError {
                        (report, touchedPages) = before
                        try syncDefer(incoming, reason: "error:\(error)")
                        report.deferred += 1
                    }
                }
                remaining = waiting
            }
            for incoming in remaining {
                try syncDefer(incoming, reason: "parent")
                report.deferred += 1
            }

            // Documents before their pages, pages before their marks: a
            // document sent to Recently Deleted keeps its pages as they were.
            for key in deletions.sorted(by: { ($0.type.applyOrder, $0.id) < ($1.type.applyOrder, $1.id) }) {
                try syncApplyDeletion(key, report: &report, touchedPages: &touchedPages)
            }
            for page in touchedPages { try syncTouchPage(page) }

            try db.run("UPDATE sync_control SET applying_remote = 0")
            // With the triggers back: these are this device's own edits and
            // have to reach the others.
            try syncRehomeOrphans()
            return report
        }
    }

    // MARK: - One record

    private func syncApplyOne(_ incoming: SyncIncoming, report: inout SyncApplyReport, touchedPages: inout Set<PageID>) throws {
        let key = incoming.record.key
        guard incoming.record.layoutVersion <= SyncRecord.layoutVersion else {
            throw SyncWriteRefusal.notUnderstood("layout \(incoming.record.layoutVersion)")
        }
        let remote = incoming.record.fields
        let remoteCore = Self.syncCore(remote)
        let known = try syncKnown(key)
        var pending = try syncOutboxEntry(key)
        let localRecord = try syncSnapshot(key)
        let isRealChange = known?.base != remoteCore

        if let entry = pending, !entry.isSave, localRecord == nil {
            guard isRealChange else {
                // The server is only repeating what this device already
                // knew; the deletion stands.
                try syncSetKnown(key, systemFields: incoming.systemFields, base: remote)
                return
            }
            // Edited there after being deleted here. The edit wins, and what
            // this device threw away has to be fetched back.
            try syncCancelDeletes(under: key)
            if key.type == .item || key.type == .page { report.needsFullRefetch = true }
            pending = nil
        }

        var resolution = SyncMerge.Resolution(merged: remoteCore)
        if let localRecord, pending?.isSave == true {
            resolution = SyncMerge.resolve(key.type, base: known?.base, local: Self.syncCore(localRecord.fields), incoming: remoteCore)
        }
        // A page deleted elsewhere while this device still has unsent work
        // on it stays.
        if key.type == .page, let localRecord, localRecord.fields["deletedAt"] == nil, remoteCore["deletedAt"] != nil,
           try syncPageHasPendingEdits(key.id) {
            resolution.merged["deletedAt"] = nil
        }

        if resolution.keepLocalCopy, let localRecord {
            try syncKeepConflictCopy(of: localRecord, report: &report, touchedPages: &touchedPages)
        }

        let localCore = localRecord.map { Self.syncCore($0.fields) }
        if localCore != resolution.merged {
            // Facts about the original come from whichever side the original
            // itself came from.
            var fields = resolution.merged
            let mergedRecord = SyncRecord(key: key, fields: fields)
            let source = Self.syncAssetReference(mergedRecord) == Self.syncAssetReference(incoming.record)
                ? remote : (localRecord?.fields ?? remote)
            for name in Self.syncAdvisoryFields { fields[name] = source[name] }
            let effect = try syncWriteRow(SyncRecord(key: key, fields: fields))
            report.changed += 1
            if let item = effect.itemID { report.affectedItems.insert(item) }
            if let page = effect.touchedPage { touchedPages.insert(page) }
        }
        try syncSetKnown(key, systemFields: incoming.systemFields, base: remote)

        if resolution.merged == remoteCore {
            try syncDropOutbox(key)
        } else if pending != nil {
            try db.run("UPDATE sync_outbox SET sent_seq = NULL WHERE record_type = ? AND record_id = ?",
                       [.text(key.type.rawValue), .text(key.id)])
        } else {
            try syncEnqueue(key, change: "save", parent: nil)
        }

        // A mark changed on a page that is in the bin. If this device put it
        // there, whoever made the mark had not seen that. Otherwise go by the
        // clocks: a mark made after the page was deleted means the same.
        if key.type == .object, isRealChange, let pageID = incoming.record.string("pageID"),
           let deletedAt = try db.query("SELECT deleted_at FROM pages WHERE id = ? AND deleted_at IS NOT NULL",
                                        [.text(pageID)], map: { $0.double(0) }).first {
            let deletedHere = try !db.query("SELECT 1 FROM sync_local_page_deletes WHERE page_id = ?",
                                            [.text(pageID)]) { $0.int(0) }.isEmpty
            if deletedHere || (incoming.record.double("modifiedAt") ?? 0) > deletedAt {
                try db.run("UPDATE pages SET deleted_at = NULL WHERE id = ?", [.text(pageID)])
                let item = try db.query("SELECT item_id FROM pages WHERE id = ?", [.text(pageID)]) { $0.text(0) }.first
                try syncEnqueue(SyncRecordKey(.page, pageID), change: "save", parent: item)
                report.changed += 1
            }
        }
    }

    /// Unsent work on a page: the page itself, or any mark on it.
    private func syncPageHasPendingEdits(_ pageID: String) throws -> Bool {
        try !db.query("""
            SELECT 1 FROM sync_outbox
            WHERE (record_type = 'page' AND record_id = ?1)
               OR (record_type = 'object' AND (parent_id = ?1 OR record_id IN (SELECT id FROM page_objects WHERE page_id = ?1)))
            LIMIT 1
            """, [.text(pageID)]) { $0.int(0) }.isEmpty
    }

    private func syncItemHasPendingEdits(_ itemID: String) throws -> Bool {
        try !db.query("""
            SELECT 1 FROM sync_outbox
            WHERE (record_type = 'item' AND record_id = ?1)
               OR (record_type = 'page' AND (parent_id = ?1 OR record_id IN (SELECT id FROM pages WHERE item_id = ?1)))
               OR (record_type = 'object' AND (parent_id IN (SELECT id FROM pages WHERE item_id = ?1)
                    OR record_id IN (SELECT o.id FROM page_objects o JOIN pages p ON p.id = o.page_id WHERE p.item_id = ?1)))
            LIMIT 1
            """, [.text(itemID)]) { $0.int(0) }.isEmpty
    }

    /// Withdraws this device's queued deletion of a record and of everything
    /// that was deleted along with it.
    private func syncCancelDeletes(under key: SyncRecordKey) throws {
        try syncDropOutbox(key)
        switch key.type {
        case .page:
            try db.run("DELETE FROM sync_outbox WHERE record_type = 'object' AND change = 'delete' AND parent_id = ?", [.text(key.id)])
        case .item:
            try db.run("""
                DELETE FROM sync_outbox WHERE record_type = 'object' AND change = 'delete' AND parent_id IN
                    (SELECT record_id FROM sync_outbox WHERE record_type = 'page' AND change = 'delete' AND parent_id = ?)
                """, [.text(key.id)])
            try db.run("DELETE FROM sync_outbox WHERE record_type = 'page' AND change = 'delete' AND parent_id = ?", [.text(key.id)])
        case .folder, .object, .signature:
            break
        }
    }

    // MARK: - Conflict copies

    private func syncKeepConflictCopy(of local: SyncRecord, report: inout SyncApplyReport,
                                      touchedPages: inout Set<PageID>) throws {
        let timestamp = now()
        switch local.key.type {
        case .page:
            guard let itemID = local.string("itemID"), let sortKey = local.string("sortKey") else { return }
            let next = try db.query("SELECT sort_key FROM pages WHERE item_id = ? AND sort_key > ? ORDER BY sort_key LIMIT 1",
                                    [.text(itemID), .text(sortKey)]) { $0.text(0) }.first
            let copyID = PageID.make().rawValue
            var fields = local.fields
            fields["sortKey"] = .string((try? SortKey.between(sortKey, next)) ?? sortKey)
            fields["deletedAt"] = nil
            fields["createdAt"] = .double(timestamp.timeIntervalSinceReferenceDate)
            try syncWriteRow(SyncRecord(key: SyncRecordKey(.page, copyID), fields: fields))
            try syncEnqueue(SyncRecordKey(.page, copyID), change: "save", parent: itemID)
            // The copy carries the marks as this device has them.
            let marks = try db.query("SELECT id FROM page_objects WHERE page_id = ?", [.text(local.key.id)]) { $0.text(0) }
            for mark in marks {
                let markCopy = PageObjectID.make().rawValue
                try db.run("""
                    INSERT INTO page_objects (id, page_id, z_key, kind, payload_json, modified_at)
                    SELECT ?, ?, z_key, kind, payload_json, modified_at FROM page_objects WHERE id = ?
                    """, [.text(markCopy), .text(copyID), .text(mark)])
                try syncEnqueue(SyncRecordKey(.object, markCopy), change: "save", parent: copyID)
            }
            if !marks.isEmpty { touchedPages.insert(PageID(rawValue: copyID)) }
            try syncNoteConflict(.pageVersion, itemID: itemID, pageID: local.key.id, copyID: copyID, at: timestamp)
            report.affectedItems.insert(ItemID(rawValue: itemID))

        case .object:
            guard let pageID = local.string("pageID") else { return }
            let copyID = PageObjectID.make().rawValue
            try syncWriteRow(SyncRecord(key: SyncRecordKey(.object, copyID), fields: local.fields))
            try syncEnqueue(SyncRecordKey(.object, copyID), change: "save", parent: pageID)
            touchedPages.insert(PageID(rawValue: pageID))
            let itemID = try db.query("SELECT item_id FROM pages WHERE id = ?", [.text(pageID)]) { $0.text(0) }.first
            try syncNoteConflict(.objectVersion, itemID: itemID, pageID: pageID, copyID: copyID, at: timestamp)
            if let itemID { report.affectedItems.insert(ItemID(rawValue: itemID)) }

        case .folder, .item, .signature:
            return
        }
        report.changed += 1
        report.newConflicts += 1
    }

    private func syncNoteConflict(_ kind: SyncConflict.Kind, itemID: String?, pageID: String?, copyID: String, at timestamp: Date) throws {
        try db.run("INSERT INTO sync_conflicts (id, kind, item_id, page_id, copy_id, created_at) VALUES (?, ?, ?, ?, ?, ?)",
                   [.text(UUID().uuidString), .text(kind.rawValue), .optionalText(itemID), .optionalText(pageID),
                    .text(copyID), .date(timestamp)])
    }

    /// Conflicts nobody has looked at yet, newest first.
    public func syncConflicts() throws -> [SyncConflict] {
        try db.query("""
            SELECT c.id, c.kind, c.item_id, i.name, c.page_id, c.copy_id, c.created_at
            FROM sync_conflicts c LEFT JOIN items i ON i.id = c.item_id
            WHERE c.resolved_at IS NULL ORDER BY c.created_at DESC, c.id
            """) { s in
            SyncConflict(id: s.text(0), kind: SyncConflict.Kind(rawValue: s.text(1)) ?? .objectVersion,
                         itemID: s.optionalText(2).map(ItemID.init(rawValue:)), itemName: s.optionalText(3),
                         pageID: s.optionalText(4).map(PageID.init(rawValue:)), copyID: s.text(5), createdAt: s.date(6))
        }
    }

    /// Marks a conflict as dealt with. `keepingCopy: false` also removes this
    /// device's version — a page goes the way any deleted page does and can
    /// be undone until the next launch; a mark is deleted.
    public func syncResolveConflict(_ id: String, keepingCopy: Bool) throws {
        try db.transaction {
            guard let conflict = try syncConflicts().first(where: { $0.id == id }) else { return }
            if !keepingCopy {
                switch conflict.kind {
                case .pageVersion: try deletePages([PageID(rawValue: conflict.copyID)])
                case .objectVersion: try deleteObject(PageObjectID(rawValue: conflict.copyID))
                }
            }
            try db.run("UPDATE sync_conflicts SET resolved_at = ? WHERE id = ?", [.date(now()), .text(id)])
        }
    }

    // MARK: - Deletions

    private func syncForgetPage(_ pageID: String, droppingOutbox: Bool) throws {
        let scope = "(record_type = 'page' AND record_id = ?1) OR (record_type = 'object' AND record_id IN (SELECT id FROM page_objects WHERE page_id = ?1))"
        try db.run("DELETE FROM sync_records WHERE \(scope)", [.text(pageID)])
        if droppingOutbox {
            try db.run("DELETE FROM sync_outbox WHERE \(scope) OR (record_type = 'object' AND parent_id = ?1)", [.text(pageID)])
        }
    }

    private func syncForgetItem(_ itemID: String, droppingOutbox: Bool) throws {
        let scope = """
            (record_type = 'item' AND record_id = ?1)
            OR (record_type = 'page' AND record_id IN (SELECT id FROM pages WHERE item_id = ?1))
            OR (record_type = 'object' AND record_id IN
                (SELECT o.id FROM page_objects o JOIN pages p ON p.id = o.page_id WHERE p.item_id = ?1))
            """
        try db.run("DELETE FROM sync_records WHERE \(scope)", [.text(itemID)])
        if droppingOutbox {
            try db.run("""
                DELETE FROM sync_outbox WHERE \(scope) OR (record_type = 'page' AND parent_id = ?1)
                    OR (record_type = 'object' AND parent_id IN (SELECT id FROM pages WHERE item_id = ?1))
                """, [.text(itemID)])
        }
    }

    private func syncRequeuePage(_ pageID: String) throws {
        let item = try db.query("SELECT item_id FROM pages WHERE id = ?", [.text(pageID)]) { $0.text(0) }.first
        try syncEnqueue(SyncRecordKey(.page, pageID), change: "save", parent: item)
        try syncEnqueueRows(.object, select: "SELECT id, page_id AS parent FROM page_objects WHERE page_id = ?", [.text(pageID)])
    }

    private func syncApplyDeletion(_ key: SyncRecordKey, report: inout SyncApplyReport, touchedPages: inout Set<PageID>) throws {
        let pending = try syncOutboxEntry(key)
        guard let local = try syncSnapshot(key) else {
            // Already gone here too.
            try syncForget(key)
            if pending?.isSave == false { try syncDropOutbox(key) }
            return
        }
        // Not a record the server ever confirmed to this device — never
        // synced, or already cut loose below. Not the server's to delete.
        guard try syncKnown(key) != nil else { return }
        let timestamp = now()

        switch key.type {
        case .object, .signature:
            if pending?.isSave == true {
                // Edited here, deleted there: it goes up again as new.
                try syncForget(key)
                try db.run("UPDATE sync_outbox SET sent_seq = NULL WHERE record_type = ? AND record_id = ?",
                           [.text(key.type.rawValue), .text(key.id)])
                return
            }
            if key.type == .object {
                try db.run("DELETE FROM page_objects WHERE id = ?", [.text(key.id)])
                if let page = local.string("pageID"), local.string("kind") != "comment" { touchedPages.insert(PageID(rawValue: page)) }
            } else {
                try db.run("DELETE FROM signatures WHERE id = ?", [.text(key.id)])
            }
            try syncForget(key)

        case .page:
            let alreadyBinned = local.fields["deletedAt"] != nil
            if !alreadyBinned, try syncPageHasPendingEdits(key.id) {
                try syncForgetPage(key.id, droppingOutbox: false)
                try syncRequeuePage(key.id)
            } else {
                // Thirty days in limbo, like any deleted page, then gone.
                try syncForgetPage(key.id, droppingOutbox: true)
                try db.run("UPDATE pages SET deleted_at = coalesce(deleted_at, ?) WHERE id = ?", [.date(timestamp), .text(key.id)])
            }
            if let item = local.string("itemID") { report.affectedItems.insert(ItemID(rawValue: item)) }

        case .item:
            if local.fields["deletedAt"] != nil {
                // In the bin here as well: both sides have let it go.
                try syncForgetItem(key.id, droppingOutbox: true)
                try db.run("DELETE FROM search_index WHERE item_id = ?", [.text(key.id)])
                try db.run("DELETE FROM items WHERE id = ?", [.text(key.id)])
            } else if try syncItemHasPendingEdits(key.id) {
                try syncForgetItem(key.id, droppingOutbox: false)
                try syncEnqueue(key, change: "save", parent: nil)
                try syncEnqueueRows(.page, select: "SELECT id, item_id AS parent FROM pages WHERE item_id = ?", [.text(key.id)])
                try syncEnqueueRows(.object, select: """
                    SELECT o.id AS id, o.page_id AS parent FROM page_objects o JOIN pages p ON p.id = o.page_id WHERE p.item_id = ?
                    """, [.text(key.id)])
            } else {
                // Live here, deleted for good elsewhere. It goes to Recently
                // Deleted on this device, whole, and restoring it sends it
                // back to iCloud as a new document.
                try syncForgetItem(key.id, droppingOutbox: true)
                try db.run("UPDATE items SET deleted_at = ? WHERE id = ?", [.date(timestamp), .text(key.id)])
                // Pages binned moments ago by the same deletion arriving
                // page-first come back with their document.
                try db.run("""
                    UPDATE pages SET deleted_at = NULL WHERE item_id = ?1 AND deleted_at IS NOT NULL
                      AND id NOT IN (SELECT page_id FROM sync_local_page_deletes)
                      AND NOT EXISTS (SELECT 1 FROM sync_records r WHERE r.record_type = 'page' AND r.record_id = pages.id)
                    """, [.text(key.id)])
            }
            report.affectedItems.insert(ItemID(rawValue: key.id))

        case .folder:
            try syncForget(key)
            try syncDropOutbox(key)
            try db.run("UPDATE folders SET deleted_at = coalesce(deleted_at, ?), modified_at = ? WHERE id = ?",
                       [.date(timestamp), .date(timestamp), .text(key.id)])
        }
        report.changed += 1
    }

    /// A folder deleted on one device may hold a document another device put
    /// there while offline. Nothing is left inside a folder that no longer
    /// shows: it moves up to the nearest folder that does.
    private func syncRehomeOrphans() throws {
        func liveAncestor(of folder: String?) throws -> String? {
            var cursor = folder
            var steps = 0
            while let c = cursor, steps < 64 {
                guard let row = try db.query("SELECT parent_id, deleted_at IS NOT NULL FROM folders WHERE id = ?", [.text(c)], map: {
                    ($0.optionalText(0), $0.bool(1))
                }).first else { return nil }
                if !row.1 { return c }
                cursor = row.0
                steps += 1
            }
            return nil
        }
        let timestamp = now()
        let strandedItems = try db.query("""
            SELECT i.id, i.folder_id FROM items i JOIN folders f ON f.id = i.folder_id WHERE f.deleted_at IS NOT NULL
            """) { ($0.text(0), $0.text(1)) }
        for (item, folder) in strandedItems {
            try db.run("UPDATE items SET folder_id = ?, modified_at = ? WHERE id = ?",
                       [.optionalText(try liveAncestor(of: folder)), .date(timestamp), .text(item)])
        }
        let strandedFolders = try db.query("""
            SELECT c.id, c.parent_id FROM folders c JOIN folders f ON f.id = c.parent_id
            WHERE f.deleted_at IS NOT NULL AND c.deleted_at IS NULL
            """) { ($0.text(0), $0.text(1)) }
        for (child, parent) in strandedFolders {
            try db.run("UPDATE folders SET parent_id = ?, modified_at = ? WHERE id = ?",
                       [.optionalText(try liveAncestor(of: parent)), .date(timestamp), .text(child)])
        }
    }

    // MARK: - Records that have to wait

    private func syncDefer(_ incoming: SyncIncoming, reason: String) throws {
        try db.run("""
            INSERT OR REPLACE INTO sync_deferred (record_type, record_id, record_json, system_fields, reason, received_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """, [.text(incoming.record.key.type.rawValue), .text(incoming.record.key.id), .text(try json(incoming.record.fields)),
                  incoming.systemFields.map(SQLValue.blob) ?? .null, .text(reason), .date(now())])
    }

    private func syncLoadDeferred() throws -> [SyncIncoming] {
        try db.query("SELECT record_type, record_id, record_json, system_fields FROM sync_deferred") { s -> SyncIncoming? in
            guard let type = SyncRecordType(rawValue: s.text(0)) else { return nil }
            let fields = try decoder.decode(SyncFields.self, from: Data(s.text(2).utf8))
            return SyncIncoming(record: SyncRecord(key: SyncRecordKey(type, s.text(1)), fields: fields),
                                systemFields: s.isNull(3) ? nil : s.blob(3))
        }.compactMap { $0 }
    }

    /// Whether anything is waiting on a newer version of the app.
    public func syncHasRecordsFromNewerApp() throws -> Bool {
        try !db.query("SELECT 1 FROM sync_deferred WHERE reason LIKE 'newer:%' LIMIT 1") { $0.int(0) }.isEmpty
    }
}
