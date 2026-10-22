# Session handoff

## Continuation notes for Codex (design relay, started 2026-10-21 18:50)

The owner asked Claude and Codex to work on the design together, handing off through files. Claude writes these notes and updates them after every step, so they stay current if Claude's session ends. **Read this section first, then `docs/CLEAN_NATIVE_DESIGN.md`.**

### Who is editing what (update this line when you start or stop)

- **Claude:** design pass 2 **finished (20:30)** and verified: 119 unit tests, 6 iOS UI tests, Mac and iOS builds with 0 warnings, iPhone screenshots `docs/screenshots/design-2-*` (en/fr/es/dark). **Claude is not editing any file now.** What it changed:
  - Store: `renameFolder`, `deleteFolder` (contents move up; the row stays as a sync tombstone), `scopeCounts`, `StoreError.folderNotFound`.
  - `LibraryModel`: folders, counts, `sortOrder` (remembered), `currentFolderID` (imports go to the folder shown; from the iPhone home, to the root), `recentItems`, `open(_:)` / `homeDocument`, `isShowingScanner` / `isShowingSettings`.
  - `RootView`: sidebar counts (`.badge`), a Folders section with + / Rename / Delete Folder…, the iPhone home on compact width (`LibraryHomeSections` in the new `LibraryHome.swift`), and `LibraryPresentations` (file importer, camera, Settings, errors, password prompt) attached once at the root.
  - `LibraryView`: scope titles, item count (Mac subtitle), sort menu, tiles per the mockup with a ⋯ menu (same actions as the context menu, plus Move to Folder), empty-folder state; `CaptureActions` is shared with the home.
  - `Theme.libraryBackground` (white library; the editor keeps the gray canvas). Seeder `--folder`.
  - **Why the odd bits:** see the "Found and fixed" notes in TEST_MATRIX.md (buttons and the Recent row sit in section headers; documents from Recent push over the home).
- **Claude: design pass 3 (Export sheet) finished at 21:00. `ExportSheet.swift` is free.** What changed: `ExportSheet` (tiles via `ChoiceTile`/`ChoiceTileStyle`, destination first: Save / Copy / Share), `Clipboard.write(files:)`, 7 new strings (`export.destination*`, `export.copy.unavailable`, `export.copied`), two new UI tests, and the layout test now checks `export-format-pdf`. `SaveExportedFiles` is unchanged (Settings still uses it). Tiles sit inside Form rows with their own button style and inset row edges; see the comments there.
- **Claude: design pass 4 (document view) finished at 21:30. `DocumentView.swift` is free; Claude is not editing anything.** What changed: `DocumentModel.rename(to:)` / `setFavorite(_:)`; the title `▾` menu (`.toolbarTitleMenu`: Rename / Favorites / Export); on iPad `.toolbarRole(.editor)` with rotate/crop/filter as `.secondaryAction` (Mac: `.principal`), Export + `⋯` (add/replace items, Delete Page) as `.primaryAction`; the page column's `+` (same add/replace menu, `strip-add-pages`); iPhone `filterStrip` (`editor-filter`, `filter-original|grayscale|blackAndWhite`); `PageFilter.title`. No new strings. New UI test `testFilterStripAndTitleMenu` (it restores the filter and favorite, because `testSidebarNavigation…` expects "No Favorites").
- **Claude: pass 7 (Apple Pencil on iPad, first slice) finished at 22:50. Claude is not editing anything.** New: `InkConversion.swift`, `InkCanvas.swift` (iOS), ink in `PageRenderer`/`Exporter`, `LibraryStore.applyObjectChanges`, `DocumentModel.changeInk`/`selectedPageObjects`, `PageImageView(includesInk:)`, Markup + Draw with Finger toggles in the iPad toolbar, strings `page.markup`, `page.drawWithFinger`, `undo.ink`, plural `ink.strokeCount`. `InkPoint.pressure` was renamed `widthScale` (width relative to the stroke). Tests: `InkRenderTests`, `InkExportTests`, `ObjectChangeTests`, `InkConversionTests`, workflow `inkChangesUndoRedoAndSurviveRelaunch`, and the iPad UI test `testMarkupWithFingerDrawingSavesAStroke` (run it with `scripts/ui-test-ios.sh 62328381-19FB-400A-A8FC-4F4AD13EB5C4 -only-testing:PaperNest-iOSUITests/AppUITests/testMarkupWithFingerDrawingSavesAStroke`; it skips on iPhone). Limitations and what's next are in `CLEAN_NATIVE_DESIGN.md` → pass 7. **Follow-up (23:45, Claude, files `InkCanvas.swift`, `DocumentView.swift`, the Markup test in `AppUITests.swift`):** ink undo moved to the document's undo history so the palette's Undo/Redo work (iPad test passes, also after a pinch-zoom); zoom buttons hidden while marking up.
- **iPad simulators exist** (iOS 26.5 and 27.0 runtimes): e.g. iPad Air 13-inch (M4) `62328381-19FB-400A-A8FC-4F4AD13EB5C4`. Screenshot with `xcrun simctl io <udid> screenshot <file>`. Screens: `docs/screenshots/design-4-ipad-*`.
- **Next, in order (any agent):** (1) a **visual check of the Mac app**, which no one has viewed (library, document window, export sheet, File > Import, Replace Page); (2) **Apple Pencil, next slices:** a check with a real iPad and Apple Pencil (feel); document-level undo for ink after leaving Markup; drawing on iPhone (finger) and Mac (mouse/trackpad); a custom palette if the owner wants the mockup's look; (3) the page column's selected page as a blue border instead of the system highlight (keep drag-to-reorder and keyboard selection); (4) a search field on the iPhone home; (5) ⋯ menus on Recent cards; (6) drag documents onto sidebar folders; (7) post-scan review screen (pass 6) needs a device for the camera.
- If you see no update from Claude for a while and the owner tells you to continue, take over Claude's pass from its status in `CLEAN_NATIVE_DESIGN.md` → "Work plan".

### Repository state

- Nothing is committed since `cdbf280` (Settings). The working tree mixes three things:
  1. Claude's **rescan / replace page** work (verified: 115 unit tests, 3 iOS UI tests, Simulator end to end).
  2. Codex's **Clean & Native pass 1** (`Theme.swift`, `LibraryView`, `DocumentView`, `PageImageView`, `AppUITests`, `docs/CLEAN_NATIVE_DESIGN.md`, `docs/screenshots/clean-native-*`, `AGENTS.md`).
  3. The design reference mockups in `docs/design/mockups/`.
- On the combined tree at 18:52: `./scripts/test.sh` **passed, 115 tests**. `scripts/ui-test-ios.sh`: **passed, 4 UI tests** (including Codex's layout-switch test).
- Don't commit unless the owner asks. At 20:40 Claude asked the owner for a checkpoint commit of the combined tree (rescan + pass 1 + pass 2) before pass 3, so each agent's later work is its own diff. Check `git log` to see whether it happened.

### Do not undo (each one fixed a real bug)

- `DocumentView`: `filePurpose` and `isShowingFilePicker` are **separate** state. The `fileImporter` binding clears its value *before* `onCompletion` runs, so folding the purpose back into the presented flag turns "Replace Page" into "Add Pages".
- `scripts/build-ios-sim-app.sh` builds the **Xcode project's** app (`com.example.papernest`). A hand-assembled bundle has no `__TEXT,__entitlements` section, and every file picked in the Simulator then fails with "Could not resolve bookmark… permission".
- `LibraryStore.replacePage` / `revertPageReplacement` / `reapplyPageReplacement` are single transactions. `SQLiteDatabase.transaction` nests as savepoints, so keep store operations composable rather than re-adding separate commits.

### Notes for the Export sheet pass (Codex)

- `AppUITests.testLibraryLayoutSwitchStillOpensDocumentsAndEditingTools` ends with `app.segmentedControls.buttons["PDF"]`. Update that assertion when the formats become tiles (give each tile an identifier such as `export-format-pdf` and an `accessibilityValue` of selected/not selected).
- `SaveExportedFiles` is also used by `SettingsView` (backup); `testSettingsShowsTheLibraryAndExportsABackup` covers it.
- Seed a screenshot library with folders: `scripts/swift.sh run papernest-seed <lib> <files…> --folder "Receipts"` (new option). The iPhone Simulator 63992C10-… opens `-PaperNestLibraryPath /tmp/pn-design-lib` (already seeded, 5 documents, 2 folders). On this single-display device, `simctl io … screenshot` must be run **without** `--display=primary`.

### Shared files, to avoid collisions

- `Localization.swift` and the three `Localizable.strings` files: `LocalizationTests` fails on keys that are declared but unused. Add keys in the **same change** as the code that uses them, in a block commented with your pass name (`// Design pass 3: export sheet`).
- `AppUITests.swift`: add new tests at the end; don't reorder existing ones.

### Design rules (details in `docs/CLEAN_NATIVE_DESIGN.md`)

- The mockups are in `docs/design/mockups/` (PNG and WebP), with a text description of every screen in the design doc in case you can't open images.
- Match the look for features that **exist**. Leave out entirely, with no disabled placeholders: iCloud "Synced" status, the cloud button, the OCR button, the "Searchable text (OCR)" toggle, Word and Plain text export tiles, pen/Pencil tools, New note, a Notes tab, Cleanup and custom camera modes. Each of those arrives with its milestone.
- The mockups' sidebar section called "Notebooks" is implemented as **Folders** (notebook is a separate M3 item kind). That was Claude's call, not the owner's.

## Session 1 (2026-10-20)

### Completed

- Inspected the environment. At the start: no Xcode, Command Line Tools 26.2 (Swift 6.2.3, macOS 26.2 SDK), not a git repository. I ran `git init`. The initial commit was made at the owner's request on 2026-10-21.
- Decisions recorded in ARCHITECTURE.md:
  - SQLite as the only metadata authority, with content-addressed immutable assets
  - CKSyncEngine planned for sync
  - Native macOS app, not Catalyst
  - iOS 17 / macOS 14 minimum
  - No third-party dependencies
- M0 foundation and the M1 Mac path:
  - Swift package modules for Core, Store, Import, Render, Export and UI
  - Dev build scripts for Mac and iOS Simulator
  - 87 passing tests (105 cases)
  - en/fr/es localization with parity tests
  - Synthetic samples
  - XcodeGen spec, Info.plists, entitlements and a privacy manifest
  - All required docs
- After the owner accepted the Xcode 27.1 license:
  - Tests pass under Xcode.
  - Thread Sanitizer passed ×4 and Address Sanitizer ×1, both clean.
  - The first iOS compile (Simulator and device) succeeded with 0 warnings.
  - The iPhone app runs in the Simulator, and its screens were verified from screenshots (`docs/screenshots/`).

### Fixed this session

- **Redo was broken.** Undo handlers registered their inverse inside an async Task. The inverse is now registered synchronously (`DocumentModel`). Tested.
- **Permanent delete could destroy an original that an undoable page deletion still needed.** Pages are now soft-deleted (`pages.deleted_at`, schema **v2**) until `purgeDeletedPages` runs at the next launch. Tested, including the v1→v2 migration.
- **iPhone layout:** the document view now shows the page full width with a thumbnail scroller and bottom-toolbar actions; reordering is in a Pages sheet.
- **Export sheet:** it was clipped on iPhone, and option values truncated in French and Spanish. It now uses inline option rows on iOS.
- **Shortcut clash:** ⌘E clashed with "Use Selection for Find", so Export is now ⇧⌘E.
- **Rescan / replace a page** (2026-10-21): Rescan Page (camera), Replace Page with File… (all platforms) and Scan Pages (add camera pages to a document). The page keeps its place, the look carries over and the geometry resets, with undo/redo. Schema **v3** `page_content_history` keeps the old scan until the next launch. Picker failures now show an error. Replace + extra pages commit in one transaction (`LibraryStore.replacePage`; `SQLiteDatabase.transaction` nests as savepoints). **Verified end to end in the Simulator with Replace Page with File…** after fixing replace-became-add (picker purpose cleared by the `fileImporter` binding) and switching `build-ios-sim-app.sh` to the Xcode project's app (the old hand-built bundle had no entitlements section, so file picks failed). 8 new tests (115 total). The camera path still needs a device.
- **Settings** (2026-10-21): storage figures, Export All Documents (ZIP of PDFs) as a backup, language, version and privacy note. iPhone/iPad open it from the ⋯ menu, the Mac from ⌘,. No login or profile, as the brief requires. 4 new unit tests (107 total) and a UI test (3 UI tests in total, now `AppUITests`).
- **Crop tool** (2026-10-21): editor sheet, ⌘K, toolbar buttons, undoable `setCrop`, a thumbnail-cache key that includes the transform, dark underlays so the frame shows on white paper, and a VoiceOver value. Review then found that filtered PDF pages with tight crops failed to render or export; they now rasterize only the crop. 15 new unit tests (102 total), plus the first UI-test target (`PaperNest-iOSUITests`, run with `scripts/ui-test-ios.sh`), whose crop drag test passes.
- **`scripts/test.sh`** failed under Xcode (bash 3.2 empty-array bug).
- **Build output and built apps** moved out of the iCloud-synced checkout. `codesign` was rejecting test bundles there, iCloud broke app signatures after signing, and it was creating "debug 2" conflict copies.

### Status

| Area | State |
|---|---|
| Core/Store/Import/Render/Export | Automated tests passed (macOS); sanitizers clean |
| Mac app | Builds, launches, opens a library. **UI not visually verified** (the owner declined Claude's control of the app). |
| iPhone app | Builds for Simulator and device. Library, document and export screens **Simulator verified (screenshots only, no taps)** in en/fr/es. |
| iPad | Compiles. **Layout not verified**: the installed iOS 27.1 runtime only supports the "iPhone Duo" simulator. |
| Xcode project | Generated with XcodeGen 2.46.0; both app schemes build (Simulator / Mac, no signing team yet) |
| Sync, notebook editor, OCR, DOCX/TXT, subscriptions | Not started (designs in ARCHITECTURE.md) |

### Waiting on the owner

1. Recommended: **move the project out of the iCloud-synced Desktop** (for example to `~/Developer/PaperNest`). iCloud has already made conflict copies inside build folders and could do the same inside `.git`. Moving the whole folder keeps the git history. The build cache path follows the checkout, so a move just starts a fresh cache.
2. A manual look at the **Mac app**: the checklist is in TEST_MATRIX.md. Or allow Claude to control the dev build.
3. Apple Developer team, bundle ID and iCloud container, before M2 (APPLE_SETUP.md).
4. Optional: an iPad simulator runtime (Xcode > Settings > Components) for iPad layout checks.

### Simulator used

"PaperNest iPhone Duo", UDID `F5269418-AA12-4CF9-8EE4-6B6B89F228B8` (iOS 27.1), created for this project on 2026-10-21. The first one, and every other iOS 27.1 simulator, disappeared overnight for reasons outside this session. Its library is seeded with `Samples/` plus a cropped "Cropped-whiteboard". Delete it with `xcrun simctl delete F5269418-AA12-4CF9-8EE4-6B6B89F228B8` when it's no longer needed. The device has two displays; screenshot with `--display=primary`.

### Next commands

```bash
git log --oneline | head                     # initial commit on main
./scripts/test.sh                            # expect 115 tests passing (5 per-target runs under Xcode)
./scripts/ui-test-ios.sh                     # iOS UI tests, headless in the Simulator (expect AppUITests to pass)
xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build
./scripts/build-ios-sim-app.sh               # Xcode-project app (com.example.papernest); then: xcrun simctl install <udid> <path>
./scripts/run-mac-app.sh /tmp/pn-dev         # dev Mac app with a seeded throwaway library
```

### Next work, in order

1. Crop: **done on iPhone** (UI test passes). Remaining: a manual check of the Mac drag, and VoiceOver resizing (it can only reset today).
2. A real-device camera test (Scan Pages, Rescan Page, multi-page capture) completes the M1 gate. Rescan is implemented and the file path is Simulator-verified. Also do a Mac check of Page > Replace Page with File….
3. Exercise taps in the Simulator: the Pages sheet reorder, filters, the adjustments sheet, export and save.
4. Polish: on iOS, inline option rows show their label as a plain row; consider section headers.
5. Start M2: the v4 migration (`sync_state`, `outbox`, `tombstones`), then the CKSyncEngine adapter.

### Open risk

- A one-off iPhone navigation glitch (thumbnail tap → Favorites, then stuck). The sidebar binding was corrected, but the fix is unproven and the glitch didn't reproduce (TEST_MATRIX.md).

- One unexplained SIGSEGV in one test run, on an intermediate build (TEST_MATRIX.md, "Open issue"). Not reproduced in 11 later runs or under the sanitizers.

### Notes for whoever continues

- SwiftUI's `LibraryItem` type clashes with ours; write `PaperNestCore.LibraryItem` in SwiftUI files.
- PDFKit `dataRepresentation()` of an unlocked encrypted PDF stays encrypted. The importer copies the pages into a new document instead (see `PDFInspector`).
- ImageIO happily decodes truncated JPEG/PNG files, which is why the importer checks their structure itself.
- Under Xcode 27, `swift test` runs each test target in its own process and code-signs the bundles.
