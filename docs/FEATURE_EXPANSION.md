# Expanded PaperNest feature roadmap

Owner request: add the features visible in Photos 1–9 (Documents by Readdle reference), then explicitly asked Codex to start implementation here. This extends the original scope; `CLAUDE_CODE_PROMPT.md` stays unchanged. Reference functionality is the goal; PaperNest keeps its own Clean & Native design and branding.

This is a multi-release expansion. The table is a coverage ledger, not a statement that these features already work. **Existing** means code was found; verification remains in TEST_MATRIX. **Partial** means only the stated subset exists. All other rows are **Planned** until implemented and verified. Hidden/cropped photo-tool tiles and the generic “30+ tools”/“AI” marketing claims do not specify additional identifiable features.

## Feature coverage from the nine photos

| Area / reference | Required capability | Current baseline / workstream |
|---|---|---|
| Files (1, 3, 8, 9) | Browse local files and folders, grid/list, rename, sort, search, favorites, recent files, trash | Existing for PaperNest documents and general file items (F2a) |
| Files (1, 3) | Color labels, select multiple, copy/duplicate, move, file details, share/email | F1 selection/duplicate/color/batch actions done; F2a general file details/share/save implemented |
| Files (8) | Import from Photos, Files, camera, computer/cable; create folders, PDF notes and text files | Files/camera/folders exist; Photos/text/notebooks F2/F3; computer transfer F6 |
| PDF (1, 5, 7) | Read PDFs, scanned documents and books, navigate/search/bookmark | Page viewer exists; text search/bookmarks/reading mode F3/F4; supported book formats must be explicit |
| PDF (1, 5) | Merge documents, split/extract pages, rotate/reorder/delete | Rotate/reorder/delete/add exist; merge/extract F1; per-page split F1 follow-up |
| PDF (1, 5, 7) | Edit existing PDF text and images | F5 engine evaluation and implementation; overlay text alone does not satisfy this |
| PDF (1, 5, 7) | Highlight/underline/strike through, freehand ink, notes/comments, stickers, shapes, inserted text/images | iPad ink/highlighter first slice exists; rest F3/F5 |
| PDF (1, 5, 7) | Fill form fields, place text/checkmarks/initials, draw/save/reuse signatures | F3 visual fill/sign, F5 interactive PDF form preservation; visual signatures are described as such |
| PDF (5) | Redact PDF | F5: exported redaction must remove underlying content, including text extraction and OCR; a dark rectangle alone is not redaction |
| PDF (3, 5) | Set PDF passwords and protect access | Protected PDF import exists; encrypted export and app lock F3/F5 |
| Notes (6, 7, 9) | Create editable notes/notebooks, templates/planners, sketch, type, Apple Pencil, pen colors/widths, eraser, lasso, shapes | Models/templates and iPad ink exist; notebook creation/editor and remaining tools F3 |
| Conversion (1, 5) | Images ↔ PDF (JPG/JPEG, PNG, HEIC, WEBP) | PDF/JPEG/PNG paths exist; HEIC/WEBP capability checks and codec support F4 |
| Conversion (5) | Word documents, spreadsheets, presentations, plain text → PDF | F4 basic TXT/DOCX, F5 Office rendering; DOCX/XLSX/PPTX format support documented individually |
| Conversion (1, 5) | PDF → editable Word, Excel, PowerPoint, plain text | F4 OCR/TXT/basic DOCX; F5 table/layout reconstruction and PPTX/XLSX. Retain layout and editable output are separate modes |
| Compression (1, 3, 5) | Reduce PDF/photo size, compress files/folders, show resulting size and quality | PDF/image export quality exists; explicit compression comparison and general archives F2/F4 |
| Archives (1, 3) | Create ZIP, inspect/extract ZIP and RAR, share archives | ZIP packaging/export-all exists; arbitrary ZIP compression/extraction + RAR extraction F2; RAR creation is not requested |
| Scanning (1, 3, 8) | Receipt/book/document scanning, OCR, searchable PDFs, cloud save | Camera wrapper/import/rescan exist; real camera test pending; OCR F4; cloud F6 |
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
- **F2 — General file library and archives (partly implemented):** F2a now stores any file type, streams large imports, supports library operations/details/share/save, and opens system Quick Look previews. Grid/list thumbnails still use type symbols. Remaining: thumbnail generation, Photos import, Copy to, Inbox, ZIP extraction and archive compression presets; RAR needs a licensing decision. Existing page-based documents remain editable. Secure bounded extraction with traversal/symlink/expansion-size checks; cancellation leaves no partial library entries.
- **F3 — Notes, annotations and access:** finish notebook creation/templates, text/images/shapes, richer ink, signatures and visual form filling, device authentication/app lock. Preserve existing ink work. Verify edit/reopen/export on each platform.
- **F4 — OCR and first conversion set (partly implemented):** en/fr/es Vision recognition, recognized-text search and searchable PDF are implemented. Remaining: correction/status UI, automatic scan/rescan recognition, language override, TXT and basic DOCX. Add HEIC/WEBP only where codecs are verified; expose explicit compression presets/results. PDFs with selectable text use their text where possible.
- **F5 — Advanced PDF and Office engine:** real PDF text/image editing, interactive forms, permanent redaction, password export, Office-to-PDF and PDF-to-Office reconstruction. Evaluate a vetted local engine/SDK against synthetic fixtures before committing to paid dependencies or cloud processing.
- **F6 — Cloud and transfer:** iCloud sync first, then direct Dropbox/Google Drive adapters and local computer transfer. Provider sign-in is for that provider; no new PaperNest username/password service. Stable IDs, conflicts, offline edits, revocation and interrupted transfers need real integration tests.
- **F7 — Media and transcription:** audio/video/audiobooks, background playback and resume, codecs/export, editable transcripts. Long-running operations must support cancel/relaunch without corrupting originals.
- **F8 — Browser and photo tools:** browser/download manager, web-to-PDF, object removal with reversible previews. Network/document access remains an explicit user action.
- **F9 — VPN:** complete a separate technical/service design and real-device networking tests. UI is shipped only with a working provider. No service purchase, server deployment, or account enrollment is implied by this roadmap.

These workstreams extend M1/M3/M4 and preserve M2 sync, M5 subscriptions and M6 release hardening. Work can proceed locally while provisioning-dependent integrations await the necessary credentials and owner decisions. Nothing is removed from the requested scope by placing it later.

## Architecture and quality gates

- SQLite LibraryStore remains the single metadata authority; assets remain immutable/content-addressed. General files use schema v5 with `file_items`, never dummy PDF pages. Color labels use v4; planned sync must use v6 or the next unused migration.
- Document composition copies current transforms and editable objects with fresh IDs while sharing immutable originals; no rasterization or file reimport just to merge. History/undo stacks are not copied. Validate all sources and commit a batch atomically.
- A Tools screen should list only working tools. Add categories as implementations land. Do not create dozens of disabled marketing tiles.
- Keep Clean & Native UI, iPhone/iPad/native Mac, en/fr/es, keyboard access and VoiceOver. Reference competitor screenshots are feature references, not assets for the shipped app.
- For each slice: meaningful unit/store tests, persistence/relaunch and failure rollback, real iOS interactions, Mac/iOS compile, layout checks and honest TEST_MATRIX results. Security-sensitive output (redaction/encryption/archive extraction) requires adversarial fixtures and independent review before a release claim.
- Existing `InkCanvas.swift` work is outside F1 and must be preserved. Commit only at the owner's request.
