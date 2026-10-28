# Compressing an archive — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Row 35's last remainder, folder/archive compression. `exportArchive` packs a selection into one ZIP — documents as PDFs, files byte for byte — and has no way to make any of it smaller. ZIP's own deflate does nearly nothing to a PDF or a JPEG, so the archive is the sum of its parts whatever the selection.

## The design question that blocked this, and its answer
The earlier slice deferred this because a `CompressionResult` needs an honest "before", and for a document that is the originals it is made of — which live in the store that `Exporter` cannot see. Passing those in made the API ugly.

**The answer is not to invent a before at all.** Applying a preset returns the ordinary `ExportOutput`; the caller already knows what it had and can compare. No fabricated baseline, no store dependency, and nothing claimed that was not measured.

## Constraints and review focus
- **Never drop an entry.** An archive missing a file is data loss, and it would be invisible until someone went looking. Anything that cannot be compressed goes in as it was. A test counts entries both ways.
- **Never grow one.** A re-encode that came out bigger is discarded and the original kept, the same rule the document and file paths already follow.
- **Non-image files keep their bytes exactly.** `LibraryExportEntry` already says why: re-encoding someone's video or spreadsheet would be a lie about what they got back. A preset does not change that — it only reaches things that can genuinely be re-encoded.
- **An image file re-encoded in an archive changes extension** (`.png` becomes `.jpg`). That is a real change to what someone gets back, so it is stated here and in the brief rather than discovered.
- Without a preset nothing changes at all, and a regression test pins that.

## Task 1 — apply a preset through the archive
- [x] Failing tests: an archive of a scanned document is smaller with a preset than without; a non-image file inside comes back **byte-identical**; an already-compact image is not grown; the entry count is the same either way; without a preset the archive is unchanged.
- [x] `preset:` on `exportArchive`, threaded to documents via `rasterQuality` and to image files via `compress(fileNamed:)`, keeping the original whenever compression refuses or loses.

## Task 2 — verify and record
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX, close row 35, note the extension change in CODEX_BRIEF, release the claim.

## Execution ledger
- Baseline: 428 tests passing, 0 warnings, Mac and iOS builds clean, committed as `3b1eb52`.

## Outcome
433 tests, 0 warnings, Mac and iOS builds clean. The blocker was never the code — it was insisting on a "before" that `Exporter` had no honest way to know. Dropping that requirement made the whole slice fall out in one parameter and a small helper.
