# Text Export Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** F4's outstanding TXT deliverable, and row 34's "PDF to Text". A document's words can be searched inside PaperNest but cannot be got *out* as text: every export is a PDF or an image.
**Architecture:** `ExportFormat` gains `.txt`, because plain text genuinely is an export format and `ExportOptions.format` is its natural home. A page's text comes from the best source it has: current completed recognition first, because those lines keep their structure; failing that the text a digital PDF already carries, which the vector-PDF indexing slice records. Pages are separated by a form feed (U+000C), the conventional ASCII page break — deliberately not a worded separator, which would need a localized string and therefore a file another session owns.
**Tech Stack:** Swift 6, Swift Testing; no dependencies.
**Spec:** Engine only. Codex's queue is F3 interface work; the export sheet's format tiles are hand-written one per format, so a new case appears in no UI until someone adds a tile — which is the honest state for an engine slice.

## Constraints and review focus
- **Never write an empty file and call it an export.** A document with no text on any page throws `ExportError.noTextToExport` rather than producing a zero-byte or separator-only file. This is the "empty-content warning" the roadmap asks for, expressed where it cannot be ignored.
- **Recognition first, embedded text second, and no invention.** Recognized lines keep their line structure. The embedded-PDF text is stored normalized for the search index, so its whitespace is collapsed and a page of it arrives as one paragraph: a real limitation to state plainly, not paper over. Nothing is synthesised for a page that has neither.
- Only text that is **current for the page** counts. `recognizedLines(for:)` already refuses a result from an older revision, and the embedded text is cleared when a page's content is replaced, so a rescanned page cannot export words describing paper it no longer shows.
- `ExportFormat` is public and `CaseIterable`, but nothing iterates it and the picker tiles are hand-written, so the new case breaks nothing. Adding a *tile*, its content type and any format-specific options is the UI owner's work, and it must not appear as a tool that does not work.
- Reading the stored text needs a store accessor. Follow the existing pattern: `PageRenderer` already exposes `recognizedLines(for:)` and `inkStrokes(for:)` to the exporter, so embedded text joins them rather than giving `Exporter` its own store reference.

## Task 1 — getting the stored text back
- [ ] Add failing tests: a page's indexed embedded text reads back; a page with only an empty marker reads back as nothing; a page never looked at reads back as nothing; the text disappears when the page's content is replaced.
- [ ] Add `LibraryStore.embeddedText(for:)` and `PageRenderer.embeddedText(for:)`.
- [ ] Run focused tests, record red/green.

## Task 2 — the writer
- [ ] Add failing tests: a scanned document exports its recognized words; a digital PDF exports its own text with no recognition present; recognition wins when a page has both; pages are separated by a form feed in page order; a page with no text contributes nothing without breaking its neighbours; a document with no text anywhere throws `noTextToExport` and writes nothing; the file is valid UTF-8.
- [ ] Add `ExportFormat.txt`, its extension, and the writer behind the existing `export` switch.
- [ ] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build.
- [ ] Record honest results in TEST_MATRIX, release the claim. No commit unless the owner asks.

## Execution ledger
- Baseline: `081ffe6` plus my uncommitted recognition, F2d and file-compression slices, **325 tests passing**, 0 warnings.
- DOCX, the harder sibling, is deliberately not in this slice: it needs a real container writer and validation against an external editor.
