# Q2 — Bulk selection of recognized text lines

Status lives in PROGRESS.md. Start after Q1's focused test passes. Keep Q1 intact.

**Goal:** In More → Annotate Text, select every recognized line or clear the selection with one tap before applying a style/color.

**Allowed code files:**
- `Sources/PaperNestUI/TextAnnotationSheet.swift` — one new local-selection control.
- `Apps/iOS/UITests/AppUITests.swift` — append `testTextAnnotationBulkSelection`.
- `scripts/ui-test-ios.sh` — dedicated synthetic library copies only.

Also update progress/claims/TEST_MATRIX and screenshots. Reuse existing L10n labels; no new localization or Core/Store/Render/DocumentModel changes.

## Existing interfaces

`recognition: PageRecognition?`, `selection: Set<Int>`, and `busy: Bool` are local sheet state. The saved OCR snapshot is already validated by the store on Apply. `load()` clears selection. The sheet has rows `annotation-line-<index>`, buttons `annotation-recognize`, `annotation-apply`, `annotation-cancel`, and `annotation-style-highlight/underline/strikethrough`.

## Exact behavior

- Add one Button row before the lines in the existing nonempty-recognition branch.
- Identifier: `annotation-toggle-all`. Complete selection is `Set(recognition.lines.indices)`; do not approximate word boxes or rerun OCR to select lines.
- If every line is selected, label `L10n.deselectAll`; otherwise label `L10n.selectAll`. Tap clears or selects all accordingly, including from a partial selection.
- Hide the bulk button without recognized lines. Existing Form busy handling disables it during loading/recognition/save.
- Do not change the selected style/color, OCR data, Apply implementation, crop mapping, or cancellation semantics. Selecting never saves ink. Cancel writes no annotation. Apply uses the existing selected-line set and dismisses after the existing save succeeds.

## Work in order

- [ ] Read this sheet and existing `testRecognizedLinesCanBeMarkedAndKeptAfterRelaunch` plus Q1's new test for selectors/scrolling.
- [ ] Add copies of the pristine MARKUP_LIBRARY to `/tmp/papernest-qwen-bulk-lines-en`, `-fr`, `-es`. Keep Q1's libraries separate.
- [ ] Append `testTextAnnotationBulkSelection` looping en/fr/es. Use real OCR on `Markup target`; do not fabricate recognition rows.
- [ ] Run focused test first. Expected red: missing `annotation-toggle-all` after real recognition.
- [ ] Add the specified Button/local state logic only.
- [ ] Rerun focused test; when green, run the queue's final unit/Mac/iPhone/iPad commands from QWEN_HANDOFF. Record actual results and release claims. Do not start a third feature.

## Test assertions

1. Before recognition: no bulk selector, Apply disabled. Recognize Text produces more than one line.
2. Count actual `annotation-line-` rows; do not hardcode the OCR engine's line count.
3. Select All selects every row, enables Apply and shows Deselect All. Deselect All clears every row and disables Apply.
4. Select one line then Select All: every line selected. Cancel returns to a page with zero strokes. Reopening the sheet has no selected lines.
5. Select All again, Apply: document stroke count equals the observed line count. Relaunch preserves that count. Reopen Annotate Text and verify no stale local selection carried over.
6. Keep screenshots of the selected bulk control in en/fr/es (`qwen-bulk-lines-en/fr/es`).

The document image identifier is `document-page-image`; its accessibility value begins with the ink count (see the existing test). Query row identifiers by prefix. Reuse Q1's bounded scroll approach; scroll back up if needed to reach the new row. Match More menu entries by localized label because menu identifiers may be hidden by SwiftUI.

```bash
./scripts/ui-test-ios.sh 63992C10-33B4-4CE3-91C3-EE23ECC595A5 -only-testing:PaperNest-iOSUITests/AppUITests/testTextAnnotationBulkSelection > /tmp/papernest-qwen/q2-iphone.log 2>&1
```

Expected green: named test executed and passed, `TEST SUCCEEDED`, exit 0. Keep the initial red log separately. Do not remove existing recognition or stale-data tests. Native Mac interaction and screenshots cannot be reported as checked merely because the Mac build passes.
