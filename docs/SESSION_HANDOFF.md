# Session handoff

**Read this page first, then `docs/IMPLEMENTATION_PLAN.md`. The product brief is `CLAUDE_CODE_PROMPT.md` and never changes.**

## Start here — state on 2026-10-22, 15:20

- **Who is editing what: nobody.** Claude has released every file. Codex last wrote at 06:01 and its F1 work is finished, verified and committed.
- **The work is committed** on the branch **`document-tools-ocr-and-file-items`** (there is no remote): `cb7a85c` then `2653994`. The working tree is clean and sits on that branch. `main` still points at `bca0ba9`; move it with `git checkout main && git merge --ff-only document-tools-ocr-and-file-items`, or just keep working on the branch.
- **Verify before you change anything** (expected numbers as of `2653994`):

```bash
./scripts/test.sh                                   # 191 tests, 0 failures, 0 warnings
./scripts/build-mac-app.sh                          # 0 warnings
xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build
./scripts/ui-test-ios.sh 63992C10-33B4-4CE3-91C3-EE23ECC595A5     # iPhone: 16 passed, Markup skipped
./scripts/ui-test-ios.sh 62328381-19FB-400A-A8FC-4F4AD13EB5C4 -only-testing:PaperNest-iOSUITests/AppUITests/<name>
```

- Simulators in use: iPhone 17 Pro `63992C10-33B4-4CE3-91C3-EE23ECC595A5`, iPad Air 13-inch (M4) `62328381-19FB-400A-A8FC-4F4AD13EB5C4`.
- Screenshot hooks: `-PaperNestDebugOpenItem <name>`, `-PaperNestDebugShowExport YES`, `-PaperNestDebugShowCrop YES`, `-PaperNestDebugShowMarkup YES` (iPad), `-PaperNestDebugShowTools YES`. The last one is new and is **not** yet listed in CLAUDE.md, which is the owner's file.

## What works today

Library (import, folders, favourites, sort, rename, trash with 30-day purge, title search, colour labels, multi-select) · document tools (duplicate, merge in an explicit order, extract pages, split into one document per page, export a selection as one ZIP) · a **Tools screen** listing only tools that work · page editing (rotate, reorder, delete, add, crop, filters, undo/redo, rescan with history) · Apple Pencil ink on iPad · **text recognition** (Vision, en/fr/es) with search over recognised text · **searchable PDF export** · **file items**: any file type kept as itself, with a type symbol, its size, a details sheet, Share and Save a Copy.

Evidence for every claim is in `docs/TEST_MATRIX.md`, newest rows first. Capability coverage against the owner's reference screenshots is `docs/REFERENCE_FEATURE_INVENTORY.md` (48 rows).

## Next, in order

1. **F2a step 3 — QuickLook preview.** The owner chose it (decision 4 in `docs/F2_FILE_ITEMS_DESIGN.md`); the details sheet stands in until then. `QLPreviewController` on iOS; on the Mac decide between `QLPreviewPanel` and opening a temporary copy.
2. **F2b — archives.** Create a ZIP from a selection (`Exporter` already writes valid ZIPs), then extract with traversal, symlink and expansion-size limits. RAR only once the owner settles licensing.
3. **F2c** — Photos import, a system Inbox folder, Copy to.
4. **Rest of F4** — a recognition status surface outside the menu, automatic recognition after a scan, re-recognition after a rescan, a user language override, and pulling text out of vector PDFs into the search index.
5. **F3** — highlight/underline/strikethrough over recognised text, notes, stamps, shapes, visual fill & sign, app lock.

F5–F9 (PDF text editing, cloud, media, browser, VPN) are blocked on owner decisions; see below.

## Traps found the hard way — read before touching these

- **Migrations that rebuild a table.** This store runs `PRAGMA foreign_keys = ON`, so `DROP TABLE items` performs an implicit delete that **cascades into `pages` and empties the library** (reproduced: *pages before 2 → after 0*). Mark such a migration `rebuildsTables`; the runner disables foreign keys around it and verifies `PRAGMA foreign_key_check` inside the transaction. Never hand-roll a rebuild.
- **Recognised text is indexed only when `.completed` *and* `sourceRevision` matches the page.** Ordinary edits (rotate, crop, ink) keep the text findable; `replacePageContent` clears it, because a rescan puts different paper on the page. Do not widen this to every revision bump — an existing composition test depends on it.
- **The OCR text layer must be drawn in source space** with the page transform concatenated onto the CTM. Placing lines by their page-space bounding box collapses a rotated page's text into slivers.
- **`CTLineDraw` overrides `CGContext.textMatrix`** from the line's own runs. Any horizontal stretch belongs on the CTM.
- **A dynamic UTI is never stored.** The system invents one for an unknown extension; it means nothing after sync, so those files are recorded as `public.data`.
- **`LibraryView.importableTypes` is now every type.** Add Pages and Replace Page must keep using `LibraryView.pageTypes`, or a video could be picked to replace a page.
- **The iPhone document toolbar has no ⋯ menu** — only iPad and Mac do. Document actions go in the bottom bar's ⋯ there. Each layout has exactly one overflow menu.
- **The iPhone home has no vertical room left.** A third large button in `CaptureActions` pushed the Folders **+** off screen and broke a test. Put new entry points in the toolbar.
- **SwiftUI menu items do not expose `accessibilityIdentifier`** to XCUITest; match them by label. A `LabeledContent` row is one element labelled `"<label>, <value>"`. The title menu's button is labelled `"<name>, Actions Menu"`.
- **swift-testing reports a failure when an optional inside a `#expect` expression is nil**, even when the condition is true. Bind `pdf.page(at:)?.string` to a local first.
- **Deliberate contract change:** importing a `.txt` no longer fails as "unsupported type"; it becomes a file item. The M1 gate test asserts the new behaviour.

See also "Do not undo" below, which still holds.

## Waiting on the owner — these block real work

1. Apple Developer team, bundle ID, iCloud container — blocks M2 sync, camera capture and every on-device test.
2. PDF text/image editing engine: build or license. Also gates Office conversion and real redaction.
3. RAR extraction library and licence.
4. Transcription engine: on-device only, or a disclosed network service.
5. VPN provider, entitlement, provisioning, billing, privacy position. No VPN UI until a connection actually works.
6. Cloud providers to support first, and credentials for each.
7. Pricing and trial length, for the paywall.

Answered on 2026-10-22, recorded in `docs/F2_FILE_ITEMS_DESIGN.md` §11: F2a goes ahead as designed, any file type is accepted, no size ceiling, tapping a file opens QuickLook, and F4 came before F2a.

## Where the detail lives

| File | What it holds |
|---|---|
| `docs/TEST_MATRIX.md` | Every command run and its real outcome. Never mark an unrun check as passed. |
| `docs/REFERENCE_FEATURE_INVENTORY.md` | The 48 capabilities from the owner's screenshots, with honest status |
| `docs/F2_FILE_ITEMS_DESIGN.md` | The file-items design and the owner's answers |
| `docs/FEATURE_EXPANSION.md` | Delivery order F1–F9 (Codex owns this file) |
| `docs/IMPLEMENTATION_PLAN.md` | Milestones M0–M6 |
| `docs/CLEAN_NATIVE_DESIGN.md` | Design rules and pass history |
| `docs/design/reference/` | The owner's ten reference screenshots: research input only, never shipped |

## Earlier passes, newest first (condensed log)

> **Codex, read this first (added by Claude, 2026-10-22 06:55).** The owner supplied ten more reference screenshots of *Documents by Readdle* — the App Store listing, the in-app Tools/Files/Notes/Media/Browser/VPN screens and the paywall — and said: **"I want all these features."** Everything visible in them is written up, screen by screen, in **[REFERENCE_FEATURE_INVENTORY.md](REFERENCE_FEATURE_INVENTORY.md)**, with a 48-row capability checklist, honest per-row status, the suggested next slices and the eight decisions that are still the owner's. The images themselves are in `docs/design/reference/`. That file is the capability record; [FEATURE_EXPANSION.md](FEATURE_EXPANSION.md) keeps the delivery order. The reference screenshots are research input only — never ship their images, copy, branding or marketing claims.


- **Claude: F1 follow-up — split into pages — finished and released at 08:55. Claude is not editing any file now.** What changed: `LibraryStore.splitItem(_:nameForPage:)` in `LibraryComposition.swift` (one document per live page, stored order, source's folder and color kept, source intact, whole batch in one transaction); `LibraryModel.split(_:)`; a **Split into Pages** row in the library item's ⋯ / context menu, disabled below two pages; the `isDuplicating` flag in `LibraryView` renamed **`isComposing`** since it now guards duplicate *and* split; strings `tools.split` and `tools.splitName` ("%@ — Page %d") in en/fr/es; new `Tests/PaperNestStoreTests/DocumentSplitTests.swift` (4 tests, written first); a new UI test at the end of `AppUITests.swift`; and `scripts/ui-test-ios.sh` now seeds a third disposable library from `Samples/multilingual-letter.pdf`. **Verified:** 148 unit tests, 0-warning Mac and iOS builds, iPhone UI suite TEST SUCCEEDED (12 passed + Markup skipped), iPad TEST SUCCEEDED (split and merge/extract). Details in TEST_MATRIX. **Then, 09:00–09:35, the last F1 piece: export a selection as one ZIP.** New `Sources/PaperNestUI/BulkExportSheet.swift` (`BulkExportModel` + `BulkExportSheet`) and an **Export as ZIP…** entry in the selection bar's ⋯ menu, enabled while at least one selected document has pages. The archive writer is unchanged: `Exporter.exportLibrary` already took an item list. Strings `tools.exportZip`, `tools.exportZip.title`, `.footer` and `.archiveName` in en/fr/es; new `Tests/PaperNestUITests/BulkExportTests.swift` (3 tests) and one more UI test at the end of `AppUITests.swift`. **Verified:** 151 unit tests, 0-warning Mac and iOS builds, iPhone TEST SUCCEEDED (13 passed + Markup skipped), iPad TEST SUCCEEDED (bulk export and split). **Claude has released every file and is not editing anything.** **F1 is now complete as scoped** — `docs/FEATURE_EXPANSION.md` still says splitting and bulk share are follow-ups; Codex owns that file, so please update that line. **Then, 09:40–10:05, the Tools screen** (`Sources/PaperNestUI/ToolsSheet.swift`, `LibraryModel.isShowingTools`, a wrench toolbar button in `LibraryView` and `RootView`, 10 new strings in en/fr/es, one UI test, and a 4th seeded library in `scripts/ui-test-ios.sh`). Create (Scan, Import) and Documents (Merge, Extract, Split, Export as ZIP), each document tool pushing a picker that enforces its own rule. **Only tools that work are listed** — no placeholders. **Watch out:** the Tools entry started as a third large button in `CaptureActions` and that pushed the Folders **+** off the iPhone home, breaking `testAFolderMadeInTheSidebarHoldsAMovedDocument`; it now lives in the toolbar. That home screen has no vertical room left. New screenshot hook **`-PaperNestDebugShowTools YES`** opens the sheet at launch (worth adding to CLAUDE.md's debug-args line, which is the owner's file). **Verified:** 151 unit tests, 0-warning Mac and iOS builds, iPhone TEST SUCCEEDED (14 passed + Markup skipped), iPad TEST SUCCEEDED; fr/es screenshots inspected (`docs/screenshots/f1-tools-screen-*`). **Claude has released every file and is not editing anything.** **Then, 10:15–11:40, F4a: text recognition and search inside pages.** New `Sources/PaperNestRender/TextRecognizer.swift` (Vision, on device) and `PageRenderer.renderSourceForRecognition` (upright, uncropped, unfiltered — OCR reads the paper, not the current view); `NormalizedRect.exact` so a text line is not inflated to the minimum crop side; `LibraryStore.saveRecognition` now maintains `search_index` in the same transaction and `replacePageContent` clears a page's OCR rows; `DocumentModel.recognizeText()` plus a **Recognize Text** entry in each layout's overflow menu; new strings `document.recognizeText` / `document.recognizeProgress`; new `TextRecognitionTests` ×5, `RecognitionSearchTests` ×6, `RecognitionWorkflowTests` ×2 and one iOS UI test; `Tests/Support/SyntheticDocuments.textImage` fixture; a 5th seeded library in `scripts/ui-test-ios.sh`. **Verified:** 164 unit tests, 0-warning Mac and iOS builds, iPhone TEST SUCCEEDED (15 passed + Markup skipped), the recognition test also passing on iPad. **Two things to know:** the iPhone document toolbar has **no ⋯ menu** (only iPad/Mac do) — document actions must go in the bottom bar's ⋯ there; and **SwiftUI menu items do not expose `accessibilityIdentifier`** to XCUITest, so match menu entries by label. **Rule to keep:** indexed text requires `.completed` *and* a matching `sourceRevision`; ordinary edits keep text findable, a rescan clears it. **Claude has released every file and is not editing anything.** **Then, 11:45–12:30, F4b: searchable PDF export.** `ExportOptions.includesRecognizedText` (default on), `PageRenderer.recognizedLines(for:)` (same currency rule as search) and an invisible text layer in `Exporter.writePDF`; new `SearchablePDFTests` ×7 reading the file back with PDFKit. **Verified:** 171 unit tests, 0-warning Mac and iOS builds, iPhone TEST SUCCEEDED (15 passed + Markup skipped). **Two traps to remember:** the text layer must be drawn in **source space** with the page transform on the CTM — placing lines by their page-space bounding box collapses a rotated page's text into slivers; and **`CTLineDraw` overrides `CGContext.textMatrix`**, so any horizontal stretch belongs on the CTM. Also: swift-testing flags a nil optional inside a `#expect` expression as a failure even when the condition is true — bind it to a local first. **Claude has released every file and is not editing anything.** **Then, 12:40–13:40, F2a step 1: schema v5 and file items in the store.** **Read this before touching migrations:** this store runs with `PRAGMA foreign_keys = ON`, so `DROP TABLE items` in a table rebuild **cascades into `pages` and empties the library** — proved with sqlite3 before the migration was written. `Schema.Migration.rebuildsTables` now marks such migrations; the runner disables foreign keys around them and verifies `PRAGMA foreign_key_check` inside the transaction. v5 rebuilds `items` and `assets` to accept `'file'` and adds `file_items`. New store API: `createFileItem`, `filePayload`, `ItemSummary.file`, `ItemKind.file`, `AssetKind.file`, `FilePayload`; `deleteUnreferencedAssetRows` now also checks `file_items`, so a file's bytes survive the deletion of a document that shared them. New `FileItemMigrationTests` ×3 and `FileItemTests` ×6. **Verified:** 180 unit tests, 0-warning Mac and iOS builds, iPhone TEST SUCCEEDED (15 passed + Markup skipped). **Claude has released every file and is not editing anything.** **Then, 13:50–15:10, F2a step 2: files in the library.** Streaming import (`AssetFileStore.store(contentsOf:)`, copies and hashes in one pass), `FileItemImporter`, Import now accepting every type with a fallback to a file item, file tiles showing a type symbol and size, and a details sheet with Share and Save a Copy. The seeder has the same fallback. New `StreamingAssetTests` ×5, `FileItemImportTests` ×6 and one iOS UI test, passing on iPhone and iPad. **Verified:** 191 unit tests, 0-warning Mac and iOS builds, iPhone TEST SUCCEEDED (16 passed + Markup skipped). **Three things to carry forward:** a **dynamic UTI is never stored** (an unknown extension becomes `public.data`, because a dynamic identifier means nothing after sync); **Add Pages and Replace Page must stay on `LibraryView.pageTypes`**, not `importableTypes`, which is now every type; and a `LabeledContent` row is one accessibility element labelled "<label>, <value>". **Contract change:** importing a `.txt` no longer fails — it becomes a file item, and the M1 gate test was updated to assert that. **Claude has released every file and is not editing anything.** **Next — F2a step 3:** QuickLook preview (the owner chose it; the details sheet stands in for now), then F2b archives (ZIP create/extract with traversal, symlink and expansion limits), Photos import and a system Inbox.
- **Earlier, at 10:10, the F2 design** — **[F2_FILE_ITEMS_DESIGN.md](F2_FILE_ITEMS_DESIGN.md)**, a proposal with nothing built: a third item kind (`items.kind = 'file'` plus a 1:1 `file_items` row) rather than dummy one-page documents or a second store; schema v5 needing table rebuilds because `items.kind` and `assets.kind` are CHECK-constrained; the asset-sweep hazard when a document and a file share bytes; streaming import for large files; QuickLook thumbnails; and slices F2a–F2d. **It is waiting on five owner decisions in its §11** (go/no-go, import policy, size ceiling, whether tapping a file opens QuickLook, and whether F2a or F4 OCR comes first). Don't start F2 code before those are answered. **Claude is not editing any file.**
- **Codex: expanded file tools — finished, verified and committed.** (Left as written at the time; the work landed in `cb7a85c`.) Owns LibraryView/LibraryModel, new document-tools sheet, color label model/schema/store code, localization, related tests and expansion roadmap. Codex now owns `LibraryComposition.swift` and `DocumentCompositionTests.swift` too; the worker stopped after implementing them. Claude’s ink changes were independently committed as `bca0ba9` during this work; preserve them. Read `docs/FEATURE_EXPANSION.md` for the full nine-screenshot request and rollout as it is added.
- **Claude took `Apps/iOS/UITests/AppUITests.swift` and `Sources/PaperNestUI/DocumentToolsSheet.swift` at 06:28 (owner's instruction), fixed the two iPad UI-test failures, and released them at 06:42. Claude is not editing any file now.** The change: the test waits for the new document's navigation bar (`Combined test`, then `Combined test — Pages`) instead of `page-thumbnail-1`, which exists only in the compact-width `PageScroller`; and each merge row's name `Text` carries an `accessibilityIdentifier` `merge-row-<n>` that the test matches, instead of matching the bare document name, which on iPad found the library tile behind the form sheet. Nothing else in either file was touched — the extract sheet's black checkmark is still there (see below). **Re-verified after the fix:** `./scripts/test.sh` 144 tests passed / 0 warnings, `build-mac-app.sh` and the iOS Simulator build 0 warnings, `ui-test-ios.sh 63992C10-…` (iPhone) TEST SUCCEEDED 11 passed + Markup skipped, `ui-test-ios.sh 62328381-…` (iPad, the two tools tests) TEST SUCCEEDED. The iPad run exercised **extraction and the fr/es flows on iPad for the first time**; its screenshots are `docs/screenshots/f1-tools-ipad-*.png`.
- **Claude: F1 verification (2026-10-22, 06:03–06:25). Claude edited no source file during the verification itself; it touched only `docs/TEST_MATRIX.md`, `docs/IMPLEMENTATION_PLAN.md` (the F1 status line), this file, the plan's verification note, and eleven new `docs/screenshots/f1-tools-*.png` evidence files.** Codex's F1 files were last written at 06:01, so they were left alone. Results are in TEST_MATRIX ("F1 document tools" row). In short: `./scripts/test.sh` **144 tests passed**, Mac and iOS builds **0 warnings**, `scripts/ui-test-ios.sh 63992C10-…` on iPhone **TEST SUCCEEDED (11 passed, Markup skipped)**, and all nine en/fr/es screenshots were inspected with no truncation. **Two things for Codex:**
  - **Both new UI tests failed on iPad** (iPad Air 13-inch M4, iOS 26.5) before the fix above; both pass now. **One open question remains:** `…LocalizedSelectionOrderAndCancellation` matched the library grid's tile name texts behind the form sheet (both `minY` 556.0), but `ItemCell` is `.accessibilityElement(children: .ignore)`, so those texts should not be separate elements at all. The fixed test no longer depends on it; check selection mode with VoiceOver or the Accessibility Inspector.
  - **Design nit:** the extract sheet's per-page checkmark is plain black while every other selection indicator is `Theme.accent` blue (`DocumentToolsSheet.swift:97`).
  Two code risks were checked and are **not** problems: `applyObjectChanges` writes no `search_index` rows, so `LibraryComposition`'s derived-text insert is not a duplicate; and merge/extract names are normalized, because `createItem` → `NameDeduplicator.uniqueName` → `normalizedDisplayName` trims, strips control characters and caps at 200. Still unverified: extraction on iPad, the whole feature on the Mac, a long document name in the merge/selection UI, and a failed save keeping the sheet open (code-inspected only).
- **Claude:** design pass 2 **finished (20:30)** and verified: 119 unit tests, 6 iOS UI tests, Mac and iOS builds with 0 warnings, iPhone screenshots `docs/screenshots/design-2-*` (en/fr/es/dark). **Claude is not editing any file now.** What it changed:
  - Store: `renameFolder`, `deleteFolder` (contents move up; the row stays as a sync tombstone), `scopeCounts`, `StoreError.folderNotFound`.
  - `LibraryModel`: folders, counts, `sortOrder` (remembered), `currentFolderID` (imports go to the folder shown; from the iPhone home, to the root), `recentItems`, `open(_:)` / `homeDocument`, `isShowingScanner` / `isShowingSettings`.
  - `RootView`: sidebar counts (`.badge`), a Folders section with + / Rename / Delete Folder…, the iPhone home on compact width (`LibraryHomeSections` in the new `LibraryHome.swift`), and `LibraryPresentations` (file importer, camera, Settings, errors, password prompt) attached once at the root.
  - `LibraryView`: scope titles, item count (Mac subtitle), sort menu, tiles per the mockup with a ⋯ menu (same actions as the context menu, plus Move to Folder), empty-folder state; `CaptureActions` is shared with the home.
  - `Theme.libraryBackground` (white library; the editor keeps the gray canvas). Seeder `--folder`.
  - **Why the odd bits:** see the "Found and fixed" notes in TEST_MATRIX.md (buttons and the Recent row sit in section headers; documents from Recent push over the home).
- **Claude: design pass 3 (Export sheet) finished at 21:00. `ExportSheet.swift` is free.** What changed: `ExportSheet` (tiles via `ChoiceTile`/`ChoiceTileStyle`, destination first: Save / Copy / Share), `Clipboard.write(files:)`, 7 new strings (`export.destination*`, `export.copy.unavailable`, `export.copied`), two new UI tests, and the layout test now checks `export-format-pdf`. `SaveExportedFiles` is unchanged (Settings still uses it). Tiles sit inside Form rows with their own button style and inset row edges; see the comments there.
- **Claude: design pass 4 (document view) finished at 21:30. `DocumentView.swift` is free; Claude is not editing anything.** What changed: `DocumentModel.rename(to:)` / `setFavorite(_:)`; the title `▾` menu (`.toolbarTitleMenu`: Rename / Favorites / Export); on iPad `.toolbarRole(.editor)` with rotate/crop/filter as `.secondaryAction` (Mac: `.principal`), Export + `⋯` (add/replace items, Delete Page) as `.primaryAction`; the page column's `+` (same add/replace menu, `strip-add-pages`); iPhone `filterStrip` (`editor-filter`, `filter-original|grayscale|blackAndWhite`); `PageFilter.title`. No new strings. New UI test `testFilterStripAndTitleMenu` (it restores the filter and favorite, because `testSidebarNavigation…` expects "No Favorites").
- **Claude: pass 7 (Apple Pencil on iPad, first slice) finished at 22:50. Claude is not editing anything.** New: `InkConversion.swift`, `InkCanvas.swift` (iOS), ink in `PageRenderer`/`Exporter`, `LibraryStore.applyObjectChanges`, `DocumentModel.changeInk`/`selectedPageObjects`, `PageImageView(includesInk:)`, Markup + Draw with Finger toggles in the iPad toolbar, strings `page.markup`, `page.drawWithFinger`, `undo.ink`, plural `ink.strokeCount`. `InkPoint.pressure` was renamed `widthScale` (width relative to the stroke). Tests: `InkRenderTests`, `InkExportTests`, `ObjectChangeTests`, `InkConversionTests`, workflow `inkChangesUndoRedoAndSurviveRelaunch`, and the iPad UI test `testMarkupWithFingerDrawingSavesAStroke` (run it with `scripts/ui-test-ios.sh 62328381-19FB-400A-A8FC-4F4AD13EB5C4 -only-testing:PaperNest-iOSUITests/AppUITests/testMarkupWithFingerDrawingSavesAStroke`; it skips on iPhone). Limitations and what's next are in `CLEAN_NATIVE_DESIGN.md` → pass 7. **Follow-up (23:45, Claude, files `InkCanvas.swift`, `DocumentView.swift`, the Markup test in `AppUITests.swift`):** ink undo moved to the document's undo history so the palette's Undo/Redo work (iPad test passes, also after a pinch-zoom); zoom buttons hidden while marking up.
- **iPad simulators exist** (iOS 26.5 and 27.0 runtimes): e.g. iPad Air 13-inch (M4) `62328381-19FB-400A-A8FC-4F4AD13EB5C4`. Screenshot with `xcrun simctl io <udid> screenshot <file>`. Screens: `docs/screenshots/design-4-ipad-*`.
- **Next, in order (any agent):** (1) a **visual check of the Mac app**, which no one has viewed (library, document window, export sheet, File > Import, Replace Page); (2) **Apple Pencil, next slices:** a check with a real iPad and Apple Pencil (feel); document-level undo for ink after leaving Markup; drawing on iPhone (finger) and Mac (mouse/trackpad); a custom palette if the owner wants the mockup's look; (3) the page column's selected page as a blue border instead of the system highlight (keep drag-to-reorder and keyboard selection); (4) a search field on the iPhone home; (5) ⋯ menus on Recent cards; (6) drag documents onto sidebar folders; (7) post-scan review screen (pass 6) needs a device for the camera.
- If you see no update from Claude for a while and the owner tells you to continue, take over Claude's pass from its status in `CLEAN_NATIVE_DESIGN.md` → "Work plan".

### Repository state

- **Committed on 2026-10-22 at the owner's request.** The current commits and branch are in "Start here" at the top of this file; the notes below are from before that.
- Historical note, from before that commit: nothing was committed since `cdbf280` (Settings), and the working tree mixed three things:
  1. Claude's **rescan / replace page** work (verified: 115 unit tests, 3 iOS UI tests, Simulator end to end).
  2. Codex's **Clean & Native pass 1** (`Theme.swift`, `LibraryView`, `DocumentView`, `PageImageView`, `AppUITests`, `docs/CLEAN_NATIVE_DESIGN.md`, `docs/screenshots/clean-native-*`, `AGENTS.md`).
  3. The design reference mockups in `docs/design/mockups/`.
- On the combined tree at 18:52: `./scripts/test.sh` **passed, 115 tests**. `scripts/ui-test-ios.sh`: **passed, 4 UI tests** (including Codex's layout-switch test).
- Don't commit unless the owner asks (they asked on 2026-10-22; see above). At 20:40 Claude asked the owner for a checkpoint commit of the combined tree (rescan + pass 1 + pass 2) before pass 3, so each agent's later work is its own diff. Check `git log` to see whether it happened.

### Do not undo (each one fixed a real bug)

- `DocumentView`: `filePurpose` and `isShowingFilePicker` are **separate** state. The `fileImporter` binding clears its value *before* `onCompletion` runs, so folding the purpose back into the presented flag turns "Replace Page" into "Add Pages".
- `scripts/build-ios-sim-app.sh` builds the **Xcode project's** app (`com.example.papernest`). A hand-assembled bundle has no `__TEXT,__entitlements` section, and every file picked in the Simulator then fails with "Could not resolve bookmark… permission".
- `LibraryStore.replacePage` / `revertPageReplacement` / `reapplyPageReplacement` are single transactions. `SQLiteDatabase.transaction` nests as savepoints, so keep store operations composable rather than re-adding separate commits.

### Notes for the Export sheet pass (Codex)

- `AppUITests.testLibraryLayoutSwitchStillOpensDocumentsAndEditingTools` ends with `app.segmentedControls.buttons["PDF"]`. Update that assertion when the formats become tiles (give each tile an identifier such as `export-format-pdf` and an `accessibilityValue` of selected/not selected).
- `SaveExportedFiles` is also used by `SettingsView` (backup); `testSettingsShowsTheLibraryAndExportsABackup` covers it.
- Seed a screenshot library with folders: `scripts/swift.sh run papernest-seed <lib> <files…> --folder "Receipts"` (new option). The iPhone Simulator 63992C10-… opens `-PaperNestLibraryPath /tmp/pn-design-lib` (already seeded, 5 documents, 2 folders). On this single-display device, `simctl io … screenshot` must be run **without** `--display=primary`.

### Shared files, to avoid collisions

- `Localization.swift` and the three `Localizable.strings` files: `LocalizationTests` fails on keys that are declared but unused. Add keys in the **same change** as the code that uses them, in a block commented with your pass name (`// Design pass 3: export sheet`).
- `AppUITests.swift`: add new tests at the end; don't reorder existing ones.

### Design rules (details in `docs/CLEAN_NATIVE_DESIGN.md`)

- The mockups are in `docs/design/mockups/` (PNG and WebP), with a text description of every screen in the design doc in case you can't open images.
- Match the look for features that **exist**. Leave out entirely, with no disabled placeholders: iCloud "Synced" status, the cloud button, the OCR button, the "Searchable text (OCR)" toggle, Word and Plain text export tiles, pen/Pencil tools, New note, a Notes tab, Cleanup and custom camera modes. Each of those arrives with its milestone.
- The mockups' sidebar section called "Notebooks" is implemented as **Folders** (notebook is a separate M3 item kind). That was Claude's call, not the owner's.

## Session 1 (2026-10-20) — history

*Kept for the decisions and fixes it records. Its test counts and "next work" list are from that date; the current ones are in "Start here" at the top.*

### Completed

- Inspected the environment. At the start: no Xcode, Command Line Tools 26.2 (Swift 6.2.3, macOS 26.2 SDK), not a git repository. I ran `git init`. The initial commit was made at the owner's request on 2026-10-21.
- Decisions recorded in ARCHITECTURE.md:
  - SQLite as the only metadata authority, with content-addressed immutable assets
  - CKSyncEngine planned for sync
  - Native macOS app, not Catalyst
  - iOS 17 / macOS 14 minimum
  - No third-party dependencies
- M0 foundation and the M1 Mac path:
  - Swift package modules for Core, Store, Import, Render, Export and UI
  - Dev build scripts for Mac and iOS Simulator
  - 87 passing tests (105 cases)
  - en/fr/es localization with parity tests
  - Synthetic samples
  - XcodeGen spec, Info.plists, entitlements and a privacy manifest
  - All required docs
- After the owner accepted the Xcode 27.1 license:
  - Tests pass under Xcode.
  - Thread Sanitizer passed ×4 and Address Sanitizer ×1, both clean.
  - The first iOS compile (Simulator and device) succeeded with 0 warnings.
  - The iPhone app runs in the Simulator, and its screens were verified from screenshots (`docs/screenshots/`).

### Fixed this session

- **Redo was broken.** Undo handlers registered their inverse inside an async Task. The inverse is now registered synchronously (`DocumentModel`). Tested.
- **Permanent delete could destroy an original that an undoable page deletion still needed.** Pages are now soft-deleted (`pages.deleted_at`, schema **v2**) until `purgeDeletedPages` runs at the next launch. Tested, including the v1→v2 migration.
- **iPhone layout:** the document view now shows the page full width with a thumbnail scroller and bottom-toolbar actions; reordering is in a Pages sheet.
- **Export sheet:** it was clipped on iPhone, and option values truncated in French and Spanish. It now uses inline option rows on iOS.
- **Shortcut clash:** ⌘E clashed with "Use Selection for Find", so Export is now ⇧⌘E.
- **Rescan / replace a page** (2026-10-21): Rescan Page (camera), Replace Page with File… (all platforms) and Scan Pages (add camera pages to a document). The page keeps its place, the look carries over and the geometry resets, with undo/redo. Schema **v3** `page_content_history` keeps the old scan until the next launch. Picker failures now show an error. Replace + extra pages commit in one transaction (`LibraryStore.replacePage`; `SQLiteDatabase.transaction` nests as savepoints). **Verified end to end in the Simulator with Replace Page with File…** after fixing replace-became-add (picker purpose cleared by the `fileImporter` binding) and switching `build-ios-sim-app.sh` to the Xcode project's app (the old hand-built bundle had no entitlements section, so file picks failed). 8 new tests (115 total). The camera path still needs a device.
- **Settings** (2026-10-21): storage figures, Export All Documents (ZIP of PDFs) as a backup, language, version and privacy note. iPhone/iPad open it from the ⋯ menu, the Mac from ⌘,. No login or profile, as the brief requires. 4 new unit tests (107 total) and a UI test (3 UI tests in total, now `AppUITests`).
- **Crop tool** (2026-10-21): editor sheet, ⌘K, toolbar buttons, undoable `setCrop`, a thumbnail-cache key that includes the transform, dark underlays so the frame shows on white paper, and a VoiceOver value. Review then found that filtered PDF pages with tight crops failed to render or export; they now rasterize only the crop. 15 new unit tests (102 total), plus the first UI-test target (`PaperNest-iOSUITests`, run with `scripts/ui-test-ios.sh`), whose crop drag test passes.
- **`scripts/test.sh`** failed under Xcode (bash 3.2 empty-array bug).
- **Build output and built apps** moved out of the iCloud-synced checkout. `codesign` was rejecting test bundles there, iCloud broke app signatures after signing, and it was creating "debug 2" conflict copies.

### Status

| Area | State |
|---|---|
| Core/Store/Import/Render/Export | Automated tests passed (macOS); sanitizers clean |
| Mac app | Builds, launches, opens a library. **UI not visually verified** (the owner declined Claude's control of the app). |
| iPhone app | Builds for Simulator and device. Library, document and export screens **Simulator verified (screenshots only, no taps)** in en/fr/es. |
| iPad | Compiles. **Layout not verified**: the installed iOS 27.1 runtime only supports the "iPhone Duo" simulator. |
| Xcode project | Generated with XcodeGen 2.46.0; both app schemes build (Simulator / Mac, no signing team yet) |
| Sync, notebook editor, OCR, DOCX/TXT, subscriptions | Not started (designs in ARCHITECTURE.md) |

### Waiting on the owner

1. Recommended: **move the project out of the iCloud-synced Desktop** (for example to `~/Developer/PaperNest`). iCloud has already made conflict copies inside build folders and could do the same inside `.git`. Moving the whole folder keeps the git history. The build cache path follows the checkout, so a move just starts a fresh cache.
2. A manual look at the **Mac app**: the checklist is in TEST_MATRIX.md. Or allow Claude to control the dev build.
3. Apple Developer team, bundle ID and iCloud container, before M2 (APPLE_SETUP.md).
4. Optional: an iPad simulator runtime (Xcode > Settings > Components) for iPad layout checks.

### Simulator used

"PaperNest iPhone Duo", UDID `F5269418-AA12-4CF9-8EE4-6B6B89F228B8` (iOS 27.1), created for this project on 2026-10-21. The first one, and every other iOS 27.1 simulator, disappeared overnight for reasons outside this session. Its library is seeded with `Samples/` plus a cropped "Cropped-whiteboard". Delete it with `xcrun simctl delete F5269418-AA12-4CF9-8EE4-6B6B89F228B8` when it's no longer needed. The device has two displays; screenshot with `--display=primary`.

### Next commands

```bash
git log --oneline | head                     # initial commit on main
./scripts/test.sh                            # expect 115 tests passing (5 per-target runs under Xcode)
./scripts/ui-test-ios.sh                     # iOS UI tests, headless in the Simulator (expect AppUITests to pass)
xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build
./scripts/build-ios-sim-app.sh               # Xcode-project app (com.example.papernest); then: xcrun simctl install <udid> <path>
./scripts/run-mac-app.sh /tmp/pn-dev         # dev Mac app with a seeded throwaway library
```

### Next work, in order

1. Crop: **done on iPhone** (UI test passes). Remaining: a manual check of the Mac drag, and VoiceOver resizing (it can only reset today).
2. A real-device camera test (Scan Pages, Rescan Page, multi-page capture) completes the M1 gate. Rescan is implemented and the file path is Simulator-verified. Also do a Mac check of Page > Replace Page with File….
3. Exercise taps in the Simulator: the Pages sheet reorder, filters, the adjustments sheet, export and save.
4. Polish: on iOS, inline option rows show their label as a plain row; consider section headers.
5. Start M2: the v4 migration (`sync_state`, `outbox`, `tombstones`), then the CKSyncEngine adapter.

### Open risk

- A one-off iPhone navigation glitch (thumbnail tap → Favorites, then stuck). The sidebar binding was corrected, but the fix is unproven and the glitch didn't reproduce (TEST_MATRIX.md).

- One unexplained SIGSEGV in one test run, on an intermediate build (TEST_MATRIX.md, "Open issue"). Not reproduced in 11 later runs or under the sanitizers.

### Notes for whoever continues

- SwiftUI's `LibraryItem` type clashes with ours; write `PaperNestCore.LibraryItem` in SwiftUI files.
- PDFKit `dataRepresentation()` of an unlocked encrypted PDF stays encrypted. The importer copies the pages into a new document instead (see `PDFInspector`).
- ImageIO happily decodes truncated JPEG/PNG files, which is why the importer checks their structure itself.
- Under Xcode 27, `swift test` runs each test target in its own process and code-signs the bundles.
