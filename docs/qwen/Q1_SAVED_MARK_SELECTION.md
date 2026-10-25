# Q1 — Bulk selection of saved marks

Status lives in PROGRESS.md. Run this card before Q2. No product implementation exists yet.

**Goal:** In More → Manage Markup, select every saved mark or clear the selection with one tap. Existing recolor/removal works on that selection.

**Allowed code files:**
- `Sources/PaperNestUI/MarkupManagerSheet.swift` — one new local-selection control.
- `Apps/iOS/UITests/AppUITests.swift` — append `testSavedMarkupBulkSelection`; retain all existing tests.
- `scripts/ui-test-ios.sh` — add only the dedicated synthetic library copies below.

Also update progress/claims/TEST_MATRIX; optionally add screenshots under docs/screenshots. No other production files. Read `L10n.selectAll`/`deselectAll` definitions as reference only.

## Existing interfaces

The manager already has `objects: [PageObject]` (filtered to ink), `selected: Set<PageObjectID>`, `color: RGBAColor`, `busy: Bool`, `toggle(_:)`, `load()` and `apply(_:)`. Its Form is disabled while busy. Saved rows use `markup-row-<UUID>` with a selected-state/color accessibility value. Do not alter load/apply or the renderer below the sheet.

## Exact behavior

- Insert one ordinary Button row immediately before the saved mark rows, inside their nonempty branch.
- Identifier: `markup-toggle-all` (same for both labels).
- Compute the complete ID set from the current `objects`, never from row positions. When `selected` equals this nonempty set, show `L10n.deselectAll`; otherwise show `L10n.selectAll`.
- Tap while all selected: empty `selected`. Tap otherwise: assign the complete ID set.
- If selecting all from an empty selection, initialize `color` from the first ink object's color, as the existing single-row toggle does. Preserve the chosen color when expanding a partial selection.
- No control for the empty list; loading/saving remains disabled by the existing Form.
- Selection must not write to storage or create an undo step. Done/reopen starts unselected. Keep the existing session-change refresh and stale-snapshot protection.

## Work in order

- [ ] Read this sheet and the existing `testSavedMarkupSupportsColorsSelectionRemovalAndRelaunch` method as the interaction pattern.
- [ ] In the seed script, immediately after MARKUP_LIBRARY is seeded, copy it to `/tmp/papernest-qwen-bulk-marks-en`, `-fr`, `-es`. Reset only those exact test paths using the existing loop pattern. Do not reuse another test's mutable library.
- [ ] Append `testSavedMarkupBulkSelection`. Use the existing launch helper and `Markup target`; loop en/fr/es. Create two green marks using the existing Annotate Text UI. Then assert the behaviors below.
- [ ] Run the focused test before adding the button; it must fail because `markup-toggle-all` does not exist, not due to setup.
- [ ] Implement only the Button and local selection logic specified above.
- [ ] Rerun the same focused test. Fix concrete failures, preserve the existing API guards. Update PROGRESS and proceed to Q2 when green.

## Test assertions

1. Two saved rows exist; new control says localized Select All. No selection means Apply Color and Remove Selected are disabled.
2. Select All selects both rows and changes the label to Deselect All. Deselect All clears both and disables actions.
3. Select just one row, then Select All: both selected. Done, reopen: still two green marks, both unselected. No color/removal write occurred.
4. Select All, choose blue, Apply Color: both rows show `#1A59CC`; selection clears. Close and relaunch: both are still blue.
5. Select All, Remove Selected: empty message appears, bulk selector is absent. Relaunch preserves empty state.
6. Keep screenshots with the bulk control selected in each locale (`qwen-bulk-marks-en/fr/es`).

Menu labels: en `Annotate Text` / `Manage Markup`; fr `Annoter le texte` / `Gérer les annotations`; es `Anotar texto` / `Gestionar anotaciones`. Bulk labels already exist in localization files; read them rather than inventing translations. Reuse stable IDs for other controls from the existing test. Scroll the Form if needed; after scrolling down, scroll back up to reach the bulk row. Do not use screen coordinates or unbounded retries.

```bash
./scripts/ui-test-ios.sh 63992C10-33B4-4CE3-91C3-EE23ECC595A5 -only-testing:PaperNest-iOSUITests/AppUITests/testSavedMarkupBulkSelection > /tmp/papernest-qwen/q1-iphone.log 2>&1
```

Create the log directory first. Expected green: the named test executed and passed, `TEST SUCCEEDED`, exit 0. Preserve a separate red-run log. At queue end, both tasks also run on iPad as specified in the handoff. A small view-only change does not need unit tests that merely repeat Set operations.
