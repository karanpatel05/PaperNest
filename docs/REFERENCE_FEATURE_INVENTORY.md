# Reference feature inventory (owner's screenshots, 2026-10-21/22)

**For Codex, to continue the expansion.** Written by Claude on 2026-10-22 from ten screenshots the owner supplied of *Documents by Readdle* (iPhone and iPad App Store listing, in-app screens and paywall). The owner's instruction was: **"I want all these features."**

This file is the capability record behind [FEATURE_EXPANSION.md](FEATURE_EXPANSION.md), which keeps the delivery order (F1–F9). Nothing here changes `CLAUDE_CODE_PROMPT.md`, which stays as written.

**Scope confirmed again on 2026-10-23:** after reviewing the Convert Files / Enjoy Media picture and its feature-by-feature status, the owner said **“All features to pipeline including media.”** Every identified feature in this inventory remains in scope. Media rows 42–44 are explicit deliverables; see the F7a–F7d breakdown in FEATURE_EXPANSION. This confirmation does not mark planned tools as built.

## How to use this file

- It is a **capability reference, not a design reference.** PaperNest keeps its own Clean & Native look ([CLEAN_NATIVE_DESIGN.md](CLEAN_NATIVE_DESIGN.md)) and the owner's mockups in `docs/design/mockups/`.
- The screenshots in `docs/design/reference/` are the competitor's copyrighted material. They are **research input only**: never ship their images, icons, screenshots, copy or brand in PaperNest, and never copy their marketing claims ("50+ premium actions", "30+ professional tools", "115M+ downloads", "558K ratings", "Editors' Choice", "Powered by seamlessly integrated AI"). PaperNest states only what PaperNest actually does.
- Feature rows below are paraphrased observations of what the reference app claims or shows, not transcriptions.
- **A capability listed here is not a promise that it works in PaperNest.** The status column is the truth; `docs/TEST_MATRIX.md` is the evidence.

## Source images

| File | What it shows |
|---|---|
| `docs/design/reference/01-paywall-trial-timeline.png` | Paywall: "How your free trial works" timeline, price, CTA |
| `docs/design/reference/02-app-store-description.png` | Full App Store description, section by section |
| `docs/design/reference/03-secure-browsing-vpn.png` | "Secure browsing" screenshot: VPN panel and built-in browser |
| `docs/design/reference/04-work-with-files-actions.png` | "Work with files": the file action sheet, compress, passcode |
| `docs/design/reference/05-convert-files-and-media.png` | "Convert Files" and "Enjoy Media" screenshots side by side |
| `docs/design/reference/06-tools-screen-full.png` | The Tools screen in full: every converter and PDF tool tile |
| `docs/design/reference/07-take-notes.png` | "Take Notes": weekly-plan template, ink, highlights, stickers |
| `docs/design/reference/08-edit-pdf.png` | "Edit PDF": Annotate/Insert/Draw/Pens tabs, colour picker |
| `docs/design/reference/09-manage-files.png` | "Manage Files": sidebar, My Files grid, import/create menu |
| `docs/design/reference/10-hero-positioning.png` | Hero card: the six headline capabilities |

---

## 1. What the reference app claims (App Store description, paraphrased)

**File manager** — browse, organise and manage local files and folders in one browser; rename and colour-tag them; import from a computer; download from the built-in web browser; work with iCloud, Dropbox, Google Drive and other cloud drives *without downloading first*.

**Archives** — unzip and extract ZIP and RAR on device; create ZIP archives from several files; compress large files and folders to save space.

**PDF editor, viewer and converter** — view PDFs, books and scans in a fast viewer; edit or modify existing text *inside* a PDF; highlight, add notes, place stickers; merge, split, rotate and reorder pages; convert PDF to Word, JPG, PNG, HEIC and more.

**Sign documents** — add a signature to contracts and forms; fill forms and place text, checkmarks and initials anywhere; store signed contracts and reach them from any device.

**File converter and compressor** — convert between PDF, DOCX, JPG, JPEG, PNG, HEIC, WEBP and more; compress PDFs, photos and files to get under email or upload limits; create PDFs from photos, scans or documents and convert them back to editable formats.

**Scanner** — scan receipts, books and documents with a built-in OCR scanner; save scans as searchable PDFs, locally or to a cloud drive.

**Also inside** — transcribe audio and video to text, then edit or export the transcript; a "Smart Eraser" that removes unwanted objects from photos; music and video playback; file transfer to a Mac or PC over Wi-Fi.

Hero card headline capabilities: organise files, edit PDF, take notes, convert files, enjoy media, and a large set of professional tools.

---

## 2. Screen-by-screen inventory

### 2.1 Manage Files (`09-manage-files.png`)

- Sidebar sections — **My Files**, **Tools**, **Browser**, **VPN**, **Recent Files**; then **CONNECTIONS**: Computer, Files (the OS file provider), Documents in iCloud, Dropbox, Google Drive, **Add Connection**; then **FAVORITES**, an empty drop target reading "Drag and drop files or folders here to add them to Favorites list".
- Content pane: a **grid of mixed item kinds** — a system "Inbox" folder with an item count, a "Photos" folder bound to Apple Photos, a "Cable Connections" folder, ordinary folders, and **arbitrary files with their real sizes** (`.txt` 2 KB, PDFs 4 MB / 24 MB, a video 350 MB with a duration badge, audio tracks). Each tile has a ⋯ menu.
- A floating **+** opens a combined sheet: **IMPORT** — Import from Photos, Add from iPadOS Files, Connect to Computer; **CREATE** — New Folder, PDF Note, Scan Document, Text File, Take Photo, Add Connection; **IMPORT FROM CLOUD STORAGE** — Dropbox.

**Implication for PaperNest:** the library must hold **arbitrary file items**, not only page-based documents, with real byte sizes, type-specific previews and a system Inbox. That is workstream **F2** and needs a schema design of its own — not dummy single-page documents wrapping a file.

### 2.2 Edit PDF (`08-edit-pdf.png`)

- Document toolbar tabs: **Annotate · Insert · Draw · Pens**, plus `+`, search, text-size control and ⋯.
- Annotate row: three highlight styles (highlight, underline, strikethrough), a text box tool, pen, colour swatch, eraser, a **note/comment** tool, a **stamp/sticker** tool and an image/sticker tool, with undo.
- Visible on the page: coloured highlights over running text, a hand-drawn circle, a sticky-note block with a bulleted list, an underline, and a photo placed in the page.
- A **Customize Colors** popover: full colour matrix, an eyedropper, PRESETS row and Restore.

**Implication:** highlight / underline / strikethrough over *recognised text runs* (not freehand), text boxes, notes, stamps and placed images, each independently editable, all in `PageGeometry` source space. Workstreams **F3** (annotation objects) and **F5** (true in-PDF text editing).

### 2.3 Take Notes (`07-take-notes.png`)

- A **weekly-plan template** with day rows (M/T/W/T/F/S) and a to-do column, written in ink.
- Mixed content on one page: handwriting, highlighter strokes in several colours, strike-through on completed items, arrows connecting blocks, an emoji sticker, and typed-looking headings.
- Toolbar: Annotate · Insert · **Draw** · Pens, with shape tools (lasso, rectangle, circle, line, arrow), pen/marker/eraser and undo.

**Implication:** notebook creation plus templates (the model and rendering already exist in PaperNest), shape tools, lasso selection and a pen/marker/eraser palette. Workstream **F3**, building on the existing `InkCanvas` work — **do not regress it**.

### 2.4 Tools screen (`06-tools-screen-full.png`) — the full tile list

This is the single most useful screenshot: it enumerates the product's tool surface.

| Group | Tiles |
|---|---|
| **Pro Converter — Convert to PDF** | Image to PDF, Spreadsheet to PDF, Document to PDF, Presentation to PDF, Text to PDF, Merge to PDF |
| **Pro Converter — Convert from PDF** | PDF to Image, PDF to Excel, PDF to Word, PDF to PowerPoint, PDF to Text |
| **PDF Editor** | Manage Pages, Sign PDF, Reduce File Size, Edit PDF, Merge PDFs, Set Password, Annotate, Redact PDF, Fill Form |
| **Photo Tools** | (partly cut off; at least three tiles, one of which is the object remover) |

**Implication:** PaperNest's own Tools screen is the natural home for F1's merge/extract and everything after. Our rule stands: **a tile appears only when the tool works.** No greyed-out marketing tiles.

### 2.5 Convert Files and Enjoy Media (`05-convert-files-and-media.png`)

- Converter screenshot caption: convert to and from PDF, and convert to MP3.
- Media: a **music player** (artwork, scrubber, elapsed/remaining, shuffle/repeat, previous/play/next, a PLAYER / LIBRARY segmented control, a speed control showing 0.8× / **1.0×** / 1.25×), a **video player** with a fit/fill control and picture-in-picture, and an audio **library list** showing MP3s with size and date.

**Implication:** workstream **F7**. Background playback, resume position, playlists and per-format support need to be verified per platform rather than assumed.

### 2.6 Work with files (`04-work-with-files-actions.png`) — the file action sheet

Caption: Zip & Unzip · Scan · Protect with a passcode. The long-press/⋯ sheet on a 129.6 MB `.MOV` contains:

- A header row of four round actions: **Nearby**, **Share**, **Email**, **upload to cloud**.
- **Transcribe to Text** (badged **New**), **Convert to MP3**, save to **Photos**, **Copy to**, **Move**, **Rename**.
- **Compress** (callout), **Delete** (destructive), **Highlight with Color**, **Add to Favorites**, **Show Info**.

**Implication:** per-item actions are kind-aware (Convert to MP3 and Transcribe only make sense for media). "Highlight with Color" is the same idea as PaperNest's new **colour labels**, already shipped in the F1 slice. "Show Info" is the file-details sheet **F2** needs. Nearby/Email/cloud upload are share destinations.

### 2.7 Secure browsing (`03-secure-browsing-vpn.png`)

- **Built-in browser**: address bar with a VPN pill, tabs, a page open, a **Downloads** panel listing in-flight downloads with size and percent complete, a **Save Page** action, and share/RSS buttons.
- **VPN**: a world map, a big power button reading **STOP**, a session timer (`00:00:10`), and purpose chips — Video Streaming, Music Streaming, Sports Streaming, Unblock Gaming.

**Implication:** workstreams **F8** (browser + download manager + save page as PDF) and **F9** (VPN). F9 is a *service*, not a UI: it needs a provider, entitlement, provisioning, billing and a privacy position before any of it is shown. Do not build a VPN screen that does not connect.

### 2.8 Hero positioning (`10-hero-positioning.png`)

Six headline capabilities: organise files · edit PDF · take notes · convert files · enjoy media · a large professional-tool set. Useful as a **grouping** for PaperNest's own Tools screen and onboarding; the numbers and awards on that card are theirs, not ours.

### 2.9 Paywall and trial (`01-paywall-trial-timeline.png`)

Reference flow, for **M5** when it is built:

- Title "How your free trial works", with a four-step vertical timeline: **Install & Set up** (done) → **Today: Get Instant Access** → **Day 5: Trial Reminder** (email/notification that the trial is ending) → **Day 7: Trial Ends**.
- Footer: **$9.99/month · 7-day free trial**, "Recurring billing · Cancel anytime", a primary **Try for $0.00 now** button, and **Restore purchases**.
- A close (×) button is present — the paywall is dismissible.

**Rules for PaperNest's paywall (from the brief and CLAUDE.md):**
- Prices come from **StoreKit**, never hard-coded. The $9.99 above is the reference app's price and is **not** a decision for PaperNest — the owner sets pricing and trial length.
- "Day 5: Trial Reminder" is a real obligation: it needs a scheduled local notification and/or email, or the screen must not claim it.
- Restore must actually restore. Documents stay readable and exportable after a subscription lapses.
- No fake purchase flow and no mock entitlement state, ever.

---

## 3. Capability checklist

Status as of 2026-10-24, except where a row carries a later date of its own. **Done** = implemented *and* recorded in TEST_MATRIX. **Partial** = only the stated subset. **Planned** = not implemented.

| # | Capability | Status in PaperNest | Workstream |
|---|---|---|---|
| 1 | Browse/organise folders, rename, sort, search, favourites, recent, trash | **Done** for page-based documents | M1 |
| 2 | Colour labels on items | **Done** (schema v4, seven colours) | F1 |
| 3 | Multi-select, duplicate, batch move/delete | **Done** | F1 |
| 4 | Merge documents with an explicit order | **Done** | F1 |
| 5 | Extract pages into a new editable document | **Done** | F1 |
| 6 | Split a document into one file per page | **Done** (2026-10-22) | F1 follow-up |
| 7 | Bulk share / export a selection as one ZIP | **Done** (2026-10-22). Size-reduction presets are row 35, not this | F1 follow-up |
| 8 | Arbitrary file items (any type) with real size and previews | **Partial** (2026-10-22) — any type imports, shows its size/type symbol and opens in system Quick Look; generated grid/list thumbnails remain open | F2a |
| 9 | File details / "Show Info" sheet | **Done** (2026-10-22) — kind, original name, size, dates, Share, Save a Copy | F2a |
| 10 | Import from Photos | **Done** for images (2026-10-22); video needs a streaming transfer and is still open | F2c |
| 11 | System Inbox folder | **Planned** | F2 |
| 12 | Create ZIP from a selection | **Done** (2026-10-22) — documents as PDFs, files byte for byte, from the selection bar, the Tools screen and the Settings backup | F2b |
| 13 | Extract ZIP | **Done** (2026-10-22) — traversal, symlink, encryption, expansion-ratio and total-size limits, each with an adversarial test | F2b |
| 14 | Extract RAR | **Planned** — licensing question first; creation is *not* requested | F2 |
| 15 | PDF/page viewer | **Done** | M1 |
| 16 | Rotate, reorder, delete, add pages | **Done** | M1 |
| 17 | Crop | **Done** | M1 |
| 18 | Rescan / replace a page | **Done** (file path; camera path needs a device) | M1 |
| 19 | Freehand ink, Apple Pencil on iPad | **Done, first slice** (`InkCanvas`, undo, export) — **preserve this** | M3/F3 |
| 20 | Highlight / underline / strike through text | **Partial** (2026-10-24) — whole recognized lines, editable ink, undo/reopen/export covered by unit tests; iPhone/iPad Simulator workflows pass in en/fr/es. Native Mac annotation interaction remains unrun. F3b preset/custom colors and saved-ink selection/recolor/removal are implemented; iPhone/iPad preset-manager workflows pass in en/fr/es. System custom-picker interaction remains unrun. **Word-level boxes now exist** (2026-10-27): recognition carries each line's words with their own boxes, from Vision rather than from dividing the line box by character count, so a screen can select one word instead of the sentence around it. Results recognised before this have no words and fall back to the line — nothing is recomputed behind the user's back. **The selection UI itself, moving/resizing marks outside PencilKit and semantic annotation objects remain planned.** | F3 |
| 21 | Notes/comments, stickers, shapes, inserted text and images | **Partial** (2026-10-25) — private per-page comments (add/edit/delete, guarded undo/redo, kept out of PDF/image exports, schema v7) and outlined rectangles/ellipses/lines/arrows saved as editable ink with preview placement, colour and width. Stickers/stamps, text boxes and placed images remain planned; models for text/image objects exist. Post-save shape resize handles and exported positioned PDF comment annotations are separate work | F3 |
| 22 | Notebook creation, templates, planners | **Partial** (2026-10-25) — Tools creates a one-page blank/lined/grid A4 notebook and opens the existing editor, and further blank/lined/grid A4 pages can be inserted after the selected page with guarded undo/redo. Planners and notebook-specific navigation remain | F3 |
| 23 | Visual fill & sign, saved signatures, initials, checkmarks | **Partial** (2026-10-27) — **saved signatures work in the engine**: ink captured once, kept at schema v9, and placed again on any page with its **aspect ratio preserved** (a stretched signature is a different shape from the one the person drew). Checkmarks already shipped as symbol stamps. **It is a picture of a signature, not a cryptographic one** — no certificate, no timestamp, nothing attested; the honest verb is *placed*, and no screen may say "signed" or "verified". No UI, and initials and typed fill-in remain planned | F3 |
| 24 | Interactive PDF form fields preserved | **Planned.** An unedited page is now copied rather than redrawn on export (2026-10-26), so a field widget and its `/T` name do survive, checked through PDFKit. But no document-level `AcroForm` is written — verified through Core Graphics, where the exported catalog has no form dictionary, and neither does the synthetic fixture — so nothing here says a real form stays fillable in another reader. **Done 2026-10-27 for text fields.** The hand-built fixture exists — raw PDF bytes with computed xref offsets, since PDFKit keeps an `/AcroForm` but never creates one — and `PDFForm` reads a real form's fields and fills them, with the filled value verified in the written file **through Core Graphics**. Unknown names and form-less PDFs are refused rather than ignored. **Checkboxes are fillable too as of 2026-10-27**: `buttonWidgetState` writes both `/V` and `/AS` as names, using the widget's own on-state name, and `FormValue` is typed so text offered for a box — or a tick for a text field — is refused rather than coerced. **Choice fields are still reported but not fillable**, since picking a value means reading the options the form declares. Filling does not flatten, and PaperNest still writes no AcroForm of its own, so a form can be filled but not created. No UI. | F5 |
| 25 | Edit existing text and images inside a PDF | **Planned** — needs an engine decision | F5 |
| 26 | Permanent redaction (content removed, not covered) | **Partial — engine only** (2026-10-27). `PageRedaction.redactedPNG` flattens the page to pixels and paints the regions, so the words are not in the bytes at all; adversarial tests check the text is gone and the pixels are black, not that a rectangle was drawn. `LibraryStore.forgetReplacedContent(for:)`, `deleteRecognition(for:)` and `isAssetReferenced(_:)` let the original be swept and the recognised words deleted. **Three honest limits:** a digital PDF loses selectable text across the whole page, not just the redacted part; a **shared** original is kept because another page needs it, and that is reported rather than hidden; and deleting a file does not scrub the disk. **Now callable as one operation** (2026-10-27): `PageRedactor.redact` renders, stages, replaces the page's content, deletes the recognised words, forgets the undo history and deletes the original — reporting `originalStillInLibrary`, where **true is the unsafe answer**, because a shared original cannot be deleted and the words stay reachable through the other page. `LibraryStore.deleteAssetIfUnreferenced` is targeted rather than a sweep. Still **no UI**, and ink/comments under a rectangle are untouched | F5 |
| 27 | Set a PDF password / encrypted export | **Partial** (2026-10-27) — protected PDFs import, and `Exporter.export` now takes an optional password and writes a PDF that needs it to open. **It is AES-128** (`/V 4 /R 4 /Length 128 /AESV2`), read out of the written bytes and pinned by a test — not RC4, and not the AES-256 of revision 6, which Apple's APIs do not expose. Revision 4's key derivation is fast, so the strength is the password, and the wording on any screen must say so. User and owner passwords are both set, because a document opens with either. No UI; permissions (print/copy flags separate from opening) are not settable; the password must be ASCII, since even a Latin-1 one failed to write; and only its first 32 bytes are honoured | F3/F5 |
| 28 | App lock (passcode / biometric) | **Planned** — distinct from encryption at rest | F3 |
| 29 | Scanner with OCR, searchable PDF | **Partial** — camera wrapper and import exist; **OCR and searchable-PDF export both work** (2026-10-22); the real-camera test is still open | M4/F4 |
| 30 | Text search across documents | **Done** for recognized text and titles (2026-10-22) and for the text digital PDFs already carry (2026-10-25); typed notes follow with F3 | F4 |
| 31 | Images ↔ PDF (JPEG, PNG) | **Done** | M1 |
| 32 | HEIC and WEBP | **Partial** (2026-10-27) — HEIC import and conversion to PDF implemented (2026-10-22), verified against ImageIO. **WebP import now works too**, added only after checking: `CGImageSourceCopyTypeIdentifiers` lists `org.webmproject.webp` and `CGImageDestinationCopyTypeIdentifiers` lists **no** WebP at all. So the support is asymmetric and settled, not pending — **converting *to* WebP is impossible with system frameworks** and needs a third-party encoder (libwebp), with the licensing and binary-size decision that implies. An animated WebP decodes to its first frame; that is not animation support. Schema **v8** widens the asset-kind constraint; next migration must be v9. **HEIC export now works** (2026-10-27), measured the same way: ImageIO's HEIC support is symmetric, and on a 1600×2000 page HEIC is 94,742 bytes against 284,377 as JPEG and 209,699 as PNG, with the requested dpi preserved. A test reads the written bytes back, because the old `format == .jpeg ? .jpeg : .png` would have put PNG bytes in a `.heic` file. **Compatibility is the caveat and JPEG stays the default** — HEIC is the format most likely to reach somewhere that cannot open it. No UI tile | F2c/F4 |
| 33 | Office → PDF (DOCX, XLSX, PPTX), TXT → PDF | **Partial** (2026-10-26) — **TXT → PDF works in the engine**: CoreText pagination, wrapping, real extractable text so the result is searchable and annotatable, and an explicit conversion that leaves normal `.txt` import keeping the file as itself. No UI, and the layout is fixed (Helvetica 11pt, A4, 54pt margins). Office formats need a real renderer and remain F5 | F4/F5 |
| 34 | PDF → Word / Excel / PowerPoint / Text | **Partial** (2026-10-26) — PDF/scan → **plain text and basic Word (.docx)** both work in the engine, from recognized text and the text digital PDFs carry, with page breaks and a refusal when there is no text; no UI for either and **nobody has yet opened a .docx in a word processor**. A digital PDF's text now keeps its lines (2026-10-27): it is read from the page's own file rather than from the search index, which also fixes a second fault — export used to depend on the background indexer having run, so a PDF exported soon after import was refused as having no text at all. The Word output is words-in-paragraphs, not layout. Excel and PowerPoint remain, and retain-layout versus editable-output are still separate modes | F4/F5 |
| 35 | Compression presets with before/after size | **Partial** (2026-10-26) — engine presets (light/strong/smallest) produce a smaller PDF and report measured before/after bytes, reporting no saving honestly when a source cannot be reduced. **Scanned PDFs now compress too** (2026-10-26): a page with no text of its own is re-encoded, kept only when it beats the page it replaces — 193,043 → 113,235 at Strong, 56,430 at Smallest. A page *with* text is never rasterized, and most scanner apps embed an invisible OCR layer that counts as text, so only image-only scans benefit; Light (300 dpi) upsamples most scans and leaves them alone. **PDF file items compress too** (2026-10-27), by the same rule: 193,043 → 111,920 at Strong, 55,115 at Smallest, while a digital PDF comes back readable and reports no saving. **Image-format output now exists** (2026-10-27): `compress(fileNamed:data:preset:format:)` can write HEIC instead of JPEG, about a third the size at the same quality. **JPEG stays the default** — compression exists to make a file easier to send, and a HEIC the recipient cannot open is worse than a larger JPEG — so the caller opts in. The PDF path is unaffected, since HEIC is not a PDF image filter. **Archive compression now works too** (2026-10-27), which closes the row's engine work: `exportArchive(…preset:)` applies a preset across a selection, returning the ordinary output rather than inventing a "before" the caller already knows. **Nothing is ever dropped** — anything that cannot be compressed goes in as it was — and **nothing is grown**, so a re-encode that came out bigger is discarded. Non-image files keep their bytes exactly; a re-encoded image changes extension. No UI for any of it | F2/F4 |
| 36 | Bookmarks, reading mode, book formats | **Partial** (2026-10-27) — the **navigation** half for one explicitly named format: `PageRenderer.outline(for:)` reads a PDF's own table of contents and resolves it against the pages the document shows now, dropping any entry whose page was deleted and gathering both outlines when a document was built from two PDFs. Entries keep the author's order and nesting, so a reordered document's outline will not ascend — a true description of the file rather than a re-sort. Read-only: no schema change, nothing stored, no UI. **User-created bookmarks, reading mode and non-PDF book formats remain Planned**, and the condition stands that any format must be named explicitly | F3/F4 |
| 37 | iCloud sync | **Planned** — design in ARCHITECTURE.md; needs an Apple team and container | M2/F6 |
| 38 | Dropbox / Google Drive / other providers | **Planned** | F6 |
| 39 | Remote files without downloading first (cached / remote-only / downloading / offline states) | **Planned** | F6 |
| 40 | Wi-Fi transfer to a Mac or PC; cable/Files access | **Partial** — native share exists | F6 |
| 41 | Nearby / Email / cloud-upload share destinations | **Partial** — native share sheet only | F2/F6 |
| 42 | Audio and video playback, audiobooks, playlists, speed, background, resume | **Planned; explicitly confirmed 2026-10-23** — includes seek, metadata/artwork, previous/next, shuffle/repeat, system controls and supported picture-in-picture | F7a/F7b |
| 43 | Convert media to MP3 / extract audio | **Planned; explicitly confirmed 2026-10-23** — codec and licensing review first; progress, cancellation and real output verification | F7c |
| 44 | Audio/video → editable transcript with timestamps and export | **Planned; explicitly confirmed 2026-10-23** — disclose on-device vs network per engine; persist transcript edits | F7d |
| 45 | Smart Eraser / object removal in photos | **Planned** — preview, undo, original preserved | F8 |
| 46 | Built-in browser, downloads, save web content | **Planned** | F8 |
| 47 | VPN with real connection state and server choice | **Planned** — ship only with a working provider | F9 |
| 48 | Subscription, free trial, trial reminder, restore | **Planned** — StoreKit 2; prices from StoreKit | M5 |

---

## 4. Where PaperNest stands today (2026-10-24)

- F1 document tools are implemented. General file items, previews/details, Photos/HEIC import, ZIP creation/extraction, OCR/search/searchable PDFs and the first text-annotation slice are also implemented; remaining work is described by the individual rows above.
- Latest implementation verification: 235 unit tests and a Mac build passed; F3a annotation workflows passed on iPhone/iPad in en/fr/es and F3b manager/color controls passed on both devices, with the iPad drawing regression also passing. Real camera/Pencil and remaining native Mac checks are still open. Exact evidence and run scope are in [TEST_MATRIX.md](TEST_MATRIX.md).
- F5–F9, including dedicated media playback/conversion/transcription, remain planned. The 2026-10-23 pipeline confirmation did not implement media or other future tools.
- Current branch/commit and uncommitted work are recorded in [SESSION_HANDOFF.md](SESSION_HANDOFF.md). **Commit only when the owner asks.**

## 5. Suggested order for Codex

The delivery order in FEATURE_EXPANSION.md still stands. Concretely, the next slices:

1. ~~**Finish F1**~~ — **done 2026-10-22**: `LibraryStore.splitItem` and selection-wide ZIP export (`BulkExportModel`). F1 is complete as scoped.
2. ~~**Tools screen**~~ — **done 2026-10-22** (`ToolsSheet.swift`): Create (Scan, Import) and Documents (Merge, Extract, Split, Export as ZIP), each with a picker that enforces its own selection rule. Only working tools are listed. Page tools (crop, rotate, filters) stay in the document, where they have a page to act on.
3. **F2 general files** — the schema design is written: **[F2_FILE_ITEMS_DESIGN.md](F2_FILE_ITEMS_DESIGN.md)** (owner decisions recorded in §11; F2a implemented in stages). It covers schema v5, the two CHECK-constraint table rebuilds, asset sweeping across both item kinds, streaming import for large files, QuickLook thumbnails, and the F2a–F2d slices.
4. **F4 OCR** — first slice **done 2026-10-22**: `TextRecognizer`, source-space boxes, FTS over recognised text, and a Recognize Text action. Searchable-PDF export landed the same day. Still open: a status surface outside the menu, automatic recognition after a scan, re-recognition after a rescan, and a user language override.
5. **F3 annotations and app lock** — whole-line highlights/underlines/strikethroughs are implemented; colors and saved-ink selection/recolor/removal are implemented with unit and iPhone/iPad preset-workflow coverage. Word selection, notes, stamps, shapes, visual fill & sign and device authentication remain.
6. **F5–F9 expansion, including media** — retain all confirmed features in the pipeline. F7a local playback → F7b library/continuity → F7c MP3/audio extraction → F7d editable transcription. Keep engine/provider decisions attached to the capability that needs them; a transcription decision does not block local playback. See FEATURE_EXPANSION for the complete sequence and dependencies.

Each slice: meaningful store tests, persistence and relaunch, rollback on failure, real iOS interaction tests, Mac and iOS compiles, layout checks in en/fr/es on iPhone and iPad, and an honest TEST_MATRIX row.

## 6. Decisions the owner still has to make

1. **Pricing and trial** — price, trial length, and whether the Day-5 reminder is a local notification, an email, or both. Nothing in M5 can be built honestly without this.
2. **Apple Developer team, bundle ID and iCloud container** — blocks M2 sync, real-camera testing and any device verification (`APPLE_SETUP.md`).
3. **RAR extraction** — which library, under which licence.
4. **PDF text editing / Office conversion (F5)** — build, or license a vetted engine? This is the largest single decision in the expansion.
5. **Transcription engine** — on-device only, or a disclosed network service?
6. **"AI" features** — the only identifiable ones in the reference are transcription and object removal. PaperNest will not ship an invented assistant or fabricated output.
7. **VPN (F9)** — provider, entitlement, provisioning, billing and privacy policy. Until then there is no VPN UI.
8. **Cloud providers** — which ones first, and the developer credentials for each.

## 7. Non-negotiables carried into every slice

- `LibraryStore` (SQLite) stays the only metadata authority. Assets stay immutable and content-addressed. A mutating call commits before it returns.
- `PageGeometry` stays the only coordinate mapping. Originals are never modified; edits are `PageTransform`s with history.
- Swift 6 strict concurrency, warning-free builds, all strings through `L10n` in en/fr/es, iPhone/iPad/native Mac, keyboard access and VoiceOver.
- **No simulated functionality**: no fake sync indicators, no mock purchases, no fabricated OCR, no disabled marketing tiles, no "redaction" that only draws a black box.
- Record real command outcomes in TEST_MATRIX. Never mark an unrun check as passed.
- Check "Who is editing what" at the top of [SESSION_HANDOFF.md](SESSION_HANDOFF.md) before editing shared UI files.
