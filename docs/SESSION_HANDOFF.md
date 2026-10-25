# Session handoff

## Work division — read this before you touch anything

Two agents share this one working tree. On 2026-10-22 both were editing it at the same time and a `git add -A`
swept Codex's in-flight work into commit `5abebea` under a Claude message. Codex recorded the same event from its
side. The commit is kept as it is; these rules exist so it does not happen again.

### Rules for both of you

1. **Claim your files in "Current claims" below before you edit them.** First run `ls -lT` on them. If anything
   changed in the last few minutes, stop and re-read this page: the other session may still be running.
2. **Never `git add -A`.** Stage by explicit path, and only paths you wrote.
3. **Commit only when the owner asks.** They asked on 2026-10-22; the current branch is
   `document-tools-ocr-and-file-items` and there is no remote.
4. **Verify before you claim anything works**, and record the real outcome in `docs/TEST_MATRIX.md`. Never mark an
   unrun check as passed.
5. **Shared files** — `Localization.swift`, the three `Localizable.strings`, `Apps/iOS/UITests/AppUITests.swift`,
   `scripts/ui-test-ios.sh` — are touched by nearly every slice. Add keys in the same change as the code that uses
   them, in a block commented with your slice name, and append UI tests at the end of the file without reordering
   the existing ones.

### Who takes what

| | Area | Targets |
|---|---|---|
| **Claude** | Engine and data: schema and migrations, store APIs, composition, import/export, rendering, OCR, and anything security-sensitive (archives, encryption, redaction) | `PaperNestCore`, `PaperNestStore`, `PaperNestImport`, `PaperNestExport`, `PaperNestRender`, their test targets |
| **Codex** | Interface: views, navigation, the Clean & Native design passes against the owner's mockups, XCUITest flows, screenshots and layout checks in en/fr/es | `PaperNestUI`, `Apps/iOS/UITests`, `docs/CLEAN_NATIVE_DESIGN.md` |

Most slices span both. The agent who owns the **workstream** writes the thin layer it needs on the other side and
says so in Current claims — that is how the ZIP work below has a `LibraryModel.extractArchive` in it, and how the
file-preview work has a `FileKind.prepareTemporaryCopy` in it.

### Current claims

**Codex finished and released page comments — 2026-10-25:** private page comments are implemented through **More → Comments** on documents/notebooks. Add/edit/delete, cancel, guarded undo/redo and duplicate/reopen persistence. Schema **v7** widens page_objects to include comments; next migration must be v8 or later. Comments do not change rendered page revisions/OCR and are explicitly excluded from PDF/image exports. Conflict drafts remain open with **Save as New Comment** to preserve both versions. New PageComments.swift, PageCommentsSheet.swift and PageCommentDraft.swift plus store/model/UI/migration/localization/test/docs changes. Qwen-reserved sheets untouched. **254 unit tests**, final Mac build and focused iPhone/iPad workflows in en/fr/es passed; six screenshots inspected. Fresh review found mixed-history and stale-draft recovery issues; fixed with red→green regressions and full suite (no re-review claimed). Native Mac interaction, actual multiwindow conflict UI, VoiceOver/large type, real devices and injected I/O-failure UI remain unrun. Details: `docs/TEST_MATRIX.md`; plan: `docs/superpowers/plans/2026-10-25-page-comments.md`. Local commit titled **Add private page comments with guarded undo and draft recovery** follows 2e64487; no push. All files released and no test command remains active. Next feature slice: shapes/stamps or word-level markup; exported/positioned PDF comment annotations remain separate work.

**Codex finished and released additional notebook pages — 2026-10-25:** checkpoint `7444b4d` saved all prior work at the owner’s request. This feature is saved in the separate commit titled **Add notebook template pages with guarded undo and redo** on `document-tools-ocr-and-file-items`; no push (no remote). Notebooks support blank/lined/grid A4 insertion after selection, cancel, selection after durable save, and conflict-safe undo/redo. All document history callbacks now share one queue; fresh page edits wait for pending history. Three timing issues were reproduced and fixed; final independent review found no remaining actionable issues. **245 unit tests**, final Mac build, localized iPhone/iPad notebook flows and existing iPad drawing/undo/redo/reopen passed. Final-source iPhone run includes all fixes; exact intermediate/final run scope is in TEST_MATRIX. Six en/fr/es screenshots inspected and saved. Native Mac interaction, real-device Pencil/camera, VoiceOver, large type and injected save-failure UI remain unrun. New files: NotebookPages.swift, NotebookPageSheet.swift and two test files; shared model/view/localization/UI-test/docs updates. Qwen-reserved sheets untouched. Plan/decisions: `docs/superpowers/plans/2026-10-25-notebook-pages.md`. No test commands or edits remain active for this slice. Continue with remaining notebook/planner or F3 work from the roadmap; do not repeat this implementation or its checkpoint.

**Codex finished and released notebook-creation files — 2026-10-24:** Tools → New Notebook creates a named, one-page A4 notebook with blank/lined/grid paper in the current folder, then opens the existing editor. 236 unit tests, Mac build, iPhone creation/relaunch + Tools merge, and iPad creation/relaunch passed. No compiler warnings in unit/Mac runs. New NotebookCreationSheet.swift and NotebookCreationTests.swift; updates to LibraryModel, ToolsSheet, localization and appended AppUITests. Qwen reservations untouched. No commit/push. Further template pages/planners and native Mac/localized visual checks remain. See TEST_MATRIX for logs and limits. No commands or edits remain active for this slice.

**Qwen queue prepared; Codex released its files — 2026-10-24:** the owner asked for work sized to a Qwen 9B model. Start at `QWEN.md` and `docs/QWEN_HANDOFF.md`; progress is `docs/qwen/PROGRESS.md`. Q1 = saved-mark Select All/Deselect All; Q2 = recognized-line Select All/Deselect All. This reserves `MarkupManagerSheet.swift` then `TextAnnotationSheet.swift`, with appended XCUITests and separate synthetic fixture copies. **Reservation only: Qwen is not running and has not claimed or implemented either task.** Other workers should avoid starting these two tasks unless the owner reassigns them. Qwen must claim the current card's files when it actually starts. Higher-risk engine work stays with Claude/Codex. The interrupted next-feature turn made no app changes. This preparation changed documentation/startup pointers only; no model install, launch, server change, commit, push or new app-test claim. Local Ollama listed `qwen3.5:4b`, not 9B; do not silently substitute model identities.

**Codex finished and released all files — 2026-10-24, F3b:** preset/custom annotation colors and selection/recolor/removal of saved ink are implemented. New `InkEdit.swift`, `InkEditStore.swift`, `MarkupColorPicker.swift` and `MarkupManagerSheet.swift`; updates to text markup/store APIs, `DocumentModel.swift`, `DocumentView.swift`, `TextAnnotationSheet.swift`, localized strings, tests, UI seed script and docs. Existing uncommitted work is retained; no commit or GitHub push made. Plan: `docs/superpowers/plans/2026-10-24-markup-controls.md`. Final **235 unit tests**, Mac build, iPhone manager flow and iPad manager + PencilKit flows pass; en/fr/es manager screenshots inspected on both devices. Two review findings (stale undo/redo and manager refresh) are fixed, with conflict regressions. Independent follow-up was unavailable due to the reviewer's usage limit; no final independent sign-off claimed. Native Mac manager/custom-picker and native two-window interaction remain unrun. No Codex edit or test command is running; the next agent may take these files.

**Pipeline follow-up — 2026-10-23:** the owner said **“All features to pipeline including media”** after reviewing the latest converter/media picture. Updated only FEATURE_EXPANSION, REFERENCE_FEATURE_INVENTORY, IMPLEMENTATION_PLAN and this handoff for that request; all four files are released. All identified features are confirmed in scope, including F7a local audio/video/audiobook playback, F7b library/playlists/background/resume, F7c MP3/audio extraction and F7d editable transcription/export. These media features remain planned. This request did not start implementation or change the current delivery order. Preserve the earlier uncommitted application work below.

**Codex finished and released all files — 2026-10-23, 20:36 CDT:** checkout is now **`/Users/karanpatel/Desktop/PaperNest`** (formerly `DOCS PRO`). Audit fixes are uncommitted in `ExportSheet.swift`, `FileItemViews.swift`, `LibraryView.swift`, `ToolsSheet.swift`, and `FilePreviewTests.swift`. Native Mac: Export freeze fixed; text-file Save a Copy extension fixed; Tools Continue fixed and page extraction completed; preview/Info/dismissal and Settings viewed. 219 unit tests and full iPhone suite passed (17 passed, 1 iPad-only skip). Focused tests after the last two Mac fixes passed (3/3); see TEST_MATRIX for exact scope.

**F3a implemented and verified:** recognized-line highlight/underline/strikethrough as ordinary editable ink. Changed `DocumentModel.swift`, `DocumentView.swift`, new `TextAnnotationSheet.swift`, `Localization.swift` plus en/fr/es strings, new Core `TextMarkup.swift`, Store `TextMarkupStore.swift`/`StoreError.swift` and the ink-only `bumpRevision` path in `LibraryStore.swift`, new related tests, and an appended XCUITest plus its seed library. Reuses rendering/export/ink undo; no schema change. Review follow-up also changed `PageRenderer.swift` and new `TextMarkupRenderTests.swift`: preserve exact constant-width marks so small underlines remain visible and contained. Notes, shapes and word-level selection remain later slices; F3b adds custom colors and saved-mark controls below. No commit request was received in this continuation; all changes remain uncommitted. This F3a entry is historical; consult the current F3b claim before editing.

### Next for Claude, in order

1. **A system Inbox folder.** Deliberately not built with Photos import: an Inbox with no inbound channel is just a folder with a special name. It needs
   "Open in PaperNest" (document types and URL handling) first, which is F6 transfer work.
2. **Rest of F4** — recognise text automatically after a scan, offer re-recognition after a rescan, a user
   language override, and pull text out of vector PDFs into the search index (today only recognised text is
   indexed, so a digital PDF is findable by title alone).
3. **F2d** — compression presets with real before-and-after sizes. Note this is *size reduction*, which F2b did
   not do: F2b packs, it does not compress.
4. **RAR extraction**, once the owner settles the licensing question.

### Next for Codex, in order

1. **Finish the remaining Mac audit checks**, including the new annotation sheet, localized fr/es layouts, backup, import/paste, crop/reorder/keyboard and sandboxed save. Representative native Mac library/document/export, Tools extraction, file preview/details/save and Settings checks have now passed; no longer claim the entire Mac app was never viewed.
2. **Continue F3** — word-level selection, stamps, shapes and exported/positioned comment annotations. Private page comments, whole-line marks, preset/custom colors and saved-ink selection/recolor/removal are implemented. Preserve the store snapshot guards and existing PencilKit ink workflow. See the current verification section for exact run scope.
3. **Notebook follow-ups** — creation and additional blank/lined/grid pages are implemented. Planners, text/image editing and richer notebook navigation remain.
4. **Visual fill & sign**, then app lock (device authentication).

### Planned expansion and remaining dependencies

All identified F5–F9 features and M5 subscriptions are in the confirmed pipeline. Resolve dependencies for each implementation slice: F5 editing/conversion engine and licensing, F6 provider credentials/provisioning, F7c codec/encoder licensing, F7d transcription processing choice, F8 object-removal engine, F9 VPN provider/entitlements and M5 pricing/product setup. The details are under "Waiting on the owner".

**F7a/F7b local media playback and library controls are not blocked by the transcription or MP3 decisions.** They remain planned in the existing sequence, with platform/format verification required. Browser/download work likewise has no blanket dependency on the object-removal engine. Scope confirmation does not authorize service purchases, private-document uploads, deployment or publishing; existing constraints still apply.

**Read this page first, then `docs/IMPLEMENTATION_PLAN.md`. The product brief is `CLAUDE_CODE_PROMPT.md` and never changes.**

## Historical snapshot — 2026-10-24 (superseded by Current claims)

- **Working directory:** `/Users/karanpatel/Desktop/PaperNest`. `Desktop/DOCS PRO` no longer exists. Pass the new workdir explicitly if the chat still points at the old path. Build cache is now `~/Library/Caches/PaperNest/build-17de0868e51d`.
- **Branch:** `document-tools-ocr-and-file-items`, HEAD `3d25653`, no remote. The audit, F3a and F3b changes are **uncommitted**. Do not reset them or stage everything indiscriminately. No commit request was received in this continuation.
- **Current schema:** v6 (HEIC assets); general file items use v5. Future sync must use v7 or the next unused migration. F3a/F3b add no migration.
- **Current verification:** 235 unit tests and final Mac build pass. The F3b manager workflow passes in en/fr/es on iPhone and iPad after review fixes, and iPad PencilKit drawing/undo/redo/reopen passes. The earlier iPhone annotation regression also passed. Screenshots were inspected on both devices. Independent review found two multiwindow issues; both are fixed with regression coverage for conflicting undo/redo. Independent follow-up hit a usage limit, so no second reviewer sign-off is claimed. Exact logs and remaining checks are in TEST_MATRIX.

```bash
./scripts/test.sh
./scripts/build-mac-app.sh
./scripts/ui-test-ios.sh 63992C10-33B4-4CE3-91C3-EE23ECC595A5
./scripts/ui-test-ios.sh 62328381-19FB-400A-A8FC-4F4AD13EB5C4 -only-testing:PaperNest-iOSUITests/AppUITests/testRecognizedLinesCanBeMarkedAndKeptAfterRelaunch
```

Do not run two UI seed scripts at once: they reset shared disposable libraries in `/tmp`.

- Simulators in use: iPhone 17 Pro `63992C10-33B4-4CE3-91C3-EE23ECC595A5`, iPad Air 13-inch (M4) `62328381-19FB-400A-A8FC-4F4AD13EB5C4`.
- Screenshot hooks: `-PaperNestDebugOpenItem <name>`, `-PaperNestDebugShowExport YES`, `-PaperNestDebugShowCrop YES`, `-PaperNestDebugShowMarkup YES` (iPad), `-PaperNestDebugShowTools YES`. The last one is new and is **not** yet listed in CLAUDE.md, which is the owner's file.

## F3b implementation details for the next agent

- **Entry points:** document More → Annotate Text now includes five presets and a native custom color picker. More → Manage Markup lists saved ink with stroke swatches, selection state and a page preview outlining selected marks. Select one or more, then Apply Color or Remove Selected. Actions persist immediately; Done only closes. Opening/selecting/closing alone does not write.
- **Storage:** `InkEdit.swift`, optional color in `TextMarkupStyle`/`addTextMarkup`, and `InkEditStore.swift`. `editInk` atomically validates live parent, exact page revision and selected snapshots before recoloring/removing. IDs/z-order/geometry, unrelated objects, current OCR and originals are preserved. Legacy freehand/annotation strokes work without a migration.
- **Undo safety:** `applyInkChanges` checks expected replaced/deleted objects and globally absent IDs before inverse writes. Unrelated mark edits may coexist. Conflicting undo/redo does not overwrite another window: refresh, show the localized changed-page message, and clear this document model's undo actions because the pre-registered inverse is no longer safe. Red/green workflow regression covers recolor undo, removal redo and restoring a reused ID; store coverage checks atomic mixed rejection and foreign-page ID collisions.
- **Live manager:** observes `session.changeToken`; refreshes rows/preview and clears stale selections after another window changes the page. Request IDs and cancellation checks prevent an older load from overwriting a newer snapshot. A change elsewhere in the library preserves the selection when this page is unchanged.
- **Coverage/limits:** real persistence, undo/redo, relaunch and exported blue-pixel tests. Preset controls are exercised by XCUITest in en/fr/es. Custom color components/storage are unit-tested, but manual interaction with the system custom picker and native Mac manager remain unrun. Multiwindow snapshot conflicts are model-tested; a native two-window UI pass remains open. No word-level/semantic annotation labels are inferred from old ink.
- Plan: `docs/superpowers/plans/2026-10-24-markup-controls.md`. Evidence and actual run status: TEST_MATRIX. No commit or push was made.

## F3a implementation details for the next agent

- `TextMarkupStyle.stroke(for:in:)`: full normalized OCR line → source-point vector stroke; yellow highlighter or blue pen. Rounded caps fit within the original box, including narrow boxes. `PageRenderer.drawInk` now bypasses freehand width quantization for constant-width pens: a 0.1-point mark remains visible, and a 1.2-point mark no longer expands to 1.25. A four-case rendered-pixel regression was run red/green. No new object kind or schema.
- `LibraryStore.addTextMarkup`: validates completed OCR, exact saved snapshot, page revision, live parent, line indices and bounds inside one transaction; saves fresh IDs in reading order above current z-order. A changed/rescanned page cannot receive an old selection.
- Object edits now carry forward **only current completed OCR** in `bumpRevision`. This preserves searchable text through annotations and ink undo/redo. **Transform/reorder code still invalidates OCR for rendering through its separate revision path** (existing behavior), although the search index remains. Do not claim this patch fixed every OCR revision issue. Follow-up: carry recognition through source-preserving transforms with explicit regression tests; the old composition stale-result fixture currently uses rotation to make OCR stale.
- `TextAnnotationSheet` is available from each layout’s More menu. It recognizes only the target page if needed, selects whole lines, handles stale-data retry, guards repeated Apply and dismisses only after commit. Marks can be edited with existing iPad ink tools; word-level selection remains follow-up work; F3b now supplies custom colors and dedicated saved-mark controls on all layouts.
- `DocumentModel.addTextMarkup` registers the existing ink inverse under a localized annotation action name. Store/model tests verify undo/redo and reopen; exported PDF pixel geometry and searchable text are checked. UI accessibility reports stroke count on the document image.
- **Potential engine follow-up, code-inspected only:** Settings and bulk archive code still resolve general file assets with `kind: .file`. Preview now resolves the actual asset record. A file item referencing a shared PDF asset may therefore preview correctly yet fail archive/backup. Add a regression before changing those engine paths.
- Plan/checklist: `docs/superpowers/plans/2026-10-23-text-markup.md`. Screenshots: `docs/screenshots/text-markup-*-iphone.png` and `text-markup-*-ipad.png`. See TEST_MATRIX for limitations and review status.

## What works today

Library (import, folders, favourites, sort, rename, trash with 30-day purge, title search, colour labels, multi-select) · document tools (duplicate, merge in an explicit order, extract pages, split into one document per page, export a selection as one ZIP) · a **Tools screen** listing only tools that work · page editing (rotate, reorder, delete, add, crop, filters, undo/redo, rescan with history) · Apple Pencil ink on iPad · **whole recognized-line highlight/underline/strikethrough** with preset/custom colors, saved-ink selection/recolor/removal and undo · **text recognition** (Vision, en/fr/es) with search over recognised text · **searchable PDF export** · **file items**: any file type kept as itself, with a type symbol, its size, a **QuickLook preview** from the library and from Recent, a details sheet, Share and Save a Copy · **ZIP extraction** that refuses anything unsafe, and **archiving a selection** (documents as PDFs, files byte for byte).

Evidence for every claim is in `docs/TEST_MATRIX.md`, newest rows first. Capability coverage against the owner's reference screenshots is `docs/REFERENCE_FEATURE_INVENTORY.md` (48 rows).

## Traps found the hard way — read before touching these

- **The title menu's button is labelled `"<name>, Actions Menu"`.** Match it by label prefix with an existence check. An exact match on the name misses it, and the `staticTexts` fallback is not reliably present — a test written that way passes on luck.
- **Restart the simulator before investigating a spread of unrelated UI failures.** One run showed three, including an app that would not launch at all; all passed after `simctl shutdown` and a clean boot.

- **QuickLook supplies its own Done button only when it presents itself.** Inside a SwiftUI sheet or cover, SwiftUI owns the presentation, so install the dismissal yourself (`file-preview-done`).
- **Temporary copies have an owner.** Await `FileKind.prepareTemporaryCopy`, retain its `PreparedFileCopy` for the entire preview/share/save lifetime, and let it clean up its own directory on release. Do not delete on `onDisappear`: child presentations can cover the parent. Info reuses the preview copy. Never give Quick Look the immutable asset path.
- **Recent previews belong to RootView.** A presentation modifier on the empty List sections in `LibraryHomeSections` did not present. The home callback now sets `RootView.homeFilePreview`.
- **A known Simulator flake:** *"test runner exited with code 0 before establishing connection"* fails a run before any test executes. Rerun once before investigating; it has never reproduced twice in a row here.

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

## Tools screen continuation verification — 2026-10-24

The resumed chat referenced the old DOCS PRO checkout and unfinished Tools toolbar verification. The current checkout is Desktop/PaperNest; the existing 2026-10-23 Tools fixes were preserved. No application source changes were needed in this continuation.

- Full `./scripts/test.sh`: 235 tests passed (47 + 76 + 47 + 26 + 39); no compiler warning/error matches in the log. Log: `/private/tmp/papernest-tools-resume-tests.log`.
- iPhone 17 Pro: `testToolsScreenPicksTwoDocumentsAndMergesThem` and `testAFolderMadeInTheSidebarHoldsAMovedDocument` both passed, 0 failures; `TEST SUCCEEDED`. Log: `/private/tmp/papernest-tools-resume-ui.log`. Result: cache `build-17de0868e51d/xcodeproj/Logs/Test/Test-PaperNest-iOS-2026.10.24_13-10-01--0500.xcresult`.
- This run covers Tools merge and the folder regression on iPhone. It does not newly verify iPad, Mac UI, all Tools actions, or real camera access. Xcode emitted operating-system-build parsing diagnostics after the successful tests.
- Existing work and Qwen reservations remain intact. No commit or push. No test process remains active from this continuation.
