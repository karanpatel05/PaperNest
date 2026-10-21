# Session handoff

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

"PaperNest iPhone Duo", UDID `AF21A6E2-14AE-4E73-AE95-B016FBC54A5B` (iOS 27.1), created for this project. Its library is seeded with `Samples/`. Delete it with `xcrun simctl delete AF21A6E2-14AE-4E73-AE95-B016FBC54A5B` when it's no longer needed. The device has two displays; screenshot with `--display=primary`.

### Next commands

```bash
git log --oneline | head                     # initial commit on main
./scripts/test.sh                            # expect 87 tests passing (5 per-target runs under Xcode)
xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build
./scripts/build-ios-sim-app.sh               # prints the app path; then: xcrun simctl install AF21A6E2-14AE-4E73-AE95-B016FBC54A5B <path>
./scripts/run-mac-app.sh /tmp/pn-dev         # dev Mac app with a seeded throwaway library
```

### Next work, in order

1. Crop UI: a draggable crop rectangle stored as `PageTransform.crop`. Model, render and export already support crop, with tests.
2. Rescan a page (iOS), then a real-device camera test. That completes the M1 gate.
3. Exercise taps in the Simulator: the Pages sheet reorder, filters, the adjustments sheet, export and save.
4. Polish: on iOS, inline option rows show their label as a plain row; consider section headers.
5. Start M2: the v3 migration (`sync_state`, `outbox`, `tombstones`), then the CKSyncEngine adapter.

### Open risk

- One unexplained SIGSEGV in one test run, on an intermediate build (TEST_MATRIX.md, "Open issue"). Not reproduced in 11 later runs or under the sanitizers.

### Notes for whoever continues

- SwiftUI's `LibraryItem` type clashes with ours; write `PaperNestCore.LibraryItem` in SwiftUI files.
- PDFKit `dataRepresentation()` of an unlocked encrypted PDF stays encrypted. The importer copies the pages into a new document instead (see `PDFInspector`).
- ImageIO happily decodes truncated JPEG/PNG files, which is why the importer checks their structure itself.
- Under Xcode 27, `swift test` runs each test target in its own process and code-signs the bundles.
