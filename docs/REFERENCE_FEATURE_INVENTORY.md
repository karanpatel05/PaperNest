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
| 20 | Highlight / underline / strike through text | **Partial** (2026-10-24) — whole recognized lines, editable ink, undo/reopen/export covered by unit tests; iPhone/iPad Simulator workflows pass in en/fr/es. Native Mac annotation interaction remains unrun. F3b preset/custom colors and saved-ink selection/recolor/removal are implemented; iPhone/iPad preset-manager workflows pass in en/fr/es. System custom-picker interaction remains unrun. Word-level selection, moving/resizing marks outside PencilKit and semantic annotation objects remain planned. | F3 |
| 21 | Notes/comments, stickers, shapes, inserted text and images | **Partial** (2026-10-25) — private per-page comments (add/edit/delete, guarded undo/redo, kept out of PDF/image exports, schema v7) and outlined rectangles/ellipses/lines/arrows saved as editable ink with preview placement, colour and width. Stickers/stamps, text boxes and placed images remain planned; models for text/image objects exist. Post-save shape resize handles and exported positioned PDF comment annotations are separate work | F3 |
| 22 | Notebook creation, templates, planners | **Partial** (2026-10-25) — Tools creates a one-page blank/lined/grid A4 notebook and opens the existing editor, and further blank/lined/grid A4 pages can be inserted after the selected page with guarded undo/redo. Planners and notebook-specific navigation remain | F3 |
| 23 | Visual fill & sign, saved signatures, initials, checkmarks | **Planned** | F3 |
| 24 | Interactive PDF form fields preserved | **Planned** | F5 |
| 25 | Edit existing text and images inside a PDF | **Planned** — needs an engine decision | F5 |
| 26 | Permanent redaction (content removed, not covered) | **Planned** — adversarial fixtures required | F5 |
| 27 | Set a PDF password / encrypted export | **Partial** — protected PDFs *import*; no encrypted export | F3/F5 |
| 28 | App lock (passcode / biometric) | **Planned** — distinct from encryption at rest | F3 |
| 29 | Scanner with OCR, searchable PDF | **Partial** — camera wrapper and import exist; **OCR and searchable-PDF export both work** (2026-10-22); the real-camera test is still open | M4/F4 |
| 30 | Text search across documents | **Done** for recognized text and titles (2026-10-22) and for the text digital PDFs already carry (2026-10-25); typed notes follow with F3 | F4 |
| 31 | Images ↔ PDF (JPEG, PNG) | **Done** | M1 |
| 32 | HEIC and WEBP | **Partial** — HEIC import and conversion to PDF implemented (2026-10-22), verified against ImageIO. HEIC export and WEBP conversion remain planned | F2c/F4 |
| 33 | Office → PDF (DOCX, XLSX, PPTX), TXT → PDF | **Planned** | F4/F5 |
| 34 | PDF → Word / Excel / PowerPoint / Text | **Planned** — retain-layout and editable-output are separate modes | F4/F5 |
| 35 | Compression presets with before/after size | **Partial** — export quality levels exist; no explicit compressor | F2/F4 |
| 36 | Bookmarks, reading mode, book formats | **Planned** — supported formats must be named explicitly | F3/F4 |
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
