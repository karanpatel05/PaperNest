import CoreGraphics
import Foundation
import PaperNestCore

/// The authority for library metadata: one SQLite database (WAL,
/// `synchronous=FULL`) plus the content-addressed `AssetFileStore`.
///
/// Every mutating method commits one transaction before returning, so a value
/// returned from it has been durably stored. Callers must not show an edit as
/// saved until the call returns.
public actor LibraryStore {
    public nonisolated let directoryURL: URL
    public nonisolated let assets: AssetFileStore

    private let db: SQLiteDatabase
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }()
    private let decoder = JSONDecoder()

    public static let databaseFilename = "Library.sqlite"

    public init(directory: URL, now: @escaping @Sendable () -> Date = { Date() }) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directoryURL = directory
        assets = try AssetFileStore(rootURL: directory.appendingPathComponent("Assets", isDirectory: true))
        self.now = now
        db = try SQLiteDatabase(path: directory.appendingPathComponent(Self.databaseFilename).path)
        try db.execute("PRAGMA journal_mode = WAL")
        try db.execute("PRAGMA synchronous = FULL")
        try db.execute("PRAGMA foreign_keys = ON")
        try Self.migrate(db)
    }

    static func migrate(_ db: SQLiteDatabase) throws {
        let current = try db.userVersion
        guard current <= Schema.latestVersion else {
            throw StoreError.newerSchema(found: current, supported: Schema.latestVersion)
        }
        for migration in Schema.migrations where migration.version > current {
            try db.transaction {
                try db.execute(migration.sql)
                try db.setUserVersion(migration.version)
            }
        }
    }

    public func schemaVersion() throws -> Int { try db.userVersion }

    /// SQLite's own consistency check plus a check that every referenced
    /// local asset file exists.
    public func integrityCheck() throws -> [String] {
        var problems = try db.query("PRAGMA quick_check") { $0.text(0) }.filter { $0 != "ok" }
        let referenced = try db.query("""
            SELECT DISTINCT a.id, a.kind FROM assets a
            JOIN pages p ON p.asset_id = a.id
            WHERE a.availability = 'local'
            """) { (AssetID(sha256: $0.text(0)), AssetKind(rawValue: $0.text(1)) ?? .pdf) }
        for (id, kind) in referenced where !FileManager.default.fileExists(atPath: assets.url(for: id, kind: kind).path) {
            problems.append("missing asset \(id.sha256)")
        }
        return problems
    }

    // MARK: - Items

    public struct NewPage: Sendable {
        public var sourceSize: CGSize
        public var content: PageContent
        public var transform: PageTransform

        public init(sourceSize: CGSize, content: PageContent, transform: PageTransform = .identity) {
            self.sourceSize = sourceSize
            self.content = content
            self.transform = transform
        }
    }

    /// Creates an item with its pages in one transaction. Every asset a page
    /// references must already be durably stored via `assets.store`.
    public func createItem(
        kind: ItemKind,
        name: String,
        folderID: FolderID? = nil,
        pages newPages: [NewPage],
        assets staged: [AssetFileStore.StagedAsset]
    ) throws -> LibraryItem {
        let timestamp = now()
        return try db.transaction {
            let siblings = try namesInFolder(folderID)
            let item = LibraryItem(
                kind: kind,
                name: NameDeduplicator.uniqueName(name, existing: siblings),
                folderID: folderID,
                createdAt: timestamp,
                modifiedAt: timestamp
            )
            try db.run("""
                INSERT INTO items (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version)
                VALUES (?, ?, ?, ?, ?, ?, ?, NULL, ?)
                """, [
                    .text(item.id.rawValue), .text(item.kind.rawValue), .text(item.name),
                    .optionalText(item.folderID?.rawValue), .bool(item.isFavorite),
                    .date(item.createdAt), .date(item.modifiedAt), .int(Int64(item.schemaVersion)),
                ])
            try insertAssetRows(staged, at: timestamp)
            let keys = SortKey.evenlySpaced(count: newPages.count)
            for (newPage, key) in zip(newPages, keys) {
                try insertPage(Page(itemID: item.id, sortKey: key, sourceSize: newPage.sourceSize, content: newPage.content,
                                    transform: newPage.transform, createdAt: timestamp, modifiedAt: timestamp))
            }
            try reindexTitle(item)
            return item
        }
    }

    public func item(_ id: ItemID) throws -> LibraryItem? {
        try db.query("SELECT \(Self.itemColumns) FROM items WHERE id = ?", [.text(id.rawValue)], map: Self.decodeItem).first
    }

    public enum Scope: Hashable, Sendable {
        case all
        case favorites
        case recentlyDeleted
        case folder(FolderID?)
    }

    public struct ItemSummary: Identifiable, Hashable, Sendable {
        public var item: LibraryItem
        public var pageCount: Int
        public var coverPage: Page?
        public var id: ItemID { item.id }
    }

    public func items(in scope: Scope) throws -> [ItemSummary] {
        let filter: String
        var values: [SQLValue] = []
        switch scope {
        case .all: filter = "deleted_at IS NULL"
        case .favorites: filter = "deleted_at IS NULL AND is_favorite = 1"
        case .recentlyDeleted: filter = "deleted_at IS NOT NULL"
        case .folder(nil): filter = "deleted_at IS NULL AND folder_id IS NULL"
        case .folder(let id?):
            filter = "deleted_at IS NULL AND folder_id = ?"
            values = [.text(id.rawValue)]
        }
        let order = scope == .recentlyDeleted ? "deleted_at DESC" : "modified_at DESC"
        let items = try db.query("SELECT \(Self.itemColumns) FROM items WHERE \(filter) ORDER BY \(order), id", values, map: Self.decodeItem)
        return try items.map { item in
            let count = try db.query("SELECT count(*) FROM pages WHERE item_id = ? AND deleted_at IS NULL",
                                     [.text(item.id.rawValue)]) { $0.int(0) }.first ?? 0
            let cover = try db.query("SELECT \(Self.pageColumns) FROM pages WHERE item_id = ? AND deleted_at IS NULL ORDER BY sort_key, id LIMIT 1",
                                     [.text(item.id.rawValue)], map: decodePage).first
            return ItemSummary(item: item, pageCount: count, coverPage: cover)
        }
    }

    @discardableResult
    public func rename(_ id: ItemID, to proposed: String) throws -> LibraryItem {
        try db.transaction {
            guard var item = try item(id) else { throw StoreError.itemNotFound }
            let siblings = try namesInFolder(item.folderID, excluding: id)
            item.name = NameDeduplicator.uniqueName(proposed, existing: siblings)
            item.modifiedAt = now()
            try db.run("UPDATE items SET name = ?, modified_at = ? WHERE id = ?",
                       [.text(item.name), .date(item.modifiedAt), .text(id.rawValue)])
            try reindexTitle(item)
            return item
        }
    }

    public func setFavorite(_ id: ItemID, _ isFavorite: Bool) throws {
        let changed = try db.run("UPDATE items SET is_favorite = ? WHERE id = ?", [.bool(isFavorite), .text(id.rawValue)])
        guard changed == 1 else { throw StoreError.itemNotFound }
    }

    /// Soft delete: the item stays restorable in Recently Deleted.
    public func moveToRecentlyDeleted(_ ids: [ItemID]) throws {
        let timestamp = now()
        try db.transaction {
            for id in ids {
                try db.run("UPDATE items SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL", [.date(timestamp), .text(id.rawValue)])
            }
        }
    }

    public func restore(_ ids: [ItemID]) throws {
        try db.transaction {
            for id in ids {
                guard var item = try item(id), item.isDeleted else { continue }
                // The folder may have gained an item with the same name meanwhile.
                item.name = NameDeduplicator.uniqueName(item.name, existing: try namesInFolder(item.folderID, excluding: id))
                try db.run("UPDATE items SET deleted_at = NULL, name = ? WHERE id = ?", [.text(item.name), .text(id.rawValue)])
                try reindexTitle(item)
            }
        }
    }

    /// Permanently removes items that are already in Recently Deleted, and
    /// any originals no other page still uses. Returns the count removed.
    @discardableResult
    public func deletePermanently(_ ids: [ItemID]) throws -> Int {
        let (removed, orphaned) = try db.transaction { () -> (Int, [(AssetID, AssetKind)]) in
            var removed = 0
            for id in ids {
                try db.run("DELETE FROM search_index WHERE item_id = ?", [.text(id.rawValue)])
                removed += try db.run("DELETE FROM items WHERE id = ? AND deleted_at IS NOT NULL", [.text(id.rawValue)])
            }
            return (removed, try deleteUnreferencedAssetRows())
        }
        // Files go only after the rows are gone; a crash here leaves orphan
        // files that the launch sweep removes.
        for (id, kind) in orphaned {
            try? assets.remove(id, kind: kind)
        }
        return removed
    }

    /// Purges Recently Deleted items older than the retention period.
    @discardableResult
    public func purgeExpiredDeletions() throws -> Int {
        let cutoff = RetentionPolicy.purgeCutoff(now: now())
        let expired = try db.query("SELECT id FROM items WHERE deleted_at IS NOT NULL AND deleted_at < ?", [.date(cutoff)]) {
            ItemID(rawValue: $0.text(0))
        }
        return try deletePermanently(expired)
    }

    public func search(_ text: String) throws -> [ItemID] {
        guard let match = Self.ftsQuery(text) else { return [] }
        return try db.query("""
            SELECT DISTINCT s.item_id FROM search_index s
            JOIN items i ON i.id = s.item_id
            WHERE search_index MATCH ? AND i.deleted_at IS NULL
            ORDER BY i.modified_at DESC
            """, [.text(match)]) { ItemID(rawValue: $0.text(0)) }
    }

    /// Turns user input into a safe FTS5 query. Input is split the way the
    /// `unicode61` tokenizer splits text (anything but letters and digits
    /// separates words, so "l'été" is "l" + "été"), and each word becomes a
    /// quoted prefix term; FTS operators and quotes are never interpreted.
    static func ftsQuery(_ text: String) -> String? {
        let words = text.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
        let terms = words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        return terms.isEmpty ? nil : terms.joined(separator: " ")
    }

    // MARK: - Storage

    public struct StorageUsage: Sendable, Equatable {
        /// Documents and notebooks not in Recently Deleted.
        public var documents: Int
        /// Live pages of those items.
        public var pages: Int
        /// Everything the library occupies on disk: database, originals and
        /// anything still kept for Recently Deleted or undo.
        public var bytes: Int64
    }

    public func storageUsage() throws -> StorageUsage {
        let documents = try db.query("SELECT count(*) FROM items WHERE deleted_at IS NULL") { $0.int(0) }.first ?? 0
        let pages = try db.query("""
            SELECT count(*) FROM pages p JOIN items i ON i.id = p.item_id
            WHERE p.deleted_at IS NULL AND i.deleted_at IS NULL
            """) { $0.int(0) }.first ?? 0
        return StorageUsage(documents: documents, pages: pages, bytes: Self.diskSize(of: directoryURL))
    }

    static func diskSize(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in files {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        return total
    }

    // MARK: - Folders

    public func createFolder(named name: String, parentID: FolderID? = nil) throws -> Folder {
        let timestamp = now()
        return try db.transaction {
            let siblings = try db.query("SELECT name FROM folders WHERE parent_id IS ? AND deleted_at IS NULL",
                                        [.optionalText(parentID?.rawValue)]) { $0.text(0) }
            let folder = Folder(name: NameDeduplicator.uniqueName(name, existing: siblings), parentID: parentID,
                                createdAt: timestamp, modifiedAt: timestamp)
            try db.run("INSERT INTO folders (id, name, parent_id, created_at, modified_at) VALUES (?, ?, ?, ?, ?)", [
                .text(folder.id.rawValue), .text(folder.name), .optionalText(parentID?.rawValue),
                .date(timestamp), .date(timestamp),
            ])
            return folder
        }
    }

    public func folders() throws -> [Folder] {
        try db.query("SELECT id, name, parent_id, created_at, modified_at, deleted_at FROM folders WHERE deleted_at IS NULL ORDER BY name COLLATE NOCASE, id") {
            Folder(id: FolderID(rawValue: $0.text(0)), name: $0.text(1), parentID: $0.optionalText(2).map(FolderID.init(rawValue:)),
                   createdAt: $0.date(3), modifiedAt: $0.date(4), deletedAt: $0.optionalDate(5))
        }
    }

    public func move(_ ids: [ItemID], to folderID: FolderID?) throws {
        let timestamp = now()
        try db.transaction {
            for id in ids {
                guard var item = try item(id) else { throw StoreError.itemNotFound }
                item.name = NameDeduplicator.uniqueName(item.name, existing: try namesInFolder(folderID, excluding: id))
                try db.run("UPDATE items SET folder_id = ?, name = ?, modified_at = ? WHERE id = ?",
                           [.optionalText(folderID?.rawValue), .text(item.name), .date(timestamp), .text(id.rawValue)])
            }
        }
    }

    @discardableResult
    public func renameFolder(_ id: FolderID, to proposed: String) throws -> Folder {
        try db.transaction {
            guard var folder = try folders().first(where: { $0.id == id }) else { throw StoreError.folderNotFound }
            let siblings = try db.query("SELECT name FROM folders WHERE parent_id IS ? AND deleted_at IS NULL AND id IS NOT ?",
                                        [.optionalText(folder.parentID?.rawValue), .text(id.rawValue)]) { $0.text(0) }
            folder.name = NameDeduplicator.uniqueName(proposed, existing: siblings)
            folder.modifiedAt = now()
            try db.run("UPDATE folders SET name = ?, modified_at = ? WHERE id = ?",
                       [.text(folder.name), .date(folder.modifiedAt), .text(id.rawValue)])
            return folder
        }
    }

    /// Removes a folder without deleting anything in it: its documents
    /// (including any in Recently Deleted) and subfolders move up to its
    /// parent, renamed if a name is taken there. The row is kept, marked
    /// deleted, as a tombstone for sync.
    public func deleteFolder(_ id: FolderID) throws {
        let timestamp = now()
        try db.transaction {
            guard let folder = try folders().first(where: { $0.id == id }) else { throw StoreError.folderNotFound }
            let contained = try db.query("SELECT id FROM items WHERE folder_id = ?", [.text(id.rawValue)]) { ItemID(rawValue: $0.text(0)) }
            try move(contained, to: folder.parentID)
            let destinationNames = try db.query("SELECT name FROM folders WHERE parent_id IS ? AND deleted_at IS NULL AND id IS NOT ?",
                                                [.optionalText(folder.parentID?.rawValue), .text(id.rawValue)]) { $0.text(0) }
            var taken = destinationNames
            for child in try folders().filter({ $0.parentID == id }) {
                let name = NameDeduplicator.uniqueName(child.name, existing: taken)
                taken.append(name)
                try db.run("UPDATE folders SET parent_id = ?, name = ?, modified_at = ? WHERE id = ?",
                           [.optionalText(folder.parentID?.rawValue), .text(name), .date(timestamp), .text(child.id.rawValue)])
            }
            try db.run("UPDATE folders SET deleted_at = ?, modified_at = ? WHERE id = ?", [.date(timestamp), .date(timestamp), .text(id.rawValue)])
        }
    }

    /// How many items each sidebar entry shows. Folder counts are direct
    /// members only and exclude Recently Deleted.
    public struct ScopeCounts: Sendable, Equatable {
        public var all = 0
        public var favorites = 0
        public var recentlyDeleted = 0
        public var folders: [FolderID: Int] = [:]

        public init() {}
    }

    public func scopeCounts() throws -> ScopeCounts {
        var counts = ScopeCounts()
        let row = try db.query("""
            SELECT
                count(*) FILTER (WHERE deleted_at IS NULL),
                count(*) FILTER (WHERE deleted_at IS NULL AND is_favorite = 1),
                count(*) FILTER (WHERE deleted_at IS NOT NULL)
            FROM items
            """) { ($0.int(0), $0.int(1), $0.int(2)) }.first
        (counts.all, counts.favorites, counts.recentlyDeleted) = row ?? (0, 0, 0)
        for (id, count) in try db.query("SELECT folder_id, count(*) FROM items WHERE deleted_at IS NULL AND folder_id IS NOT NULL GROUP BY folder_id",
                                        map: { (FolderID(rawValue: $0.text(0)), $0.int(1)) }) {
            counts.folders[id] = count
        }
        return counts
    }

    // MARK: - Pages

    public func pages(of itemID: ItemID) throws -> [Page] {
        try db.query("SELECT \(Self.pageColumns) FROM pages WHERE item_id = ? AND deleted_at IS NULL ORDER BY sort_key, id",
                     [.text(itemID.rawValue)], map: decodePage)
    }

    /// A live (not deleted) page.
    public func page(_ id: PageID) throws -> Page? {
        try db.query("SELECT \(Self.pageColumns) FROM pages WHERE id = ? AND deleted_at IS NULL", [.text(id.rawValue)], map: decodePage).first
    }

    /// Inserts pages after `afterPageID`, or at the end when nil.
    @discardableResult
    public func insertPages(
        _ newPages: [NewPage],
        into itemID: ItemID,
        after afterPageID: PageID?,
        assets staged: [AssetFileStore.StagedAsset]
    ) throws -> [Page] {
        let timestamp = now()
        return try db.transaction {
            guard try item(itemID) != nil else { throw StoreError.itemNotFound }
            try insertAssetRows(staged, at: timestamp)
            var ordered = try pages(of: itemID)
            if try needsRebalance(ordered) { ordered = try rebalance(itemID) }
            let insertIndex: Int
            if let afterPageID {
                guard let idx = ordered.firstIndex(where: { $0.id == afterPageID }) else { throw StoreError.pageNotFound }
                insertIndex = idx + 1
            } else {
                insertIndex = ordered.count
            }
            var lower = insertIndex > 0 ? ordered[insertIndex - 1].sortKey : nil
            let upper = insertIndex < ordered.count ? ordered[insertIndex].sortKey : nil
            var inserted: [Page] = []
            for newPage in newPages {
                let key = try SortKey.between(lower, upper)
                let page = Page(itemID: itemID, sortKey: key, sourceSize: newPage.sourceSize, content: newPage.content,
                                transform: newPage.transform, createdAt: timestamp, modifiedAt: timestamp)
                try insertPage(page)
                inserted.append(page)
                lower = key
            }
            try touchItem(itemID, at: timestamp)
            return inserted
        }
    }

    /// Records the previous transform in history, then applies `transform`.
    @discardableResult
    public func updateTransform(_ pageID: PageID, to transform: PageTransform) throws -> Page {
        let timestamp = now()
        return try db.transaction {
            guard var page = try page(pageID) else { throw StoreError.pageNotFound }
            guard page.transform != transform else { return page }
            try db.run("INSERT OR REPLACE INTO page_transform_history (page_id, revision, transform_json, recorded_at) VALUES (?, ?, ?, ?)",
                       [.text(pageID.rawValue), .int(Int64(page.revision)), .text(try json(page.transform)), .date(timestamp)])
            page.transform = transform
            page.revision += 1
            page.modifiedAt = timestamp
            try db.run("UPDATE pages SET transform_json = ?, revision = ?, modified_at = ? WHERE id = ?",
                       [.text(try json(transform)), .int(Int64(page.revision)), .date(timestamp), .text(pageID.rawValue)])
            try touchItem(page.itemID, at: timestamp)
            return page
        }
    }

    public func transformHistory(_ pageID: PageID) throws -> [PageTransform] {
        try db.query("SELECT transform_json FROM page_transform_history WHERE page_id = ? ORDER BY revision", [.text(pageID.rawValue)]) {
            try decoder.decode(PageTransform.self, from: Data($0.text(0).utf8))
        }
    }

    /// Moves a page so it ends up at `index` in its item's page order.
    /// Only the moved page's key changes.
    @discardableResult
    public func movePage(_ pageID: PageID, toIndex index: Int) throws -> Page {
        let timestamp = now()
        return try db.transaction {
            guard var page = try page(pageID) else { throw StoreError.pageNotFound }
            var ordered = try pages(of: page.itemID)
            if try needsRebalance(ordered) {
                ordered = try rebalance(page.itemID)
                page = ordered.first { $0.id == pageID }!
            }
            ordered.removeAll { $0.id == pageID }
            guard (0...ordered.count).contains(index) else { throw StoreError.invalidOrder }
            let lower = index > 0 ? ordered[index - 1].sortKey : nil
            let upper = index < ordered.count ? ordered[index].sortKey : nil
            page.sortKey = try SortKey.between(lower, upper)
            page.revision += 1
            page.modifiedAt = timestamp
            try db.run("UPDATE pages SET sort_key = ?, revision = ?, modified_at = ? WHERE id = ?",
                       [.text(page.sortKey), .int(Int64(page.revision)), .date(timestamp), .text(pageID.rawValue)])
            try touchItem(page.itemID, at: timestamp)
            return page
        }
    }

    /// A deleted page, as needed to undo the deletion.
    public struct DeletedPage: Sendable, Hashable {
        public var page: Page

        public init(page: Page) {
            self.page = page
        }
    }

    /// Marks pages deleted. They disappear from every query but stay in the
    /// database, with their objects, OCR and originals, until
    /// `purgeDeletedPages` runs at the next launch, so undo within a session
    /// can always restore them exactly.
    @discardableResult
    public func deletePages(_ ids: [PageID]) throws -> [DeletedPage] {
        let timestamp = now()
        return try db.transaction {
            var deleted: [DeletedPage] = []
            for id in ids {
                guard let page = try page(id) else { continue }
                try db.run("UPDATE pages SET deleted_at = ? WHERE id = ?", [.date(timestamp), .text(id.rawValue)])
                try touchItem(page.itemID, at: timestamp)
                deleted.append(DeletedPage(page: page))
            }
            return deleted
        }
    }

    /// Undoes `deletePages`. Fails with `pageNotFound` once the pages have
    /// been purged.
    public func restorePages(_ deleted: [DeletedPage]) throws {
        let timestamp = now()
        try db.transaction {
            for entry in deleted {
                let restored = try db.run("UPDATE pages SET deleted_at = NULL WHERE id = ? AND deleted_at IS NOT NULL",
                                          [.text(entry.page.id.rawValue)])
                guard restored == 1 else { throw StoreError.pageNotFound }
                try touchItem(entry.page.itemID, at: timestamp)
            }
        }
    }

    /// Launch housekeeping: permanently removes pages deleted in a previous
    /// session (no undo stack survives a relaunch). Run before
    /// `sweepOrphanAssets` so their originals can be reclaimed.
    @discardableResult
    public func purgeDeletedPages() throws -> Int {
        try db.transaction {
            try db.run("DELETE FROM search_index WHERE page_id IN (SELECT id FROM pages WHERE deleted_at IS NOT NULL)")
            return try db.run("DELETE FROM pages WHERE deleted_at IS NOT NULL")
        }
    }

    // MARK: - Replacing a page's content (rescan)

    /// What a page shows: its original and how it is processed. Swapping
    /// snapshots replaces a page's content without changing its identity,
    /// position, objects or anything that refers to it.
    public struct PageContentSnapshot: Sendable, Hashable {
        public var sourceSize: CGSize
        public var content: PageContent
        public var transform: PageTransform

        public init(sourceSize: CGSize, content: PageContent, transform: PageTransform) {
            self.sourceSize = sourceSize
            self.content = content
            self.transform = transform
        }

        public init(page: Page) {
            self.init(sourceSize: page.sourceSize, content: page.content, transform: page.transform)
        }
    }

    /// Replaces a live page's content in place (same ID and position) and
    /// returns what it showed before. The previous content, and the
    /// original it uses, is kept until `purgeReplacedPageContent` runs at the
    /// next launch, so undo can always restore it. OCR for the page becomes
    /// stale through the revision bump.
    @discardableResult
    public func replacePageContent(
        _ pageID: PageID,
        with snapshot: PageContentSnapshot,
        assets staged: [AssetFileStore.StagedAsset]
    ) throws -> (previous: PageContentSnapshot, page: Page) {
        let timestamp = now()
        return try db.transaction {
            guard var page = try page(pageID) else { throw StoreError.pageNotFound }
            try insertAssetRows(staged, at: timestamp)
            if let assetID = snapshot.content.assetID {
                let present = try db.query("SELECT count(*) FROM assets WHERE id = ?", [.text(assetID.sha256)]) { $0.int(0) }.first ?? 0
                guard present == 1 else { throw StoreError.assetMissing(assetID.sha256) }
            }
            let previous = PageContentSnapshot(page: page)
            let old = Self.contentColumns(previous.content)
            try db.run("""
                INSERT OR REPLACE INTO page_content_history
                    (page_id, revision, source_width, source_height, content_kind, asset_id, pdf_page_index, template, transform_json, replaced_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, [
                    .text(pageID.rawValue), .int(Int64(page.revision)), .double(previous.sourceSize.width), .double(previous.sourceSize.height),
                    .text(old.kind), .optionalText(old.assetID), old.pdfIndex, .optionalText(old.template),
                    .text(try json(previous.transform)), .date(timestamp),
                ])
            let new = Self.contentColumns(snapshot.content)
            page.sourceSize = snapshot.sourceSize
            page.content = snapshot.content
            page.transform = snapshot.transform
            page.revision += 1
            page.modifiedAt = timestamp
            try db.run("""
                UPDATE pages SET source_width = ?, source_height = ?, content_kind = ?, asset_id = ?, pdf_page_index = ?,
                    template = ?, transform_json = ?, revision = ?, modified_at = ?
                WHERE id = ?
                """, [
                    .double(page.sourceSize.width), .double(page.sourceSize.height), .text(new.kind), .optionalText(new.assetID),
                    new.pdfIndex, .optionalText(new.template), .text(try json(page.transform)), .int(Int64(page.revision)),
                    .date(timestamp), .text(pageID.rawValue),
                ])
            try touchItem(page.itemID, at: timestamp)
            return (previous, page)
        }
    }

    /// One rescan: the page that kept its place, what it showed before and
    /// after, and the further pages the new capture added right after it.
    public struct PageReplacement: Sendable, Hashable {
        public var pageID: PageID
        public var previous: PageContentSnapshot
        public var replacement: PageContentSnapshot
        public var inserted: [Page]
    }

    /// Rescan: replaces a page's content and inserts `extras` right after
    /// it, in one transaction. If anything fails, nothing changes.
    public func replacePage(
        _ pageID: PageID,
        with snapshot: PageContentSnapshot,
        inserting extras: [NewPage],
        assets staged: [AssetFileStore.StagedAsset]
    ) throws -> PageReplacement {
        try db.transaction {
            let (previous, page) = try replacePageContent(pageID, with: snapshot, assets: staged)
            let inserted = extras.isEmpty ? [] : try insertPages(extras, into: page.itemID, after: pageID, assets: [])
            return PageReplacement(pageID: pageID, previous: previous, replacement: snapshot, inserted: inserted)
        }
    }

    /// Undoes `replacePage` in one transaction: the added pages go (soft
    /// delete, as for any page) and the page shows its previous content.
    public func revertPageReplacement(_ change: PageReplacement) throws {
        try db.transaction {
            if !change.inserted.isEmpty { try deletePages(change.inserted.map(\.id)) }
            try replacePageContent(change.pageID, with: change.previous, assets: [])
        }
    }

    /// Redoes a reverted `replacePage` in one transaction.
    public func reapplyPageReplacement(_ change: PageReplacement) throws {
        try db.transaction {
            if !change.inserted.isEmpty { try restorePages(change.inserted.map(DeletedPage.init(page:))) }
            try replacePageContent(change.pageID, with: change.replacement, assets: [])
        }
    }

    /// Launch housekeeping: forgets content replaced in a previous session
    /// (no undo stack survives a relaunch). Run before `sweepOrphanAssets`.
    @discardableResult
    public func purgeReplacedPageContent() throws -> Int {
        try db.transaction { try db.run("DELETE FROM page_content_history") }
    }

    // MARK: - Page objects and recognition

    public func objects(on pageID: PageID) throws -> [PageObject] {
        try db.query("SELECT id, page_id, z_key, payload_json, modified_at FROM page_objects WHERE page_id = ? ORDER BY z_key, id",
                     [.text(pageID.rawValue)]) {
            PageObject(id: PageObjectID(rawValue: $0.text(0)), pageID: PageID(rawValue: $0.text(1)), zKey: $0.text(2),
                       payload: try decoder.decode(PageObject.Payload.self, from: Data($0.text(3).utf8)), modifiedAt: $0.date(4))
        }
    }

    public func saveObject(_ object: PageObject) throws {
        try db.transaction {
            guard let page = try page(object.pageID) else { throw StoreError.pageNotFound }
            try upsertObjectRow(object)
            try bumpRevision(page)
        }
    }

    /// One edit of a page's objects (strokes drawn, erased or moved by one
    /// gesture): saves and deletes in a single transaction with a single
    /// revision bump, and returns the updated page. Objects must belong to
    /// `pageID`; nothing changes if any don't.
    @discardableResult
    public func applyObjectChanges(on pageID: PageID, saving: [PageObject], deleting: [PageObjectID]) throws -> Page {
        try db.transaction {
            guard let page = try page(pageID) else { throw StoreError.pageNotFound }
            guard saving.allSatisfy({ $0.pageID == pageID }) else { throw StoreError.pageNotFound }
            for object in saving { try upsertObjectRow(object) }
            for id in deleting {
                try db.run("DELETE FROM page_objects WHERE id = ? AND page_id = ?", [.text(id.rawValue), .text(pageID.rawValue)])
            }
            if !saving.isEmpty || !deleting.isEmpty { try bumpRevision(page) }
            guard let updated = try self.page(pageID) else { throw StoreError.pageNotFound }
            return updated
        }
    }

    public func deleteObject(_ id: PageObjectID) throws {
        try db.transaction {
            guard let pageIDString = try db.query("SELECT page_id FROM page_objects WHERE id = ?", [.text(id.rawValue)], map: { $0.text(0) }).first,
                  let page = try page(PageID(rawValue: pageIDString)) else { return }
            try db.run("DELETE FROM page_objects WHERE id = ?", [.text(id.rawValue)])
            try bumpRevision(page)
        }
    }

    public func recognition(for pageID: PageID) throws -> PageRecognition? {
        try db.query("SELECT result_json FROM page_recognition WHERE page_id = ?", [.text(pageID.rawValue)]) {
            try decoder.decode(PageRecognition.self, from: Data($0.text(0).utf8))
        }.first
    }

    public func saveRecognition(_ recognition: PageRecognition) throws {
        try db.transaction { try upsertRecognitionRow(recognition) }
    }

    private func upsertObjectRow(_ object: PageObject) throws {
        try db.run("INSERT OR REPLACE INTO page_objects (id, page_id, z_key, kind, payload_json, modified_at) VALUES (?, ?, ?, ?, ?, ?)", [
            .text(object.id.rawValue), .text(object.pageID.rawValue), .text(object.zKey), .text(object.payload.kind),
            .text(try json(object.payload)), .date(object.modifiedAt),
        ])
    }

    private func upsertRecognitionRow(_ r: PageRecognition) throws {
        try db.run("INSERT OR REPLACE INTO page_recognition (page_id, source_revision, engine_version, status, result_json) VALUES (?, ?, ?, ?, ?)", [
            .text(r.pageID.rawValue), .int(Int64(r.sourceRevision)), .text(r.engineVersion), .text(r.status.rawValue), .text(try json(r)),
        ])
    }

    // MARK: - Assets

    public func assetRecord(_ id: AssetID) throws -> AssetRecord? {
        try db.query("SELECT id, kind, byte_count, original_filename, availability, created_at FROM assets WHERE id = ?", [.text(id.sha256)]) {
            AssetRecord(id: AssetID(sha256: $0.text(0)), kind: AssetKind(rawValue: $0.text(1)) ?? .pdf, byteCount: $0.int64(2),
                        originalFilename: $0.optionalText(3), availability: AssetAvailability(rawValue: $0.text(4)) ?? .remoteOnly,
                        createdAt: $0.date(5))
        }.first
    }

    /// Reads an original's bytes, refusing ones that are not on this device.
    public func assetData(_ id: AssetID) throws -> (Data, AssetKind) {
        guard let record = try assetRecord(id) else { throw StoreError.assetMissing(id.sha256) }
        guard record.availability == .local else { throw StoreError.assetMissing(id.sha256) }
        return (try assets.read(id, kind: record.kind), record.kind)
    }

    /// Launch-time cleanup after interrupted work: removes asset rows no page
    /// uses, files no row describes, and stale staging files. Files younger
    /// than `gracePeriod` are kept in case an import is still in flight.
    @discardableResult
    public func sweepOrphanAssets(gracePeriod: TimeInterval = 3600) throws -> Int {
        let cutoff = now().addingTimeInterval(-gracePeriod)
        assets.clearStaging(olderThan: cutoff)
        let orphanedRows = try db.transaction { try deleteUnreferencedAssetRows() }
        var removed = 0
        for (id, kind) in orphanedRows {
            try? assets.remove(id, kind: kind)
            removed += 1
        }
        let known = Set(try db.query("SELECT id FROM assets") { AssetID(sha256: $0.text(0)) })
        for file in try assets.allFiles() where !known.contains(file.id) && file.modified < cutoff {
            try? FileManager.default.removeItem(at: file.url)
            removed += 1
        }
        return removed
    }

    // MARK: - Private helpers

    private static let itemColumns = "id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version"
    private static let pageColumns = "id, item_id, sort_key, source_width, source_height, content_kind, asset_id, pdf_page_index, template, transform_json, revision, created_at, modified_at"

    private static func decodeItem(_ s: Statement) -> LibraryItem {
        LibraryItem(id: ItemID(rawValue: s.text(0)), kind: ItemKind(rawValue: s.text(1)) ?? .document, name: s.text(2),
                    folderID: s.optionalText(3).map(FolderID.init(rawValue:)), isFavorite: s.bool(4), createdAt: s.date(5),
                    modifiedAt: s.date(6), deletedAt: s.optionalDate(7), schemaVersion: s.int(8))
    }

    private func decodePage(_ s: Statement) throws -> Page {
        let content: PageContent
        switch s.text(5) {
        case "image": content = .image(AssetID(sha256: s.text(6)))
        case "pdfPage": content = .pdfPage(AssetID(sha256: s.text(6)), index: s.int(7))
        default: content = .template(PageTemplate(rawValue: s.text(8)) ?? .blank)
        }
        return Page(id: PageID(rawValue: s.text(0)), itemID: ItemID(rawValue: s.text(1)), sortKey: s.text(2),
                    sourceSize: CGSize(width: s.double(3), height: s.double(4)), content: content,
                    transform: try decoder.decode(PageTransform.self, from: Data(s.text(9).utf8)), revision: s.int(10),
                    createdAt: s.date(11), modifiedAt: s.date(12))
    }

    private static func contentColumns(_ content: PageContent) -> (kind: String, assetID: String?, pdfIndex: SQLValue, template: String?) {
        switch content {
        case .image(let id): ("image", id.sha256, .null, nil)
        case .pdfPage(let id, let index): ("pdfPage", id.sha256, .int(Int64(index)), nil)
        case .template(let t): ("template", nil, .null, t.rawValue)
        }
    }

    private func insertPage(_ page: Page) throws {
        let (kind, assetID, pdfIndex, template) = Self.contentColumns(page.content)
        try db.run("""
            INSERT INTO pages (id, item_id, sort_key, source_width, source_height, content_kind, asset_id, pdf_page_index, template, transform_json, revision, created_at, modified_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, [
                .text(page.id.rawValue), .text(page.itemID.rawValue), .text(page.sortKey),
                .double(page.sourceSize.width), .double(page.sourceSize.height), .text(kind), .optionalText(assetID),
                pdfIndex, .optionalText(template), .text(try json(page.transform)), .int(Int64(page.revision)),
                .date(page.createdAt), .date(page.modifiedAt),
            ])
    }

    private func insertAssetRows(_ staged: [AssetFileStore.StagedAsset], at timestamp: Date) throws {
        for asset in staged {
            // A row must never describe a file that is not durably present.
            guard FileManager.default.fileExists(atPath: assets.url(for: asset.id, kind: asset.kind).path) else {
                throw StoreError.assetMissing(asset.id.sha256)
            }
            try db.run("""
                INSERT INTO assets (id, kind, byte_count, original_filename, availability, created_at) VALUES (?, ?, ?, ?, 'local', ?)
                ON CONFLICT(id) DO UPDATE SET availability = 'local'
                """, [.text(asset.id.sha256), .text(asset.kind.rawValue), .int(asset.byteCount), .optionalText(asset.originalFilename), .date(timestamp)])
        }
    }

    private func deleteUnreferencedAssetRows() throws -> [(AssetID, AssetKind)] {
        // Placed images inside page objects also reference assets.
        let placed = Set(try db.query("SELECT payload_json FROM page_objects WHERE kind = 'image'") {
            try decoder.decode(PageObject.Payload.self, from: Data($0.text(0).utf8))
        }.compactMap { payload -> AssetID? in
            if case .image(let placed) = payload { return placed.assetID }
            return nil
        })
        let unreferenced = try db.query("""
            SELECT a.id, a.kind FROM assets a
            WHERE NOT EXISTS (SELECT 1 FROM pages p WHERE p.asset_id = a.id)
              AND NOT EXISTS (SELECT 1 FROM page_content_history h WHERE h.asset_id = a.id)
            """) { (AssetID(sha256: $0.text(0)), AssetKind(rawValue: $0.text(1)) ?? .pdf) }
            .filter { !placed.contains($0.0) }
        for (id, _) in unreferenced {
            try db.run("DELETE FROM assets WHERE id = ?", [.text(id.sha256)])
        }
        return unreferenced
    }

    private func namesInFolder(_ folderID: FolderID?, excluding: ItemID? = nil) throws -> [String] {
        try db.query("SELECT name FROM items WHERE folder_id IS ? AND deleted_at IS NULL AND id IS NOT ?",
                     [.optionalText(folderID?.rawValue), .optionalText(excluding?.rawValue)]) { $0.text(0) }
    }

    private func touchItem(_ id: ItemID, at timestamp: Date) throws {
        try db.run("UPDATE items SET modified_at = ? WHERE id = ?", [.date(timestamp), .text(id.rawValue)])
    }

    private func bumpRevision(_ page: Page) throws {
        let timestamp = now()
        try db.run("UPDATE pages SET revision = revision + 1, modified_at = ? WHERE id = ?", [.date(timestamp), .text(page.id.rawValue)])
        try touchItem(page.itemID, at: timestamp)
    }

    private func reindexTitle(_ item: LibraryItem) throws {
        try db.run("DELETE FROM search_index WHERE item_id = ? AND field = 'title'", [.text(item.id.rawValue)])
        try db.run("INSERT INTO search_index (item_id, page_id, field, content) VALUES (?, NULL, 'title', ?)",
                   [.text(item.id.rawValue), .text(item.name)])
    }

    /// Equal or invalid neighbouring keys (possible after merging concurrent
    /// edits) leave no room between them; respacing fixes that.
    private func needsRebalance(_ ordered: [Page]) throws -> Bool {
        zip(ordered, ordered.dropFirst()).contains { !($0.sortKey < $1.sortKey) } || ordered.contains { !SortKey.isValid($0.sortKey) }
    }

    private func rebalance(_ itemID: ItemID) throws -> [Page] {
        var ordered = try pages(of: itemID)
        for (i, key) in SortKey.evenlySpaced(count: ordered.count).enumerated() {
            ordered[i].sortKey = key
            try db.run("UPDATE pages SET sort_key = ? WHERE id = ?", [.text(key), .text(ordered[i].id.rawValue)])
        }
        return ordered
    }

    private func json(_ value: some Encodable) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
