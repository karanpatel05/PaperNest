# Compressing a PDF kept as a file — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** `Exporter.compress(fileNamed:data:preset:)` refuses a PDF outright with `unsupportedFormat`, on the grounds that shrinking one means rasterizing its pages and destroying selectable text. Since 2026-10-26 that reason is only half true: a page with **no text of its own** can be re-encoded safely, and the document path already does exactly that. Row 35 names PDF file items as the remainder.
**Architecture:** The document path works on library `Page` models through `PageRenderer` and a store. A loose file has none of those, so this is a standalone PDF→PDF pass: for each page, keep it as it is when it carries text, and otherwise re-encode it as a JPEG at the preset — keeping the re-encode **only when it beats the page it would replace**, the same rule and the same `carriesText` / `byteCount(of:)` helpers.
**Tech Stack:** Swift 6, PDFKit, Core Graphics, Swift Testing; no dependencies.
**Spec:** Backend only, my lane. Codex is on native UI polish in `PaperNestUI`; nothing here touches it.

## Constraints and review focus
- **Never rasterize a page that has text.** Same rule as the document path, same helper. Most scanner apps embed an invisible OCR layer, which counts as text, so only image-only scans benefit — that bound is real and gets recorded, not glossed.
- **Assemble the output fresh in PDFKit**, copying text pages with `PDFPage.copy()`. The pass-through slice established that editing a document in place loses form-field names; copying also keeps links and annotations on the pages that are not re-encoded.
- **A re-encode is kept only when it is smaller than the page it replaces**, measured per page the same way. At 300 dpi Light upsamples most scans, so it will usually decline.
- **A refusal must still write nothing.** The existing contract: everything that can fail runs before a temporary directory exists. Bytes that are neither a re-encodable image nor a readable PDF keep throwing `unsupportedFormat`.
- **No fake savings.** A PDF whose pages all carry text comes back with real byte counts and `isSmaller == false`, exactly as an already-compact photo does. It is not dressed up, and it is not refused either — it is a PDF this *can* read, it simply cannot be made smaller.
- Page count, order and the document's own attributes are unchanged.

## Task 1 — a PDF→PDF reduction that respects text
- [x] Failing tests: a scanned PDF file shrinks at Smallest; a digital text PDF file reports no saving and keeps its text; page count and order survive; non-PDF, non-image bytes still refuse without writing.
- [x] Make `PageRenderer.rasterizePDFPage` public so there is one rasterizer, not two.
- [x] Add the PDF branch to `compress(fileNamed:data:preset:)`.

## Task 2 — verify and record
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record measured before/after bytes in TEST_MATRIX, update row 35 and the PRODUCT_SPEC line that says a PDF file item is deliberately refused, release the claim.

## Execution ledger
- Baseline: 378 tests passing, 0 warnings, Mac and iOS builds clean.

## What the plan did not foresee
- **A copied `PDFPage` is read lazily from its document.** The rebuilt one-page document was a local, so it died on return and the page serialized blank: 869 bytes from a 193 KB scan. The rebuilt documents are now held until the output is serialized. The pass-through slice recorded this exact trap; writing it down was not enough to avoid it.
- **`isSmaller` is not a test.** A blank page satisfies it perfectly. The test now renders the output page and asserts it has content, with a size floor as well.

## Measured
| source | original | light | strong | smallest |
|---|---|---|---|---|
| 1600×2000 scan in a 612×792 page | 193,043 | 193,092 | 111,920 (−42%) | 55,115 (−71%) |
| digital text PDF | 8,007 | 8,028 | 8,028 | 8,028 |
