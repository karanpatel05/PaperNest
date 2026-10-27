# Redaction as an operation — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** The redaction engine landed earlier today and **nothing calls it**. `PageRedaction.redactedPNG` produces redacted bytes and the store can forget the original, but composing those into one durable operation was left out. Until that exists, a screen cannot redact anything without reimplementing the sequence — and getting any step of it wrong leaves the words in the library.
**Architecture:** A `PageRedactor` in `PaperNestRender`, which already depends on Core and Store and already hosts `PageRedaction`. It renders, stages the new asset, replaces the page's content, deletes the recognised words, forgets the undo history, and then reports — truthfully — whether the old paper is gone.
**Tech Stack:** Swift 6, Swift Testing; no dependencies.
**Spec:** Backend only, my lane. The screen and its wording stay out: `DocumentModel` is Codex's, and the required wording is already in `docs/CODEX_BRIEF.md`.

## Constraints and review focus
- **Every step, or none of the promise.** Rendering alone leaves the original in the library; replacing alone leaves the recognised words in `page_recognition`; forgetting alone leaves the asset file on disk. The operation exists precisely so a caller cannot do three of the four.
- **The dangerous state is the one that must be loud.** Assets are content-addressed, so two pages of identical paper share one file. Redacting one page cannot delete it, and the words stay reachable through the other page. The outcome reports `originalStillInLibrary`, named so that the *unsafe* case is the `true` one and a caller has to look at it before claiming anything.
- **A targeted delete, not a sweep.** `sweepOrphanAssets` has a one-hour grace period protecting assets staged but not yet referenced; calling it with no grace period to collect one file could take another operation's freshly staged bytes with it. `deleteAssetIfUnreferenced` touches exactly one asset and refuses if anything still points at it.
- **Row before file.** Delete the `assets` row first, then the file. A crash between them leaves an orphan file the sweep collects; the other order leaves a row pointing at nothing, which is a broken library. This matches what `sweepOrphanAssets` already does.
- **The page keeps its place.** Same sort key, same transform, same source size: the new content is the whole upright sheet as pixels, so an existing crop or rotation still applies and must not be baked in twice.
- **Still not a promise of erasure.** Deleting a file unlinks it; the bytes may persist until overwritten. Nothing here may say "securely erased".

## Task 1 — a targeted asset delete
- [x] Failing tests: an unreferenced asset is deleted, row and file; a referenced one is refused and kept.
- [x] `LibraryStore.deleteAssetIfUnreferenced(_:)`.

## Task 2 — the operation
- [x] Failing tests: after redacting, the page's content is the new image, the words are not findable, the recognition row is gone, and the old file is off disk; a **shared** original survives and is reported; the page keeps its sort key and transform.
- [x] `PageRedactor.redact(_:rectangles:)` returning `RedactionOutcome`.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX, update row 26, release the claim.

## Execution ledger
- Baseline: 411 tests passing, 0 warnings, Mac and iOS builds clean.

## Outcome
415 tests, 0 warnings, Mac and iOS builds clean. The first green run passed every test but raised four warnings (unnecessary `await`/`try` — `store.assets` is not isolated — and an unused `transaction` result); a warning-free build is part of done here, so they were fixed before the slice was claimed.
