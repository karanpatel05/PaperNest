# Architecture

## Modules

```
PaperNestCore      domain models, PageGeometry, SortKey, Brand. No I/O.
  └ PaperNestStore   LibraryStore (SQLite) + AssetFileStore (content-addressed files)
      ├ PaperNestImport   file/data → validated originals → items/pages
      ├ PaperNestRender   pages → CGContext (vector PDF, upright images, filters)
      │   └ PaperNestExport   PDF / JPEG / PNG / ZIP writers
      └ PaperNestUI       SwiftUI views + @Observable view models + L10n
Apps/Mac   native macOS entry point (SwiftPM executable + Xcode target)
Apps/iOS   iPhone/iPad entry point (Xcode target)
```

Planned modules, created only when they get real code:
- **Sync** (M2): the CKSyncEngine adapter, outbox and conflict policy.
- **Notebook** (M3): the ink canvas (PencilKit adapter on iPad, own renderer everywhere), text boxes and templates.
- **Recognition** (M4): Vision OCR and the search index feed.
- **Billing** (M5): StoreKit 2 products, entitlement evaluation and paywall.
- **Export additions** (M4): TXT and DOCX.

The modules are separate so each can be tested without UI, platform-specific code stays at the edges (`#if os(iOS)` VisionKit camera, AppKit pasteboard), and the dependency direction stays acyclic.

## Platform and deployment targets

| Decision | Choice | Why |
|---|---|---|
| Mac app | **Native macOS (SwiftUI + AppKit bridges)**, not Catalyst | The brief requires a genuine Mac app with menus, multiple windows and save panels. VisionKit's document camera isn't on macOS, so the Mac imports files (and later Continuity Camera) instead. |
| Minimum OS | **iOS/iPadOS 17.0, macOS 14.0** | `CKSyncEngine` (the planned sync engine) and the Observation framework (`@Observable`) both need these versions. `ContentUnavailableView` is 17/14 as well. Tradeoff: iPhone 8/X-era devices stuck on iOS 16 are excluded. Dropping to iOS 16 would mean a hand-written CloudKit sync loop and `ObservableObject`. |
| Language | Swift 6 language mode, strict concurrency | Data-race safety for the store, renderer and export pipeline. |
| Dependencies | None (Apple frameworks and system SQLite) | Smaller audit and licensing surface. Nothing to vendor. |

## Persistence

### Decision: one SQLite database, plus immutable content-addressed files

| Option | Verdict |
|---|---|
| **SQLite (system library) as the only metadata authority** | **Chosen.** Real transactions (WAL, `synchronous=FULL`), FTS5 search in the same database, explicit migrations, and no compile-time model tooling (works with Command Line Tools). Sync can later write its outbox *in the same transaction* as the edit, which keeps one owner of state. |
| Core Data + `NSPersistentCloudKitContainer` | Rejected. Mirroring owns the sync state and gives coarse control over conflicts and asset ordering, while the brief requires conflict copies and tombstones. `momc` isn't available without Xcode. |
| SwiftData (+ automatic CloudKit) | Rejected for the same sync-control reasons. Migration and history behavior was also harder to reason about for an integrity-first app. |
| JSON manifests per item + SQLite index | Rejected. Two sources of truth invite divergence. |

Layout of a library directory:

```
Library/
  Library.sqlite (+ -wal, -shm)
  Assets/<first 2 hex>/<sha256>.<pdf|jpg|png>   immutable originals
  Assets/.staging/                              in-flight writes
```

### Durability protocol

1. **Asset:** write to `.staging/<uuid>`, `fsync`, rename to the content address, `fsync` the directory. An existing file is reused only after its checksum is verified.
2. **Metadata:** a single `BEGIN IMMEDIATE … COMMIT` inserts the asset row, item and pages. Inserting a row whose file is missing throws, so the database never references a missing file.
3. A crash between 1 and 2 leaves an unreferenced file. `sweepOrphanAssets` (run at launch, with a 1-hour grace period) removes it, along with unreferenced rows and stale staging files.
4. Every mutating `LibraryStore` method commits before returning. View models update `pages` and `items` only from committed results.
5. Deleting a page only sets `pages.deleted_at`. The page, its objects and OCR, and its original stay put, so in-session undo always works. At the next launch, housekeeping runs in this order: `purgeDeletedPages`, `purgeReplacedPageContent`, `purgeExpiredDeletions` (Recently Deleted older than 30 days), then `sweepOrphanAssets`. A rescan (`replacePage`) replaces the content and inserts any extra captured pages in one transaction (`SQLiteDatabase.transaction` nests as savepoints, so store operations compose atomically). Rescans use the same principle as page deletion: the previous content stays referenced in `page_content_history` until the next launch. Permanent deletion of items therefore never removes an original that a deleted-but-undoable page still references.
6. A library written by a newer schema (`user_version` above the supported version) is refused untouched, and the UI explains it.

Tests cover each step: `DurabilityTests`, `LibraryStoreTests`, `DeletionTests`.

### Schema (v3)

`folders`, `items`, `tags`/`item_tags`, `assets` (keyed by SHA-256, with `availability` local or remoteOnly), `pages`, `page_transform_history`, `page_objects` (ink/text/image JSON payloads), `page_recognition` (OCR, stale when `source_revision` is older than the page's revision), and `search_index` (FTS5, `unicode61 remove_diacritics 2`, derived and rebuildable). v2 adds `pages.deleted_at` (soft delete until next launch). v3 adds `page_content_history`: a rescanned page's previous content, whose original stays referenced (so it can't be swept) until the next launch. See `Sources/PaperNestStore/Schema.swift`. Migrations are ordered and each runs in its own transaction with its `user_version` bump.

### Ordering

Pages (and later page objects) use **fractional-index sort keys** (`SortKey`, base-62). Moving a page rewrites only that page's key, so reorders are small and merge well during sync. Ties from concurrent edits are broken by stable ID, and equal or invalid neighbors trigger a rebalance.

### Revisions and derived data

Each page has a `revision` that increments on every committed change. Thumbnails (in-memory LRU) are keyed by `(page, revision, size)`. OCR results record the `source_revision` they came from, and a newer page revision marks them stale. Exports are separate temporary files and never written back.

## Page coordinates

`PageGeometry` is the only mapping between spaces:

- **Source/content space:** upright, uncropped content in points, top-left origin, y down. For images, EXIF orientation is applied. For PDFs, `/Rotate` is applied. **Ink, text boxes and OCR boxes live here**, so they follow the page through crop and rotation.
- **Page space:** crop, then a clockwise quarter-turn rotation. This is what's shown and exported.
- `pdfToSource(box:rotationDegrees:)` maps PDF user space (y up) into source space. `yUpToYDown` handles image drawing.
- `PaperLayout` fits page space onto paper (Letter/A4) by uniform scaling with centering, never cropping, and turns the paper to match the page's orientation.

Display, thumbnails and every export path draw through `PageRenderer.draw(_:source:in:pageToContext:)`, so the export matches the editor. `PageGeometryTests` and the pixel-probe rendering and export tests pin the behavior.

## Rendering

- `PageRenderer.prepareSource` gives each page one of three sources:
  - **Images:** decoded upright at only the resolution needed (ImageIO thumbnails, size-bucketed, LRU `SourceCache`).
  - **PDF pages:** stay vector (`CGContext.drawPDFPage`) unless a pixel filter applies, in which case they are rasterized at the target resolution.
  - **Template pages:** lines are drawn.
- Filters use Core Image (`CIColorControls`, `CIColorThresholdOtsu`) with one shared `CIContext`.
- Bitmaps are capped at 100 MP. The UI renders through `ThumbnailCache`: an LRU of 240 entries with at most 4 concurrent renders (`AsyncGate`), so long documents scroll without unbounded memory.
- PDF export embeds lossy raster content as JPEG via `CGImage(jpegDataProviderSource:)`. A test confirms the PDF contains `/DCTDecode`.

## Import

`DocumentImporter.prepare` reads the file through `NSFileCoordinator` (so cloud providers can download it) and a security scope, sniffs the type from the bytes, validates it, then stores the original durably. Only then does a single store transaction commit the pages.

PDF handling:
- Locked PDFs are opened with PDFKit `unlock`, and the pages are copied into a new unencrypted `PDFDocument`. PDFKit's own `dataRepresentation()` stays encrypted, which was verified on macOS 26. The result is checked before it's accepted.
- PDFs that restrict copying or printing are declined.

Image handling:
- ImageIO accepts truncated files, so JPEG (end-of-image after the last scan) and PNG (`IEND`) completeness are checked structurally.

## UI layer

- `LibrarySession` (one per process) opens the library once, runs launch housekeeping (orphan sweep, Recently Deleted purge), and publishes a `changeToken` after each commit.
- `LibraryModel` (one per window) holds the scope, search, import flows and the password-prompt queue.
- `DocumentModel` holds one open document's pages and edits. Each edit commits, then registers its inverse with the window's `UndoManager`. Undo and redo handlers register their own inverse *synchronously*, before the async store write, so redo works.
- Mac commands are wired through `FocusedValues`. Windows reload when `changeToken` changes, so multiple windows stay consistent.
- Localization: `L10n` looks up keys in `PaperNestUI`'s bundle, using en/fr/es `.lproj` `Localizable.strings` plus `.stringsdict` plurals. String Catalogs need `xcstringstool` (Xcode only), so migrating to `.xcstrings` is a follow-up once Xcode builds are routine. `LocalizationTests` enforces key parity, matching format arguments, no unused keys, French typography and plural rules.

## Sync design (M2, not yet implemented)

- **Engine:** `CKSyncEngine` on the private database, in a custom zone. Its serialized state is persisted in a `sync_state` table (a v4 migration) and restored at launch.
- **Single owner:** an `outbox` table is written *in the same transaction* as each edit (record name and change kind). The engine's "next batch" is built from the outbox, so a crash can't lose a pending change or double-apply one. IDs are stable UUIDs and SHA-256 hashes, so retries are idempotent.
- **Records:** `Item`, `Folder`, `Page`, `PageObject` (one record per stroke or text box), and `Asset` (CKAsset keyed by SHA-256). OCR and thumbnails are derived and not synced.
- **Ordering of arrival:** a page whose asset hasn't arrived gets `availability = remoteOnly` and is shown as downloading, never as available offline.
- **Conflicts:**
  - Independent fields merge (name, favorite, folder, sort key).
  - Independent strokes merge naturally because each is its own record.
  - When the same object or page transform is changed concurrently, the server version is kept and the local version becomes a **conflict copy** (an object or page marked as a conflict). The newest whole document is never chosen silently.
- **Deletion:** `pages.deleted_at` already marks deleted pages. `tombstones` keep deleted record names through the retention window, so an offline device can't resurrect deleted content. Recently Deleted is honored across devices.
- **Accounts:** the iCloud account identity is recorded per library. Sign-out or an account switch pauses sync and asks the user what to do. Documents are never deleted, and one account's documents are never uploaded to another.

## Billing design (M5, not yet implemented)

- StoreKit 2 with one subscription group containing monthly and annual products. Product IDs come from configuration, not code.
- Entitlement is derived from `Transaction.currentEntitlements`, with `Transaction.updates` listened to from launch. Only `.verified` results count. Revocation, expiry and grace periods are evaluated from the transaction itself.
- No user-editable `isPro` flag is authoritative. A cached hint may exist for offline display and is re-evaluated against StoreKit.
- The StoreKit purchase identity is kept separate from the iCloud document account.
