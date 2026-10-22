# File tools implementation plan

> For agentic workers: use the executing-plans or subagent-driven-development workflow task by task. The owner explicitly requested implementation in Codex. Do not commit without a separate request.

**Goal:** Deliver the first working slice of the nine-photo expansion: document selection, duplication, merge, page extraction and color labels.

**Architecture:** LibraryStore performs atomic edits and returns durable results. Composition creates fresh document/page/object IDs referencing existing immutable assets; LibraryModel publishes after commit. Existing library menus and a native sheet expose the operations, without a placeholder Tools dashboard.

**Tech Stack:** Swift 6, SwiftUI, SQLite, Swift Testing, XCUITest; no added dependencies.

**Spec:** `docs/FEATURE_EXPANSION.md`, F1; `docs/CLEAN_NATIVE_DESIGN.md`.

## Global constraints

- iOS 17 / macOS 14 minimum; iPhone, iPad, native Mac; en/fr/es through L10n.
- LibraryStore is the metadata authority, originals immutable, UI changes after commit.
- PageGeometry remains the coordinate mapping. Copy current ink/text/image objects without flattening them.
- Preserve the existing uncommitted InkCanvas change. Do not change the original product brief.
- Builds outside the iCloud checkout; use project scripts. No simulated functionality.

## Review focus

- Source deletion or missing assets during composition must leave no partial document.
- Selected pages from a different document, deleted pages and duplicate IDs must be rejected.
- Copies must survive original deletion without sharing mutable ink/text object IDs.
- Selection must not silently change the merge order after sorting or refreshing.
- Long names and large translated controls must fit or scroll; failed saves must keep the sheet open.

## Tasks

### 1. Durable composition (worker)

Files: create `Sources/PaperNestStore/LibraryComposition.swift`, `Tests/PaperNestStoreTests/DocumentCompositionTests.swift`.

Interfaces: `duplicateItems(_ ids: [ItemID]) throws -> [LibraryItem]`; `mergeItems(_ ids: [ItemID], named: String, folderID: FolderID?) throws -> LibraryItem`; `extractPages(_ pageIDs: [PageID], from: ItemID, named: String) throws -> LibraryItem`.

- [ ] Add failing tests for order, new identities, editable objects, rollback, invalid/deleted sources and independent lifetime after deleting originals.
- [ ] Implement using the actor's nested SQLite transaction and existing create/page/object APIs. Duplicate/extract retain color labels; merge starts unlabeled.
- [ ] Run `./scripts/test.sh --filter DocumentCompositionTests`; require zero failures.

### 2. Color labels (main)

Files: `LibraryModels.swift`, new `LibraryColors.swift`, `Schema.swift`, `LibraryStore.swift`, new `ColorLabelTests.swift`.

Interface: optional `LibraryItem.colorLabel: ItemColor?`; `setColorLabel(_ color: ItemColor?, for ids: [ItemID]) throws`.

- [ ] Test v3 migration, set/remove/relaunch and all-or-nothing batch edits with missing/deleted IDs.
- [ ] Add v4 nullable constrained column and seven stable color values; update item decoding and batch write.
- [ ] Run `./scripts/test.sh --filter ColorLabelTests`; require zero failures.

### 3. Real library actions (main)

Files: `LibraryView.swift`, `LibraryModel.swift`, new `DocumentToolsSheet.swift`, localization resources, `Apps/iOS/UITests/AppUITests.swift`.

- [ ] Add selection mode and explicit selection indicators, clear/prune selection on scope/query changes.
- [ ] Single-item menu: Duplicate, Extract Pages, Color Label. Bulk menu: Duplicate, Merge, Move, Color Label, Delete (soft delete).
- [ ] Merge sheet snapshots selected items in visible order, permits reordering and naming, then creates/opens the merged document. Extraction sheet selects source pages and creates/opens a new document. Keep sources intact, disable submission during commit, retain errors in the presented sheet.
- [ ] Add a real iOS workflow test using synthetic documents: duplicate, select/merge, then select/extract pages and verify resulting counts/content. Color state is exposed through accessibility text.
- [ ] Run full unit tests, Mac/iOS builds and UI tests, inspect screenshots. Record exact outcomes and remaining work in TEST_MATRIX and SESSION_HANDOFF.

Follow-up F1: ~~per-page splitting~~ and ~~bulk archive/share~~ — **both done 2026-10-22** (`LibraryStore.splitItem` + `DocumentSplitTests`; `BulkExportModel`/`BulkExportSheet` + `BulkExportTests`; one iPhone/iPad UI test each). **F1 is complete as scoped.** Later workstreams remain tracked in the expansion spec.

## Verification (Claude, 2026-10-22, no source files edited)

Tasks 1–3 are implemented in the working tree. The checkboxes above are left as Codex set them; this records what was actually run, and the full detail is in `docs/TEST_MATRIX.md` ("F1 document tools" row).

- Task 1 and 2 test gates: covered by the full run — `./scripts/test.sh` **passed, 144 tests**, 0 failures, 0 compiler warnings, including `DocumentCompositionTests` and `ColorLabelTests`.
- Task 3: `./scripts/build-mac-app.sh` and the `PaperNestUI` iOS Simulator build **passed with 0 warnings**; `scripts/ui-test-ios.sh 63992C10-…` on iPhone 17 Pro **succeeded, 11 tests** (Markup skipped as designed); the nine en/fr/es screenshots the localized test captures were exported and inspected (no truncation).
- Both new UI tests failed on iPad at first (iPhone-only `page-thumbnail-1`; app-wide `staticTexts` matching the library grid behind a form sheet). **Fixed on the owner's instruction and re-verified: iPad `TEST SUCCEEDED`, both tests**, and everything above was re-run green afterwards. **Open question:** the grid's tile name texts should not have been matchable under `.accessibilityElement(children: .ignore)`, so selection mode still deserves a VoiceOver check.
- **Review focus not covered:** a long document name in the merge and selection UI; a failed save keeping the sheet open (code-inspected only); the whole feature on the Mac.
