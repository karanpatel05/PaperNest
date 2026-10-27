# PDF Pass-Through Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Clear the first entry under "Known limitations" in IMPLEMENTATION_PLAN: *links, form fields and annotations inside imported PDFs may not survive export.* Import a form, export it, and the fields are gone — the document comes back as a flat picture of itself. Row 24 of the ledger ("interactive PDF form fields preserved") is Planned for the same reason.
**Architecture:** Export draws every page through a `CGContext` PDF, which reproduces the marks and drops everything else. For a page that has not been changed, redrawing it is the wrong operation: the right one is to copy the original page. `writePDF` emits a placeholder for such a page and then, once the file is closed, replaces it with the source page through PDFKit. Pages that *have* been changed keep going down the drawing path exactly as now.
**Tech Stack:** Swift 6, PDFKit, Core Graphics, Swift Testing; no dependencies.
**Spec:** Backend only, my lane. Codex is concurrently on native UI polish in `PaperNestUI`; nothing here touches it.

## Constraints and review focus
- **Pass-through is only safe when the page is genuinely unchanged.** All of these must hold: the content is a PDF page, the transform is `PageTransform.identity`, the paper is `.original`, the page carries no ink, and no searchable-text layer is being written for it. Any one of them false and the page is drawn as before. A page that passed through when it should not have would silently export unedited content — the crop the user applied would simply not be there.
- **Verified before being designed around:** a probe confirmed a link and a form widget both survive `PDFPage.copy()` into a fresh document, with the URL and field name intact and the page size unchanged. The approach rests on that, not on an assumption about PDFKit.
- Ink is the subtle one. Ink is drawn by the exporter, not stored in the source PDF, so a page with ink can never pass through. The same is true of the invisible recognised-text layer, which is why a page only passes through when no such layer is being written for it — a digital PDF already carries real text, and overlaying a second copy would be worse than either.
- Page order, page count and the document's own title must be unchanged. The replacement happens by index into the file just written.
- This does not make PaperNest a form filler. The fields it preserves are the ones that were already in the file; filling them is F5 work and is not claimed here.

## Task 1 — knowing when a page is untouched
- [x] Add failing tests for the predicate: an imported PDF page with no edits qualifies; a cropped, rotated, filtered or brightness-adjusted page does not; a page carrying ink does not; export to Letter or A4 does not; an image page never does; a page getting a recognised-text layer does not.
- [x] Add `PageRenderer.sourcePDFData(for:)` beside the existing `recognizedLines` / `inkStrokes` / `embeddedText` accessors.
- [x] Implement the predicate in `PaperNestExport`.

## Task 2 — copying the page instead of redrawing it
- [x] Add failing tests: a link in an imported PDF survives export with its URL; a text form field survives with its field name; a **cropped** page loses them and gains the crop, which is the correct trade and must be pinned; page count, order and document title are unchanged; a mixed document (one untouched page, one edited) exports both correctly.
- [x] Add a synthetic fixture: a PDF carrying a link and a form field.
- [x] Implement the placeholder-and-replace in `writePDF`.
- [ ] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build. The existing pixel-probe, searchable-PDF, compression and archive tests are the real check: they all run through `writePDF`.
- [ ] Record in TEST_MATRIX, strike the limitation from IMPLEMENTATION_PLAN, release the claim.

## Execution ledger
- Baseline: `1501217`, **360 tests passing**, 0 warnings. Codex active on `PaperNestUI` polish.
- Probe result (run and deleted): after `PDFPage.copy()` into a new `PDFDocument`, both annotations survived — `kind=Link url=https://example.com/invoice` and `kind=Widget field=customer` — with text and a 612×792 media box intact. **Corrected 2026-10-26:** that result holds only because the probe built a *fresh* document. Assembling the export in place, in the document opened from the `CGContext`-written file, the field name came back `text5`/`text10` — a different invented name each run. Traced stage by stage: fixture `customer`, stored asset `customer`, exported-in-place `text5`, exported-fresh `customer`.
- The form-field claim is narrower than it first looked. Read back through Core Graphics, the exported file has no catalog `AcroForm` — and neither does the fixture, because PDFKit writes a widget's `/T` without building a form dictionary. So the widget and its name survive, but ledger row 24 stays **Planned**: nothing here shows a real form staying fillable elsewhere.
- Compression deliberately copies an unedited page too. It never re-encoded one (`PageRenderer.prepareSource` returns `.pdf` for an identity transform; `pdfSource` returns early), so a copy costs nothing: 8521 bytes copied against 8531 drawn, identical at every preset. A `rasterQuality` gate was written, measured, and removed — it would have dropped links for no size gain.
