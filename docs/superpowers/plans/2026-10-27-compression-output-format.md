# Compression output format — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Row 35 names two remainders: *image-format output* and *folder/archive compression*. This takes the first. `compress(fileNamed:data:preset:)` hardcodes JPEG, so compressing a photo gives up about two thirds of the saving now that HEIC is available and measured (94,742 bytes against 284,377 for the same page).

**Why not archive compression in the same slice:** it needs an honest "before" for each entry, and for a document that is the originals it is made of — which lives in the store, and `Exporter` has no store. Doing it properly means the caller passing those counts in, which is a design question worth its own slice rather than a guess bolted onto this one. Recorded rather than quietly skipped.

**Architecture:** One parameter on the loose-file path, defaulting to what it does today. The PDF path is untouched: HEIC is not a PDF image filter, so a document's pages cannot use it.
**Tech Stack:** Swift 6, ImageIO; no dependencies.
**Spec:** Backend only, my lane. Codex is on the Notes tool bar in `DocumentView.swift`; nothing here touches it.

## Constraints and review focus
- **JPEG stays the default, and that is a decision, not an oversight.** Compression exists to make a file easier to send; handing back a HEIC that the recipient cannot open is a worse outcome than a larger JPEG. The caller opts in.
- **Never silently change what someone gets.** The output's extension must match its bytes, and a test reads the bytes back with `CGImageSourceGetType` rather than trusting the filename — the same trap the HEIC export slice found in `writeImages`.
- **The honest-reporting rules stand.** An already-compact source still reports no saving rather than a negative one dressed up, and bytes that are not a re-encodable image are still refused with nothing written.
- A **PDF** file item keeps its existing behaviour entirely: pages that carry text are copied, text-free pages are re-encoded, and none of it becomes HEIC.

## Task 1 — let the caller choose
- [x] Failing tests: HEIC output is materially smaller than JPEG for the same photo; its bytes really are HEIC; the default is unchanged and still produces JPEG; a non-image is still refused.
- [x] A `format` parameter on `compress(fileNamed:data:preset:)`, defaulting to JPEG.

## Task 2 — verify and record
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX with measured sizes, update row 35 to name only archive compression as remaining, release the claim.

## Execution ledger
- Baseline: 420 tests passing, 0 warnings, Mac and iOS builds clean.

## Outcome
423 tests, 0 warnings, Mac and iOS builds clean. The interesting part was not the code — one parameter — but refusing to make HEIC the default because it is smaller. Compression is the step before sending, so the format that fails to open at the other end is the wrong default however good the numbers look.
