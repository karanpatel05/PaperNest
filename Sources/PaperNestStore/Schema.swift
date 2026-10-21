import Foundation

/// Ordered schema migrations, tracked in `PRAGMA user_version`. Each runs in
/// its own transaction together with its version bump, so an interrupted
/// migration leaves the previous, consistent version in place.
enum Schema {
    struct Migration {
        let version: Int
        let sql: String
    }

    static var latestVersion: Int { migrations.last!.version }

    static let migrations: [Migration] = [
        Migration(version: 1, sql: """
        CREATE TABLE folders (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            parent_id TEXT REFERENCES folders(id),
            created_at REAL NOT NULL,
            modified_at REAL NOT NULL,
            deleted_at REAL
        );

        CREATE TABLE items (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('document', 'notebook')),
            name TEXT NOT NULL,
            folder_id TEXT REFERENCES folders(id),
            is_favorite INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            modified_at REAL NOT NULL,
            deleted_at REAL,
            schema_version INTEGER NOT NULL
        );
        CREATE INDEX items_by_folder ON items(folder_id, deleted_at);

        CREATE TABLE tags (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL UNIQUE COLLATE NOCASE
        );

        CREATE TABLE item_tags (
            item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            tag_id TEXT NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
            PRIMARY KEY (item_id, tag_id)
        );

        -- Immutable originals. `id` is the SHA-256 of the file's bytes.
        CREATE TABLE assets (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('pdf', 'jpeg', 'png')),
            byte_count INTEGER NOT NULL,
            original_filename TEXT,
            availability TEXT NOT NULL CHECK (availability IN ('local', 'remoteOnly')),
            created_at REAL NOT NULL
        );

        CREATE TABLE pages (
            id TEXT PRIMARY KEY NOT NULL,
            item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            sort_key TEXT NOT NULL,
            source_width REAL NOT NULL CHECK (source_width > 0),
            source_height REAL NOT NULL CHECK (source_height > 0),
            content_kind TEXT NOT NULL CHECK (content_kind IN ('image', 'pdfPage', 'template')),
            asset_id TEXT REFERENCES assets(id),
            pdf_page_index INTEGER,
            template TEXT,
            transform_json TEXT NOT NULL,
            revision INTEGER NOT NULL,
            created_at REAL NOT NULL,
            modified_at REAL NOT NULL,
            CHECK ((content_kind = 'template') = (asset_id IS NULL))
        );
        CREATE INDEX pages_by_item ON pages(item_id, sort_key, id);
        CREATE INDEX pages_by_asset ON pages(asset_id);

        -- Previous transforms, newest last, so edits can be reviewed/reverted
        -- without ever rewriting the original.
        CREATE TABLE page_transform_history (
            page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            revision INTEGER NOT NULL,
            transform_json TEXT NOT NULL,
            recorded_at REAL NOT NULL,
            PRIMARY KEY (page_id, revision)
        );

        -- Ink, text boxes and placed images (editor arrives in M3).
        CREATE TABLE page_objects (
            id TEXT PRIMARY KEY NOT NULL,
            page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            z_key TEXT NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('ink', 'text', 'image')),
            payload_json TEXT NOT NULL,
            modified_at REAL NOT NULL
        );
        CREATE INDEX page_objects_by_page ON page_objects(page_id, z_key, id);

        -- OCR results (engine arrives in M4). Stale when source_revision is
        -- older than the page's revision.
        CREATE TABLE page_recognition (
            page_id TEXT PRIMARY KEY NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            source_revision INTEGER NOT NULL,
            engine_version TEXT NOT NULL,
            status TEXT NOT NULL CHECK (status IN ('pending', 'completed', 'failed')),
            result_json TEXT NOT NULL
        );

        -- Derived full-text index; rebuildable from the tables above.
        CREATE VIRTUAL TABLE search_index USING fts5(
            item_id UNINDEXED,
            page_id UNINDEXED,
            field UNINDEXED,
            content,
            tokenize = 'unicode61 remove_diacritics 2'
        );
        """),
        // v2: deleted pages are kept (and keep their originals referenced)
        // until the next launch, so an in-session undo can always restore
        // them. Later this column also feeds sync tombstones.
        Migration(version: 2, sql: """
        ALTER TABLE pages ADD COLUMN deleted_at REAL;
        CREATE INDEX pages_live ON pages(item_id, deleted_at, sort_key, id);
        """),
    ]
}
