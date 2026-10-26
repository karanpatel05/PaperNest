# Automatic Text Recognition Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Recognize text without being asked. Today nothing is searchable by its contents until the user opens a document's **More → Recognize Text** and waits, page by page; an imported scan is findable by title alone until they do. A rescanned page keeps its old, now-wrong text until someone notices.
**Architecture:** A background pass in the shape of `EmbeddedTextIndexer`, which this slice deliberately copies: a store query naming the work, an actor that does it in batches, and a trigger from `LibrarySession` once the library is ready and after each library change. The pass reuses the existing `PageRenderer.renderSourceForRecognition` → `TextRecognizer.recognize` → `LibraryStore.saveRecognition` path exactly as the manual action does, so recognition itself is unchanged and stays honest about where its text came from.
**Tech Stack:** Swift 6, SQLite, Vision, Swift Testing; no dependencies.
**Spec:** The next item in SESSION_HANDOFF's "Next for Claude" list, now that vector-PDF indexing is done. Covers **automatic recognition after import or scan** and **re-recognition after a rescan**. Deliberately excludes the user language override and the recognition status surface outside the menu: both are UI-led and belong with whoever owns `DocumentView.swift` next.

## Constraints and review focus
- **Never OCR a page that already carries real text.** A digital PDF's own words are better than Vision's reading of a raster of those words. A non-empty `pdfText` row means the page's text is already indexed, so the pass skips it; an *empty* marker means a scan with no text layer, which is exactly what needs OCR. This is why the previous slice's marker exists.
- **Decide "needs work" from stored state, not from a queue.** A page needs recognition when it has no result, when the result's `source_revision` no longer matches the page (a rescan), when it is still `pending`, or when it was produced by a different `engineVersion`. A **failed** result at the current revision and engine is left alone, so a page that cannot be read is not retried forever; a rescan or an engine change is what gives it another chance. `engineVersion` is passed in, because the store does not know about Vision.
- **Recognition is expensive; the pass must be interruptible and resumable.** One page at a time (a page is rendered at 2 pixels/point and large pages are big), batched, low priority, cancellation-checked, and single-flight. All progress is per-page in `page_recognition`, so a kill mid-pass loses at most one page.
- **Saving results is already correct; do not reimplement it.** `saveRecognition` commits the result and the search index together, and refuses to make a stale result findable. The pass must go through it.
- Skip template pages (nothing to read), deleted pages, deleted items, and pages whose original is not on this device.
- Unlike the embedded-text pass, this one **does** change what the user sees: a page gains searchable text and `saveRecognition` bumps nothing but the recognition row, so the library order must still not move. Verify that.

## Task 1 — the store query
- [ ] Add failing tests: a page with no result is named; a current completed result is not; a rescanned page is named again; a `pending` result is named; a result from another `engineVersion` is named; a `failed` result at the current revision and engine is **not**; a page whose PDF already carries text is **not**, while a scanned page with an empty marker **is**; template pages, deleted pages, deleted items and remote-only originals are all skipped.
- [ ] Implement `LibraryStore.pagesNeedingRecognition(engineVersion:limit:)` in a new `AutomaticRecognition.swift`.
- [ ] Run focused store tests and record red/green.

## Task 2 — the pass and its trigger
- [ ] Add failing tests: an imported scan becomes findable by a word on it with no manual action; a digital PDF is left to the embedded-text path and gets no OCR row; a rescanned page's old words stop matching and its new words match; a second pass has nothing to do; recognition does not reorder the library or change `modified_at`.
- [ ] Implement `AutomaticTextRecognizer` (actor) in `PaperNestRender`, beside `TextRecognizer`. Note in the file that the planned Recognition module in ARCHITECTURE should absorb both when it is created; do not move `TextRecognizer` in this slice, since `PaperNestUI` and `PaperNestExport` both import it from here.
- [ ] Trigger it from `LibrarySession` after `state = .ready(env)` and on each change, coalesced, exactly as the embedded-text pass is.
- [ ] Full `./scripts/test.sh`, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build.
- [ ] Record honest results in TEST_MATRIX, including what was not run, and release the claim. No commit unless the owner asks.

## Execution ledger
- Baseline: `5e0b053`, clean tree, **283 tests passing**, 0 warnings, no active claims by either session.
- Existing manual path for reference: `DocumentModel.recognizeText(on:)`, which renders at `pixelsPerPoint: 2`, saves each page as it finishes so a long document is useful early, and keeps going when one page fails.
