# Expanded PaperNest feature roadmap

Owner request: add the features visible in Photos 1–9 (Documents by Readdle reference), then explicitly asked Codex to start implementation here. This extends the original scope; `CLAUDE_CODE_PROMPT.md` stays unchanged. Reference functionality is the goal; PaperNest keeps its own Clean & Native design and branding.

This is a multi-release expansion. The table is a coverage ledger, not a statement that these features already work. **Existing** means code was found; verification remains in TEST_MATRIX. **Partial** means only the stated subset exists. All other rows are **Planned** until implemented and verified. Hidden/cropped photo-tool tiles and the generic “30+ tools”/“AI” marketing claims do not specify additional identifiable features.

## Owner-confirmed pipeline — 2026-10-23

> **Narrowed twice since, by the owner.** On **2026-10-28**: *"Live media just focus on documents and image"* — media
> (rows 42–44) is parked where it stands. Then, the same day: *"I guess we can drop idea for file conversion"* — the
> **Office-format conversions below are closed in both directions**, which were also the ones no engine could do
> honestly. What this does **not** touch: **images ↔ PDF**, which is how the app imports a photo and exports a
> document rather than a converter feature; and the three conversion engines that already ship — TXT → PDF, PDF →
> plain text, PDF → basic Word — which stay unless the owner says otherwise. The lines below are left as written,
> because they record what was asked for on 2026-10-23.

After reviewing the feature list and the Convert Files / Enjoy Media screenshot, the owner explicitly requested: **“All features to pipeline including media.”** All identified capabilities below and in the 48-row reference inventory are included in the product pipeline. This confirms scope; it does not change implementation status or move media ahead of the current document work.

- **Convert to PDF:** Image to PDF, Spreadsheet to PDF, Document to PDF, Presentation to PDF, Text to PDF, Merge to PDF.
- **Convert from PDF:** PDF to Image, PDF to Excel, PDF to Word, PDF to PowerPoint, PDF to Text. Each Office format is its own deliverable; accepting a file into the library is not conversion.
- **PDF Editor:** Manage Pages, Sign PDF, Reduce File Size, Edit PDF, Merge PDFs, Set Password, Annotate, Redact PDF, Fill Form.
- **Notes:** notebook creation, templates/planners, handwriting/sketching, text, images, highlights, notes/comments, stamps/stickers and shapes.
- **Media:** music/audio, video and audiobooks; library/playlists, playback controls and speed, background playback and resume, supported picture-in-picture, MP3 conversion/audio extraction, editable transcription and transcript export. Delivery slices are below.
- **Remaining expansion:** file management, Photos import, Inbox, ZIP/RAR, OCR/search, compression, app lock, cloud connections/sync, computer transfer, browser/downloads, photo object removal, VPN and subscriptions remain included.

Unfinished features remain planned even when credentials, licensing or an engine decision are needed. Cropped photo-tool labels remain unidentified; do not invent features from hidden tiles. Existing completed capabilities stay complete in the inventory.

## Feature coverage from the nine photos

| Area / reference | Required capability | Current baseline / workstream |
|---|---|---|
| Files (1, 3, 8, 9) | Browse local files and folders, grid/list, rename, sort, search, favorites, recent files, trash | Existing for PaperNest documents and general file items (F2a) |
| Files (1, 3) | Color labels, select multiple, copy/duplicate, move, file details, share/email | F1 selection/duplicate/color/batch actions done; F2a general file details/share/save implemented |
| Files (8) | Import from Photos, Files, camera, computer/cable; create folders, PDF notes and text files | Photos images/Files/folders exist; camera needs device verification; text/notebooks F3; computer transfer F6 |
| PDF (1, 5, 7) | Read PDFs, scanned documents and books, navigate/search/bookmark | Page viewer and recognized-text search exist; bookmarks/reading mode F3/F4; supported book formats must be explicit |
| PDF (1, 5) | Merge documents, split/extract pages, rotate/reorder/delete | Implemented; remaining platform verification is in TEST_MATRIX |
| PDF (1, 5, 7) | Edit existing PDF text and images | F5 engine evaluation and implementation; overlay text alone does not satisfy this |
| PDF (1, 5, 7) | Highlight/underline/strike through, freehand ink, notes/comments, stickers, shapes, inserted text/images | iPad ink, whole recognized-line marks, private page comments, outlined shapes and checkmark/cross/star ink stamps exist; remaining annotations F3/F5 |
| PDF (1, 5, 7) | Fill form fields, place text/checkmarks/initials, draw/save/reuse signatures | F3 visual fill/sign, F5 interactive PDF form preservation; visual signatures are described as such |
| PDF (5) | Redact PDF | F5: exported redaction must remove underlying content, including text extraction and OCR; a dark rectangle alone is not redaction |
| PDF (3, 5) | Set PDF passwords and protect access | Protected PDF import exists; encrypted export and app lock F3/F5 |
| Notes (6, 7, 9) | Create editable notes/notebooks, templates/planners, sketch, type, Apple Pencil, pen colors/widths, eraser, lasso, shapes | One-page notebook creation (blank/lined/grid A4) and existing editor/iPad ink implemented; additional template pages with guarded undo/redo and outlined shapes as editable ink implemented; planners and remaining tools F3 |
| Conversion (1, 5) | Images ↔ PDF (JPG/JPEG, PNG, HEIC, WEBP) | JPEG/PNG ↔ PDF and HEIC import → PDF exist; HEIC export and WEBP conversion remain F4 |
| Conversion (5) | Word documents, spreadsheets, presentations, plain text → PDF | F4 basic TXT/DOCX, F5 Office rendering; DOCX/XLSX/PPTX format support documented individually |
| Conversion (1, 5) | PDF → editable Word, Excel, PowerPoint, plain text | F4 OCR/TXT/basic DOCX; F5 table/layout reconstruction and PPTX/XLSX. Retain layout and editable output are separate modes |
| Compression (1, 3, 5) | Reduce PDF/photo size, compress files/folders, show resulting size and quality | PDF/image export quality exists; explicit compression comparison and general archives F2/F4 |
| Archives (1, 3) | Create ZIP, inspect/extract ZIP and RAR, share archives | ZIP creation/extraction exists; compression presets and RAR extraction remain F2; RAR creation is not requested |
| Scanning (1, 3, 8) | Receipt/book/document scanning, OCR, searchable PDFs, cloud save | Import/file replacement, OCR and searchable PDFs exist; real camera test pending; automatic OCR F4; cloud F6 |
| Cloud (1, 3, 8) | iCloud, Dropbox, Google Drive and additional cloud providers; remote browse/open/upload/download and transfers | F6; Files provider picker is existing import, not a direct cloud-sync integration |
| Cloud (1) | Work with remote files without manually downloading first | F6 provider-aware access and on-demand local bytes; distinguish cached, remote-only, downloading and offline states |
| Transfers (1, 8) | Computer/Mac/PC Wi-Fi transfer, cable/Files access, nearby/share/email handoff | Native share exists; F6 authenticated local transfer plus platform-supported Files/cable integration |
| Media (1, 4, 9) | Audio/music/video/audiobook playback, playlists/library, seek, speed, background playback, resume | F7; supported formats verified per platform |
| Media (3, 5) | Convert supported media to MP3 / extract audio | F7 codec/licensing evaluation, then genuine export with progress and cancellation |
| Transcription (1, 3) | Audio/video → editable transcript, timestamps, export | F7 speech recognition; on-device availability and any network processing disclosed per selected engine |
| Photo tools (1, 5) | Smart Eraser / object removal | F8: local model or explicitly configured service, preview, undo and original preservation |
| Browser (1, 2, 8) | Built-in web browser, web downloads, save/export web content | F8: independent browser/download feature with destination and progress |
| Privacy (2, 3) | Passcode/biometric app access | F3; app lock is distinct from encrypted-at-rest vault storage |
| VPN (2, 9) | Actual VPN connection, connection state, server choice | F9: separate service integration/operations; provider, entitlement, provisioning, billing and privacy decisions needed before shipping |
| AI (9) | Integrated AI | Specific visible capabilities are transcription and Smart Eraser; no invented assistant/chat feature or fake output |

## Delivery sequence

- **F1 — Document tools (implemented and verified):** selection, duplicate, explicit-order merge, extraction, color labels, per-page splitting and selection-wide ZIP export. Original documents and editable objects are preserved.
- **F2 — General file library and archives (partly implemented):** F2a now stores any file type, streams large imports, supports library operations/details/share/save, and opens system Quick Look previews. Grid/list thumbnails still use type symbols. Photos/HEIC import, safe ZIP extraction and ZIP creation have also landed. Remaining: thumbnail generation, Copy to, Inbox and compression presets; RAR needs a licensing decision. Existing page-based documents remain editable. Secure bounded extraction with traversal/symlink/expansion-size checks; cancellation leaves no partial library entries.
- **F3 — Notes, annotations and access (text markup and saved-mark controls implemented):** full recognized-line highlight/underline/strikethrough uses editable ink with atomic snapshot validation and undo; F3a iPhone/iPad workflows in en/fr/es pass. F3b preset/custom colors and a saved-mark selection/recolor/removal manager are implemented; 235 unit tests pass, as do manager workflows in en/fr/es on iPhone/iPad Simulators. Conflict-safe ink undo/redo preserves newer edits from another window. System custom-picker interaction remains unrun; preset workflows are verified. Native Mac annotation interaction remains unrun. One-page notebook creation from Tools now supports blank/lined/grid A4 paper (236 unit tests, phone/iPad creation/relaunch, Mac build verified). Additional blank/lined/grid A4 pages can now be inserted after selection with guarded undo/redo. Private page comments now support add/edit/delete and guarded undo/redo; comments stay in PaperNest and are excluded from PDF/image exports. Outlined rectangles, ellipses, lines and arrows now save as ink with preview placement, color/width, guarded undo and export. Checkmark/cross/star symbol stamps use the same placement, history and export paths. Text/custom-image stamps and dedicated post-save shape resizing/fills remain. Next: planners, text/images, richer ink, signatures and visual form filling, device authentication/app lock. Preserve existing ink work. Verify edit/reopen/export on each platform.
- **F4 — OCR and first conversion set (partly implemented):** en/fr/es Vision recognition, recognized-text search and searchable PDF are implemented. Remaining: correction/status UI, automatic scan/rescan recognition, language override, TXT and basic DOCX. HEIC is implemented and verified in F2c; add WEBP only after codec verification; expose explicit compression presets/results. PDFs with selectable text use their text where possible.
- **F5 — Advanced PDF and Office engine:** real PDF text/image editing, interactive forms, permanent redaction, password export, Office-to-PDF and PDF-to-Office reconstruction. Evaluate a vetted local engine/SDK against synthetic fixtures before committing to paid dependencies or cloud processing.
- **F6 — Cloud and transfer:** iCloud sync first, then direct Dropbox/Google Drive adapters and local computer transfer. Provider sign-in is for that provider; no new PaperNest username/password service. Stable IDs, conflicts, offline edits, revocation and interrupted transfers need real integration tests.
- **F7 — Media and transcription (explicitly included by the owner):** local audio/video/audiobook playback, library/playlists and player controls, background/resume, audio extraction/MP3 conversion and editable transcripts. All F7 slices below remain planned; storing media files or opening Quick Look is not completion of the dedicated player.
- **F8 — Browser and photo tools:** browser/download manager, web-to-PDF, object removal with reversible previews. Network/document access remains an explicit user action.
- **F9 — VPN:** complete a separate technical/service design and real-device networking tests. UI is shipped only with a working provider. No service purchase, server deployment, or account enrollment is implied by this roadmap.

These workstreams extend M1/M3/M4 and preserve M2 sync, M5 subscriptions and M6 release hardening. Work can proceed locally while provisioning-dependent integrations await the necessary credentials and owner decisions. Nothing is removed from the requested scope by placing it later.

## Media pipeline (F7)

| Slice | Deliverable | Completion checks / dependencies |
|---|---|---|
| **F7a — Local playback** | Open supported audio/music, video and audiobook files from the library; play/pause, seek, elapsed/remaining time, video fit/fill; stream large local files without loading the whole file into memory. Include video import from Photos and saving supported media back to Photos. | Verify formats on each platform with synthetic media, playback after relaunch, missing/corrupt/unsupported-file errors and original-byte preservation. Photos access follows system permission flows. |
| **F7b — Player library and continuity** | Metadata/artwork where available, media library and playlists, previous/next, shuffle/repeat, speed control, remembered position, background audio, system media controls and video picture-in-picture where supported. | Verify persisted order/position, audio interruptions and route changes; real-device checks for background playback and platform-specific controls. State support explicitly per platform. |
| **F7c — Audio conversion** | Extract audio from supported videos and convert supported media to MP3; choose destination, show progress, cancel safely, then share/save the output. | Verify an actual decoder/encoder and its licence before implementation commitments. Play exported files back, compare duration, test failure/cancellation and keep originals. Playback is not blocked by the MP3 encoder choice. |
| **F7d — Transcription** | Audio/video → timestamped text, editable transcript, save/reopen and text export. | Select and disclose on-device versus network processing, verify supported languages, handle silence/failure/cancellation, and persist edits. Network processing depends on an explicit service/privacy decision; local playback does not. |

The sequence above is the delivery breakdown within F7, not a release-date commitment. Media is part of PaperNest's intended product scope alongside document tools.

## Architecture and quality gates

- SQLite LibraryStore remains the single metadata authority; assets remain immutable/content-addressed. General files use schema v5 with `file_items`, never dummy PDF pages. Color labels use v4 and HEIC assets use v6; page comments use v7; planned sync must use v8 or the next unused migration.
- Document composition copies current transforms and editable objects with fresh IDs while sharing immutable originals; no rasterization or file reimport just to merge. History/undo stacks are not copied. Validate all sources and commit a batch atomically.
- A Tools screen should list only working tools. Add categories as implementations land. Do not create dozens of disabled marketing tiles.
- Keep Clean & Native UI, iPhone/iPad/native Mac, en/fr/es, keyboard access and VoiceOver. Reference competitor screenshots are feature references, not assets for the shipped app.
- For each slice: meaningful unit/store tests, persistence/relaunch and failure rollback, real iOS interactions, Mac/iOS compile, layout checks and honest TEST_MATRIX results. Security-sensitive output (redaction/encryption/archive extraction) requires adversarial fixtures and independent review before a release claim.
- Existing `InkCanvas.swift` work is outside F1 and must be preserved. Commit only at the owner's request.
