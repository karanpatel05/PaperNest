# Page Comments Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Add/edit/delete page-level comments in documents and notebooks with durable persistence and guarded undo/redo.
**Architecture:** A new PageObject.Payload.comment(String) uses the existing object store and composition paths; schema v7 widens its kind constraint. Atomic compare-and-swap checks preserve other-window edits. DocumentModel uses the existing serialized history queue. A native Comments sheet captures the page ID and keeps unsaved drafts on errors.
**Tech Stack:** Swift 6, SwiftUI, SQLite, Swift Testing, XCUITest; no dependencies.
**Spec:** Scope described in this chat: page-level comments stored in PaperNest, explicitly excluded from PDF/image exports; no page-position pins, threads, authors, sharing service or shapes in this slice. Builder decisions: trim outer whitespace, reject empty text and text over 10,000 characters, preserve line breaks. Existing shared checkout retained; no worktree needed for the established in-place workflow.

## Constraints and review focus
- en/fr/es strings; native phone/iPad/Mac layout; Qwen reservations unchanged.
- Expected-object validation, deleted page/parent, restored ID collisions, rapid native history and stale edit forms must not lose newer data.
- Migration must preserve all existing objects; composition must copy comments with fresh IDs. Exports must not leak private comments.
- Save/cancel keep drafts until successful save; other-window changes refresh the list but never replace draft text.

## Task 1 — store and migration
- [x] Add failing PageCommentTests for migration v6→v7; add/edit/delete and inverse; reopen/copy; invalid text/parent; stale change and collision rejection.
- [x] Add comment payload and schema v7 rebuild of page_objects.
- [x] Implement setPageComment(on:replacing:text:) -> PageCommentChange and applyPageCommentChange(_:) -> Page, with inverse token and atomic guards.
- [x] Run focused store tests and record red/green results.

## Task 2 — model and sheet
- [x] Add model tests for create/edit/delete/undo/redo, conflict safety and export privacy.
- [x] Integrate model comment APIs with the shared history queue; add Comments to both More menus.
- [x] Build Comments list + editor sheet with add/edit/delete, localized errors/footer, disabled invalid/duplicate saves and retained draft on failure.
- [x] Full tests, Mac build, phone/iPad UI add/edit/cancel/delete/undo/relaunch in en/fr/es, inspect screenshots.
- [x] Fresh independent review, fix significant findings with regressions, update handoff/roadmap/test matrix and commit explicit owned paths.

## Execution ledger
- Baseline: 2e64487, 245 tests passed in prior slice; clean working tree before claim.
- Store API test first failed on missing setPageComment; focused store/model green (5 store + 2 UI-model tests). Migration v6→v7 preserves old text objects, corrupt FK migration rolls back. Full 252 tests and Mac build passed; simulator checks and fresh review underway. Logs: /private/tmp/papernest-comments-*.log.
- Final review found mixed comment/page undo invalidation. Reproduced in `papernest-comments-mixed-red.log`; fixed private-comment persistence to touch the item but preserve the rendered page row/OCR. Exact object snapshots still protect notebook undo from live comments.
- Final review found stale recovery instructions discarded the draft. Replaced close/reopen recovery with an owned PageCommentDraft and explicit Save as New Comment; stale original remains untouched. Draft-model regression failed on missing API in `papernest-comments-draft-red.log`; both review regressions passed in `papernest-comments-review-green.log`. No follow-up reviewer pass; tests verify fixes.
- First phone test failed because typing into an existing TextEditor inserted at the cursor rather than the assumed end. Test now captures the edited value, asserts both old/new text are present and verifies that exact text after relaunch. Short editor title uses localized Comment to fit compact layouts.
- Complete: 254 unit tests, Mac build, iPhone/iPad localized workflows passed; six screenshots inspected. Final verification details/limits recorded in TEST_MATRIX. Local commit: Add private page comments with guarded undo and draft recovery. Claims released; no push.
