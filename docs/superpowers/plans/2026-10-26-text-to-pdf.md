# Text to PDF Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Half of ledger row 33, and the "Text to PDF" tile in the reference converter list. A `.txt` file is kept as an opaque file item today: you can preview and share it, but not annotate, crop, reorder or export it, because it has no pages. Converting it makes it a real document.
**Architecture:** CoreText lays the text out and paginates it — `CTFramesetter` breaks lines and reports how much fitted, which is what makes page breaks correct rather than guessed. The result is PDF data, handed to the existing importer so it becomes an ordinary page-based document through the path every other import already uses. Nothing new owns the library.
**Tech Stack:** Swift 6, CoreText, Swift Testing; no dependencies.
**Spec:** Backend only, my lane. Conversion is **explicit**, not automatic: importing a `.txt` keeps storing it as a file item exactly as it does now, because that behaviour is covered by existing tests and is the right default for a file someone wants kept as itself. This adds a conversion someone can choose.

## Constraints and review focus
- **Pagination must be real, not estimated.** `CTFramesetterSuggestFrameSizeWithConstraints` and the range a frame actually consumed decide where a page ends. Guessing by character count breaks the moment a line wraps, and silently drops text off the bottom of a page — the worst outcome, because the file looks fine.
- **Nothing may be lost.** The test that matters is a round trip: render text to PDF, extract it back with `PDFTextExtractor`, and find the words. That also ties the feature to the indexing already built, so a converted document is searchable by its contents for free.
- **Long lines wrap, they do not clip.** A single line wider than the page must break, and a very long word must not vanish off the right margin.
- Text that is empty, or only whitespace, is refused rather than producing a blank one-page PDF that looks like a successful conversion of nothing.
- UTF-8 throughout: accents and non-Latin text survive, and the PDF carries real extractable text rather than an image of text.
- A4 by default to match the notebook paper the project already uses, with margins that leave the result readable rather than edge-to-edge.

## Task 1 — the renderer
- [ ] Add failing tests: short text yields one page whose words extract back; text longer than a page yields several pages with nothing lost across the break; a single over-long line wraps instead of clipping; accents survive; empty and whitespace-only text are refused.
- [ ] Implement `TextToPDF.render(_:pageSize:margin:)` in `PaperNestImport`.
- [ ] Run focused tests, record red/green.

## Task 2 — becoming a document
- [ ] Add failing tests: converting a text file produces a **document** with the expected page count, not a file item; its pages are real PDF pages; the words are findable through the existing embedded-text indexing; the original text file is untouched.
- [ ] Add the conversion entry point on `DocumentImporter`, reusing the existing import path so the store, durability and dedup rules are unchanged.
- [ ] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build.
- [ ] Record in TEST_MATRIX, note that no UI offers the conversion yet, and release the claim.

## Execution ledger
- Baseline: `32b0b58`, **348 tests passing**, 0 warnings, no active claims by either session.
- Reuses `PDFTextExtractor` from the vector-PDF indexing slice for the round-trip check — the strongest available proof that nothing was dropped.
- Not in scope: DOCX, XLSX and PPTX to PDF, which need a real Office renderer and belong to the F5 engine decision. This is the one part of row 33 that needs no external engine.
