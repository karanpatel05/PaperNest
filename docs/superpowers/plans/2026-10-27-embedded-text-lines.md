# A digital PDF's text keeps its lines on export — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Clear the limitation recorded with the TXT export slice: *embedded PDF text is stored normalized, so such a page exports as one paragraph rather than its lines.* Export a digital PDF as TXT and a page of twelve lines arrives as one run-on paragraph; as DOCX it arrives as a single `<w:p>`. Both shipped features are degraded by it, and `writeText`'s own doc comment admits it.
**Architecture:** The cause is that export reads its text from the **search index**. `LibraryStore.embeddedText` returns what was indexed for FTS, which is normalized for matching — right for search, wrong for export. The fix is to read the lines from the page's own source PDF at export time, which `PaperNestExport` can already do: it has `renderer.sourcePDFData(for:)` and PDFKit. The index is left exactly as it is.
**Tech Stack:** Swift 6, PDFKit, Swift Testing; no dependencies.
**Spec:** Backend only, my lane. Codex is on native UI polish in `PaperNestUI`; nothing here touches it.

## Why not move `PDFTextExtractor`
The earlier note said this needed `PDFTextExtractor` reachable from `PaperNestExport`, which would mean a module move: it lives in `PaperNestImport`, and `PaperNestExport` depends on Core, Store and Render but **not** Import. That move is unnecessary. `PDFPage.string` gives the text with its line breaks, and `PaperNestExport` already opens source PDFs with PDFKit for pass-through. No module graph change, no new dependency.

## Constraints and review focus
- **Precedence is unchanged.** Current completed recognition still wins; the page's own PDF text is the fallback. Nothing is invented for a page with neither, and a document with no text anywhere still throws `noTextToExport` rather than writing a file of separators.
- **Currency is preserved by construction.** Reading from the asset `page.content` points at means the text always describes the paper the page currently shows; a rescanned page cannot export words from the paper it replaced. This is stronger than the index rule it replaces, not weaker.
- **The search index keeps its normalized copy.** It is correct for matching. This slice does not touch `indexEmbeddedText`, the `pdfText` field, or anything search reads.
- **Open each source file once.** A hundred-page document must not open its PDF a hundred times.
- **A cropped page still exports the whole page's text**, as it did before — the crop is a display transform, not a redaction. Unchanged by this slice, and worth stating so nobody reads the improvement as more than it is.

## Task 1 — read the lines from the source
- [x] Failing tests: a three-line digital PDF exports three lines as TXT, and three paragraphs as DOCX.
- [x] A shared helper in `PaperNestExport` returning a page's embedded text line by line.
- [x] `writeText` and `writeDocx` use it; both doc comments lose the apology.

## Task 2 — verify and record
- [x] Regression tests: recognition still takes precedence; a text-free page still contributes nothing; `noTextToExport` still thrown.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX, strike the limitation from the handoff and row 34, release the claim.

## Execution ledger
- Baseline: 397 tests passing, 0 warnings, Mac and iOS builds clean.

## What the plan did not foresee
- **A second fault, found by the failing test rather than by reading the code.** The expected red was "one paragraph"; the actual red was `noTextToExport`. The search index is written by a background pass, so a PDF exported soon after import had no text at all. The same change fixes it, and the export no longer depends on indexing having run.
- **The existing tests were asserting on fiction.** Every embedded-text export test indexed text that was not in the PDF; two asserted a document had no text while importing one that had some, passing only because nothing had been indexed. Rewritten to put the text in the PDF, with a scan for the genuinely-textless cases. This was not in scope and had to be, because the change makes the fiction visible.
- **Accents survive the new source.** `Café Müller reçu 12,50 €` round-trips through `PDFPage.string`, which was worth checking rather than assuming given the fr/es builds.
