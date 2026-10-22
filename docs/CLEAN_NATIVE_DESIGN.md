# Clean & Native UI

## Source of truth

The owner supplied three reference mockups on 2026-10-21 (shared with Claude; the earlier note that the images were unavailable applied only to Codex's chat). They live in `docs/design/mockups/`, as PNG and WebP:

| File | Shows |
|---|---|
| `mac-workspace.png` | Mac library window (top) and Mac document window (bottom) |
| `ipad-notebook-export.png` | iPad notebook editor (top) and the Export sheet (bottom) |
| `iphone-scan-library.png` | iPhone library, the camera, and the post-scan Edit screen |

The mockups picture the **whole product**, including M2–M5 features (sync, OCR, handwriting, Word export). The sample content (biology notes, receipts) is illustrative only; tests and screenshots keep using synthetic samples.

**The rule:** match the look for features that exist. Leave out entirely any control or status for a feature that doesn't work yet, with no disabled placeholders and no "coming soon". The brief forbids fake sync indicators and fabricated OCR. The one existing exception stays: Scan is disabled, with a hint, on devices without a document camera.

## Visual language (all platforms)

- **Color:** system blue accent. Primary actions are filled blue (`.borderedProminent`); secondary actions are gray filled (`.bordered`). The canvas is light gray (`systemGroupedBackground`, or the Mac window background). Paper is always white, with a soft shadow. Use semantic colors so Dark Mode and Increase Contrast adapt; paper stays white in Dark Mode.
- **Document tile (library):** the mockup has *no white card*. A rounded light-gray thumbnail tile (corner radius about 10) holds the page preview, centered with a shadow. **Under** the tile, on the canvas: the name (semibold, 1–2 lines), the date (secondary, caption), and a trailing `⋯` button with the same actions as the context menu. Pass 1 put the name and date inside a white bordered card; pass 2 changes that to match.
- **Type:** SF, Dynamic Type, large titles on library screens.
- **Icons:** SF Symbols, outline style in toolbars, filled for the selected state.
- **Selection:** the selected page thumbnail has a blue rounded border (about 2.5 pt) and a blue page number.
- **Spacing:** 20 pt outer margins and 16–20 pt grid gaps.

## Screens, described

### Mac library window (`mac-workspace.png`, top)

- **Sidebar.** At the top, with trailing counts in secondary text:
  - **Library**, the selected row, a blue pill (all documents, "24 items")
  - **Favorites** (5 items)
  - **Notebooks** (3 notebooks)
  - **Recently Deleted** (2 items)

  Next comes a section titled **Notebooks**, with a `+` in its header, listing colored collections ("Biology notes 8 items", "Project notes", "Receipts"). The footer reads "iCloud · Synced".
- **Toolbar.**
  - A wide search field: "Search documents, text, or tags…"
  - An **Import** button with a dropdown chevron
  - A filled blue **Scan from iPhone** button (camera icon)
  - A `⋯` button
- **Content.**
  - A large title, **Library**, with "24 items" under it
  - On the right: a grid/list segmented toggle and a "Sort by Date Added ▾" menu
  - Below: a grid of four columns of document tiles (as described above)

### Mac document window (`mac-workspace.png`, bottom)

- **Toolbar.**
  - A sidebar toggle
  - The title "Biology notes ▾", with "● iCloud • Synced" under it
  - A centered tool group: pen, highlighter, eraser, text, selection
  - An **OCR** button
  - A bordered **Export** button (icon and label)
  - A `⋯` button
- **Left column** (about 140 pt, light gray): page thumbnails with numbers under them. The selected page has a blue border. A `+` button sits at the bottom.
- **Center:** the white page, large on a light-gray canvas.

### iPad notebook (`ipad-notebook-export.png`, top)

- **Sidebar:** "Notebooks", with rows for Biology notes (12 pages, thumbnail icon), Project notes and Receipts.
- **Thumbnail column** with page numbers and a `+` at the bottom.
- **Navigation bar:** back, "Biology notes ▾", share, `⋯`, search, compose.
- **Pencil palette:** floating, rounded, at the bottom, with undo/redo, pens, an eraser, lasso and color dots.

### Export sheet (`ipad-notebook-export.png`, bottom)

A centered card titled **Export**, with Cancel on the left and ✕ on the right. From top to bottom:

1. A document row: small thumbnail, name, "12 pages".
2. **Format:** five equal tiles (icon and label). The selected tile has a blue border and a checkmark badge. The tiles are PDF, JPEG, PNG, Word and Plain text.
3. **Pages:** three segments: "All pages (12)", "Current page (1)", and "Custom range" (e.g. 2–5, 8).
4. **Include:** a "Searchable text (OCR)" toggle and an "Include images" toggle.
5. **Export to:** four tiles: Save to Files (selected), Copy, Share, More.
6. A full-width filled blue **Export** button.

### iPhone library (`iphone-scan-library.png`, left)

- A large title, **Documents**, with a `⋯` button and a cloud button at the top right.
- A search field, "Search documents, notes, folders…", with a mic.
- Two big buttons side by side: **Scan document** (filled blue, camera) and **New note** (gray, pencil).
- **Recent**, with "See All": a horizontal row of document tiles (thumbnail, name, date, `⋯`).
- **Folders**, with "See All": list rows, each with a colored folder icon, a name, "12 items" and a chevron.
- A tab bar: Library, Notes, Scan, Settings.

### iPhone camera (middle)

A custom camera: Cancel, "Auto ▾", flash and `⋯` at the top; detected page corners in blue; a Document / Whiteboard / Photo mode switch; a shutter; a last-page thumbnail; and "3 pages ›".

### iPhone post-scan Edit (right)

- Cancel / **Edit** / Save.
- A large page preview.
- A filter strip of live thumbnails: Original, **Auto** (selected), Enhanced, B&W, High Contrast.
- A bottom bar: Crop, Rotate, Filters, Cleanup, More.

## Element map

| Element | Decision | Why / when |
|---|---|---|
| Sidebar Library / Favorites / Recently Deleted **with counts** | **Build now** | Real scopes; needs a cheap count query |
| Sidebar "Notebooks" row | Leave out | Notebooks are M3 |
| Sidebar "Notebooks" section with `+` | **Build now as "Folders"** | Store, model and tests exist (`createFolder`, `folders`, `move`); no UI yet. *Naming is Claude's call:* a notebook is a separate M3 item kind |
| Folder colors (green, blue, yellow) | Later | The store has no folder color. Use one system folder icon for now |
| "iCloud · Synced", the cloud button, "● iCloud • Synced" | **Never until M2 works**, and then only to show real sync state | Brief: no fake sync |
| Search field | Built on library screens, prompt "Search titles". **Not yet on the iPhone home** | The prompt widens when text search exists (M4) |
| Import with dropdown | **Build now** | Menu: Import Files… (and Paste on Mac) |
| "Scan from iPhone" (Mac) | Only once Continuity Camera import (`ImportFromDevicesCommands` / `NSMenuItem.importFromDeviceIdentifier`) is verified with real hardware | Can't be tested without an iPhone near the Mac |
| Title + "N items" subtitle | **Build now** | |
| Grid/list toggle | Done in pass 1 | |
| "Sort by Date Added ▾" | **Build now**: Date Added, Date Modified, Name | Sort in `LibraryModel`; remember the choice in `@AppStorage` |
| Tile with name, date and `⋯` (no white card) | **Build now** | |
| Document title `▾` menu | **Build now**: Rename, Favorite, Export | |
| Pen, highlighter, eraser, text, selection, Pencil palette | Leave out | M3 |
| OCR button, "Searchable text (OCR)" toggle | Leave out | M4 |
| Thumbnail column with page numbers and `+` | **Build now** (Mac and iPad) | `+` = Add Pages… |
| Labeled **Export** button | **Build now** | |
| Export: PDF / JPEG / PNG tiles | **Build now** | |
| Export: Word, Plain text tiles | Leave out | DOCX/TXT export (M4/M5, Pro) |
| Export: All / Current / Custom range | **Build now** | The current sheet supports a contiguous range; "2–5, 8" lists are a later enhancement |
| Export: "Include images" | Leave out | No meaning today |
| Export to: Save to Files / Copy / Share / More | **Build now** | Destination first, then Export. See the risk notes below |
| iPhone "Scan document" (filled blue) | **Build now** (restyle) | |
| iPhone "New note" | Leave out; **Import** takes that slot until M3 | |
| iPhone Recent row + See All | **Built** (pass 2) | See All = All Documents. A document opened from Recent pushes over the home, so Back returns there |
| iPhone Folders list + See All | **Built** as the home's Folders section (all folders listed, so no See All) | |
| iPhone tab bar (Library, Notes, Scan, Settings) | Not yet | A tab bar without Notes would be three tabs, one of them a button. Revisit with M3. Settings stays in the `⋯` menu |
| Custom camera, modes, flash | Leave out | VisionKit's camera can't be restyled. A custom AVFoundation + Vision camera is a separate project that needs device testing |
| Post-scan Edit screen | Later (after pass 4) | A flow change: review before saving |
| Filter strip with live thumbnails | **Build now** in the document view (replaces the Filter menu on iPhone) | Original, Grayscale, B&W are real. "Auto", "Enhanced" and "High Contrast" may appear **only** as real presets with defined parameters, documented here before shipping |
| Cleanup | Leave out | Not implemented |

## Work plan

| Pass | Scope | Owner | Status |
|---|---|---|---|
| 1 | Theme, Scan/Import buttons, grid/list, labeled phone tools | Codex | Done 17:42. Verified on the combined tree: 115 unit tests and 4 UI tests pass |
| 2 | **Library + sidebar + iPhone home:** counts; Folders (create, rename, delete, Move to Folder, import into the shown folder); title + "N items"; sort menu; tiles with `⋯`; iPhone home (Scan/Import, Recent + See All, library, folders) | Claude | **Done 20:30** (see TEST_MATRIX.md). Follow-ups: home search field, `⋯` on Recent cards, drag to folders, folder colors, Mac/iPad visual check |
| 3 | **Export sheet** redesign, all platforms | Codex (suggested) | Open |
| 4 | **Document view:** Mac/iPad thumbnail column with `+`, title `▾` menu, labeled Export, `⋯` menu; iPhone filter strip | open | Open |
| 5 | Continuity Camera "Scan from iPhone" on Mac | open | Needs hardware to verify |
| 6 | Post-scan review (Edit) screen on iPhone | open | After pass 4 |

When you finish a pass, update this table and the "Who is editing what" line in `SESSION_HANDOFF.md`, and record results in `TEST_MATRIX.md`.

## Risks to handle

- **Truncation in French and Spanish.** The five Format tiles and four Export-to tiles will truncate at iPhone width ("Enregistrer dans Fichiers", "Guardar en Archivos"). Use `ViewThatFits` (one row, falling back to two rows or a vertical list) and check fr/es screenshots at compact width and with large text.
- **Destination first, then Export.** This changes the flow behind `SaveExportedFiles`, which `SettingsView` also uses for the backup. Keep Settings working (its UI test covers it).
- **Copy:** copy a single exported file (one PDF, or one image for a one-page image export) to the pasteboard. For several images, use the ZIP file URL. Don't copy anything you didn't export.
- **Folder deletion (decided in pass 2):** deleting a folder deletes nothing in it. Its documents (including any in Recently Deleted) and subfolders move up to its parent, renamed if a name is taken, and the folder row is kept as a tombstone for sync. Tested in `FolderTests` and the folder UI test.
- **Accessibility:** every new control needs a label; tiles and segments need `accessibilityIdentifier` and an `accessibilityValue` (selected state) for UI tests.

## Pass 1 notes (Codex, 2026-10-21)

- Kept SwiftUI and the existing navigation, import, rescan, crop and export flows.
- Made Scan and Import visible, labeled actions at the top of the iPhone/iPad library, and gave Settings a direct toolbar button. Camera availability still comes from VisionKit.
- Showed real document previews on pale gray surfaces, with consistent preview bounds and readable name, page count and date. Grid and list layouts use the same documents and context actions.
- Gave the phone editor labeled Rotate, Crop, Filter, Pages and More controls; Add/Replace and Export stay in the navigation bar. The current page shows above the thumbnail strip.
- Kept the native sidebar and page-strip navigation on larger screens; existing keyboard commands remain.
- **Colors:** system blue (#007AFF in standard light appearance), white paper and surfaces (#FFFFFF), grouped canvas (#F2F2F7), primary ink (#000000), secondary labels (#3C3C43 at system opacity). Semantic colors throughout, with source paper staying white.
- **Typography:** SF with Dynamic Type: large navigation titles, headline for sections and actions, semibold document names, caption metadata.
- **Layout:** left-aligned content, 20 pt outer margins, 16 pt grid gaps, 14 pt card corners. Shadows only on paper previews.

## Verification (every pass)

- Build Mac and iOS. Run `./scripts/test.sh` and `scripts/ui-test-ios.sh`.
- Add a UI test for each new interaction (sort, folder create/open, export destination).
- Take iPhone screenshots in en, fr and es, in Dark Mode and with large text. Inspect iPad when a runtime is available.
- Record the real outcomes in `TEST_MATRIX.md`. Name screenshots `docs/screenshots/design-<pass>-<screen>-<lang>.png`.
