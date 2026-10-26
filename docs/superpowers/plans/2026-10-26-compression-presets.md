# Compression Presets Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** F2d. Reduce a document's size on purpose, and say by how much. Row 35 of the capability ledger is **Partial** today: export quality levels exist, but nothing is presented as compression and no before-and-after size is ever measured. SESSION_HANDOFF notes the distinction that matters — F2b *packs* (ZIP), it does not *compress*.
**Architecture:** The raster path already downsamples and JPEG-encodes per `PDFImageQuality`; what is missing is explicit presets, a measured original size to compare against, and honest reporting when nothing can be saved. `Exporter.compress` produces the output and a `CompressionResult` carrying both byte counts. "Before" comes from a new `LibraryStore.originalByteCount(of:)`: the bytes of the originals the live pages are made of, a shared original counted once — not the size of some previous export.
**Tech Stack:** Swift 6, Core Graphics/ImageIO, Swift Testing; no dependencies.
**Spec:** Engine-only slice, item 3 in "Next for Claude". Codex's queue is entirely F3 interface work (Mac audit, word-level selection, text/custom-image stamps, fill & sign, app lock), so none of these files are contended. No UI in this slice: a Compress action belongs with whoever owns the sheets, and it must not ship until it can show real numbers.

## Constraints and review focus
- **Never claim a saving that did not happen.** Re-encoding an already-compact source can produce a *larger* file. `CompressionResult` reports `isSmaller` and a `savedByteCount` that is zero rather than negative, and the caller must be able to tell "no saving possible" from "saved nothing yet". This is the single most important behaviour here: a compressor that lies about sizes is worse than no compressor.
- **A vector PDF cannot be compressed by this path and must say so.** `pdfSource` passes vector pages through untouched, by design, because rasterizing text to shrink a file would destroy its quality and its selectable text. A document of vector pages therefore reports no saving. Do not "fix" this by rasterizing.
- **Do not change `PDFImageQuality`'s cases.** It is `CaseIterable` and drives the export sheet's picker, which Codex owns; a new case would silently appear in the UI. Introduce an internal `RasterQuality` (max dpi plus optional JPEG quality), give `PDFImageQuality` a computed `rasterQuality`, and thread an optional override through the private `pdfSource`. Public API and the picker stay exactly as they are.
- Compression reads the library and writes only to its own temporary directory. It must not touch originals, page rows, revisions or `modified_at` — originals are immutable and this is an export, not an edit.
- Output goes in the same private temporary directory every export uses, and the caller removes it. Leaving one behind breaks `cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind`, which asserts on the process-wide temporary root.

## Task 1 — the measured "before"
- [ ] Add failing tests: the original byte count of a document equals its single original's size; a document whose pages share one original counts it once; pages deleted or belonging to a deleted item are excluded; a notebook of template pages has no originals and reports zero.
- [ ] Implement `LibraryStore.originalByteCount(of:)` in a new `ItemSizes.swift`.
- [ ] Run focused store tests, record red/green.

## Task 2 — presets and honest results
- [ ] Add failing tests: a scanned document is measurably smaller at `.strong` than at `.light`, and smaller still at `.smallest`; each output is a valid PDF with the original page count; an already-compact source reports `isSmaller == false` and `savedByteCount == 0`; a vector PDF document reports no saving and keeps its text; compression leaves `modified_at`, page revisions and the originals untouched; the output directory is removable and nothing is left behind.
- [ ] Add `RasterQuality`, `PDFImageQuality.rasterQuality`, and the optional override on the private PDF path.
- [ ] Implement `CompressionPreset`, `CompressionResult` and `Exporter.compress` in a new `Compression.swift`.
- [ ] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build.
- [ ] Record honest results in TEST_MATRIX, including what was not run, and release the claim. No commit unless the owner asks.

## Execution ledger
- Baseline: `081ffe6` plus my uncommitted automatic-recognition slice, **304 tests passing**, 0 warnings.
- Run every verification under a hard timeout. A full run hung for four hours earlier today on the Vision deadlock recorded in TEST_MATRIX; the lesson stands regardless of cause.
