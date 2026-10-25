# F3b — Markup colors and saved-mark controls

Owner: continue implementing the existing pipeline. Proceed inline in the current checkout because the required F3a changes are uncommitted here; preserve them and do not commit.

## Design and scope

Keep the native SwiftUI forms, system type, semantic backgrounds and blue actions. Add compact named color swatches and the system custom color picker to Annotate Text. Keep existing default style colors until the user chooses a color. New marks retain the selected sRGB color through persistence/export.

Add More → Manage Markup on iPhone/iPad/Mac. Show existing ink, including legacy annotations and freehand strokes, as numbered rows with small stroke previews, color and selection state. A page preview outlines selected marks at their source-space positions after crop/rotation. Multi-select marks, Apply Color or Remove Selected. Opening, selecting and closing make no writes. Edits commit atomically, keep the sheet open, refresh the page, and register one existing document undo step. Existing iPad PencilKit behavior remains unchanged. No inferred OCR annotation labels or new storage schema are needed.

Word-level text selection, text comments and notebook creation remain later slices.

## Task 1 — Durable color and ink edits

- [x] Write failing tests for custom colors, invalid components, atomic recolor/delete, stale page/object snapshots, mixed/foreign selections and preserving unrelated text/ink/OCR.
- [x] Add an optional color argument to text markup generation/store API; validate components.
- [x] Add `InkEdit` (recolor/remove) and store `editInk(on:expectedRevision:objects:edit:)`, comparing exact object snapshots inside the transaction and returning previous/saved objects for undo. Guard live item/page, nonempty unique IDs, ink-only matching objects. One revision bump.
- [x] Run focused tests, then full suite.

## Task 2 — Model and native controls

- [x] Model color forwarding and undoable edit API; workflow test verifies recolor/delete undo/redo, reopen and exported pixels.
- [x] Reusable preset/custom color picker; Annotate Text color input; Manage Markup sheet with selected-mark preview, multi-selection, actions, empty/loading/error/stale states and duplicate-action guard.
- [x] en/fr/es labels and accessibility identifiers; stable Mac sheet sizing and no nested-navigation confirmation toolbar.
- [x] Keep cropped-out marks manageable, but clip their preview outline to the displayed page. Use PageGeometry only.

## Task 3 — Verification and handoff

- [x] Add UI test with its own synthetic library: color creation, selection/cancel, recolor, removal, persistence; exercise en/fr/es. Retest existing annotation and iPad ink workflow.
- [x] Full unit suite, Mac build, focused iPhone/iPad UI tests. Inspect screenshots. Native Mac interaction only if proper UI tools are available; otherwise document unrun.
- [x] Independent review, fix substantive findings, update TEST_MATRIX/roadmap/README/handoff and release file claims. No commit.

## Review focus

Stale editor snapshots must not erase or overwrite unseen edits; mixed invalid selections must not partially apply. Preserve IDs/z-order/points on recolor, non-ink objects on both actions, OCR currency and originals. Undo must restore exact objects in either direction. UI selection must identify actual persisted objects, not row indices, and clear when reloaded after stale-data rejection. Color controls must not silently produce transparent/invisible marks or misreport the saved color. Cropping/rotation and old ink must continue to work.

## Execution record

- Plan created before implementation. Tests will target real store/model/render behavior, with logs under `/tmp/papernest-f3b-*`.

- Task 1/2: APIs ran red (missing color/edit APIs); green focused store/core tests, then full suite 233 passed (46 UI +75 Store +47 Import +26 Export +39 Core), no compiler warnings. Logs `/tmp/papernest-f3b-store-red.log`, `-store-green.log`, `-model-red.log`, `-unit-first.log`. Model workflow covers persistence, undo/redo and actual exported blue pixels.
- Implemented colors and saved-ink manager without schema or PencilKit changes. The manager includes older annotation/freehand strokes; selection never infers OCR identities. Initial iPhone UI checks passed; independent reviewer James found the two issues below.

- Review fixes: atomically validate ink inverse snapshots and absent IDs, preserve unrelated edits, reject conflicting undo/redo with refresh/error and discard invalid history. Manager now observes session changes and guards cancelled/overlapping loads. Conflict tests reproduced the three overwrites before the fix, then passed. Final suite: 235 tests; final Mac build passes. iPhone manager passed again after fixes. Independent reviewer follow-up hit a usage limit; no final independent sign-off claimed. iPad manager/color flow in en/fr/es and existing drawing/undo/redo/reopen both pass (2/2). Manager screenshots inspected on iPhone/iPad in all three languages. TEST_MATRIX, README, roadmap and handoff updated; claims released. No commit or push made.
