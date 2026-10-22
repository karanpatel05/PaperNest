# F2 design: general file items

**Status: F2a implemented in stages, 2026-10-22.** The owner’s decisions are recorded in §11. Schema v5, streaming imports of any file type, library operations and details/share/save are committed. Native Quick Look previews are being verified on the current shared tree (see TEST_MATRIX and SESSION_HANDOFF). Grid/list tiles still use type symbols: Quick Look thumbnail generation remains open. F2b–F2d are not complete. The design rationale below describes the pre-F2 baseline where stated.

Context: [FEATURE_EXPANSION.md](FEATURE_EXPANSION.md) (F2), [REFERENCE_FEATURE_INVENTORY.md](REFERENCE_FEATURE_INVENTORY.md) (rows 8–14, 35, 41), [ARCHITECTURE.md](ARCHITECTURE.md).

## 1. What the reference app does, and what PaperNest does today

`docs/design/reference/09-manage-files.png` shows a library holding things PaperNest cannot hold: a `.txt` of 2 KB, PDFs of 4 MB and 24 MB, a 350 MB video with a duration badge, audio tracks, a Photos-backed folder and a system Inbox — each with its real size and a type-appropriate preview. `04-work-with-files-actions.png` adds per-file actions: Show Info, Copy to, Compress, Convert to MP3, Transcribe.

Before F2, PaperNest's library held **only page-based items** (`document`, `notebook`). An import is turned into pages; anything that is not a PDF, JPEG or PNG is rejected. Every row in `items` is assumed to have pages: `ItemSummary` carries `pageCount` and a `coverPage`, the grid cell renders that cover, export renders pages, and composition (merge/extract/split) copies pages.

So F2 is not "import more types". It is: **a library item that is a file, not a sequence of pages**, living beside the page-based ones in the same library, folders, trash, labels and search.

## 2. What a file item must support (the bar for calling F2 done)

1. Import any file type; keep the bytes exactly, with the real size and the original filename.
2. Appear in the library, folders, Favorites and Recently Deleted next to documents.
3. Rename, move to a folder, colour label, duplicate, delete and restore — all the F1 verbs that are not page-specific.
4. A type-appropriate preview (thumbnail) in the grid and list.
5. A details sheet: name, kind, size, where it came from, created/modified, folder.
6. Share and "save a copy" of the exact bytes.
7. Be skipped, not crash, in page-only flows (export as PDF, merge, extract, split, crop, ink).

**Not in F2's first slice:** ZIP/RAR, Photos import, conversion, playback, transcription. Those sit on top of this and are listed in §10.

## 3. The shape: a third item kind, not a second store

Three options were considered.

| Option | Shape | Verdict |
|---|---|---|
| **A. `items.kind = 'file'` + a `file_items` row** | One `items` row as today, plus a 1:1 `file_items` row holding the asset, UTI and original filename | **Recommended** |
| B. A file is a one-page document whose page content is `.file(assetID)` | No new table | **Rejected.** This is the "dummy PDF page" the expansion spec forbids. It would give files a `sourceSize`, a transform, a page revision and a place in composition, all meaningless, and every page-shaped invariant would need a "unless it's really a file" exception |
| C. A separate `file_items` table with its own identity, unioned into the library listing | Clean separation | **Rejected.** Folders, favourites, colour labels, trash, retention, rename-dedup and search are all keyed on `items.id`. Duplicating that machinery is where a second source of truth creeps in, which CLAUDE.md forbids |

Option A keeps `items` as the one identity for everything in the library. `pages` stays exactly what it is: a file item simply has none.

## 4. Schema v5

> **Implemented 2026-10-22 (step 1).** The sketch below was right about *what* to change and wrong about *how*: with foreign keys enforced, `DROP TABLE items`
> cascades into `pages` and empties the library. Proved with sqlite3 (*pages before: 2 → pages after: 0*) before the migration was written. The runner now
> marks such migrations `rebuildsTables`, runs them with foreign keys off, and verifies `PRAGMA foreign_key_check` before committing. See the TEST_MATRIX row.

Two existing `CHECK` constraints block this, and SQLite cannot alter a constraint in place. Both tables need the documented 12-step rebuild (create new table, copy, drop old, rename), which is fine because each migration already runs inside its own transaction with its version bump.

```sql
-- 1. items.kind currently CHECK (kind IN ('document','notebook')).
--    Rebuild to allow 'file'. Columns are otherwise unchanged, including
--    color_label from v4.
CREATE TABLE items_new (
    id TEXT PRIMARY KEY NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('document', 'notebook', 'file')),
    name TEXT NOT NULL,
    folder_id TEXT REFERENCES folders(id),
    is_favorite INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL,
    modified_at REAL NOT NULL,
    deleted_at REAL,
    schema_version INTEGER NOT NULL,
    color_label TEXT CHECK (color_label IN ('red','orange','yellow','green','blue','purple','gray'))
);
INSERT INTO items_new SELECT id, kind, name, folder_id, is_favorite, created_at, modified_at, deleted_at, schema_version, color_label FROM items;
DROP TABLE items;
ALTER TABLE items_new RENAME TO items;
CREATE INDEX items_by_folder ON items(folder_id, deleted_at);

-- 2. assets.kind currently CHECK (kind IN ('pdf','jpeg','png')).
--    Rebuild to allow 'file', the kind used for bytes we do not interpret.
--    (Same pattern; assets has no dependent indexes beyond those recreated.)

-- 3. The file payload: one row per file item.
CREATE TABLE file_items (
    item_id TEXT PRIMARY KEY NOT NULL REFERENCES items(id) ON DELETE CASCADE,
    asset_id TEXT NOT NULL REFERENCES assets(id),
    uti TEXT NOT NULL,                 -- e.g. "public.mpeg-4", from the bytes where possible
    original_filename TEXT NOT NULL,   -- what the user picked, including extension
    byte_count INTEGER NOT NULL        -- denormalized from assets for cheap listing
);
CREATE INDEX file_items_by_asset ON file_items(asset_id);
```

Notes:

- **`pages_by_asset` and asset retention already work.** Permanent deletion sweeps assets no row references; `file_items.asset_id` must be included in that sweep's "still referenced" check, or deleting a document would delete a file's bytes. This is the single most dangerous line in the whole change and needs a test that imports the same bytes as both a page and a file.
- **Dedup is automatic and correct.** `assets.id` is the SHA-256, so importing the same file twice stores one copy and two items.
- **`byte_count` is denormalized** only so the library listing does not join `assets` per row. `assets.byte_count` stays the authority; a test asserts they agree.
- **v5 is now spent on files, and v6 on HEIC.** Sync (M2) must take v7 or later. The plan says sync takes the next unused number, whatever it is by then.

## 5. The asset store and the file-extension problem

`AssetFileStore.url(for:kind:)` builds `<sha256>.<kind.fileExtension>`, so every asset's path carries a type. For bytes we do not interpret, `AssetKind.file` gets the extension `bin`.

That means the stored path loses the real extension, which matters in two places:

- **Preview generation** — `QLThumbnailGenerator` sniffs by extension/UTI. Generate from a temporary hard link or copy named with `original_filename`, or pass the UTI explicitly where the API allows.
- **Share and save a copy** — the user must get `Report.docx`, not `3f9a….bin`. Copy to a temporary file named `original_filename` first, exactly as the export pipeline already does for PDFs.

The alternative — storing the real extension in the path — was rejected: it makes the path depend on mutable metadata, and two items sharing one asset could disagree about it.

## 6. Swift API changes

**Core**
- `ItemKind` gains `case file`.
- `AssetKind` gains `case file` (extension `bin`).
- New `FilePayload { assetID, uti: String, originalFilename: String, byteCount: Int64 }`.

**Store**
- `createFileItem(name:folderID:staged:uti:originalFilename:) throws -> LibraryItem`, one transaction, asset written durably before the row (the existing rule).
- `filePayload(_ itemID:) throws -> FilePayload?`.
- `ItemSummary` gains `file: FilePayload?`. `pageCount` stays 0 for files.
- `storageUsage()` counts file bytes.
- Asset sweeping learns about `file_items`.
- `duplicateItems` handles a file item by copying the row and sharing the asset — a one-line branch in `LibraryComposition.composeItem`; **merge, extract and split must reject file items explicitly** (`StoreError.invalidOrder`) rather than silently producing an empty document.

**Import**
- Today's importer sniffs type and rejects the unknown. It gains a path: "not a supported page type" is no longer a failure but a file import, **only when the caller asked for that**. The existing "unsupported file" error must stay reachable where pages are required (Add Pages, Replace Page).

**UI**
- `ItemCell` renders a file's thumbnail, falling back to a UTI-based SF Symbol, and shows the size instead of the page count.
- Opening a file item shows a native Quick Look preview, with Show Info/Share/Save available from its Info button; page-based items keep `DocumentView`. Recent uses the same viewer.
- The Tools screen's document pickers filter file items out; the ZIP export accepts them.
- Page-only menu entries (Export as PDF, Extract, Split, Crop) are absent for files.

## 7. Previews

The full viewer uses `QLPreviewController` on iOS and an embedded `QLPreviewView` on macOS. Mac previews close the native view on dismantle. Loading and copy errors retain Done and Info. A cancellable background copy restores the original extension; a retained `PreparedFileCopy` owns cleanup and is shared with Info. The library asset is never passed to Quick Look. System-supported formats can be viewed; importing a format does not guarantee the OS has a previewer.

**Thumbnail generation is still planned:** `QLThumbnailGenerator` (iOS 13+/macOS 10.15+, no third-party) covers images, PDFs, video, audio artwork, text and Office files. Cache by `assetID + pixel size`, reusing `ThumbnailCache`'s shape. A failed or unsupported preview falls back to a symbol chosen from the UTI — never a blank tile, never a wrong-looking "document" page.

## 8. What does not change

`pages`, `PageGeometry`, transforms, ink, OCR, composition, the renderer and the exporter are untouched. A file item never enters them. This is deliberate: F2 adds a second kind of thing to the library, it does not generalise the page model.

## 9. Risks

1. ~~**Asset sweeping**~~ — **handled 2026-10-22**: `deleteUnreferencedAssetRows` also checks `file_items`, covered by a test where a document and a file hold the same content-addressed bytes and the document is permanently deleted.
2. **Unbounded sizes.** A 350 MB video is a realistic import. Importing must stream to the asset store rather than `Data(contentsOf:)` the whole file into memory; the current `store(_ data:)` path takes `Data`. This needs a streaming `store(contentsOf: URL)` with hashing as it copies.
3. **Sandbox and security scope** on iOS/macOS for large picked files; the existing bookmark handling in the importer already covers the pattern.
4. **"Everything is a file" creep** — the temptation to re-express documents as files later. Explicitly out of scope.

## 10. Suggested slices

- **F2a — file items exist**: schema v5, streaming import, library/folders/trash/labels/duplicate, details sheet, thumbnails, share/save a copy, page-only flows rejecting files. This is the slice this design is for.
- **F2b — archives**: create a ZIP from a selection (the writer exists), extract ZIP with traversal, symlink and expansion-size limits, then RAR extraction if licensing allows.
- **F2c — sources**: Photos import, a system Inbox folder, "Copy to" between folders.
- **F2d — compression presets** with real before/after sizes (reference row 35).

## 11. Decisions — answered by the owner, 2026-10-22

1. **F2a goes ahead as specified.** Files beside documents in one library, schema v5, the F1 verbs (rename, move, label, duplicate, delete, share) available on files, page-based operations rejecting them.
2. **Any file type is accepted.** The bytes are stored content-addressed and never interpreted, so there is no new parsing risk; only previews differ by type.
3. **No size ceiling was set.** Treat §9.2 (streaming import) as required rather than optional, since a large video is a realistic first import.
4. **Tapping a file opens QuickLook** — **done 2026-10-22**: `QLPreviewController` on iOS and `QLPreviewView` (QuickLookUI) on Mac, with the details sheet behind the preview’s Info button or the library’s ⋯ menu. `QLPreviewPanel` was not needed. Verification evidence is in TEST_MATRIX; Mac interaction remains unverified.
5. **F4 OCR comes first**, then F2a. OCR unlocks search, searchable PDF export and the text-based annotation tools that F3 needs.

The original questions, for the record:

### The questions as asked

1. **Does F2a go ahead as specified** — files beside documents in one library, schema v5, no viewer yet beyond a details sheet?
2. **Import policy**: accept *any* file type, or an allowlist first (documents, images, audio, video, archives, text)? Accepting anything is simpler and matches the reference; an allowlist is easier to support.
3. **A size ceiling for import?** None, or a warning above some size (the library lives in the app container and, later, iCloud).
4. **What does tapping a file item do in F2a** — details sheet only, or QuickLook preview (`QLPreviewController` on iOS, `QLPreviewPanel` on Mac) for the types the system can show? QuickLook is a day of work and makes files genuinely useful.
5. **Order**: F2a now, or F4 OCR first? OCR unlocks search, searchable PDFs and the annotation tools, and is closer to the product's core; F2 unlocks breadth. The reference app does both, and this is a sequencing call, not a technical one.
