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

### Schema (v7)

`folders`, `items`, `tags`/`item_tags`, `assets` (keyed by SHA-256, with `availability` local or remoteOnly), `pages`, `page_transform_history`, `page_objects` (ink/text/image/comment JSON payloads), `page_recognition` (OCR, stale when `source_revision` is older than the page's revision), `file_items` (one row per general file: its bytes and what they are), and `search_index` (FTS5, `unicode61 remove_diacritics 2`, derived and rebuildable, holding `title`, `ocr`, `text` and `pdfText` rows).

Migrations, in order: **v2** adds `pages.deleted_at` (soft delete until next launch). **v3** adds `page_content_history`: a rescanned page's previous content, whose original stays referenced (so it can't be swept) until the next launch. **v4** adds nullable `items.color_label` with seven stable color values. **v5** takes general file items, widening `items.kind` and `assets.kind` to accept `file` and adding `file_items`. **v6** widens `assets.kind` to accept `heic`. **v7** widens `page_objects.kind` to accept `comment`.

SQLite cannot alter a CHECK constraint, so v5, v6 and v7 rebuild their tables. Those migrations run with foreign keys disabled and are checked with `PRAGMA foreign_key_check` before they commit, which is SQLite's documented procedure: with foreign keys enforced, `DROP TABLE items` performs an implicit delete that **cascades into `pages`** and empties the library. Each migration runs in its own transaction with its `user_version` bump, so an interrupted one leaves the previous, consistent version in place.

Sync took **v10**. **v11** adds `bookmarks`, the reader's own place-marks: one row per marked page (`page_id` is unique and `ON DELETE CASCADE`), a name and two dates. It adds a table and rebuilds none, so the sync triggers are left where they were; `BookmarkTests` checks that. The next migration is v12. Shape annotations and embedded PDF text needed none: shapes save as ordinary ink, and `search_index` is derived, rebuildable and has an unconstrained `field`. See `Sources/PaperNestStore/Schema.swift`.

### Ordering

Pages (and later page objects) use **fractional-index sort keys** (`SortKey`, base-62). Moving a page rewrites only that page's key, so reorders are small and merge well during sync. Ties from concurrent edits are broken by stable ID, and equal or invalid neighbors trigger a rebalance.

### Revisions and derived data

Each page has a `revision` that increments on every committed change. Thumbnails (in-memory LRU) are keyed by `(page, revision, size)`. OCR results record the `source_revision` they came from, and a newer page revision marks them stale. Exports are separate temporary files and never written back.

**Corrected recognition** (since 2026-11-16). A person can correct a page's current result line by line (`LibraryStore.correctRecognition`, `RecognitionCorrection.swift`): each line keeps its box, a changed line keeps its word boxes only when it still has as many words, and an emptied line is removed. The result gets `correctedAt`, and the write is a compare-and-swap token whose inverse is the undo; "the same result" ignores `sourceRevision`, because drawing on a page carries a current result forward without changing a word. A correction **moves the page's revision**, as any edit of what the page shows does: find and text selection re-read a page only when its revision changes. A revision-only page change is not synced, and recognition is not synced at all, so corrections stay on the device where they were made. `pagesNeedingRecognition` leaves a corrected result alone when only the engine changed (`json_extract(result_json, '$.correctedAt') IS NULL`), and reads it again when the paper changed. Recognize Text chosen by hand still replaces it; the OCR panel says so first.

**Search hits** (since 2026-11-16). `LibraryStore.searchHits` reads the same FTS5 index as `search(_:)`, with the same query (`ftsQuery`) and rules, and adds where each match is: FTS5's own `snippet()` around the match, the matched tokens marked with private-use characters and parsed into runs (marks that do not pair up give plain text), white space and line breaks made single spaces, and a page number counted over the document's live pages in `(sort_key, id)` order. One hit per page — a page's own PDF text, then recognized text, then typed text, the order find reads a page in — at most three per document and sixty in all; a title match is returned with no page. **A deleted page's words no longer answer either call** (`livePageRow`): its index rows stay until the purge so undo can restore it, and until 2026-11-16 `search(_:)` kept returning the document. `LibraryModel.pageHits` holds the hits for the documents on screen, in their order, published under the same guard as `items`; opening a hit goes through `LibrarySession.requestPage`, which a document's model takes on its first load or, already open, when the request changes — navigation, not `didChange()`.

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
  - **A PDF page's annotations** — a form field's typed answer, a checkbox's tick, boxes and stamps another app drew — are not page content, and `drawPDFPage` leaves them out. `PageAnnotations` draws them over the content, through PDFKit, in the same space and under the same clip (since 2026-11-14; before that a filled-in form showed empty boxes). Links, pop-ups and anything its author hid are not drawn. For the screen everything the author lets a reader see is drawn; for paper — Print, a page an export had to redraw, or a JPEG, PNG or HEIC picture of a page — only what the author also marked for printing (`PageAnnotations.Use`). A redrawn page therefore carries a field's answer as part of the page: it is no longer a field there, but it is no longer lost either. A page with no annotations, checked from the page dictionary through Core Graphics, never touches PDFKit.
  - **Code that builds a page's annotations itself runs one caller at a time** under `PDFKitAnnotationLock`: page drawing (`PageAnnotations`), `PDFForm` and the link reader. Building a form field makes CoreText look up the field's font over synchronous XPC, and several of those at once on the cooperative pool deadlock — measured twice: eight concurrent form fills (`PDFForm`), and sixteen concurrent page pictures of a form with the lock taken out (all sixteen stuck in `xpc_connection_send_message_with_reply_sync`). A second lock of its own anywhere would reopen it. **The exporter's page copies and PDFKit writes do not take it**, and were not found to need it: sixteen pictures of a filled form drawn while four protected print exports of it ran, copying its page and writing it through PDFKit, finished every time (7 of 7 runs of `printingAFormWhileItsPicturesAreDrawnFinishes`). That is measured, not explained. New code that reads a page's `annotations` takes the lock.
  - **Template pages:** lines are drawn.
- Filters use Core Image (`CIColorControls`, `CIColorThresholdOtsu`) with one shared `CIContext`.
- **A scan being reviewed has a look of its own** (since 2026-11-15): `ScanAppearance` in `PaperNestCore` is one preset (`ScanPreset`: Original, Auto, Enhanced, Grayscale, Black & White, High Contrast) and the Cleanup tool's three amounts (`ScanCleanup`, each 0…1). `ScanImageProcessor.apply` in `PaperNestRender` draws it, and the scanner's `ScannerPage.rendered` is its only caller in the app. It is never stored: a scan's look is drawn into the picture that is imported, and the capture's bytes stay as taken until then. This is separate from a saved page's `PageTransform`/`PageFilter`, which `ImageAdjustments` draws and which is unchanged.
  - **Sizes are shares of the page**, and the look is applied after the page is scaled, so a 160-pixel thumbnail, the 900-pixel picture in the Cleanup sheet and the full capture show the same thing (pinned by a test).
  - **Remove shadows and Black & White read the lighting from the paper alone** (`ScanImageProcessor.Lighting`): on a copy 256 pixels long, text is closed over, each point is asked whether it has the paper's colour, and the light measured on paper is carried across everything that is not. A heading bar or a picture is then lit like the paper around it instead of being taken for a deep shadow and bleached, which the first version did. What it cannot tell apart is a filled area in a gray close to the paper's own colour; that is lightened. Black & White divides by that lighting and thresholds, so a shadow does not turn into a black patch as it would under one threshold for the page (`PageFilter.blackAndWhite` still uses Otsu).
  - **Auto must not reach Vision.** `CIImage.autoAdjustmentFilters` looks for faces through Vision unless it is given a `features` list, and Vision parks the calling thread. Pages are drawn on Swift concurrency's threads, several at once; measured, 48 calls at once never return, and with an empty list they take 26 ms together. `ScanImageProcessor` passes the empty list, and a test stops the run with the reason if that is ever undone. The scanner's Enhance had this fault before, one page at a time. The same trap as `TextRecognizer.recognizeOnADedicatedThread`.
- Several pages of a scan are edited together through `ScanPageBatch` (`PaperNestCore`): delete, duplicate, move as one block, and one edit for each picked page. Each gives back the queue and the index of the page to show, so the page on screen stays the same page.
- **What the scanner looks for depends on its mode** (since 2026-11-16). `ScanCaptureMode` in `PaperNestCore` (Document, Whiteboard, Photo, ID / Card) gives each mode a `ScanDetection`, which says what to ask Vision's rectangle detector for and which of its answers to take, and the look a new capture starts with. `ScanEdgeDetector` in `PaperNestRender` does the asking, for the live outline (`ScannerCamera`) and for the still (`ScannerPage.detectedCorners`) alike, so a capture is cropped by the rule its outline was drawn with.
  - Document asks exactly what the scanner always asked: one rectangle, the detector's own range of shapes. Whiteboard asks for several, lets corners be further from square, and takes the largest. Card asks for small rectangles of about a card's shape and takes the one nearest 54 by 85.6. Photo looks for nothing and keeps the whole frame.
  - Measured on drawn scenes, through the real detector: Document's request does not find a board whose short side is under half its long side, nor one seen from the side, and beside a card it takes the sheet of paper. Whiteboard and Card take the board and the card. The detector's shares are of the picture and not of the thing, so shapes are judged again in true proportions (`ScanDetection.best`).
  - A board starts as High Contrast with its lighting evened out; a photo starts as taken; a document or a card starts with the person's default filter.
  - A card's two sides are two pages. `ScanCardPairing` records which is which: a kept capture is a front and its back is offered, and only the answer "Scan back" makes the next capture that front's back.
  - The scanner's defaults (`ScanSettings`: mode, filter, automatic shutter on opening) are three preferences read through `ScanSettingsStore`, never the library, and each falls back by itself when missing or unknown.
- Bitmaps are capped at 100 MP. The UI renders through `ThumbnailCache`: an LRU of 240 entries with at most 4 concurrent renders (`AsyncGate`), so long documents scroll without unbounded memory.
- PDF export embeds lossy raster content as JPEG via `CGImage(jpegDataProviderSource:)`. A test confirms the PDF contains `/DCTDecode`.
- **Export watermarks** (since 2026-11-16, design `docs/WATERMARK_DESIGN_CLAUDE.md`). A `Watermark` (`PaperNestExport`: preset Confidential, Draft, Approved or Custom; text, placement, opacity, rotation, optional date line) rides on `ExportOptions.watermark`, which is nil unless the export sheet sets it, so the backup, printing, the form workspace, bulk export and Compress never draw one. Nothing about it is stored, and the page under it is never changed.
  - `WatermarkDrawing` lays the marks out and draws them in page space (points, top-left origin, y down). **Letters are drawn as glyph outlines, not text**, so a reader's search, copy or text extraction never finds the watermark's words, and a scan's invisible OCR layer stays the only text on its page. Sizes are shares of the page, and letters are shaped at one reference size and scaled, because the system font's optical sizes would otherwise make a mark a different shape on A5, on Letter and in the sheet's small preview.
  - A PDF places the mark on the **paper** (`PaperLayout.paperSize`), so a corner mark sits in the corner of the Letter or A4 sheet and not of the page fitted inside it. A JPEG, PNG or HEIC places it on the page picture (`WatermarkDrawing.applying`). The sheet's preview draws through the same function over a thumbnail of the first exported page on the same paper.
  - **A visible watermark turns pass-through off** (`isUntouched`): a copied page cannot be drawn on, so an untouched imported PDF page is redrawn and loses its links and form fields, the trade every redraw already makes. The sheet says so under a PDF. TXT and Word, in both layouts, refuse one with `ExportError.watermarkNotSupported` rather than writing the file without it. Word page images could carry one through `writeDocxPageImages`, but that is not built.
- **Word export has two layouts** (`ExportOptions.docxLayout`, since 2026-11-16), as the brief asks: **editable text** (`DocxExport.swift`: one paragraph per line the pages really carry; refused with `noTextToExport` when there is none) and **page images** (`DocxPageImages.swift`: each page drawn as a JPEG export draws it — ink, marks, the source's paper annotations — and placed alone on a Word page of its own size, or fitted on Letter/A4 with the space around it as margins). Page images carry no words and never say they do. Both go through `Exporter.export`, so a PDF whose author switched copying off leaves as neither.
  - **One section per page, the picture inline.** Each page's paragraph ends its own section (`DocxPageSection`: page size and margins in twips, the picture in EMUs derived from the same whole twips, so the picture is exactly the area inside the margins), so a document of portrait and landscape pages keeps both and no page-break paragraph leaves a blank page behind a full-page picture. A floating picture anchored to the page was tried first: Quick Look's Word reader put such pictures out of order and on top of each other, and kept inline ones in order at their sizes. Pages larger than Word's 22-inch limit are shrunk whole.
  - What a screen should ask is `ExportOptions.keepsOnlyWords` and `writesArchive(pageCount:)`, never the format alone: Word is words in one layout and pictures in the other, and only several JPEG/PNG/HEIC pages ever become a ZIP.

## Import

`DocumentImporter.prepare` reads the file through `NSFileCoordinator` (so cloud providers can download it) and a security scope, sniffs the type from the bytes, validates it, then stores the original durably. Only then does a single store transaction commit the pages.

PDF handling:
- Locked PDFs are opened with PDFKit `unlock`, and the pages are copied into a new unencrypted `PDFDocument`. PDFKit's own `dataRepresentation()` stays encrypted, which was verified on macOS 26. The result is checked before it's accepted.
- A PDF that opens without a password is stored exactly as it arrived, **including one whose author switched copying or printing off** (every USCIS form). Until 2026-11-13 these were declined. A file that is locked *and* restricted still is: the unlocked copy above could not carry the limits.

**An author's limits** (`DocumentPermissions`: copying, printing) are never stored. `PageRenderer.permissions(for:)` reads them from the stored originals each time, so they cannot drift from the file and they follow a page into any document it is merged, split or duplicated into. They are **kept in one place, `Exporter.export`**, which every way out of the app goes through — the export sheet, Print, bulk export, the library backup, the form workspace:

- copying off and a format other than PDF: refused (`ExportError.copyingNotAllowed`) before anything is written;
- printing off and the export is for the print panel: refused (`ExportError.printingNotAllowed`);
- a PDF that has to be *rebuilt* (something drawn on it, pages left out, other paper, a password) is written with the same limits under an owner password made up for the occasion and never kept (`AuthorProtection`), by both writers — `CGPDFContext` and the PDFKit pass that copies untouched pages in. Measured: without this a USCIS form's pages come out unencrypted with copying allowed;
- the finished file is **opened and checked** before it is handed over, and an export that came out freer than its sources fails.

A password the person exporting asks for opens such a file as a reader, never as its owner. The one exit that is not an export, Copy on selected text, asks the open document's `permissions`. **Anything new that lets page content out must go through `Exporter.export` or ask the same question.** The two engines that rewrite a page into a new original, which would carry no limits, already do: `PageRedactor.redact` refuses a page from a restricted PDF (`RedactionError.restrictedByAuthor`) before anything is drawn or written; compressing a library document goes through `Exporter.export`, and compressing a loose PDF file refuses any encrypted one.

Image handling:
- ImageIO accepts truncated files, so JPEG (end-of-image after the last scan) and PNG (`IEND`) completeness are checked structurally.

## UI layer

- `LibrarySession` (one per process) opens the library once, runs launch housekeeping (orphan sweep, Recently Deleted purge), and publishes a `changeToken` after each commit.
- `LibraryModel` (one per window) holds the scope, search, import flows and the password-prompt queue.
- `DocumentModel` holds one open document's pages and edits. Each edit commits, then registers its inverse with the window's `UndoManager`. Undo and redo handlers register their own inverse *synchronously*, before the async store write, so redo works.
- Mac commands are wired through `FocusedValues`. Windows reload when `changeToken` changes, so multiple windows stay consistent.
- Localization: `L10n` looks up keys in `PaperNestUI`'s bundle, using en/fr/es `.lproj` `Localizable.strings` plus `.stringsdict` plurals. String Catalogs need `xcstringstool` (Xcode only), so migrating to `.xcstrings` is a follow-up once Xcode builds are routine. `LocalizationTests` enforces key parity, matching format arguments, no unused keys, French typography and plural rules.

## Sync (M2, implemented; not yet run against a real iCloud container)

**Why CKSyncEngine.** The library is a custom SQLite store with content-addressed files, so the choice was between
`CKSyncEngine` and iCloud Documents. Core Data mirroring does not apply (no Core Data, and it would own the
conflict policy). iCloud Documents would mean syncing `Library.sqlite` as a file, which is the one thing that must
never happen to a live database. `CKSyncEngine` gives scheduling, pushes, retry and back-off, and leaves every
merge decision with the store. One mechanism per kind of data: records through the engine, original files through
plain CloudKit asset records. Nothing is in iCloud Drive.

**Where the code is.** `PaperNestStore/Sync` owns everything that touches data: schema v10, the outbox, the
three-way merge (`SyncMerge`), applying remote changes and deletions (`SyncApply`), and where each original stands
(`SyncAssets`). `PaperNestSync` owns everything that touches the network: `CloudKitSyncBackend` (the
`CKSyncEngineDelegate`), `CloudKitBlobTransport`, `BlobSyncer` and `CloudSyncController`, which the UI observes.
The backend is behind a protocol (`SyncBackend`), and the tests replace only that.

- **Outbox by trigger.** Schema v10 adds triggers on `folders`, `items`, `pages`, `page_objects`, `signatures`,
  `file_items` and `assets`. A trigger runs in the transaction that made the change, whichever of the store's many
  methods made it, so "saved locally" and "queued for iCloud" commit together. They do nothing while sync is off
  or while a remote change is being applied. **A migration that rebuilds one of those tables must recreate its
  triggers** (`SyncSchema.triggerSQL`); `SyncSchemaTests` fails otherwise.
- **Records:** `Folder`, `Item` (a file item's payload rides on it), `Page`, `PageObject` (one per stroke, text box,
  placed image or comment) and `Signature`, in zone `PaperNestLibrary`. A page's `revision` and `modified_at` are
  local bookkeeping and are not synced. OCR, search rows, thumbnails and undo history are derived and not synced.
- **Originals:** one `Original` record per SHA-256 with a `CKAsset`, in zone `PaperNestOriginals`, which the engine
  is told not to fetch (`nextFetchChangesOptions`). A device learns a document exists without downloading it;
  the page's asset row is `remoteOnly` until the bytes arrive and pass their checksum. A record that points at an
  original is held back until the upload is confirmed.
- **Ancestry.** `sync_records` keeps, per record, the server's change tag and the fields as last confirmed. A
  conflict is merged against that ancestor, field by field. Timestamps decide only who wins a same-field clash on
  a document's name, folder, favorite or label.
- **Conflicts.** Independent strokes are independent records. A rotation here and a crop there merge. The same
  page setting, or the same mark, changed two ways: the server's version stays, this device's becomes a copy (a
  page right after, or a second mark), and a row in `sync_conflicts` drives "Review changes".
- **Deletion.** Recently Deleted is a field. With sync on, a deleted page is kept 30 days as a tombstone. An edit
  beats a deletion: the device that still holds the content sends it again. A document deleted for good elsewhere
  but live here goes to Recently Deleted here. An original leaves iCloud 30 days after its last local use.
- **Accounts.** The account's record name is stored with the library. A different account stops sync until the
  person chooses; choosing to sync forgets everything the old account confirmed and uploads as new.
- **Bookmarks are not synced (decided 2026-11-13).** A bookmark (`bookmarks`, schema v11) is written to this
  device's library only: no trigger queues it and it has no record type, and `BookmarkTests` pins that — with sync
  on, adding, renaming and removing one leaves the outbox exactly as it was. Two reasons. Each record type needs
  its own triggers, record mapping, merge rule and multi-device scenarios, and the five that exist have not yet
  exchanged a byte with a real iCloud container; a sixth should not be stacked on an engine still waiting for its
  first real run. And nothing is lost by waiting: the table was shaped for it — UUID ids that can be record names,
  a `modified_at`, the page referred to by id, one bookmark to a page so two devices marking the same page
  converge on one — so adding it later is triggers on a table that needs no rebuild, plus a `Bookmark` record
  whose parent is its page. Until then a bookmark made on the iPad is not on the Mac, and with sync on the
  Bookmarks list says so in a line at its foot. A page another device deletes still takes its bookmark here,
  through the foreign key, as it takes its ink.

Known limits are listed in TEST_MATRIX under the 2026-11-13 entry.

## Billing design (M5, not yet implemented)

- StoreKit 2 with one subscription group containing monthly and annual products. Product IDs come from configuration, not code.
- Entitlement is derived from `Transaction.currentEntitlements`, with `Transaction.updates` listened to from launch. Only `.verified` results count. Revocation, expiry and grace periods are evaluated from the transaction itself.
- No user-editable `isPro` flag is authoritative. A cached hint may exist for offline display and is re-evaluated against StoreKit.
- The StoreKit purchase identity is kept separate from the iCloud document account.


### Document composition (F1, 2026-10-22)

`LibraryComposition.swift` provides atomic duplicate, merge and extraction operations on the existing LibraryStore actor. Nested store calls use SQLite savepoints beneath one outer transaction. Sources must be live and local assets readable; invalid selections or failures leave no partial output. New item/page/object identities preserve independent editing while sharing immutable asset files. Current transforms and object paint order are retained, but undo/history is not cloned. Duplicate/extract preserve the source label; merge starts unlabeled. Extraction follows source page order; merge follows the explicit document order reviewed in the sheet.

Current completed OCR is remapped to the new page revision; stale or unfinished results become pending with no copied text. Derived text/OCR index rows refer only to the new identities. This preserves recognition metadata when present; it does not introduce an OCR engine.
