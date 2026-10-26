# Shape Annotations Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline with test-first implementation and one final independent review.

**Goal:** Add rectangles, ellipses, lines and arrows as editable ink, with page preview, color/width, drag placement, persistence, undo/redo and PDF/image export.
**Architecture:** Core generator accepts normalized displayed-page endpoints and maps through PageGeometry to source-space InkStroke. Store validates exact displayed Page snapshot and active parent atomically; model reuses guarded ink/history machinery. Native localized sheet reuses PageImageView and MarkupColorPicker.
**Tech Stack:** Swift 6, SwiftUI, SQLite, CoreGraphics; no new dependency or migration.
**Spec:** User delegated choosing another roadmap feature. Builder scope: outlined shapes, widths 1/2/4 source points, visible sRGB colors, default centered placement; drag endpoints plus accessible position sliders; shapes save as ink and can be recolored/removed in Manage Markup. Geometry respects crop/rotation. No fill, shape recognition or dedicated post-save resize handles in this slice.

## Review focus
- Crop/rotation mapping; reverse drags; nonfinite/empty/extreme geometry; outline remains within visible page.
- Snapshot changed or deleted while sheet is open: no stale geometry saved; draft remains open on error.
- One stroke per shape, one undo step; rapid history and mixed page-add/shape undo must work without erasing external edits.
- Rendering/export use the same saved strokes; page composition preserves them.
- en/fr/es compact layouts, cancellation and duplicate-save prevention; Qwen reservations intact.

## Tasks
- [x] Core/store tests red: all kinds and rotations/reverse drags, invalid coordinates/color/width, stale snapshot/parent; implement generator and atomic API; focused green.
- [x] Model tests red: add/undo/redo/reopen/export, mixed page insertion history; integrate with existing ink manager and resolve regressions without weakening semantic conflict checks.
- [x] Native sheet: kinds, preview/drag, accessible positioning, colors, widths, save/cancel/errors; both editor More menus.
- [x] Full tests, Mac build, phone/iPad localized UI and screenshots, one independent review and test-first fixes.
- [x] Update handoff/roadmap/test matrix and commit owned paths; no push.

## Ledger
- Baseline 6a04173; shared in-place checkout retained; schema stays v7.

- Core/store/model APIs each failed as expected before implementation (`/private/tmp/papernest-shapes-{core,store,model}-red.log`). Mixed page/shape history then failed on page removal and redo (`-history-red.log`); all four focused tests pass after semantic snapshot comparison (`-focused.log`). Revisions and modified_at remain monotonic/cache-valid; every content column, objects, OCR, sibling order and deletion stamp stay guarded.
- First full suite caught four French ordinary-space-before-colon strings. Corrected to nonbreaking spaces; final suite and Mac build running. iPhone localized UI running; fresh independent reviewer dispatched read-only.

- Fresh independent review found PencilKit smoothing of sparse rectangle corners/arrowhead reversals. Confirmed with `shapeCornersSurvivePencilKit` RED (8 issues; visible path deviation and missed corners), then repeated the generated vertices to preserve the cubic path's sharp joins. Focused suite GREEN, including both rotated/scaled shape round-trips; no changes to general freehand conversion. Logs: `/private/tmp/papernest-shapes-pencil-{red,green}.log`. One fix pass, no re-review. Final full suite/Mac build rerun; iPad will compile this fix.

- Screenshot review of the passing first phone run showed the arrow remained at default placement while the form scrolled. Added localized coordinate accessibility value and an assertion that dragging changes it; running UI RED before changing gesture priority. Initial iPad run stopped intentionally (exit75), not a pass. Re-run both devices after the fix. This is visual QA follow-up, not a second independent review.

- Drag UI RED confirmed unchanged 25%/75% endpoints. Priority alone was insufficient: centered paper had a smaller gesture frame than the full-width accessibility target. Expanded the touch surface to the preview row and subtract its paper inset before normalizing, with high-priority drag. Position assertion now passes. Test scrolling must start in the form margin, outside this intentional drawing surface.
- Imported-document UI RED confirmed no accessible Undo action (history menu had been notebook-only). Made the existing history actions available in both document More menus; a dedicated imported-PDF shape add/undo/redo test verifies this. Log: `/private/tmp/papernest-shapes-doc-history-red.log`.
- Claude concurrently claims vector PDF text indexing (see handoff). Preserve all their engine/test/AppEnvironment work and stage only owned hunks of shared docs.

- Final combined full suite passed 276 tests (includes 17 new Claude indexing tests; shape-only state passed 259), Mac build passed. Final iPhone localized flow and imported-document undo/redo both passed. Three final screenshots inspected/copied to docs/screenshots. Final iPad localized + imported-document history + existing finger-drawing flows running sequentially after phone.

- Final iPad: existing drawing/history/relaunch and imported-document shape history passed. Localized shape test initially failed only on scrolling outside the centered sheet; corrected the test to use the preview's adjacent form margin. Repeated affected workflow: en/fr/es PASS, screenshots inspected/saved. Production code unchanged after final phone run. No native Mac interaction, real-device/VoiceOver/large-type, system-picker/slider interaction or new sanitizer pass claimed.
- Completed for the owned-path local commit; no push. Shared handoff/test-matrix staging includes only this slice, preserving Claude’s indexing sections unstaged. All feature claims released.

- 2026-10-26 integration recheck after Claude commits 6ed4a1f/be90604: 283 full tests and Mac build PASS. Production shape code unchanged from final device verification. Commit only the 26 owned paths/hunks; leave Claude’s unstaged handoff/test-matrix sections intact.
