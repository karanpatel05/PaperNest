# File Compression Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Finish the gap the previous slice left. F2d compresses a page-based document, but a photo kept as a *file item* cannot be reduced at all, and "get a photo under an email limit" is the everyday case the reference app leads with.
**Architecture:** Extends the F2d pieces rather than duplicating them. `LibraryStore.originalByteCount(of:)` learns about file items, reading `file_items.byte_count`, so one API answers "how big is this item" for both kinds. `Exporter.compress(fileNamed:data:preset:)` re-encodes image bytes at the preset's dpi and JPEG quality using the existing `downsample` and `encode` helpers, and returns the same `CompressionResult` so callers measure savings the same way everywhere.
**Tech Stack:** Swift 6, ImageIO/Core Graphics, Swift Testing; no dependencies.
**Spec:** Engine only, continuing F2d. Codex's queue is F3 interface work, so nothing here is contended. No UI, no schema change, no new strings.

## Constraints and review focus
- **A file this cannot reduce must say so, not be mangled.** Only image bytes we can decode and re-encode are candidates; a Word file, an archive or a video throws `CompressionError.unsupportedFormat`. Writing a "compressed" file that is actually a broken re-encode would be worse than refusing.
- **The same honesty rule as F2d.** An already-compact JPEG grows when re-encoded. `CompressionResult.isSmaller` and `savedByteCount` already handle that; the tests must prove it for the file path too, because this is the path where it will happen most — most photos arrive already compressed.
- **Originals are immutable.** Compression writes a new file in its own temporary directory and never replaces the stored asset. Whether a reduced copy later *becomes* a new library item is a separate decision with its own slice; this produces the bytes and the numbers only.
- Extending `originalByteCount(of:)` must not change what it already reports for page-based items, deleted pages, deleted items or template-page notebooks. Those tests stay green untouched.
- Output goes in the usual private temporary directory and the caller removes it; leaving one behind breaks the shared cancellation check that asserts on the process-wide temporary root.

## Task 1 — file items get a size
- [ ] Add failing tests: a file item reports its stored byte count; a file item in Recently Deleted reports zero; page-based behaviour is unchanged.
- [ ] Teach `originalByteCount(of:)` about `file_items`.
- [ ] Run focused store tests, record red/green.

## Task 2 — compressing image bytes
- [ ] Add failing tests: a large photo is measurably smaller, and smaller again at a stronger preset; the output decodes as a valid image with reduced pixel dimensions; an already-compact source reports `isSmaller == false` and `savedByteCount == 0`; bytes that are not an image throw `unsupportedFormat` and write nothing; the output directory is removable and leaves nothing behind.
- [ ] Implement `CompressionError` and `Exporter.compress(fileNamed:data:preset:)`.
- [ ] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build.
- [ ] Record honest results in TEST_MATRIX, release the claim. No commit unless the owner asks.

## Execution ledger
- Baseline: `081ffe6` plus my uncommitted recognition and F2d slices, **317 tests passing**, 0 warnings.
- Reuses `CompressionPreset`, `CompressionResult`, `Exporter.downsample` and `Exporter.encode` from the F2d slice; adds no second way to express a preset.
