# A document's outline — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Row 36 is *Bookmarks, reading mode, book formats*, Planned, with the standing condition that **supported formats must be named explicitly**. This takes the navigation half for one named format: a PDF's own outline — the table of contents its author wrote — so a long document can be moved through by chapter instead of by scrolling.

This is **not** user-created bookmarks. Those need a place to live and a screen to make them from; this reads something the file already carries and stores nothing.

## Verified before designing
Probed on this machine: an outline written with `PDFOutline`, serialized and reopened, comes back with its labels and page indices intact (`Beginning`→0, `Middle`→1, `End`→2), and a PDF with no outline returns `outlineRoot == nil` — so "this file has no contents page" is distinguishable from "nobody looked". That makes a synthetic fixture possible, which is what decides whether this can be tested honestly at all.

## The part that is not bookkeeping
A PDF's outline points at **pages of that file**. A PaperNest document is a list of pages that may have been reordered, cropped, deleted, or drawn from several PDFs at once. So the outline cannot be handed over as-is:

- Every entry is resolved through the document's **current** pages, by (asset, source page index) — never by trusting the index.
- An entry whose page has been **deleted** is dropped. An outline that leads somewhere the document no longer has is worse than no outline.
- A document assembled from **two** PDFs gets both outlines, each resolving to its own pages.
- Entries keep the **order and nesting the author wrote**, because that is what a table of contents is. If the user reordered pages, the outline may not ascend through the document — that is a true description of the file, and it gets documented rather than silently re-sorted.

## Constraints and review focus
- **PDF only, and said so.** Nothing here claims EPUB or any other book format; row 36 keeps its condition.
- Read-only: no schema change, nothing stored, nothing cached. The outline is read from the asset the page points at, so it is always current by construction.
- A page whose content is an image or a template contributes nothing — not an error.
- No UI. Reading the outline is the engine; presenting it is the screen owner's.

## Task 1 — read and resolve
- [x] Failing tests: a PDF's outline comes back with its titles in the author's order, each resolving to the right page; nesting depth survives; a PDF without an outline yields none rather than failing.
- [x] A synthetic `outlinedPDF` fixture, including a nested entry.
- [x] `PageRenderer.outline(for:)` returning resolved entries.

## Task 2 — the document is not the file
- [x] Failing tests: an entry whose page was deleted is dropped; a document built from two outlined PDFs yields both; reordering pages does not invent or lose entries.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX, update row 36 to say which half is done, release the claim.

## Execution ledger
- Baseline: 423 tests passing, 0 warnings, Mac and iOS builds clean, committed as `2ae1a0b`.

## Outcome
428 tests, 0 warnings, Mac and iOS builds clean. The feature is small; the care is in refusing to treat the file's page indices as the document's. Probing first settled that a fixture was possible at all — had `PDFOutline` not survived serialization, this would have had no honest test and should not have been built.
