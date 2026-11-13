## Home and scanner redesign — owner brief, 2026-11-13

The owner gave a written brief and two reference boards in session ("Paper NEST — Home screen & scanner complete UI redesign"). It supersedes the Home and Scan lines of the 2026-11-07 entry below, the 2026-11-05 rule that the wide sidebar carries no brand, and the 2026-11-04 "content-first Home without quick cards". Built by Claude on the owner's direct instruction. What was run is in TEST_MATRIX.

**Home, every platform.** A greeting chosen from the local hour (no name: there is no account to take one from), one row of quick actions, then Recent Documents from the store. Nothing on Home appears twice.

- **iPhone:** brand and mark in the header; New Note, Import File, New Folder on lavender cards; five recent documents as rows with a ⋯ menu; See All. Bottom bar: **Home, Notes, Scan, Files**. Files is the same root column showing All Documents, Favorites, Recently Deleted and the folders with New Folder.
- **iPad:** sidebar with the brand, then Home, Notes, All Documents, Folders, Favorites, Recently Deleted, and the iCloud card at the foot. Detail: "Home", a lavender banner, **Scan**, New Note, Import File, New Folder, recent documents as a strip of thumbnail cards, then folder cards with real counts and See All.
- **Mac:** the same sidebar and banner; New Note, Import File, New Folder only; recent documents in a table (Name, Modified, Size) that sorts, selects, opens on double-click and has the usual context menu. **No Scan anywhere on Mac Home.**
- **Folders** is one sidebar row leading to a Folders screen of cards (open, rename, delete, New Folder). The row stays selected while one of its folders is showing.

**Where the brief and its pictures disagree, the written brief wins.** The pictures show Documents in the phone's bar and three actions on iPad; the brief's text and acceptance criteria say Scan in the bar and a Scan action on iPad.

**Calls made here, not by the owner — change them if they are wrong.**

- **Tools and Profile sit where the pictures draw a bell.** There are no notifications to show. The Tools hub was reachable only from Home's old tool grid, so it became a header button (`home-tools-all`) instead of vanishing.
- **Home has no search field.** The pictures have none; search stays in Notes, All Documents and every folder.
- **The product is still "PaperNest".** The pictures letter it "Paper NEST". `Brand.displayName` and the real `BrandMark` are unchanged; renaming the product is not a layout decision.
- **The sidebar row says "All Documents"**, not "Documents", because that is the title of the screen it opens.
- **The selected sidebar row is the system's.** The pictures fill it purple; a custom row background makes iPadOS draw a second focus halo (see 2026-11-05), so selection is tinted, not repainted.
- **The iCloud card always shows.** It reads the sync controller. In a build made without an iCloud container it says "Not set up in this build" rather than nothing, as the brief asks. The phone keeps the small status icon in its header, which still draws nothing in such a build.
- **Size is the store's, not a guess.** A file shows its own bytes; a document shows the originals its live pages are made of (`LibraryStore.originalByteCount`, each original counted once). A notebook of drawn pages has nothing stored, so the Mac table shows "—" and the phone and iPad rows show its page count instead. Sizes are read only for the eight documents Home can list.
- **Vault never existed in this app.** Nothing was removed; the UI test that asserts its absence stays.
- **Colours.** New tokens `navy`, `lavender`, `homeBackground`, `border`, `deepAccent` in `Theme`, light values from the brief, dark values chosen here. `Theme.accent` (#7545F8) is one step from the brief's #7438F5 and was left alone so the editor does not shift.

**Scanner, iPhone and iPad.** Dark in both appearances (`ScannerChrome`). Capture: Cancel and title, flash, a ⋯ menu (Import Photos, System scanner), a mode picker, the kept pages as a thumbnail with a count, the shutter, Auto/Manual. Review: stacked on a phone; on iPad the pages down the left, the page in the middle, the tools down the right and Save at the bottom.

- **Modes: Document and Photo only.** Document finds, outlines and crops to the page's edges. Photo keeps the whole frame and turns Auto off. **ID Card and Book are not shown**: neither exists, and the brief says to show only modes that do something.
- **Tools: Enhance, Crop, Rotate, Filter, Move earlier, Move later, Duplicate, Reset, Delete.** **Clean, OCR and Merge Pages are not in the scanner**: there is no clean-up filter, and recognition and merging happen on the saved document, where they already are. No button was added for something that does nothing.
- Save still goes through the import-location sheet and the durable import; the scanner never reports a page saved before it is.
- **A saved scan does not open in the editor; its export screen opens by itself** (owner, in session, after seeing the first build: "it should not open in notes section instead give option to export if user does not want to export bring back to home screen", then "export screen should automatically pops up when doc is saved"). Once the store has the document the ordinary export sheet is presented for it, with nothing in between. Closing the sheet, having exported or not, ends on Home with nothing pushed over it, and the scan is the newest row in Recent Documents. Importing a file and creating a note still open what they made.

## Sidebar toggle placement — owner approval, 2026-11-08

Mac and iPad keep editor panel controls in the native navigation header: page thumbnails beside Back/title on the leading side, PDF tools beside Export on the trailing side. Both remain available when their panels are hidden. The centered writing row contains Pen, Eraser, Highlighter, Lasso, Image and Text only. Preserve the panel defaults, accessibility labels/IDs and existing actions. iPhone retains its current writing-row page toggle and More menu. Approved preview: `docs/design/mockups/sidebar-header-mac-approved-2026-11-08.png`.

## Approved phased redesign — owner approval, 2026-11-07

The owner approved implementation of the reference boards in `docs/design/approved-2026-11-07/`. These supersede the earlier “preview only” notes below. Preserve the real `leaf.circle` brand and existing SF/native typography, semantic lavender colors, product boundaries and durable store.

- Home: compact capture/import, Tools, actual Recent/Favorites and My Space. No Shared or sync claim without a real service. Wide layouts place collections beside recent content. Notes uses real notebook covers; Documents uses document rows and independent layout preference.
- Editor: session-local document tabs, compact icon-only tools for notebooks and PDFs, hideable page strip and default-visible trailing tools inspector on iPad/Mac. Signature, forms and page controls occupy the inspector; iPhone keeps its compact presentations. Retain per-document inline drafts, zoom and undo state when switching tabs. Confirm before discarding unsaved tool drafts.
- Scan: dark capture chrome and lavender shutter, actual edge detection and native scanner fallback, thumbnails above review, crop/rotate/filter controls and durable import destination workflow. Do not display unsupported capture modes or imply OCR text is a searchable PDF.
- Profile/Pro/Export: use existing accountless profile, actual StoreKit offer data and real export choices. Never reproduce illustrative prices, sync states or sample library content.

Verification and remaining hardware limitations are recorded in TEST_MATRIX, not inferred from the design images.

## PDF tools right sidebar — owner request, 2026-11-05

Mac and iPad expose the existing secondary editor actions in a native trailing inspector. The sidebar icon beside Text toggles it; a localized close button stays at its top. It opens by default on Mac and iPad (owner correction, 2026-11-05); either hide control restores page space. The panel uses semantic lavender surfaces, wrapping SF labels, recognizable symbols, 44-point rows and vertical scrolling. In compact iPad windows, the system adapts the inspector presentation. iPhone retains the existing More menu. Both presentations share the same action builder and existing sheets, subscription checks, history and persistence; no new PDF capabilities are implied. The separate compact editor-header/left-page-strip concept remains unimplemented pending owner approval.

## iPad sidebar headings — owner correction, 2026-11-05

Keep the regular-width iPad sidebar navigation bar untitled on Home, Notes, Documents, Favorites, folders and open documents. Preserve the sidebar toggle and all destinations. PaperNest’s logo/name belongs in the Home dashboard, not a repeated heading above sidebar navigation. Destination names stay in the main detail column. Home uses no redundant dashboard navigation title on iPhone, iPad or Mac. Keep the Home destination label in the tab/sidebar, the dashboard brand and Profile entry. Other destination titles remain unchanged.

## Preserve the project in design samples — owner instruction, 2026-11-05

All future samples must retain PaperNest’s actual existing logo and the existing project components, icons, colors, typography and navigation except for the specific changes the owner asks to explore. Reuse the exact current logo asset/symbol (`leaf.circle` in LibraryHome), not a generated substitute. Prefer a screenshot or deterministic composite when exact branding matters; label any unavoidable illustration approximation. Read the current project before creating samples. The compact editor header and hideable page-strip concept is still a preview, not approved implementation.

## Round eraser — 2026-11-05

The owner confirmed partial erasing as the default. Keep the approved toolbar icon, with a circular canvas footprint and an anchored Eraser popover on repeat selection. Offer Small/Medium/Large, a continuous relative size and a round preview; keep pen/highlighter preferences independent. Whole-stroke mode is optional. iOS uses PencilKit’s supported precision width range and hides sizing for its fixed-size whole-stroke mode. Mac maps the view-space circle through PageGeometry and preserves editable stroke fragments with undo. Text and images are never silently erased by the ink eraser.

## Notes toolbar option B — owner-approved November 5, 2026

Use the expressive writing tools from the approved two-option preview: a slanted pen with purple ink detail, pink-ended eraser, yellow highlighter nib, dotted freehand lasso, simple image frame, T and More. Original vector paths share a 24-point optical grid and rounded strokes. Keep icon-only presentation, existing localized accessibility labels/tooltips and 44-point targets. The selection is a quiet lavender rounded square; color accents identify instruments, not subscription state or current ink color. Preserve tool order and place a subtle divider before Image/Text/More. The white/tinted toolbar surface hugs its content and centers on wide screens, scrolling when it cannot fit. Lower active-tool glyph matches the upper row. All existing actions, popover anchors and persistence remain unchanged.

## Icon-only Notes toolbar — 2026-11-05

Owner correction: use the slanted SF Symbol `pencil` for writing and hide visible names in the notebook toolbar on iPhone, iPad and Mac. Keep 44-point targets, localized VoiceOver names, selection values and Mac tooltips. Primary order: Pen, Eraser, Highlighter, Lasso, Image, Text Box, More. Image and Text Box open their existing working insertion/formatting flows; secondary tools remain in More.

Pen settings must anchor to the top Pen tool, including when opened from the lower palette. Each writing tool owns its settings popover; compact iPhone presentation remains a popover near that tool rather than a bottom sheet. Text Box retains its native editor with text, size, alignment and color controls. Preserve the existing NotebookToolbar evaluation boundary and durable insertion paths.

## Compact Notes tools — 2026-11-04

Owner correction: limit the writing toolbar on every platform. Keep Pen, Eraser, Highlighter, Lasso and More, with Eraser immediately after Pen. More retains the working insert, page and document-editing actions. Reuse the existing native menus and sheet flows. Keep horizontal scrolling for long translations and accessibility text sizes.

Selecting Pen activates drawing; tapping it again opens settings. Settings include a live stroke preview, width presets plus a fine width slider, existing custom colors, and opacity. Keep independent Pen and Highlighter widths during the editor session; color changes preserve opacity. Retain whole-stroke erasing and explain it honestly. No unsupported brush names, data-model changes, or new persistence stores. Keep the separate NotebookToolbar View evaluation boundary that prevents the iPad debug stack overflow.

## Notes library — 2026-11-04

Notes is a notebook-only library, using the existing durable library and notebook editor. Its empty state describes notebooks and offers New Notebook; the same creation action remains in the toolbar once notebooks exist. Reuse NotebookCreationSheet, templates and subscription limits. Scan/import actions remain in document destinations and Home. Filter rendered rows immediately by the selected content kind while asynchronous reloads finish, and clear bulk selection when changing kind. Keep notebook creation, opening and reopening consistent on iPad and Mac. Sidebar actions reset the detail path when switching destinations; apply destination tags after badges so native selection still recognizes every row.

## Home Profile icon — 2026-11-04

Owner correction: use an icon-only circular profile symbol in the Home header on iPhone, iPad and Mac, without visible “Profile” text or rectangular button chrome. Retain a localized Profile accessibility label, at least a 44-point hit target, Dynamic Type and the existing Profile sheet. Apple does not expose an Apple Account avatar to downloaded apps or Sign in with Apple credentials; this app has no existing account-photo source. Use the honest person symbol fallback rather than inventing a photo or adding an unrelated account system.

## Native sidebar selection — 2026-11-04

Physical iPad correction: Full Keyboard Access is off; the earlier settings attribution was incorrect. Runtime inspection identified the native List collection cell and its `UIFocusHaloEffect`. The custom `listRowBackground` capsule forced a separate rectangular keyboard-focus outline. Remove the custom row background and foreground overrides; let native List own selection and focus together. Physical Home and Notes screenshots now show one rounded blue highlight without the outer square. Keep keyboard focus enabled and do not change system accessibility settings.

Home and Notes participate in native list selection on Mac and iPad. Explicit row actions preserve navigation, and switching destinations moves the highlight and accessibility selection state. Scope selection and document navigation remain backed by LibraryModel. Keep the compact iPhone Home's lavender styling.

## Home Tools placement — 2026-11-04

The owner's latest Home mockup supersedes the earlier restriction on Home Scan/Import actions: show the existing capture/import actions after search, then a labeled Tools section, then Recent. Home offers Merge Documents, Extract Pages, Split into Pages and Export as ZIP using the existing tool catalog and workflows. See All opens the complete Tools screen, including creation/import tools. Remove global Tools toolbar buttons on iPhone, iPad and Mac; editor-specific tools remain in the editor. Compact layouts retain two wrapping columns (vertical icon/label at accessibility sizes); wider windows use an adaptive grid. Mac offers Import, with no unsupported camera placeholder. Native typography and semantic lavender surfaces are unchanged. No new converters, payment rules or persistence changes.

## Unified studio reference — 2026-11-04

The owner's Biology Cell Notes, Biology Notes UI and Cross-Platform Showcase screenshots supersede the older blue/ice palette for Home, Scan and Notes. Use semantic lavender #B9A5FF / strong purple #7545F8, selected #E4DAFF and background #FAF9FF with dark counterparts. Home is content-first with no central quick-action cards. Keep actual folders and local/cloud state honest. Preserve native VisionKit behavior rather than substituting a camera without its capture guarantees. Custom Notes controls drive the existing canvas and store. Vault is separately planned per the owner's reply. Implementation and remaining capabilities: `UNIFIED_STUDIO_REDESIGN.md`.

## Tools hub refinement — 2026-11-04

The Tools screen now uses a scrolling card collection on the existing ice/navy canvas. Create and Documents remain separate labelled sections. Photos uses the same label treatment as ordinary buttons while retaining the system PhotosPicker. Document cards show their existing localized selection instructions before opening the picker. Cards use SF headline/subheadline, accent icon wells, quiet surface borders and wrapping labels. An adaptive 200-point minimum yields one column on narrow phones and more on wider windows; accessibility text sizes force one column. Mac sheet size is bounded, with Done remaining in its existing footer. All original identifiers and actions remain. No new converter, media, Vault or VPN tiles.

## Coordinated iPhone, iPad and Mac refinement — 2026-11-04

Owner confirmed all three platforms. Continue the existing premium SF/indigo/lavender direction, using real library content and working actions. First slice makes export choices explicitly stack at accessibility text sizes on iPhone/iPad, permits their detail text to wrap, and bounds Mac export/markup sheets to 680 points with a smaller minimum so grouped forms can scroll. Saved marks get three lines for distinguishing similar text boxes, a 44-point minimum row, and their full existing accessibility label. Export formats, password validation and store operations stay intact.

Next slices: consistent library hierarchy and empty states, Tools grouping, then editor control density and keyboard/VoiceOver access. Keep Notes tools side by side with reachable overflow by scrolling. Verify each slice across compact/regular layouts and en/fr/es when Simulator setup is repaired; compilation alone is not visual or interaction validation. Vault/VPN remain deferred.

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


## Inline text and PDF workspace — 2026-11-05

- Main editor tools are icon-only and centered; More sits immediately beside Text Box, with a scrolling row when needed. Keep accessible names and Mac tooltips. Icon artwork stays within 44-point targets at accessibility sizes; menus and text continue to scale.
- Text input stays on paper, with a native caret and a contextual floating formatting bar. Only dedicated handles move/resize; formatting preserves selection. Keyboard presentation must not rescale the paper under the caret.
- Form, signature and page operations use native adaptive sheets with real working actions. Preserve form controls through the success state on Mac to avoid replacing the active accessibility focus hierarchy. Keep Undo and Redo together in one toolbar container.
- Be explicit about filled copies, unsupported form fields and visual signatures. Never imply certificate signing or interactive form retention after a rendered export.


## Notebook continuation — 2026-11-08

The last notebook page ends with a quiet localized continuation hint. Deliberately scrolling to its end creates and selects one blank page with the last page's paper pattern and geometry. A gesture can append only once; opening/resizing alone never creates pages. The hint is also an accessible Add action. Reuse notebook persistence/history; do not copy page objects or append pages automatically to PDF documents. Keep drawing/lasso gestures separate from navigation scrolling.


## Continuous notebook pages — 2026-11-08

Notebooks use a single lazy vertical page stack with 20-point gaps. Scroll in either direction through existing pages; the most visible page becomes active without jumping the viewport. Only that page mounts editing canvases; other pages render saved editable content through the existing renderer. Sidebar selections still jump directly to their page. Preserve zoom across notebook pages, keep inline drafts on their original page until finished, and retain automatic matching-paper continuation only at the notebook tail. PDFs retain their selected-page workspace. Inactive pages expose a localized activation button for accessibility; the active editor keeps its existing identifiers.
