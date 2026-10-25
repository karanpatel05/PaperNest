# Recognized Text Markup Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan inline. The owner has requested implementation without more questions. Leave changes uncommitted.

**Goal:** Select recognized lines on the current page and add a highlight, underline or strikethrough, with persistent editable ink and undo/redo.

**Architecture:** Convert normalized OCR boxes to ordinary source-space `InkStroke`s. An atomic store operation validates the exact recognition snapshot before creating objects. The native sheet selects full lines and calls the document's existing ink undo machinery. Existing renderer, PDF/image export and PencilKit consume the strokes unchanged; no schema migration.

**Tech Stack:** Swift 6, SwiftUI, SQLite, existing Vision recognition and CoreGraphics rendering.

**Spec:** `docs/FEATURE_EXPANSION.md` F3 and `docs/SESSION_HANDOFF.md` next work. This is the first slice; notes, stamps, shapes, word-level selection and custom colors follow separately.

## Constraints and review focus

- Original assets unchanged; all marks persist as editable ink. Highlight yellow; underline/strike blue. Full-line selection is explicitly described in the UI.
- No invented OCR. Empty/unrecognized page offers the real recognition action for that page.
- Stale/replaced/failed recognition must reject the whole edit. Invalid line indices or invalid/nonfinite bounds must leave no partial objects.
- Crop/rotation map only through PageGeometry. Rounded line caps must fit inside the original OCR rectangle.
- Cancel creates nothing; Save stays open on failure; close only after commit; guard duplicate taps.
- en/fr/es labels, iPhone/iPad/Mac builds and iOS interaction coverage.

## Task 1: Transactional source-space marks

- [x] Add Core geometry tests and Store tests before implementation: all three styles, thin/narrow rectangles, invalid bounds, stale/replaced OCR, multiple-line rollback and persistence without altering originals.
- [x] Implement `TextMarkupStyle.stroke(for:in:) throws -> InkStroke` in `Sources/PaperNestCore/TextMarkup.swift`.
- [x] Implement `LibraryStore.addTextMarkup(_:lineIndices:style:) throws -> (page: Page, objects: [PageObject])` in `Sources/PaperNestStore/TextMarkupStore.swift`; compare current page revision and full recognition snapshot, then insert all objects in one transaction above existing z-order.
- [x] Run focused Core/Store tests and inspect results.

## Task 2: Accessible native annotation sheet and undo

- [x] Add `DocumentModel.addTextMarkup` and a workflow test covering undo/redo, reopen, search retention, and rendering/export after crop/rotation.
- [x] Add `TextAnnotationSheet.swift`: current page preview, style options, recognized-line selection, actual recognition action, loading/save/error states. Add overflow action on all device layouts and en/fr/es strings.
- [x] Reuse existing ink undo registration with a localized annotation action name. Recognition accepts an optional page ID so this sheet reads only its target page.
- [x] Append a synthetic UI workflow for recognize/select/style/apply/reopen and cancel; seed its own library.
- [x] Run unit suite, Mac build, focused iPhone/iPad annotation UI tests and relevant ink regression. Inspect generated screenshots where possible; record any unverified layout.

## Task 3: Review and handoff

- [x] Review diff for stale data, cancellation, ordering, crop/rotation, accidental writes and localization.
- [x] Update TEST_MATRIX, feature inventory and SESSION_HANDOFF with actual commands and remaining work. Preserve the earlier uncommitted Mac audit fixes. No commit.

## Verification and review notes

- 228 unit tests passed after the renderer review fix; Mac build passed. iPhone and iPad annotation workflows passed in en/fr/es, plus existing iPad ink persistence/undo/redo. The focused final iPad rerun after the renderer fix passed 2/2. See TEST_MATRIX for logs and exact run scope.
- Independent review caught width rounding in the existing pen renderer. A regression reproduced vanishing 0.1-point marks and expanded 1.2-point marks; constant-width pens now retain their exact width. Variable-width freehand batching remains unchanged. Independent reviewer follow-up found no remaining actionable findings.
- Screenshots inspected on iPhone and iPad. Native Mac annotation interaction, real-device Pencil/camera, VoiceOver, Dynamic Type and dark-mode annotation checks remain unrun.
- Changes remain uncommitted; no deployment or service enrollment.
