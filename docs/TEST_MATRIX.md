# Test matrix

Only checks that were actually run are recorded as passed. "Not run" means not run.

## Environment (session 1, 2026-10-20)

- MacBook (Apple silicon, arm64, 16 GB), macOS 26.6.2 (25G83)
- Command Line Tools 26.2: Swift 6.2.3, macOS 26.2 SDK. No iOS SDK and no simulators through most of the session.
- Xcode 27.1 (27A9275) appeared in `/Applications` mid-session. After the owner accepted its license, the later results ran under Xcode (Swift 6.4, iOS 27.1 and macOS 27.0 SDKs, iOS 27.1 simulator runtime). The earlier results used `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.
- The checkout is on the iCloud-synced Desktop, so build output goes to `~/Library/Caches/PaperNest/build-<hash>` (`scripts/env.sh`). Inside the synced folder, `codesign` rejected test bundles because of iCloud's Finder-info attributes.

## Automated results

| Command | Result |
|---|---|
| `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./scripts/test.sh` | **Passed: 87 tests in 18 suites** (parameterized tests count once; 105 cases in all), 0 failures, 0 compiler warnings. The final code passed 11 consecutive full runs. |
| `./scripts/test.sh --sanitize=thread` (CLT) | **Blocked**: macOS refused to load the CLT sanitizer runtime ("Sanitizer load violates platform policy") |
| Design pass 3 (Export sheet), Claude, 20:50–21:00 | `./scripts/test.sh`: **passed, 119 tests** (LocalizationTests cover the 7 new keys). `scripts/ui-test-ios.sh 63992C10-…`: **passed, 8 UI tests**. New: `testExportTilesSelectOneAtATimeAndCopyConfirms` (JPEG then Range then All each take their own tap inside Form rows; Copy → "Copied to the clipboard.") and `testExportSaveOpensTheSaveDialogAndClosingItKeepsTheExport` (Export → system "Save as" dialog → drag it closed → the ready footer still offers Save… and Share…). `build-mac-app.sh` and the iOS build: passed, 0 warnings. Screenshots `docs/screenshots/design-3-*`: fr (top), es (Export To), dark + largest accessibility text in fr (Pages tiles stack), en with a 5-page JPEG ZIP (Copy dimmed, note shown). **Found and fixed:** the rows' rounded corners clipped the selected tile's border (row edges are now inset); a wrapped French/Spanish label made one tile taller (tiles in a row now share a height). **Not verified:** the Mac sheet (never viewed), Share's system sheet contents, and pasting what Copy put on the clipboard into another app. |
| Design pass 2 (library, sidebar, iPhone home), Claude, 19:00–20:30 | `./scripts/test.sh`: **passed, 119 tests** (+3 `FolderTests`, +1 workflow test for folders/sort/import-into-folder). `scripts/ui-test-ios.sh 63992C10-…`: **passed, 6 UI tests**. New: `testAFolderMadeInTheSidebarHoldsAMovedDocument` (create a folder in the sidebar, move a document in from its ⋯ menu, check "1 item", delete the folder, document kept) and `testHomeRecentOpensADocumentAndSeeAllShowsTheGrid`. Existing tests updated for the iPhone home launch screen. `build-mac-app.sh` and the iOS Simulator build: passed, 0 warnings. Tapped through in the Simulator: Import from the home opens the picker, and the file lands in the library root (checked in SQLite). Screenshots `docs/screenshots/design-2-*` (library and home in en/fr/es/dark, sidebar): no truncation. **Found and fixed:** (1) buttons in a List row lost their styles (Scan looked enabled without a camera), so they moved to a section header; (2) the row's rounded corner clipped the first Recent card's date, so the Recent row is a header too; (3) on iPhone, setting the split-view selection and the library path together dropped the path (diagnosed with logs), so documents from Recent push over the home. **In-document pickers rechecked after moving the library's file importer to the root (an ancestor of every document view):** Replace Page with File… from a document opened via Recent replaced page 1 in place (3 → 5 pages, 1 history row, no new document), and Add Pages… from a document opened via All Documents added 3 pages (1 → 4, no new document), both checked in SQLite. **Not verified:** the Mac and iPad layouts; on the Mac, File > Import… and Page > Replace Page with File… after the importer move (same ancestor setup, never viewed); the camera paths (no device). |
| Combined tree: rescan + Codex's Clean & Native pass 1 (run by Claude, 18:52–19:00) | `./scripts/test.sh`: **passed, 115 tests**. `scripts/ui-test-ios.sh 63992C10-…`: **passed, 4 UI tests** (crop drag, Settings + backup, sidebar navigation, and Codex's new grid/list layout switch). |
| `./scripts/test.sh` (Xcode 27.1), after the atomic-rescan fix | **Passed: 115 tests** (20 + 26 + 17 + 17 + 35), 0 failures, 0 warnings. `scripts/ui-test-ios.sh 63992C10-…`: **3 UI tests passed**. `build-mac-app.sh` and the `PaperNestUI` iOS Simulator build: passed, 0 warnings. |
| Replace Page with File… in the owner's Simulator (iPhone 17 Pro, iOS 26.5), Xcode-built app | **Passed.** Page 2 of 3 replaced by the 3-page `multilingual-letter.pdf`: page 2 kept its place and selection, the 2 extra pages followed it (5 pages). SQLite: 1 `page_content_history` row holding the old content. Cancelling the picker (document menu and library Import) shows no alert and changes nothing. **Found and fixed on the way:** (1) replace silently became *add* (the `fileImporter` binding cleared the picker purpose before `onCompletion` ran); (2) the hand-assembled dev bundle lacked an entitlements section, so every picked file failed with "Could not resolve bookmark… permission" — `build-ios-sim-app.sh` now builds the Xcode project's app; (3) replace and extra-page insert were two commits — now one transaction (`replacePage`, nested savepoints). Undo was not exercised on the device (shake); it is covered by `LibraryWorkflowTests`. |
| `./scripts/test.sh` (Xcode 27.1), after rescan | **Passed: 111 tests** (17 + 17 + 18 + 24 + 35), 0 failures, 0 warnings. UI tests: 3 passed. |
| Rescan / replace in the owner's Simulator (iPhone 17 Pro, iOS 26.5) | The Add/Replace menu shows Scan Pages and Rescan Page **disabled** (no document camera, as intended), plus Add Pages… and Replace Page with File…; the file picker opens. **Picking failed:** "Could not resolve bookmark… you don't have permission" for files Claude copied into the simulator's Files storage from the Mac (the file provider never indexed them), so the app received nothing and the library was unchanged (checked in SQLite). Found and fixed: picker failures were silently ignored; they now show "couldn't be read". |
| `./scripts/test.sh` (Xcode 27.1), after Settings | **Passed: 107 tests** (17 + 17 + 17 + 21 + 35), 0 failures, 0 warnings |
| `scripts/ui-test-ios.sh 63992C10-…` after Settings | **Passed: 3 UI tests** (`AppUITests`: crop drag, Settings + backup, sidebar navigation), 0 warnings |
| Settings on iPhone 17 Pro (iOS 26.5), tapped through by Claude in the owner's attached Simulator | Shows 6 documents / 8 pages / 696 KB. **Export All produced `PaperNest Backup 2026-10-21.zip`; `unzip -t` OK; 6 PDFs. The cropped page is 221 × 311 pt (edit kept) and the rotated page 792 × 612.** French layout fits ("Prêt : 132 ko", Partager… / Enregistrer… / Terminé). Screenshots in `docs/screenshots/iphone-settings-*.png`. The Mac Settings window builds but has not been viewed. |
| `./scripts/test.sh` (Xcode 27.1), after the crop tool and the sidebar change | **Passed: 103 tests** (14 + 17 + 17 + 20 + 35), 0 failures, 0 warnings |
| `scripts/ui-test-ios.sh 63992C10-…` (XCUITest, iPhone 17 Pro, iOS 26.5) | **Passed: 2 UI tests**, 0 warnings: the crop drag test and a sidebar-navigation smoke test. The app also runs on iOS 26.5. |
| `scripts/ui-test-ios.sh` (XCUITest, iOS 27.1 Simulator, headless) | **Passed: `AppUITests`**, 0 warnings. Opens the crop editor, drags the top-left corner (value reads about 70% × 75%), taps Done, reopens, and finds the same crop saved. It also proved a Simulator app can open a library seeded on the Mac (`-PaperNestLibraryPath /tmp/…`). |
| `./scripts/test.sh` (Xcode 27.1) | **Passed: 87 tests** (run as 5 per-target processes: 13 + 16 + 20 + 29 + 9), 0 failures, 0 warnings |
| `./scripts/test.sh --sanitize=thread` (Xcode) | **Passed, 4 runs, 0 ThreadSanitizer reports.** `libclang_rt.tsan_osx_dynamic.dylib` confirmed linked into the test bundles with `otool -L`. |
| `./scripts/test.sh --sanitize=address` (Xcode) | **Passed, 1 run, 0 AddressSanitizer reports.** `libclang_rt.asan_osx_dynamic.dylib` confirmed linked. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **Passed**, 0 errors, 0 warnings. This was the first iOS compile of the shared code, including the VisionKit camera wrapper. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` | **Passed**, 0 errors, 0 warnings |
| `xcodegen generate` (XcodeGen 2.46.0) | **Passed**: `PaperNest.xcodeproj` with the `PaperNest-iOS` and `PaperNest-macOS` targets |
| `xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'generic/platform=iOS Simulator' build` | **Passed**, 0 compiler warnings. The bundle has ID `com.example.papernest`, MinimumOSVersion 17.0, UIDeviceFamily 1,2, the en/fr/es lproj folders, `PrivacyInfo.xcprivacy` and the UI resource bundle. |
| `xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-macOS -destination 'platform=macOS' build` | **Passed**, 0 compiler warnings. Same bundle ID, LSMinimumSystemVersion 14.0, sandbox and user-selected-file entitlements, `codesign --verify --strict` OK. |
| `./scripts/build-ios-sim-app.sh` | **Passed**: builds the Xcode project's `PaperNest-iOS` app (`com.example.papernest`), installed and launched on the simulator |
| `codesign --verify --strict` on app bundles inside the iCloud-synced checkout | **Failed after the fact**: iCloud added Finder-info attributes after signing. App output moved to `~/Library/Caches/PaperNest/…/dist`, where both bundles still verified 20 s after signing. |
| `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./scripts/build-mac-app.sh` | **Passed**: the dev `PaperNest.app` built and passed `codesign --verify --strict` (ad-hoc) right after signing |
| `open -n PaperNest.app --args -PaperNestLibraryPath <tmp>` | App launched, created the library (SQLite with WAL plus the Assets directory) at the override path, ran for several minutes, quit on SIGTERM. No crash report and no error/fault entries in `log show`. **The UI was not visually inspected.** |
| `swift run papernest-samples Samples` | **Passed**: 6 synthetic samples written |

### What the suites cover

| Area | Suites | Key checks |
|---|---|---|
| Ordering | `SortKeyTests` | Strictly ordered and valid keys, 500 random insertions against a reference array, worst-case same-gap insertion, rejection of bad bounds |
| Coordinates | `PageGeometryTests`, `PaperLayoutTests`, `ImageResolutionPolicyTests` | Each rotation moves the top-left corner to the right place. Crop then rotate. Inverse mapping. OCR boxes follow rotation. PDF `/Rotate` 0/90/180/270/−90/450. Paper fit never crops and keeps aspect ratio. Landscape paper selection. |
| Model | `CodableRoundTripTests`, `NameDeduplicatorTests` | Ink/text/image payloads with accents and € round-trip. Accent- and case-insensitive name deduplication. |
| Persistence | `LibraryStoreTests`, `DurabilityTests`, `DeletionTests`, `NamingAndSearchTests` | Reopen round trip. Moves rewrite only the moved page. Tied keys rebalance. Transform history. Exact undo of page deletion (including objects and OCR). **An undoable page deletion survives permanently deleting another item, shared original or not.** Deleted pages are purged at the next launch. **A v1 library migrates to v2 without losing pages.** **A crash between the asset write and the commit leaves only a sweepable file.** Failed transactions leave nothing. An abandoned uncommitted transaction is discarded. Newer schemas are refused and left untouched. Damaged asset files are detected. Recently Deleted restore and purge at 30 days with shared assets kept. FTS search ignores accents and is safe against injection. |
| Import | `PDFImportTests`, `ImageImportTests` | Vector PDF stored byte-identical. Rotated PDF stored upright. Password prompt, wrong password, unlocked copy with no password stored. Restricted PDFs declined. Truncated PDF/JPEG/PNG rejected. Type sniffed from content. Duplicate names. EXIF 6 rendered upright. DPI-based sizing. Scan sessions keep their order. Pages inserted mid-document. |
| Render | `RenderTests` | Rotation and crop move the marker as expected. Grayscale output is gray. B&W output is strictly two-level. Revert restores the original. Filtered PDF pages are rasterized, unfiltered ones stay vector. A missing original raises an error instead of rendering blank. |
| Export | `PDFExportTests`, `ImageExportTests`, `NamingAndZipTests` | Page order, sizes and selectable en/fr/es text. Rotated and reordered pages export upright in the new order. Letter/A4 fit without cropping. Lossy quality embeds `/DCTDecode`, Best is lossless, Compact is smaller. **Cancellation removes partial output.** ZIP validated by `/usr/bin/unzip -t`. Numbered names. Pixel size and dpi metadata. JPEG flattens transparency onto white so ink survives. Export leaves the library unchanged. CRC-32 check value. Unicode ZIP names extract byte-for-byte. |
| Rescan / replace | `PageReplacementTests`, `LibraryWorkflowTests` | Replacing keeps ID, sort key and position, bumps the revision and returns the previous content; reversing restores it exactly. **A replaced original survives permanently deleting another item and is swept only after the next launch's purge.** Missing pages and missing originals fail without changes. **A rescan with extra pages is one transaction: if an extra page fails to insert, nothing changes; revert/reapply restore it whole.** Model: a password-protected replacement file asks again after a wrong password, then replaces; a locked PDF added after a page lands right there once unlocked. Workflow: rescanning page 2 of 3 with a 2-page capture puts the extra page after it, keeps the grayscale filter and resets the rotation; undo/redo; relaunch; export order. |
| Settings / backup | `StorageUsageTests`, `LibraryBackupTests`, `AppUITests` | Live document/page counts exclude Recently Deleted and deleted pages; space used includes originals. The backup is one valid ZIP with a PDF per document under unique, sanitized names; edits (rotation) are kept; empty documents are skipped; nothing to export is an error; **cancelling leaves no files**. UI test: open Settings from the overflow menu, run the backup, close. |
| Crop | `CropMappingTests`, `CropFrameTests`, `LibraryWorkflowTests`, `RenderTests`, `PDFExportTests`, `AppUITests` | Crop ↔ editor rectangle round-trips for every rotation. Source top-left maps to top-right after a clockwise turn. A rectangle drawn on an upside-down page selects the right source half. Drag math: corners beat edges, edges clamp to the page, edges can't cross or go below the 5% minimum, moving keeps the size. **A crop of a rotated page is undoable/redoable, re-applying the same crop isn't a new edit, and it survives relaunch and exports at the cropped size, landscape, with the marker top-right.** **Found in review and fixed:** a filtered PDF page with a tight (25%) crop failed to render at 3072 px and to export to Letter/A4 (`outputTooLarge`), because the whole page was rasterized at the crop's resolution. Only the crop region is rasterized now; tests cover both paths. |
| Localization | `LocalizationTests` | Every key used exists in en/fr/es. Identical key sets and format arguments. No unused keys. Plurals (French 0/1 singular). French typography. |
| Workflow (view models) | `LibraryWorkflowTests` | **M1 gate on the Mac import path:** import PDF, EXIF photo, locked PDF (wrong password, then right) and an unsupported file. Rotate, move, delete, **undo and redo** (delete and rotate round trips). Drop the session (quit), reopen, then export: order, rotation and text preserved. Recently Deleted flow. Search. Newer-library message. |

### Simulator verified (iPhone, screenshots only)

Device: a dedicated "PaperNest iPhone Duo" simulator (iOS 27.1). It was recreated on 2026-10-21 after all iOS 27.1 simulators disappeared from the machine for reasons outside this session. It's the only device type the installed iOS 27.1 runtime supports, so **no iPad simulator was available** and the iPad layout is not verified. The library was seeded from `Samples/` with `papernest-seed` (the real importer). Screens were opened with debug-only launch arguments (`-PaperNestDebugOpenItem`, `-PaperNestDebugShowExport`) and captured with `xcrun simctl io … screenshot --display=primary`. **No taps or gestures were exercised.** Screenshots are in `docs/screenshots/`.

| Screen | Result |
|---|---|
| Empty library (en) | Correct title, search field, empty-state message, Import button. Scan is disabled because the Simulator has no document camera (intended fallback). |
| Library grid (en, fr) | All six samples render. The EXIF-6 photo is upright, the transparent PNG shows ink on white, and the protected PDF shows its unlocked content. "1 page · Oct 20, 2026" / "1 page · 20 oct. 2026". |
| Document (en, es) | **Found and fixed:** the page strip took half the iPhone width and the actions were hidden in an overflow menu. iPhone now shows the page full width, a thumbnail scroller, and the actions in the bottom toolbar. |
| Export sheet (en, fr, es) | **Found and fixed:** a 440-pt minimum width clipped the sheet on iPhone, and the option values truncated in French and Spanish ("Toutes…pages", "Tamañ…original"). It now uses inline option rows on iOS; the Mac keeps pop-up menus. |
| Crop editor (en, fr) | Opens over the uncropped page with a dimmed outside, frame, thirds guide and corner handles, Reset disabled at full crop. **Found and fixed:** the white frame and handles were invisible over white paper; they now have dark underlays. Checked with a page cropped by `papernest-seed --crop`. The drag is exercised by `AppUITests` (see above). |
| Cropped page in the document view | The app renders the seeded crop correctly: the marker and the rule are at the expected positions. |
| Launch log | **Found and fixed:** ⌘E for Export clashed with the system "Use Selection for Find" shortcut. Export is now ⇧⌘E. |

### Not covered by automated tests yet

- SwiftUI interaction beyond the crop editor. `PaperNest-iOSUITests` covers only crop so far, and the Mac has no UI tests.
- iPad layout (no compatible simulator runtime) and real devices
- Performance at 1/20/100 pages (no measurements taken; no numbers are claimed)
- Storage-full and low-memory behavior

## Open issue: an unexplained navigation glitch on iPhone (2026-10-21)

The first tap on a library thumbnail after launching on the owner's iPhone 17 Pro simulator (iOS 26.5) switched the scope to Favorites instead of opening the document. After that, Back → All Documents left navigation stuck. Root cause not identified. It could not be reproduced in three later attempts with the same sequence, or by the UI test.
- **Change made:** the sidebar selection is now optional (`LibraryModel.sidebarSelection`), as NavigationSplitView expects on iPhone, where it clears the selection when the user goes back. Unit test added.
- **Not proven to fix the glitch:** the UI smoke test passes with both the old and new binding.
- **If it recurs:** capture the exact tap timing (it happened right after a fresh install and launch) and check whether the sidebar list is hit-testable under the pushed library.

Also found by tapping and fixed: the crop sheet's title was black on the dark canvas. The sheet now uses dark appearance on iOS.

## Open issue: one unexplained crash in a test run

During session 1, one full test run ended with **SIGSEGV** (report: `~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-10-20-195924.ips`).
- It happened on an intermediate build with the redo and permanent-delete bugs still present, plus a temporary stub.
- The faulting frame is attributed to `LibraryStore` code, called from `PDFImportTests.typeComesFromContentNotExtension`. At that moment two other test threads were inside `PDFDocument.init` (PDFKit).
- The fault address points to a freed or corrupted pointer (a possible pointer-authentication failure).
- The root cause is **not identified**. It did not recur in 11 consecutive Command Line Tools runs of the final code, 4 Thread Sanitizer runs and 1 Address Sanitizer run under Xcode, none of which reported anything. That's good evidence but not proof.
- Under Xcode, each test target runs in its own process, so the cross-target concurrency of the crashing run (Store and Import tests together) is no longer exercised. If it recurs, serialize PDFKit use first (the importer and the test fixtures).

## Manual checklist

| Check | Platform | Status |
|---|---|---|
| Library window: sidebar scopes, empty states, grid thumbnails, search field | Mac | **Not run**: the owner declined Claude's control of the app |
| File > Import (⌘O) with `Samples/*`; drag files from Finder; paste a screenshot | Mac | Not run |
| Password prompt with `Samples/password-protected.pdf` (password `sample`) | Mac | Not run (covered in automated tests at the model layer) |
| Document view: page strip reorder by drag, rotate (⌘L/⌘R), filters, adjustments popover, undo/redo via Edit menu | Mac | Not run |
| Crop: Page > Crop… (⌘K), drag corners/edges/inside, Reset, Done, then undo/redo, export | Mac | Not run (on iPhone, the corner drag → Done → saved path is covered by `AppUITests`) |
| Export sheet: each format, page ranges, save panel, share menu, file opens in Preview | Mac | Not run |
| French and Spanish UI (`-AppleLanguages "(fr)"`): no truncation in sidebar, toolbar, export sheet | Mac | Not run |
| VoiceOver: grid cells read name + page count; page thumbnails read "Page n of m" | Mac | Not run |
| Sandboxed build (`--sandbox`): import via panel and drop, export via save panel | Mac | Not run |
| Tap through on iPhone: open a document, rotate, filter, Pages sheet reorder, export and save | iPhone (Simulator) | Not run: no taps were exercised |
| iPad split layout, keyboard shortcuts | iPad | **Blocked**: the installed runtime has no iPad simulator; needs an iPad runtime or device |
| Physical camera capture: multi-page scan, cancel, permission denied; Scan Pages and Rescan Page | iPhone | **Blocked**: needs a device and signing (team ID) |
| Replace Page with File… end to end (pick a file, page replaced, undo) | iPhone Simulator, Mac | **iPhone Simulator: passed** (see above; undo covered by tests only). **Mac: not run** (Page > Replace Page with File…) |
| Apple Pencil feel | iPad | Not applicable until M3 |
| Two-device iCloud sync | iPhone + iPad/Mac | Not applicable until M2 |
| Exported PDF/JPEG/PNG/ZIP open in Preview, Acrobat, Files | All | Automated structural checks passed. Not opened in external apps. |

## Performance log

No measurements yet. Record device, OS, document size (1/20/100 pages), elapsed time, peak memory and responsiveness notes here when they're taken.
