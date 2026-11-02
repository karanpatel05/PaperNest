# Premium reference redesign — 2026-10-27

The owner’s new primary specification is `DesignReferences/paper-nest-reference.png`, superseding the older clean/native mockups below. Reproduce the interfaces inside the devices using the existing working app. SF typography, indigo #5264FF and lavender #9667FF, ice #F8F9FF canvas, #F0F2FF sidebar, translucent rounded surfaces, restrained borders and shadows. Dark mode uses dark navy surfaces and lighter accent contrast. Respect Reduce Motion and Reduce Transparency.

Preserve immutable assets, SQLite authority, existing document navigation/import/export and real thumbnails. Never populate production with reference documents or invented folder counts. The owner subsequently deferred Vault and VPN to the next version: neither appears in this version. Collaboration and rich text are also absent; private page comments and notebook ink are real.

# Clean & Native UI

## Readability pass — 2026-10-26

Owner requested a better UI after the app audit. Keep SF, semantic system backgrounds, white paper and the system blue accent. Improve hierarchy and readability using the existing screens and strings: at accessibility sizes, give iPad navigation a wider text-first column instead of oversized icons crowding words; use full-width stroke-weight choices instead of fixed-height segments; make annotation instructions and the Add Comment action use primary-text contrast. Keep normal-size navigation and compact segmented controls. Normal-size shape/stamp choices use an adaptive grid with a quiet selected tint and checkmark so the paper preview stays higher on the sheet; at accessibility sizes the choices remain full-width rows. No backend capabilities or placeholder controls are added in this pass.

Validation: existing large-text/dark-mode control workflow on both devices, localized annotation-style screenshots and interactions, full unit suite and Mac build under timeouts. Retain and report known toolbar accessibility-audit failures separately; no automatic claim that this pass fixes them.

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
| Document title `▾` menu | **Built** (pass 4): Rename, Add/Remove Favorites, Export (`.toolbarTitleMenu`) | |
| Pen, highlighter, eraser, lasso, Pencil palette | **Built on iPad (pass 7)** with the system `PKToolPicker`. The mockup's custom palette is not built: offer it once the owner has tried the system one | Text boxes and other note tools stay M3 |
| OCR button, "Searchable text (OCR)" toggle | Leave out | M4 |
| Thumbnail column with page numbers and `+` | **Built** (pass 4): `+` opens the add/replace menu | Selected page: system highlight, not yet the blue border |
| Labeled **Export** button | **Built** (pass 4); labeled on the Mac, icon on iPad toolbars | |
| Export: PDF / JPEG / PNG tiles | **Built** (pass 3) | |
| Export: Word, Plain text tiles | Leave out | DOCX/TXT export (M4/M5, Pro) |
| Export: All / Current / Custom range | **Built** (pass 3): tiles with a detail line (page count, "Page n of m", the range) | Contiguous range with From/To steppers; "2–5, 8" lists are a later enhancement |
| Export: "Include images" | Leave out | No meaning today |
| Export to: Save to Files / Copy / Share / More | **Built** (pass 3) as Save to Files (Mac: Save to Disk) / Copy / Share. **"More" dropped (Claude's call):** the share sheet already is "more". The mockup's ✕ next to Cancel was dropped too (one way to close; Claude's call) | Save opens the save dialog right after Export; closing it keeps the files (ready footer: Save… / Share… / Done). Copy puts the file **contents** on the clipboard (one item per file) and is off for ZIP output. Share shows a prominent Share… button once ready (`ShareLink` can't be opened from code; auto-presenting `UIActivityViewController` would need an iPad popover anchor that can't be tested without an iPad runtime) |
| iPhone "Scan document" (filled blue) | **Build now** (restyle) | |
| iPhone "New note" | Leave out; **Import** takes that slot until M3 | |
| iPhone Recent row + See All | **Built** (pass 2) | See All = All Documents. A document opened from Recent pushes over the home, so Back returns there |
| iPhone Folders list + See All | **Built** as the home's Folders section (all folders listed, so no See All) | |
| iPhone tab bar (Library, Notes, Scan, Settings) | Not yet | A tab bar without Notes would be three tabs, one of them a button. Revisit with M3. Settings stays in the `⋯` menu |
| Custom camera, modes, flash | Leave out | VisionKit's camera can't be restyled. A custom AVFoundation + Vision camera is a separate project that needs device testing |
| Post-scan Edit screen | Later (after pass 4) | A flow change: review before saving |
| Filter strip with live thumbnails | **Built** (pass 4) on iPhone: Filter toggles a strip of live previews + Adjustments + Revert | Original, Grayscale, B&W are real. "Auto", "Enhanced" and "High Contrast" may appear **only** as real presets with defined parameters, documented here before shipping |
| Cleanup | Leave out | Not implemented |

## Work plan

| Pass | Scope | Owner | Status |
|---|---|---|---|
| 1 | Theme, Scan/Import buttons, grid/list, labeled phone tools | Codex | Done 17:42. Verified on the combined tree: 115 unit tests and 4 UI tests pass |
| 2 | **Library + sidebar + iPhone home:** counts; Folders (create, rename, delete, Move to Folder, import into the shown folder); title + "N items"; sort menu; tiles with `⋯`; iPhone home (Scan/Import, Recent + See All, library, folders) | Claude | **Done 20:30** (see TEST_MATRIX.md). Follow-ups: home search field, `⋯` on Recent cards, drag to folders, folder colors, Mac/iPad visual check |
| 3 | **Export sheet** redesign, all platforms | Claude | **Done 21:00**: document row, Format and Pages tiles, Export To tiles, one Export button (iOS: pinned full-width; Mac: Cancel/Export at the bottom right). Verified on iPhone (UI tests, en/fr/es, dark, largest text). **Mac sheet not viewed** |
| 4 | **Document view:** title `▾` menu, editing tools in the middle, Export + `⋯`, page column `+`; iPhone filter strip | Claude | **Done 21:30.** Verified on iPhone (UI test, screenshots) and, for the first time, on an **iPad** simulator (iPad Air 13-inch M4, iOS 26.5): library and document layouts match the mockups' structure. **Follow-ups:** the page column's selected page uses the system gray highlight, not the mockup's blue border (needs replacing the `List` selection while keeping drag-to-reorder and keyboard navigation); the Export toolbar button shows its label on the Mac only (iPad toolbars show icons); **Mac not viewed** |
| 5 | Continuity Camera "Scan from iPhone" on Mac | open | Needs hardware to verify |
| 6 | Post-scan review (Edit) screen on iPhone | open | After pass 4 |
| 7 | **Apple Pencil on iPad** (owner request) | Claude | **First slice done (22:50).** (1) Ink renders everywhere: `PageRenderer` (pen with per-point width; highlighter multiplied), thumbnails, PDF export (vector) and image export. (2) `LibraryStore.applyObjectChanges` (one transaction) and `DocumentModel.changeInk` with an exact undo inverse (`InkChange`). (3) iPad: a **Markup** toggle (`editor-markup`) lays `InkCanvas` (a `PKCanvasView` with the system `PKToolPicker`) over a content-only page; Apple Pencil only by default, **Draw with Finger** toggle (`editor-finger-drawing`); `InkConversion` maps PencilKit ↔ stored ink through `PageGeometry`; strokes are tracked by `randomSeed`. **Undo:** each ink change is one step in the document's undo history (also after zooming, switching pages or leaving Markup); the palette's Undo/Redo are forwarded to it (`PaletteUndoManager`). Zoom buttons are hidden while marking up (the palette covers them; pinch zooms). **Limitations (documented):** ⌘Z for ink not verified (Simulator key injection didn't reach the app's undo); ink drawn with PencilKit's pencil/crayon/watercolor textures is stored and exported as a solid pen line; iPhone and Mac show ink but can't draw yet; zooming during Markup reloads the canvas. **Needs a real iPad + Apple Pencil** for feel (latency, palm rejection, pressure, hover). |

When you finish a pass, update this table and the "Who is editing what" line in `SESSION_HANDOFF.md`, and record results in `TEST_MATRIX.md`.

## Apple Pencil on iPad (pass 7, owner request 2026-10-21)

**Goal.** On iPad, write and highlight with Apple Pencil on any page: scans, imported PDF pages and, later, blank note pages. Ink stays editable vector data (never flattened into the scan), every stroke and erase is undoable, it survives quit and relaunch, and it looks the same in thumbnails, on the Mac and in exports. This is the first slice of M3 (brief §7: "Apple Pencil drawing on compatible iPads; appropriate touch alternatives").

**Already in place (don't rebuild):**
- `InkStroke` / `InkPoint` in `PageObjects.swift`: tool (pen or highlighter), sRGB color, width, and points with pressure and time, in **source space** (upright, uncropped, top-left origin). That keeps ink attached to the content through crop and rotation.
- The `page_objects` table and `LibraryStore.objects(on:)`, `saveObject`, `deleteObject`, with tests.
- `PageGeometry`, the only mapping between source space and the displayed page. Never hand-write flips or rotations.
- The mockup palette in `ipad-notebook-export.png`: a floating bar with undo/redo, pens, eraser, lasso and color dots.

**Build, in this order:**
1. **Render ink everywhere (all platforms, testable without a Pencil).**
   - Draw a page's ink objects in `PageRenderer`, after the page content and filter, through `PageGeometry`.
   - **Pen:** an opaque path whose width varies with pressure. **Highlighter:** translucent, multiply-blended, so the scan shows through.
   - The same code feeds `PageImageView`, thumbnails and export. PDF export writes vector paths, and JPEG export flattens onto white without losing black ink.
   - The thumbnail cache key must change when a page's ink changes.
   - **Tests:** a stroke lands in the right place after rotation and crop; the PDF contains vector paths, not an image; a JPEG keeps the ink.
2. **Store and undo.**
   - Save or delete a set of strokes in **one transaction** (`db.transaction` nests as savepoints).
   - Each stroke added, erased or moved is one undo step, registered synchronously before the async write, like the other edits in `DocumentModel`.
   - Ink doesn't change the page's original. Saving or deleting ink bumps the page revision (existing store behavior), which refreshes thumbnails; it also marks OCR stale, which is acceptable now and can be refined in M4.
3. **iPad canvas (`#if os(iOS)`).**
   - A **Markup** toggle in the document toolbar (`pencil.tip.crop.circle`, identifier `editor-markup`) lays a `PKCanvasView` over the page, inside the page viewer's scroll content and sized to the page. The canvas never scrolls or zooms itself; the page viewer does that.
   - **Gestures:** `drawingPolicy = .pencilOnly` by default, so fingers keep scrolling and zooming. A **Draw with Finger** switch in the palette is the touch alternative (also how the Simulator and UI tests can draw).
   - **Conversion:** `PKStroke` ↔ `InkStroke` goes from view space to source space through the inverse of `PageGeometry`. Point location, force → pressure, and `timeOffset` → time. `PKInkingTool` `.pen` / `.marker` map to pen / highlighter. Detect added and removed strokes by diffing the drawing on `canvasViewDrawingDidChange`, and write only the changes.
   - **Eraser:** the stroke eraser (whole strokes) → `deleteObject`. **Lasso move** → save the moved points.
   - **Palette:** start with the system `PKToolPicker`. It's native, accessible, has undo/redo, and supports Pencil hover and squeeze. Show the custom mockup bar only if the owner wants that look after trying it. Record that as a decision then.
4. **iPhone and Mac: view the ink** (step 1 covers this). Drawing on iPhone and mouse or trackpad annotation on the Mac are later M3 slices. The brief says not to promise an identical Pencil experience on the Mac.

**Not in this slice:** handwriting recognition (the brief defers it), blank/lined/grid note pages and notebook creation (a separate M3 slice; template rendering exists), text boxes, shape recognition, and sync of ink (it follows M2 sync, one record per stroke).

**Free and Pro.** Basic pen, highlighter and eraser stay free. The brief puts "additional annotation tools" in Pro; decide that boundary in M5, not now.

**Verification.**
- Unit tests: conversion round trips (including rotated and cropped pages), store batch writes and undo, rendering and export.
- An iPad Simulator UI test with Draw with Finger: drag to draw → a stroke is saved → it's still there after relaunch → it appears in an exported PDF. Undo removes it.
- **A real iPad with an Apple Pencil is needed** for latency, palm rejection, pressure and hover. That's the "Apple Pencil feel" row in TEST_MATRIX. Simulator results don't count for it.

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

Owner clarification 2026-10-27: leave Vault and VPN for the next version. They are omitted from current navigation/actions; no status placeholders ship. Shared collaboration also lacks a service. No invented profiles or default folders are added.

## Notes tools — 2026-10-27

Owner requested visible tools side by side instead of a dropdown. Notes now use a labeled horizontal tool row below the title on phone, iPad and Mac. The row scrolls on narrow screens, keeps all editing/page actions reachable, and remains available when the note is empty so Add Notebook Page and Undo are not lost. Rotate/filter retain their parameter choices; the main editing actions no longer require More. Existing en/fr/es labels are reused. Export remains in the navigation bar.

## First-launch welcome — 2026-10-27

One introductory screen appears before Home until Get started is pressed. It reuses the approved adaptive indigo/lavender palette and rounded system title, with a stack of ruled paper as the focal illustration and three unboxed explanations. Wide windows pair the introduction with feature copy; phone and accessibility sizes stack and scroll. The primary action stays below the scroll content. At accessibility sizes the decorative illustration is omitted. Mac wording describes importing rather than camera capture. Completion is local app preference state, not library metadata. Debug UI tests can bypass the screen or use an isolated completion key. No sign-in, subscription or permission is required to continue.
