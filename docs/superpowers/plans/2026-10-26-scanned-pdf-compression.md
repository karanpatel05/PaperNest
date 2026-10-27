# Compressing a scanned PDF — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Clear the limitation found while measuring the pass-through slice: *compression cannot shrink a scanned PDF.* Import a PDF produced by another scanner app, pick Smallest, and the file comes back the size it started. The preset the user chose does nothing.
**Architecture:** `PageRenderer.prepareSource` returns `.pdf(document, pageNumber:)` for a `.pdfPage` whose transform needs no pixel processing, and `Exporter.pdfSource` returns early for anything that is not `.image` — so the preset's dpi and JPEG quality never touch a PDF page. The fix is to rasterize and re-encode such a page **when, and only when, it carries no text of its own**. A digital PDF's text pages keep passing through as vector.
**Tech Stack:** Swift 6, PDFKit, Core Graphics, Swift Testing; no dependencies.
**Spec:** Backend only, my lane. Codex is on native UI polish in `PaperNestUI`; nothing here touches it.

## Constraints and review focus
- **Never rasterize a page that has text.** Rasterizing a vector text page makes it *bigger* and destroys selectable text — the opposite of what was asked for twice over. `CompressionTests.aVectorPDFKeepsItsTextInsteadOfBeingRasterizedToSaveBytes` already pins this and must stay green. The signal is the page's own extractable text, read with PDFKit: empty means a scan.
- **Any text at all means leave the page alone.** A scan with a stamped page number will not compress. That is a deliberate miss in the safe direction, and it gets recorded as a limitation rather than tuned with a threshold on a guess.
- **Pass-through has to stand down for a page being rasterized** — this is the trap written into SESSION_HANDOFF during the previous slice. A copied page ignores the preset entirely, so the copy must not happen for a page we are re-encoding. A *text* page under compression still passes through, which is what keeps its links.
- **No fake savings.** `CompressionResult` already reports real byte counts; re-encoding an already-compact scan can still come out larger, and that must keep reporting no saving.
- Compression stays an export: originals are immutable and nothing in the library is touched. `compressingChangesNothingInTheLibrary` covers it.

## Task 1 — rasterize a text-free PDF page on request
- [x] Failing tests: a scanned PDF gets smaller at `.smallest`; `.smallest` beats `.light`; a vector text PDF still keeps its text; a scanned PDF's page count and order survive.
- [x] `PageRenderer.prepareSource` gains a defaulted `rasterizingPDFPages` parameter that makes the `.pdfPage` case rasterize.
- [x] `reEncodedPDFPage` builds the candidate and measures it (not `pdfSource`, which stays the vector path), so the existing downsample/JPEG path does the work.

## Task 2 — decide per page, and keep pass-through out of the way
- [x] Failing test: compressing a scanned PDF does **not** copy the page (it is re-encoded), while compressing a text PDF still keeps its link.
- [x] `writePDF` reads the source document once per asset (the cache pass-through already keeps), asks whether the page has text, and uses that to choose: rasterize, or the existing vector/copy path.
- [ ] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build.
- [ ] Record in TEST_MATRIX with real before/after bytes, reword the limitation, release the claim.

## Execution ledger
- Baseline: 371 tests passing, 0 warnings, Mac and iOS builds clean (pass-through slice, same day).
- Measured starting point for a scanned PDF: original 8461 bytes, copied 8521, drawn 8531 — identical at `.light` and `.smallest`.

## What the plan did not foresee
- **A preset can make a scan bigger.** Light is 300 dpi, which *upsamples* a scan of lower resolution: the first working version produced 416,360 bytes from a 193,043-byte page — a "compression" that more than doubled the file. A re-encode is now kept only when it beats the page it would replace, measured per page by writing the copied page alone into a document. Light therefore falls back to copying, at 193,103 bytes.
- **The budget cannot be the file size divided by the page count.** A document of one photograph and nine blank pages would let each blank page grow and refuse the photograph. Measured per page instead.
- **A blank page is text-free, so it qualifies as "a scan."** Rasterizing one turns about a kilobyte into a JPEG of white. The size rule catches it; a test pins it.
- **Rasterizing can fail where copying succeeded.** `rasterizePDFPage` throws above 100M pixels and an A0 page at 300 dpi is about 139M. That error now falls back to leaving the page alone rather than failing the export; `CancellationError` is still rethrown.
- **The synthetic `scannedPDF()` fixture could not show compression working at all.** Its 400×560 near-flat PNG is more compact than any re-encode of it, so the fixture gained a `raster:` parameter and the size tests pass a realistic 1600×2000 page of text.
- **How often this helps is bounded by the OCR layer.** Notes, Adobe Scan and ScanSnap embed invisible text, which counts as text here, so those PDFs still will not compress. Only image-only scans do.

## Measured
| source | original | plain export | light | strong | smallest |
|---|---|---|---|---|---|
| 1600×2000 scan in a 612×792 page | 193,043 | 193,103 | 193,103 | 113,235 (−41%) | 56,430 (−71%) |
| digital text PDF | 8,007 | 8,044 | 8,044 | 8,044 | 8,044 |
| blank page | 2,140 | 2,207 | 2,207 | 2,207 | 2,207 |
