import Foundation

/// Ordered schema migrations, tracked in `PRAGMA user_version`. Each runs in
/// its own transaction together with its version bump, so an interrupted
/// migration leaves the previous, consistent version in place.
enum Schema {
    struct Migration {
        let version: Int
        let sql: String
        /// SQLite cannot alter a CHECK constraint, so such a change rebuilds
        /// the table. With foreign keys enforced, `DROP TABLE items` performs
        /// an implicit delete that **cascades into `pages`** and empties the
        /// library — verified, not assumed. These migrations therefore run
        /// with foreign keys disabled and are checked with
        /// `PRAGMA foreign_key_check` before they commit, which is SQLite's
        /// documented procedure for this.
        var rebuildsTables = false
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
        // v3: a rescanned/replaced page's previous content, kept (with its
        // original referenced) until the next launch so undo can restore it.
        Migration(version: 3, sql: """
        CREATE TABLE page_content_history (
            page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            revision INTEGER NOT NULL,
            source_width REAL NOT NULL,
            source_height REAL NOT NULL,
            content_kind TEXT NOT NULL CHECK (content_kind IN ('image', 'pdfPage', 'template')),
            asset_id TEXT REFERENCES assets(id),
            pdf_page_index INTEGER,
            template TEXT,
            transform_json TEXT NOT NULL,
            replaced_at REAL NOT NULL,
            PRIMARY KEY (page_id, revision)
        );
        CREATE INDEX page_content_history_by_asset ON page_content_history(asset_id);
        """),
        Migration(version: 4, sql: """
        ALTER TABLE items ADD COLUMN color_label TEXT
            CHECK (color_label IN ('red', 'orange', 'yellow', 'green', 'blue', 'purple', 'gray'));
        """),
        // F2a: a library item can be a file rather than a sequence of pages.
        // Both CHECK constraints have to be widened, which means rebuilding
        // the two tables; see `Migration.rebuildsTables`.
        Migration(version: 5, sql: """
        CREATE TABLE items_v5 (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('document', 'notebook', 'file')),
            name TEXT NOT NULL,
            folder_id TEXT REFERENCES folders(id),
            is_favorite INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            modified_at REAL NOT NULL,
            deleted_at REAL,
            schema_version INTEGER NOT NULL,
            color_label TEXT CHECK (color_label IN ('red', 'orange', 'yellow', 'green', 'blue', 'purple', 'gray'))
        );
        INSERT INTO items_v5 (id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label)
            SELECT id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label FROM items;
        DROP TABLE items;
        ALTER TABLE items_v5 RENAME TO items;
        CREATE INDEX items_by_folder ON items(folder_id, deleted_at);

        CREATE TABLE assets_v5 (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('pdf', 'jpeg', 'png', 'file')),
            byte_count INTEGER NOT NULL,
            original_filename TEXT,
            availability TEXT NOT NULL CHECK (availability IN ('local', 'remoteOnly')),
            created_at REAL NOT NULL
        );
        INSERT INTO assets_v5 (id, kind, byte_count, original_filename, availability, created_at)
            SELECT id, kind, byte_count, original_filename, availability, created_at FROM assets;
        DROP TABLE assets;
        ALTER TABLE assets_v5 RENAME TO assets;

        -- One row per file item: the bytes it holds, and what they are.
        CREATE TABLE file_items (
            item_id TEXT PRIMARY KEY NOT NULL REFERENCES items(id) ON DELETE CASCADE,
            asset_id TEXT NOT NULL REFERENCES assets(id),
            uti TEXT NOT NULL,
            original_filename TEXT NOT NULL,
            byte_count INTEGER NOT NULL
        );
        CREATE INDEX file_items_by_asset ON file_items(asset_id);
        """, rebuildsTables: true),
        // F2c: photos from the system library are HEIC. Verified against
        // ImageIO before being offered, so this is a format we can actually
        // read, not one we hope to.
        Migration(version: 6, sql: """
        CREATE TABLE assets_v6 (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('pdf', 'jpeg', 'png', 'heic', 'file')),
            byte_count INTEGER NOT NULL,
            original_filename TEXT,
            availability TEXT NOT NULL CHECK (availability IN ('local', 'remoteOnly')),
            created_at REAL NOT NULL
        );
        INSERT INTO assets_v6 (id, kind, byte_count, original_filename, availability, created_at)
            SELECT id, kind, byte_count, original_filename, availability, created_at FROM assets;
        DROP TABLE assets;
        ALTER TABLE assets_v6 RENAME TO assets;
        """, rebuildsTables: true),
        // Page-level comments share page object lifetime and composition.
        Migration(version: 7, sql: """
        CREATE TABLE page_objects_v7 (
            id TEXT PRIMARY KEY NOT NULL,
            page_id TEXT NOT NULL REFERENCES pages(id) ON DELETE CASCADE,
            z_key TEXT NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('ink', 'text', 'image', 'comment')),
            payload_json TEXT NOT NULL,
            modified_at REAL NOT NULL
        );
        INSERT INTO page_objects_v7 SELECT id, page_id, z_key, kind, payload_json, modified_at FROM page_objects;
        DROP TABLE page_objects;
        ALTER TABLE page_objects_v7 RENAME TO page_objects;
        CREATE INDEX page_objects_by_page ON page_objects(page_id, z_key, id);
        """, rebuildsTables: true),
        // WebP, the same way HEIC arrived in v6 and for the same reason: the
        // format was checked against ImageIO before being offered. The answer
        // was narrower this time — it reads WebP and cannot write it — so this
        // widens what may be *stored*, and nothing anywhere produces one.
        Migration(version: 8, sql: """
        CREATE TABLE assets_v8 (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL CHECK (kind IN ('pdf', 'jpeg', 'png', 'heic', 'webp', 'file')),
            byte_count INTEGER NOT NULL,
            original_filename TEXT,
            availability TEXT NOT NULL CHECK (availability IN ('local', 'remoteOnly')),
            created_at REAL NOT NULL
        );
        INSERT INTO assets_v8 (id, kind, byte_count, original_filename, availability, created_at)
            SELECT id, kind, byte_count, original_filename, availability, created_at FROM assets;
        DROP TABLE assets;
        ALTER TABLE assets_v8 RENAME TO assets;
        """, rebuildsTables: true),
        // Row 23: ink a person drew once, kept so it can be placed again.
        // A picture of a signature, not a cryptographic one — the strokes are
        // ordinary ink and nothing here attests to anything.
        Migration(version: 9, sql: """
        CREATE TABLE signatures (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            strokes_json TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX signatures_by_created ON signatures(created_at, id);
        """),
    ]
}
