import Foundation

/// Schema v10: what sync needs to remember, and the triggers that notice
/// every change.
///
/// **Why triggers.** The library is written from dozens of store methods, and
/// more arrive every week. A change that reaches the database without
/// reaching the outbox is a change that silently never syncs, and nothing
/// would say so. A trigger runs inside the same transaction as the write that
/// fired it, whoever wrote it, so "saved locally" and "queued for iCloud"
/// commit together or not at all.
///
/// **What they do while sync is off:** nothing (`sync_control.enabled = 0`).
/// Turning sync on reconciles the whole library against what was last
/// synced, so nothing depends on having watched every change since install.
///
/// **What they do while a change from iCloud is being applied:** nothing
/// (`applying_remote = 1`), or every downloaded edit would be queued to be
/// uploaded straight back.
enum SyncSchema {
    /// Seconds since 2001-01-01, the same clock `SQLValue.date` writes.
    private static let now = "((julianday('now') - 2451910.5) * 86400.0)"
    private static let active = "(SELECT enabled = 1 AND applying_remote = 0 FROM sync_control)"

    private static func save(_ type: String, id: String, parent: String) -> String {
        """
        UPDATE sync_control SET seq = seq + 1;
        INSERT OR REPLACE INTO sync_outbox (record_type, record_id, change, parent_id, seq, queued_at)
            VALUES ('\(type)', \(id), 'save', \(parent), (SELECT seq FROM sync_control), \(now));
        """
    }

    /// A delete is only worth sending for a record the server has. Anything
    /// else — drawn and erased before it ever synced — just leaves the queue.
    private static func delete(_ type: String, parent: String) -> String {
        """
        DELETE FROM sync_outbox WHERE record_type = '\(type)' AND record_id = OLD.id;
        UPDATE sync_control SET seq = seq + 1;
        INSERT INTO sync_outbox (record_type, record_id, change, parent_id, seq, queued_at)
            SELECT '\(type)', OLD.id, 'delete', \(parent), (SELECT seq FROM sync_control), \(now)
            WHERE EXISTS (SELECT 1 FROM sync_records WHERE record_type = '\(type)' AND record_id = OLD.id);
        """
    }

    /// A new reference to an original is the moment to make sure iCloud
    /// still has it: another device may have dropped its last use of the same
    /// bytes and be counting down to removing them.
    private static func recheck(asset: String) -> String {
        """
        UPDATE sync_assets SET state = 'pendingUpload', changed_at = \(now), attempts = 0, last_error = NULL
            WHERE asset_id = \(asset) AND state = 'uploaded';
        """
    }

    private static func triggers(_ type: String, table: String, parent: String, updateWhen: String = "1") -> String {
        let newParent = parent.replacingOccurrences(of: "ROW.", with: "NEW.")
        let oldParent = parent.replacingOccurrences(of: "ROW.", with: "OLD.")
        return """
        CREATE TRIGGER sync_\(table)_insert AFTER INSERT ON \(table) WHEN \(active) BEGIN
        \(save(type, id: "NEW.id", parent: newParent))
        END;
        CREATE TRIGGER sync_\(table)_update AFTER UPDATE ON \(table) WHEN \(active) AND (\(updateWhen)) BEGIN
        \(save(type, id: "NEW.id", parent: newParent))
        END;
        CREATE TRIGGER sync_\(table)_delete AFTER DELETE ON \(table) WHEN \(active) BEGIN
        \(delete(type, parent: oldParent))
        END;

        """
    }

    /// A page's `revision` and `modified_at` move on every stroke drawn on
    /// it. Neither is synced — they are this device's own bookkeeping — so a
    /// change to only those must not queue the page.
    private static let pageChanged = """
        OLD.item_id IS NOT NEW.item_id OR OLD.sort_key IS NOT NEW.sort_key
        OR OLD.source_width IS NOT NEW.source_width OR OLD.source_height IS NOT NEW.source_height
        OR OLD.content_kind IS NOT NEW.content_kind OR OLD.asset_id IS NOT NEW.asset_id
        OR OLD.pdf_page_index IS NOT NEW.pdf_page_index OR OLD.template IS NOT NEW.template
        OR OLD.transform_json IS NOT NEW.transform_json OR OLD.deleted_at IS NOT NEW.deleted_at
        """

    private static let placedAsset = "json_extract(NEW.payload_json, '$.image._0.assetID')"

    static let sql = """
        -- One row. `enabled` is the person's choice for this library;
        -- `applying_remote` is raised only inside the transaction that writes
        -- a change from iCloud; `seq` orders the outbox.
        CREATE TABLE sync_control (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            enabled INTEGER NOT NULL DEFAULT 0,
            applying_remote INTEGER NOT NULL DEFAULT 0,
            seq INTEGER NOT NULL DEFAULT 0
        );
        INSERT INTO sync_control (id) VALUES (1);

        CREATE TABLE sync_meta (
            key TEXT PRIMARY KEY NOT NULL,
            value BLOB NOT NULL
        );

        -- Changes not yet confirmed by iCloud. One row per record however
        -- many times it changed. `sent_seq` is the `seq` the row had when it
        -- was last handed over for sending: a confirmation only clears the
        -- row if the two still match, so an edit made while an upload was in
        -- flight stays queued.
        CREATE TABLE sync_outbox (
            record_type TEXT NOT NULL,
            record_id TEXT NOT NULL,
            change TEXT NOT NULL CHECK (change IN ('save', 'delete')),
            parent_id TEXT,
            seq INTEGER NOT NULL,
            sent_seq INTEGER,
            queued_at REAL NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            PRIMARY KEY (record_type, record_id)
        );
        CREATE INDEX sync_outbox_by_seq ON sync_outbox(seq);
        CREATE INDEX sync_outbox_by_parent ON sync_outbox(parent_id);

        -- What iCloud last confirmed for each record: the server's token for
        -- it, and its fields as they were then. That snapshot is the common
        -- ancestor a three-way merge needs.
        CREATE TABLE sync_records (
            record_type TEXT NOT NULL,
            record_id TEXT NOT NULL,
            system_fields BLOB,
            base_json TEXT NOT NULL,
            PRIMARY KEY (record_type, record_id)
        );

        -- Downloaded records that cannot be applied yet: their parent has not
        -- arrived, or a newer app wrote them. Tried again with every batch.
        CREATE TABLE sync_deferred (
            record_type TEXT NOT NULL,
            record_id TEXT NOT NULL,
            record_json TEXT NOT NULL,
            system_fields BLOB,
            reason TEXT NOT NULL,
            received_at REAL NOT NULL,
            PRIMARY KEY (record_type, record_id)
        );

        CREATE TABLE sync_conflicts (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL,
            item_id TEXT,
            page_id TEXT,
            copy_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            resolved_at REAL
        );

        -- Where each original stands with iCloud. `pendingRemoteDelete` keeps
        -- the time the last local use went away; the bytes are only removed
        -- from iCloud after the tombstone period, and only if still unused.
        CREATE TABLE sync_assets (
            asset_id TEXT PRIMARY KEY NOT NULL,
            state TEXT NOT NULL CHECK (state IN ('pendingUpload', 'uploaded', 'pendingRemoteDelete')),
            changed_at REAL NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            last_error TEXT
        );
        CREATE INDEX sync_assets_by_state ON sync_assets(state, changed_at);

        -- Pages this device itself moved to the bin. An edit arriving for
        -- one of these was made by someone who had not seen the deletion,
        -- and brings the page back.
        CREATE TABLE sync_local_page_deletes (
            page_id TEXT PRIMARY KEY NOT NULL REFERENCES pages(id) ON DELETE CASCADE
        );

        \(triggerSQL)
        """

    /// Every trigger, on its own. SQLite drops a table's triggers with the
    /// table, so **a later migration that rebuilds `folders`, `items`,
    /// `pages`, `page_objects`, `signatures`, `file_items` or `assets` must
    /// run this again** (after `DROP TRIGGER IF EXISTS` for each name).
    /// `SyncSchemaTests` fails if any is missing from the latest schema.
    static let triggerSQL = """

        \(triggers("folder", table: "folders", parent: "ROW.parent_id"))
        \(triggers("item", table: "items", parent: "NULL"))
        \(triggers("page", table: "pages", parent: "ROW.item_id", updateWhen: pageChanged))
        \(triggers("object", table: "page_objects", parent: "ROW.page_id"))
        \(triggers("signature", table: "signatures", parent: "NULL"))

        -- A file item's bytes are part of its item's record.
        CREATE TRIGGER sync_file_items_insert AFTER INSERT ON file_items WHEN \(active) BEGIN
        \(save("item", id: "NEW.item_id", parent: "NULL"))
        \(recheck(asset: "NEW.asset_id"))
        END;
        CREATE TRIGGER sync_file_items_update AFTER UPDATE ON file_items WHEN \(active) BEGIN
        \(save("item", id: "NEW.item_id", parent: "NULL"))
        \(recheck(asset: "NEW.asset_id"))
        END;

        CREATE TRIGGER sync_pages_asset_insert AFTER INSERT ON pages
            WHEN \(active) AND NEW.asset_id IS NOT NULL BEGIN
        \(recheck(asset: "NEW.asset_id"))
        END;
        CREATE TRIGGER sync_pages_asset_update AFTER UPDATE OF asset_id ON pages
            WHEN \(active) AND NEW.asset_id IS NOT NULL AND OLD.asset_id IS NOT NEW.asset_id BEGIN
        \(recheck(asset: "NEW.asset_id"))
        END;
        CREATE TRIGGER sync_objects_asset_insert AFTER INSERT ON page_objects
            WHEN \(active) AND NEW.kind = 'image' BEGIN
        \(recheck(asset: placedAsset))
        END;

        CREATE TRIGGER sync_assets_insert AFTER INSERT ON assets WHEN \(active) BEGIN
            INSERT OR REPLACE INTO sync_assets (asset_id, state, changed_at) VALUES (NEW.id, 'pendingUpload', \(now));
        END;
        CREATE TRIGGER sync_assets_delete AFTER DELETE ON assets WHEN \(active) BEGIN
            DELETE FROM sync_assets WHERE asset_id = OLD.id AND state = 'pendingUpload';
            UPDATE sync_assets SET state = 'pendingRemoteDelete', changed_at = \(now), attempts = 0, last_error = NULL
                WHERE asset_id = OLD.id AND state = 'uploaded';
        END;

        CREATE TRIGGER sync_pages_local_delete AFTER UPDATE OF deleted_at ON pages
            WHEN \(active) AND NEW.deleted_at IS NOT NULL AND OLD.deleted_at IS NULL BEGIN
            INSERT OR REPLACE INTO sync_local_page_deletes (page_id) VALUES (NEW.id);
        END;
        CREATE TRIGGER sync_pages_local_restore AFTER UPDATE OF deleted_at ON pages
            WHEN NEW.deleted_at IS NULL AND OLD.deleted_at IS NOT NULL BEGIN
            DELETE FROM sync_local_page_deletes WHERE page_id = NEW.id;
        END;
        """
}
