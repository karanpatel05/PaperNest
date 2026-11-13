import Foundation
import PaperNestCore

/// Reading a library row as a sync record, and writing one back.
///
/// Field names here are the wire format. Renaming one orphans that field on
/// every device that already synced; add a new name and bump
/// `SyncRecord.layoutVersion` instead.
extension LibraryStore {
    /// Facts about an original that ride along with whatever references it,
    /// so a device that has never seen those bytes can still make a row for
    /// them. They describe *this device's* copy — the same bytes may be filed
    /// as a PDF here and as a plain file there — so they are never compared
    /// or merged, or two devices would correct each other for ever.
    static let syncAdvisoryFields: Set<String> = ["assetKind", "assetBytes", "assetName", SyncRecord.layoutVersionField]

    static func syncCore(_ fields: SyncFields) -> SyncFields {
        fields.filter { !syncAdvisoryFields.contains($0.key) }
    }

    private static func put(_ f: inout SyncFields, _ name: String, text s: Statement, _ col: Int32) {
        if let v = s.optionalText(col) { f[name] = .string(v) }
    }

    private static func put(_ f: inout SyncFields, _ name: String, double s: Statement, _ col: Int32) {
        if !s.isNull(col) { f[name] = .double(s.double(col)) }
    }

    private static func put(_ f: inout SyncFields, _ name: String, int s: Statement, _ col: Int32) {
        if !s.isNull(col) { f[name] = .int(s.int64(col)) }
    }

    /// The row as a record, or nil when there is no such row. Soft-deleted
    /// rows are returned: being in Recently Deleted is a field, not an
    /// absence.
    func syncSnapshot(_ key: SyncRecordKey) throws -> SyncRecord? {
        let fields: SyncFields?
        switch key.type {
        case .folder:
            fields = try db.query("SELECT name, parent_id, created_at, modified_at, deleted_at FROM folders WHERE id = ?",
                                  [.text(key.id)]) { s in
                var f: SyncFields = [:]
                Self.put(&f, "name", text: s, 0)
                Self.put(&f, "parentID", text: s, 1)
                Self.put(&f, "createdAt", double: s, 2)
                Self.put(&f, "modifiedAt", double: s, 3)
                Self.put(&f, "deletedAt", double: s, 4)
                return f
            }.first
        case .item:
            fields = try db.query("""
                SELECT i.kind, i.name, i.folder_id, i.is_favorite, i.created_at, i.modified_at, i.deleted_at,
                       i.schema_version, i.color_label, f.asset_id, f.uti, f.original_filename, f.byte_count, a.kind
                FROM items i
                LEFT JOIN file_items f ON f.item_id = i.id
                LEFT JOIN assets a ON a.id = f.asset_id
                WHERE i.id = ?
                """, [.text(key.id)]) { s in
                var f: SyncFields = [:]
                Self.put(&f, "kind", text: s, 0)
                Self.put(&f, "name", text: s, 1)
                Self.put(&f, "folderID", text: s, 2)
                Self.put(&f, "isFavorite", int: s, 3)
                Self.put(&f, "createdAt", double: s, 4)
                Self.put(&f, "modifiedAt", double: s, 5)
                Self.put(&f, "deletedAt", double: s, 6)
                Self.put(&f, "schemaVersion", int: s, 7)
                Self.put(&f, "colorLabel", text: s, 8)
                Self.put(&f, "fileAssetID", text: s, 9)
                Self.put(&f, "fileUTI", text: s, 10)
                Self.put(&f, "fileName", text: s, 11)
                Self.put(&f, "fileBytes", int: s, 12)
                Self.put(&f, "assetKind", text: s, 13)
                return f
            }.first
        case .page:
            fields = try db.query("""
                SELECT p.item_id, p.sort_key, p.source_width, p.source_height, p.content_kind, p.asset_id,
                       p.pdf_page_index, p.template, p.transform_json, p.created_at, p.deleted_at,
                       a.kind, a.byte_count, a.original_filename
                FROM pages p LEFT JOIN assets a ON a.id = p.asset_id
                WHERE p.id = ?
                """, [.text(key.id)]) { s in
                var f: SyncFields = [:]
                Self.put(&f, "itemID", text: s, 0)
                Self.put(&f, "sortKey", text: s, 1)
                Self.put(&f, "width", double: s, 2)
                Self.put(&f, "height", double: s, 3)
                Self.put(&f, "contentKind", text: s, 4)
                Self.put(&f, "assetID", text: s, 5)
                Self.put(&f, "pdfIndex", int: s, 6)
                Self.put(&f, "template", text: s, 7)
                Self.put(&f, "transform", text: s, 8)
                Self.put(&f, "createdAt", double: s, 9)
                Self.put(&f, "deletedAt", double: s, 10)
                Self.put(&f, "assetKind", text: s, 11)
                Self.put(&f, "assetBytes", int: s, 12)
                Self.put(&f, "assetName", text: s, 13)
                return f
            }.first
        case .object:
            fields = try db.query("""
                SELECT o.page_id, o.z_key, o.kind, o.payload_json, o.modified_at, a.id, a.kind, a.byte_count, a.original_filename
                FROM page_objects o
                LEFT JOIN assets a ON o.kind = 'image' AND a.id = json_extract(o.payload_json, '$.image._0.assetID')
                WHERE o.id = ?
                """, [.text(key.id)]) { s in
                var f: SyncFields = [:]
                Self.put(&f, "pageID", text: s, 0)
                Self.put(&f, "zKey", text: s, 1)
                Self.put(&f, "kind", text: s, 2)
                Self.put(&f, "payload", text: s, 3)
                Self.put(&f, "modifiedAt", double: s, 4)
                Self.put(&f, "assetID", text: s, 5)
                Self.put(&f, "assetKind", text: s, 6)
                Self.put(&f, "assetBytes", int: s, 7)
                Self.put(&f, "assetName", text: s, 8)
                return f
            }.first
        case .signature:
            fields = try db.query("SELECT name, strokes_json, created_at FROM signatures WHERE id = ?", [.text(key.id)]) { s in
                var f: SyncFields = [:]
                Self.put(&f, "name", text: s, 0)
                Self.put(&f, "strokes", text: s, 1)
                Self.put(&f, "createdAt", double: s, 2)
                return f
            }.first
        }
        guard var fields else { return nil }
        fields[SyncRecord.layoutVersionField] = .int(SyncRecord.layoutVersion)
        return SyncRecord(key: key, fields: fields)
    }

    /// The original a record points at, if it points at one.
    static func syncAssetReference(_ record: SyncRecord) -> AssetID? {
        let name: String? = switch record.key.type {
        case .item: record.string("fileAssetID")
        case .page, .object: record.string("assetID")
        case .folder, .signature: nil
        }
        return name.map(AssetID.init(sha256:))
    }

    /// Why a downloaded record could not be written yet.
    enum SyncWriteRefusal: Error, Equatable {
        /// The folder, item or page it belongs to is not here.
        case missingParent
        /// It uses something this build does not know: a newer app wrote it.
        case notUnderstood(String)
    }

    struct SyncWriteEffect {
        var itemID: ItemID?
        /// A page whose marks changed and whose revision still has to move.
        var touchedPage: PageID?
    }

    private func rowExists(_ table: String, _ id: String) throws -> Bool {
        try !db.query("SELECT 1 FROM \(table) WHERE id = ?", [.text(id)]) { $0.int(0) }.isEmpty
    }

    /// Makes sure there is a row for an original that a downloaded record
    /// uses. If the bytes are not on this device the row says so
    /// (`remoteOnly`), and nothing may present the page as available offline.
    private func ensureAssetRow(_ id: AssetID, record: SyncRecord, fallbackKind: AssetKind, bytes: Int64?) throws {
        guard try !rowExists("assets", id.sha256) else { return }
        let kind = record.string("assetKind").flatMap(AssetKind.init(rawValue:)) ?? fallbackKind
        // The bytes may already be here: an original this device once had and
        // has not swept yet. Checked, not assumed.
        let isLocal = (try? assets.verify(id, kind: kind)) != nil
        let size = bytes ?? record.int("assetBytes") ?? 0
        try db.run("""
            INSERT INTO assets (id, kind, byte_count, original_filename, availability, created_at) VALUES (?, ?, ?, ?, ?, ?)
            """, [.text(id.sha256), .text(kind.rawValue), .int(size), .optionalText(record.string("assetName")),
                  .text(isLocal ? AssetAvailability.local.rawValue : AssetAvailability.remoteOnly.rawValue), .date(now())])
        // It came from iCloud, so iCloud has it.
        try db.run("INSERT OR REPLACE INTO sync_assets (asset_id, state, changed_at) VALUES (?, 'uploaded', ?)",
                   [.text(id.sha256), .date(now())])
    }

    private static func value(_ record: SyncRecord, _ name: String) -> SQLValue {
        switch record.fields[name] {
        case .string(let s)?: .text(s)
        case .int(let i)?: .int(i)
        case .double(let d)?: .double(d)
        case nil: .null
        }
    }

    private static func require(_ record: SyncRecord, _ names: String...) throws {
        for name in names where record.fields[name] == nil {
            throw SyncWriteRefusal.notUnderstood("\(record.key.type.rawValue) without \(name)")
        }
    }

    /// Writes a downloaded record over the row with the same id, or creates
    /// it. Runs inside the caller's transaction with the triggers standing
    /// down. `INSERT … ON CONFLICT DO UPDATE` throughout, never `REPLACE`:
    /// replacing an item deletes the old row first, and that cascades into
    /// every page it has.
    @discardableResult
    func syncWriteRow(_ record: SyncRecord) throws -> SyncWriteEffect {
        let id = record.key.id
        let v = { Self.value(record, $0) }
        switch record.key.type {
        case .folder:
            try Self.require(record, "name", "createdAt", "modifiedAt")
            var parent = record.string("parentID")
            if let p = parent {
                guard try rowExists("folders", p) else { throw SyncWriteRefusal.missingParent }
                // Two devices can each move a folder into the other. Neither
                // was wrong; together they make a loop with no way in.
                var cursor: String? = p
                var steps = 0
                while let c = cursor, steps < 64 {
                    if c == id { parent = nil; break }
                    cursor = try db.query("SELECT parent_id FROM folders WHERE id = ?", [.text(c)]) { $0.optionalText(0) }.first ?? nil
                    steps += 1
                }
            }
            try db.run("""
                INSERT INTO folders (id, name, parent_id, created_at, modified_at, deleted_at) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, parent_id = excluded.parent_id,
                    created_at = excluded.created_at, modified_at = excluded.modified_at, deleted_at = excluded.deleted_at
                """, [.text(id), v("name"), .optionalText(parent), v("createdAt"), v("modifiedAt"), v("deletedAt")])
            return SyncWriteEffect()

        case .item:
            try Self.require(record, "kind", "name", "createdAt", "modifiedAt")
            guard let kindName = record.string("kind"), let kind = ItemKind(rawValue: kindName) else {
                throw SyncWriteRefusal.notUnderstood("item kind")
            }
            if let color = record.string("colorLabel"), ItemColor(rawValue: color) == nil {
                throw SyncWriteRefusal.notUnderstood("item color")
            }
            if let folder = record.string("folderID") {
                guard try rowExists("folders", folder) else { throw SyncWriteRefusal.missingParent }
            }
            try db.run("""
                INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, folder_id = excluded.folder_id,
                    is_favorite = excluded.is_favorite, created_at = excluded.created_at, modified_at = excluded.modified_at,
                    deleted_at = excluded.deleted_at, schema_version = excluded.schema_version, color_label = excluded.color_label
                """, [.text(id), .text(kind.rawValue), v("name"), v("folderID"), .int(record.int("isFavorite") ?? 0),
                      v("createdAt"), v("modifiedAt"), v("deletedAt"),
                      .int(record.int("schemaVersion") ?? Int64(LibraryItem.currentSchemaVersion)), v("colorLabel")])
            if kind == .file {
                try Self.require(record, "fileAssetID", "fileUTI", "fileName", "fileBytes")
                let asset = AssetID(sha256: record.string("fileAssetID") ?? "")
                try ensureAssetRow(asset, record: record, fallbackKind: .file, bytes: record.int("fileBytes"))
                try db.run("""
                    INSERT INTO file_items (item_id, asset_id, uti, original_filename, byte_count) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(item_id) DO UPDATE SET asset_id = excluded.asset_id, uti = excluded.uti,
                        original_filename = excluded.original_filename, byte_count = excluded.byte_count
                    """, [.text(id), .text(asset.sha256), v("fileUTI"), v("fileName"), v("fileBytes")])
            }
            if let item = try item(ItemID(rawValue: id)) { try reindexTitle(item) }
            return SyncWriteEffect(itemID: ItemID(rawValue: id))

        case .page:
            try Self.require(record, "itemID", "sortKey", "width", "height", "contentKind", "transform", "createdAt")
            guard let itemID = record.string("itemID"), try rowExists("items", itemID) else { throw SyncWriteRefusal.missingParent }
            guard let contentKind = record.string("contentKind"), ["image", "pdfPage", "template"].contains(contentKind) else {
                throw SyncWriteRefusal.notUnderstood("page content")
            }
            let assetName = record.string("assetID")
            guard (contentKind == "template") == (assetName == nil),
                  (record.double("width") ?? 0) > 0, (record.double("height") ?? 0) > 0 else {
                throw SyncWriteRefusal.notUnderstood("page shape")
            }
            if contentKind == "template", record.string("template").flatMap(PageTemplate.init(rawValue:)) == nil {
                throw SyncWriteRefusal.notUnderstood("page template")
            }
            guard let transform = record.string("transform"),
                  (try? decoder.decode(PageTransform.self, from: Data(transform.utf8))) != nil else {
                throw SyncWriteRefusal.notUnderstood("page transform")
            }
            if let assetName {
                try ensureAssetRow(AssetID(sha256: assetName), record: record,
                                   fallbackKind: contentKind == "pdfPage" ? .pdf : .jpeg, bytes: nil)
            }
            let before = try db.query("SELECT content_kind, asset_id, pdf_page_index, template FROM pages WHERE id = ?", [.text(id)]) {
                [$0.text(0), $0.optionalText(1) ?? "", $0.isNull(2) ? "" : String($0.int64(2)), $0.optionalText(3) ?? ""]
            }.first
            let timestamp = now()
            try db.run("""
                INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id, pdf_page_index,
                                   template, transform_json, revision, created_at, modified_at, deleted_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET item_id = excluded.item_id, sort_key = excluded.sort_key,
                    source_width = excluded.source_width, source_height = excluded.source_height,
                    content_kind = excluded.content_kind, asset_id = excluded.asset_id,
                    pdf_page_index = excluded.pdf_page_index, template = excluded.template,
                    transform_json = excluded.transform_json, revision = pages.revision + 1,
                    modified_at = excluded.modified_at, deleted_at = excluded.deleted_at
                """, [.text(id), .text(itemID), v("sortKey"), v("width"), v("height"), .text(contentKind), v("assetID"),
                      v("pdfIndex"), v("template"), .text(transform), v("createdAt"), .date(timestamp), v("deletedAt")])
            let after = [contentKind, assetName ?? "", record.int("pdfIndex").map(String.init) ?? "", record.string("template") ?? ""]
            if let before, before != after {
                // Different paper: what was read off the old one must stop
                // answering searches, exactly as after a rescan here.
                try db.run("DELETE FROM search_index WHERE page_id = ? AND field IN ('ocr', ?)",
                           [.text(id), .text(Self.embeddedTextField)])
            }
            return SyncWriteEffect(itemID: ItemID(rawValue: itemID))

        case .object:
            try Self.require(record, "pageID", "zKey", "kind", "payload", "modifiedAt")
            guard let pageID = record.string("pageID"), try rowExists("pages", pageID) else { throw SyncWriteRefusal.missingParent }
            guard let kind = record.string("kind"), let payloadText = record.string("payload"),
                  let payload = try? decoder.decode(PageObject.Payload.self, from: Data(payloadText.utf8)),
                  payload.kind == kind else {
                throw SyncWriteRefusal.notUnderstood("page object")
            }
            if case .image(let placed) = payload {
                try ensureAssetRow(placed.assetID, record: record, fallbackKind: .jpeg, bytes: nil)
            }
            try db.run("""
                INSERT INTO page_objects (id, page_id, z_key, kind, payload_json, modified_at) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET page_id = excluded.page_id, z_key = excluded.z_key, kind = excluded.kind,
                    payload_json = excluded.payload_json, modified_at = excluded.modified_at
                """, [.text(id), .text(pageID), v("zKey"), .text(kind), .text(payloadText), v("modifiedAt")])
            let item = try db.query("SELECT item_id FROM pages WHERE id = ?", [.text(pageID)]) { ItemID(rawValue: $0.text(0)) }.first
            // A private comment never moved the page's revision when it was
            // written here, and does not when it arrives from elsewhere.
            return SyncWriteEffect(itemID: item, touchedPage: kind == "comment" ? nil : PageID(rawValue: pageID))

        case .signature:
            try Self.require(record, "name", "strokes", "createdAt")
            guard let strokes = record.string("strokes"),
                  (try? decoder.decode([InkStroke].self, from: Data(strokes.utf8))) != nil else {
                throw SyncWriteRefusal.notUnderstood("signature")
            }
            try db.run("""
                INSERT INTO signatures (id, name, strokes_json, created_at) VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET name = excluded.name, strokes_json = excluded.strokes_json,
                    created_at = excluded.created_at
                """, [.text(id), v("name"), .text(strokes), v("createdAt")])
            return SyncWriteEffect()
        }
    }

    /// What `bumpRevision` does for a local edit, for marks that arrived from
    /// another device: the thumbnail and the typed-text index must follow,
    /// and a finished recognition of the paper underneath stays current. The
    /// item's own modification date is left alone — it has its own record.
    func syncTouchPage(_ pageID: PageID) throws {
        guard let page = try db.query("SELECT item_id, revision FROM pages WHERE id = ?", [.text(pageID.rawValue)], map: {
            (ItemID(rawValue: $0.text(0)), $0.int(1))
        }).first else { return }
        try db.run("UPDATE pages SET revision = revision + 1, modified_at = ? WHERE id = ?", [.date(now()), .text(pageID.rawValue)])
        if let live = try self.page(pageID) { try reindexTypedText(on: live) }
        if var recognition = try recognition(for: pageID), recognition.status == .completed,
           recognition.sourceRevision == page.1 {
            recognition.sourceRevision += 1
            try upsertRecognitionRow(recognition)
        }
    }
}
