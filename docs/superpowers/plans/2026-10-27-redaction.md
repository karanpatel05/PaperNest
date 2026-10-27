# Permanent redaction — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Ledger row 26, *permanent redaction (content removed, not covered)*, is Planned with "adversarial fixtures required". A black rectangle drawn over a word is the classic fake: the word is still in the file, selectable, searchable and recoverable. This builds the engine for a real one.

## The design question, and what the code answers

I expected a conflict with "originals are never modified". There isn't one — the library already supports *deleting* an original, which is a different thing from modifying it:

- `replacePageContent` swaps a page's content for new bytes and files the old content in `page_content_history`, so a replacement can be undone.
- `sweepOrphanAssets` deletes any asset referenced by no page, no history row, no file item and no placed image.

So a true redaction is: render redacted bytes → `replacePageContent` → **forget that page's history** → sweep. The original is deleted rather than edited, and the invariant stands. A redaction-only export path is not needed, and would have been the weaker promise.

`replacePageContent` already deletes the page's `ocr` and `pdfText` rows from `search_index`, so redacted words stop answering searches the moment the content changes. That is most of the work, and it was already right.

**Three things the code does *not* do, each of which this has to handle or disclose:**

1. **The recognised text survives in `page_recognition`.** Only the search index is cleared. The row still physically holds the words, with the old `source_revision`. Export refuses it, search cannot see it, but it is on disk — which is not redaction. It must be deleted.
2. **A shared original cannot be deleted.** Assets are content-addressed, so two pages of identical paper share one. If another page still references it, the sweep correctly keeps it, and the redacted content remains reachable through that other page. This must be *reported*, not silently ignored.
3. **Deleting a file does not scrub the disk.** The bytes may persist until overwritten, and on a copy-on-write filesystem that is not controllable from here. Nothing may claim otherwise.

## Constraints and review focus
- **Flattening is the mechanism, and the cost is stated.** For a PDF page, text under a painted rectangle survives any amount of drawing on top, so the page is rasterized and the region painted into the pixels. That destroys selectable text across the **whole page**, not only the redacted part. It is the honest trade and it has to be said wherever redaction is offered.
- **Adversarial tests, not cosmetic ones.** It is not enough that the region looks black. The tests must show the text is no longer extractable, the pixels that were there are gone, and a search for the redacted word finds nothing.
- **Lossless encoding.** A JPEG of a black rectangle has ringing at its edges; worse, lossy artefacts around text are the kind of thing recovery tools exploit. The redacted page is stored as PNG.
- **Geometry goes through `PageGeometry`.** Rectangles arrive in upright, uncropped source space like ink and recognition, never in view coordinates.
- `sweepOrphanAssets` has a **one-hour grace period** by default, so the original survives until the next sweep unless the caller asks for none. Stated rather than silently changed.

## Scope
**In:** the renderer that produces redacted bytes; the store operations that let the original be forgotten and the recognised words deleted; adversarial tests.
**Out, and stated:** the screen and the orchestration (`DocumentModel` is Codex's file); ink and other page objects inside the region, which are separate rows and are not touched; secure erasure of the underlying disk.

## Task 1 — redacted bytes
- [x] Failing adversarial tests: after redacting a word, the text is not extractable from the new content and the pixels where it was are black.
- [x] `PageRedaction` in `PaperNestRender`: page + rectangles in source space → PNG bytes, flattened and painted.

## Task 2 — leaving nothing behind
- [x] Failing tests: the recognised words are gone from the store; a search for them finds nothing; the old asset is swept; a **shared** original is kept and reported.
- [x] `LibraryStore.forgetReplacedContent(for:)` and `deleteRecognition(for:)`.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX, update row 26 with what is and is not true, release the claim.

## Execution ledger
- Baseline: 399 tests passing, 0 warnings, Mac and iOS builds clean.

## Outcome
406 tests, 0 warnings, Mac and iOS builds clean. The design question was answered by reading the store rather than by asking: deleting an original is not modifying one, and `replacePageContent` + `sweepOrphanAssets` already do it. The investigation also found the `page_recognition` gap, which no test or note had recorded — search could not see the words, but they were still on disk.
