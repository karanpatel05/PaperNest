# Vector PDF Text Indexing Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Make digital (vector) PDFs findable by their own body text. Today only Vision-recognized text and titles reach the search index, so an imported text PDF is findable by title alone.
**Architecture:** A fourth `search_index` field value, `pdfText`, alongside the existing `title`, `ocr` and `text`. No migration: `search_index` is an FTS5 virtual table whose `field` column is `UNINDEXED` and unconstrained, and the index is derived and rebuildable. Extraction uses PDFKit in `PaperNestImport` (which already owns PDF reading); the store gains a guarded write. Indexed text is **not** keyed to `page.revision`, because it comes from the immutable asset bytes: crop, rotate and ink must not invalidate it. Only content replacement does.
**Tech Stack:** Swift 6, SQLite/FTS5, PDFKit, Swift Testing; no dependencies.
**Spec:** Engine-only slice of the remaining F4 work (IMPLEMENTATION_PLAN M4; SESSION_HANDOFF "Next for Claude" item 2). Deliberately excludes the recognition status UI, automatic post-scan recognition and the user language override, all of which need `DocumentModel.swift`, `DocumentView.swift` and `Localization.swift` — files held by Codex's open shape-annotation claim. No new user-visible strings, so no localization change.

## Constraints and review focus
- **Stale-write race.** Extraction runs off the store actor. If a page is rescanned between the read and the write, the old PDF's words must not attach to the new content. The write takes the expected `(assetID, pdfPageIndex)` and does nothing when the page's content no longer matches. The guard must **not** use `revision`, which ink edits bump without changing the words.
- **"Checked, no text" must be distinguishable from "never checked."** Most PDFs in a scanner app are image-only, so a pass that cannot tell these apart re-extracts every scan forever. An empty-content `pdfText` row is the done-marker: it never matches a search, and the field-agnostic delete paths already remove it.
- **Indexing is not an edit.** No `touchItem`, no revision bump, no `didChange()`/`changeToken`. `search()` and the library sort by `modified_at`, so a backfill that touched items would reorder the whole library and reload every window.
- Deleted pages and deleted items are skipped. Composition (duplicate/merge/extract) must carry the row, including the empty marker, since `indexCompositionText` skips empty text.
- Existing behavior to preserve: `bumpRevision` must keep leaving `search_index` alone; `replacePage`'s existing `ocr` clearing stays as it is.

## Task 1 — extractor and store write
- [ ] Add failing tests: per-page extraction from a synthetic vector text PDF; `nil` for an image-only PDF and for an out-of-range index; whitespace-only treated as no text.
- [ ] Add failing store tests: indexed body text is found by `search`; the empty marker is written and never matches; a mismatched `expecting:` is rejected without writing; indexing leaves `modified_at`, `revision` and library order unchanged.
- [ ] Implement `PDFTextExtractor.text(in:pageIndex:)` in `PaperNestImport`.
- [ ] Implement `LibraryStore.indexEmbeddedText(_:for:expecting:)` in a new `EmbeddedText.swift`.
- [ ] Add an image-only PDF fixture to `Tests/Support/SyntheticDocuments.swift`.
- [ ] Run focused tests and record red/green results.

## Task 2 — lifecycle and backfill
- [ ] Add failing tests: rescan clears the old words at once and the new words match after indexing; rescan then undo restores the original words; page delete and item delete remove the rows; duplicate/merge/extract carry the text and the marker; crop/rotate/ink preserve it; a second `indexMissing` pass over an image-only PDF has nothing to do.
- [ ] Clear `field = 'pdfText'` in `replacePage` beside the existing `ocr` clearing (the single page-content write path; rescan undo and redo both re-enter it).
- [ ] Add `pagesMissingEmbeddedText(limit:)` and the composition copy helper.
- [ ] Implement `EmbeddedTextIndexer.indexMissing(store:)` in `PaperNestImport`: single-flight, batched, low priority, skipping deleted pages and items.
- [ ] Hook it from `LibrarySession` **after** `state = .ready(env)` so launch is not delayed, and debounced when `changeToken` advances. Claim `AppEnvironment.swift` as the thin layer on the other side, per the handoff convention.
- [ ] Full `./scripts/test.sh`, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build.
- [ ] Fresh independent review, fix significant findings with regressions, then update TEST_MATRIX and SESSION_HANDOFF in new sections of my own. No commit unless the owner asks.

## Execution ledger
- Baseline: `6a04173` plus Codex's uncommitted shape work. `./scripts/test.sh` measured **259 passed, exit 0** (59 UI + 86 Store + 47 Import + 26 Export + 41 Core) before this slice.
- Probe (run and deleted): PDFKit returns `"Hello searchable world"` and `"Second page words"` from `SyntheticDocuments.textPDF(pages:)`, confirming the fixture carries extractable vector text.
