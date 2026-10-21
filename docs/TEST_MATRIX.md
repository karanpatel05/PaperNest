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
| `./scripts/test.sh` (Xcode 27.1) | **Passed: 87 tests** (run as 5 per-target processes: 13 + 16 + 20 + 29 + 9), 0 failures, 0 warnings |
| `./scripts/test.sh --sanitize=thread` (Xcode) | **Passed, 4 runs, 0 ThreadSanitizer reports.** `libclang_rt.tsan_osx_dynamic.dylib` confirmed linked into the test bundles with `otool -L`. |
| `./scripts/test.sh --sanitize=address` (Xcode) | **Passed, 1 run, 0 AddressSanitizer reports.** `libclang_rt.asan_osx_dynamic.dylib` confirmed linked. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **Passed**, 0 errors, 0 warnings. This was the first iOS compile of the shared code, including the VisionKit camera wrapper. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` | **Passed**, 0 errors, 0 warnings |
| `xcodegen generate` (XcodeGen 2.46.0) | **Passed**: `PaperNest.xcodeproj` with the `PaperNest-iOS` and `PaperNest-macOS` targets |
| `xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'generic/platform=iOS Simulator' build` | **Passed**, 0 compiler warnings. The bundle has ID `com.example.papernest`, MinimumOSVersion 17.0, UIDeviceFamily 1,2, the en/fr/es lproj folders, `PrivacyInfo.xcprivacy` and the UI resource bundle. |
| `xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-macOS -destination 'platform=macOS' build` | **Passed**, 0 compiler warnings. Same bundle ID, LSMinimumSystemVersion 14.0, sandbox and user-selected-file entitlements, `codesign --verify --strict` OK. |
| `./scripts/build-ios-sim-app.sh` | **Passed**: Simulator `PaperNest.app` (ad-hoc signed) installed and launched on the simulator |
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
| Localization | `LocalizationTests` | Every key used exists in en/fr/es. Identical key sets and format arguments. No unused keys. Plurals (French 0/1 singular). French typography. |
| Workflow (view models) | `LibraryWorkflowTests` | **M1 gate on the Mac import path:** import PDF, EXIF photo, locked PDF (wrong password, then right) and an unsupported file. Rotate, move, delete, **undo and redo** (delete and rotate round trips). Drop the session (quit), reopen, then export: order, rotation and text preserved. Recently Deleted flow. Search. Newer-library message. |

### Simulator verified (iPhone, screenshots only)

Device: a dedicated "PaperNest iPhone Duo" simulator (iOS 27.1). It's the only device type the installed iOS 27.1 runtime supports, so **no iPad simulator was available** and the iPad layout is not verified. The library was seeded from `Samples/` with `papernest-seed` (the real importer). Screens were opened with debug-only launch arguments (`-PaperNestDebugOpenItem`, `-PaperNestDebugShowExport`) and captured with `xcrun simctl io … screenshot --display=primary`. **No taps or gestures were exercised.** Screenshots are in `docs/screenshots/`.

| Screen | Result |
|---|---|
| Empty library (en) | Correct title, search field, empty-state message, Import button. Scan is disabled because the Simulator has no document camera (intended fallback). |
| Library grid (en, fr) | All six samples render. The EXIF-6 photo is upright, the transparent PNG shows ink on white, and the protected PDF shows its unlocked content. "1 page · Oct 20, 2026" / "1 page · 20 oct. 2026". |
| Document (en, es) | **Found and fixed:** the page strip took half the iPhone width and the actions were hidden in an overflow menu. iPhone now shows the page full width, a thumbnail scroller, and the actions in the bottom toolbar. |
| Export sheet (en, fr, es) | **Found and fixed:** a 440-pt minimum width clipped the sheet on iPhone, and the option values truncated in French and Spanish ("Toutes…pages", "Tamañ…original"). It now uses inline option rows on iOS; the Mac keeps pop-up menus. |
| Launch log | **Found and fixed:** ⌘E for Export clashed with the system "Use Selection for Find" shortcut. Export is now ⇧⌘E. |

### Not covered by automated tests yet

- SwiftUI interaction (taps, drags, menus) on any platform. There's no UI-test target yet.
- iPad layout (no compatible simulator runtime) and real devices
- Performance at 1/20/100 pages (no measurements taken; no numbers are claimed)
- Storage-full and low-memory behavior

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
| Export sheet: each format, page ranges, save panel, share menu, file opens in Preview | Mac | Not run |
| French and Spanish UI (`-AppleLanguages "(fr)"`): no truncation in sidebar, toolbar, export sheet | Mac | Not run |
| VoiceOver: grid cells read name + page count; page thumbnails read "Page n of m" | Mac | Not run |
| Sandboxed build (`--sandbox`): import via panel and drop, export via save panel | Mac | Not run |
| Tap through on iPhone: open a document, rotate, filter, Pages sheet reorder, export and save | iPhone (Simulator) | Not run: no taps were exercised |
| iPad split layout, keyboard shortcuts | iPad | **Blocked**: the installed runtime has no iPad simulator; needs an iPad runtime or device |
| Physical camera capture: multi-page scan, cancel, permission denied | iPhone | **Blocked**: needs a device and signing (team ID) |
| Apple Pencil feel | iPad | Not applicable until M3 |
| Two-device iCloud sync | iPhone + iPad/Mac | Not applicable until M2 |
| Exported PDF/JPEG/PNG/ZIP open in Preview, Acrobat, Files | All | Automated structural checks passed. Not opened in external apps. |

## Performance log

No measurements yet. Record device, OS, document size (1/20/100 pages), elapsed time, peak memory and responsiveness notes here when they're taken.
