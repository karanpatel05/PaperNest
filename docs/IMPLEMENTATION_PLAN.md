# Implementation plan

Status labels: **Implemented** (code exists), **Automated tests passed**, **Simulator verified**, **Device verified**, **Blocked**, **Not started**. "Implemented" alone means unverified.

Last updated: 2026-10-25 (shape annotations; earlier milestone history retained).

## Milestone status

| Milestone | Gate | Status |
|---|---|---|
| M0 Foundation | Targets and modules exist, the adaptive shell is localized, every buildable target builds, a persistence round-trip test passes, build instructions are reproducible | **Met.** The Xcode project generated from `project.yml` (XcodeGen 2.46.0) builds `PaperNest-iOS` (Simulator) and `PaperNest-macOS` with 0 compiler warnings. Shared code also builds for iOS devices. Signed device builds wait on a development team. |
| M1 Local scan/import → export | A real scan can be saved, the app restarted, and the document reopened and exported without losing pages or orientation. Mac import is tested separately from mobile capture. | **Partly met.** Import/edit/reopen/export, crop and file-based rescan are automated and Simulator-tested. Representative native Mac library/document/export, Tools extraction, file preview/details/save and Settings checks passed on 2026-10-23. Real camera capture remains **Blocked** by device/signing. See TEST_MATRIX for unrun Mac checks. |
| M2 Cross-device sync | A scan created on iPhone appears correctly on another device, survives relaunch, and conflicting edits are preserved | Not started (design in ARCHITECTURE.md). Needs an Apple Developer team and an iCloud container. |
| M3 Editable notebooks | Save/reopen/sync/export keeps stroke appearance, position, page order and text edits | **Partly implemented.** iPad PencilKit ink, persistence, export and undo are tested. F3a recognized-line highlight/underline/strikethrough is unit-tested and verified on iPhone/iPad Simulators in en/fr/es; native Mac annotation interaction remains unrun. F3b colors and saved-mark selection/recolor/removal are implemented: 235 unit tests pass, iPhone/iPad preset-manager workflows pass in en/fr/es, and the existing iPad ink test passes. Native custom-picker interaction remains unrun. One-page notebook creation with blank/lined/grid paper now works through Tools (236 unit tests, iPhone/iPad creation/relaunch, Mac build verified). Additional blank/lined/grid A4 pages now support insertion after selection, selection after save, and guarded undo/redo. Private page comments support add/edit/delete and guarded undo/redo. Outlined rectangles/ellipses/lines/arrows now support preview placement and save as editable ink with undo and export; exported comments, planners and text/image editing remain. |
| M4 OCR and remaining exports | en/fr/es fixtures produce correct output. PDF text alignment and DOCX structure are verified. | **Partly implemented.** Vision en/fr/es recognition, full-text search and searchable PDF export are tested. Automatic recognition, language override, correction/status UI and TXT/DOCX remain. |
| M5 Subscriptions | Local StoreKit/sandbox scenarios show correct entitlement behavior. Documents stay readable and exportable after expiry. | Not started (design in ARCHITECTURE.md). Pricing/product setup and StoreKit implementation remain. |
| M6 Release hardening | Localization, accessibility, performance, storage pressure, privacy and release docs | Not started. The privacy manifest is drafted. |

## M0: Foundation

- [x] Inspected the environment: macOS 26.6.2, CLT 26.2 / Swift 6.2.3, no Xcode at the start. Xcode 27.1 appeared mid-session with its license not accepted.
- [x] Recorded architecture, storage/sync and platform decisions (ARCHITECTURE.md)
- [x] Swift package with Core/Store/Import/Render/Export/UI modules, test targets and a synthetic-fixture support target
- [x] Versioned SQLite schema (now v7; page comments) with migrations and refusal of newer schemas. Round-trip, interrupted-write, rollback and v1→v2 migration tests pass.
- [x] Localized adaptive shell (NavigationSplitView, en/fr/es) with a key-parity test
- [x] Native Mac app builds with CLT (`scripts/build-mac-app.sh`), launches and opens a library
- [x] `project.yml` (XcodeGen) for iOS and macOS targets, xcconfig signing placeholders, Info.plists, entitlements, privacy manifest
- [x] Xcode project generated (`xcodegen generate`). `PaperNest-iOS` (Simulator) and `PaperNest-macOS` build. The bundles contain the shared bundle ID, localizations, privacy manifest and (Mac) sandbox entitlements.
- [x] `PaperNestUI` builds for the iOS Simulator and device with 0 warnings. The iPhone app runs in the Simulator (`scripts/build-ios-sim-app.sh`).

## M1: Local scan/import → export

Done:
- [x] Import of PDF (vector), JPEG and PNG, with type sniffing, EXIF orientation, damaged/truncated/empty/unsupported detection, duplicate names, and password-protected and restricted PDFs
- [x] Persistent library: favorites, rename, Recently Deleted (30-day purge) with recover and permanent delete, title search
- [x] Page editing: rotate, filters (original, grayscale, black & white), brightness/contrast, revert, reorder, delete, add pages, undo/redo (redo bug found in review and fixed, with tests)
- [x] Export: PDF (original/Letter/A4, fit without cropping, vector pass-through, three quality levels), JPEG/PNG (dpi, quality), ZIP or separate files, progress and cancel, size shown
- [x] Mac: File > Import (⌘O), drag and drop, paste, Page menu shortcuts, save panel and share
- [x] iOS: VisionKit document camera wrapper, Scan button, unsupported-device fallback, camera usage strings (en/fr/es). **Compiled and Simulator fallback tested; camera capture still needs a real device.**

Remaining (in order):
1. **Mac audit partly complete (2026-10-23).** Native library/document/export, Tools extraction, file preview/details/save and Settings were exercised. Fixed an Export hang, hidden Tools Continue, malformed layout-picker label, and wrong file-copy extension. Remaining checks are listed in TEST_MATRIX; new annotation UI is built but not yet manually checked on Mac.
2. **Crop UI: done on iPhone.** Automated tests cover the mapping (all rotations), the drag math, crop → undo/redo → relaunch → export, tight crops on filtered PDFs, and a Simulator UI test that drags a corner and checks the saved crop. Still open: a manual check of the Mac drag. VoiceOver users can reset a crop but not resize it (known limitation).
3. **Rescan a page: implemented** (2026-10-21). Replace in place, extra pages inserted after, look kept and geometry reset, undo/redo, v3 history so undo survives other deletions. Store and workflow tests pass. **Camera path: needs a device** (the Simulator has no document camera). **File path: verified in the Simulator** (replace in place, extras after, cancel is silent), after fixing replace-became-add and building the Simulator app from the Xcode project. Replace and insert are one transaction. **M3 note:** a rescanned page keeps its page objects (and transform history) in the old capture's source coordinates; ink now exists; decide whether to keep, rescale or flag existing marks on rescan.
4. Real-device camera capture for the M1 gate (needs signing). Simulator imports don't count as camera tests. iPhone/iPad interaction coverage now exists; remaining flow-specific manual checks are in TEST_MATRIX.
5. Continuity Camera import on Mac (`ImportFromDevices` services menu), if feasible.
6. Adaptive black-and-white threshold for unevenly lit scans (the current Otsu threshold is global).
7. ~~Folders UI~~ **done**: create/rename/delete, move documents, counts, and iPhone interaction coverage.
8. ~~Settings screen~~ **done** (2026-10-21): storage, export-all backup, language, about; no login by design. Mac Settings window viewed on 2026-10-23; Mac backup interaction still pending.

## Later milestones (summary)

- **M2:** CKSyncEngine adapter, v7-or-later migration (`sync_state`, `outbox`, `tombstones`), asset upload/download with `remoteOnly` availability, conflict copies, account-change flow, sync status UI driven by real state. Two-device test plan in TEST_MATRIX.md.
- **M3:** notebook creation, templates (rendering exists), PencilKit adapter on iPad, mouse/trackpad ink on Mac, text boxes, image objects, the 3-notebook free limit hook. **First slice, owner request (2026-10-21): Apple Pencil on iPad** (ink rendering + export on all platforms, then the iPad PencilKit canvas). Spec: `CLEAN_NATIVE_DESIGN.md` → "Apple Pencil on iPad".
- **M4:** **First slice done 2026-10-22** — Vision `VNRecognizeTextRequest` for en/fr/es, boxes in upright uncropped source space, FTS search over recognized text, and a Recognize Text action in the document. **Searchable PDF landed the same day** (invisible text layer aligned through `PageGeometry`, `ExportOptions.includesRecognizedText`). Remaining: recognition status UI outside the menu, automatic recognition after a scan, a user language override, TXT with page separators and empty-content warnings, a DOCX writer (both variants) validated by `unzip`/XML checks and opening in an external editor.
- **M5:** StoreKit 2 entitlement service, paywall with StoreKit-supplied prices, restore and manage, expiry behavior, local `.storekit` tests.
- **M6:** accessibility audit (VoiceOver, Dynamic Type, keyboard focus), 1/20/100-page performance runs with recorded numbers, storage-full handling, release docs.

## Known limitations (current code)

- Links, form fields and annotations inside imported PDFs may not survive export.
- Black & White uses a global threshold.
- Localization uses `.strings`/`.stringsdict`. Migrate to String Catalogs once Xcode tooling is available. French and Spanish need review by a native speaker.
- Page objects (ink and text) are stored as JSON. A compact binary encoding may be needed for very dense notebooks; measure in M3.


## Owner-requested feature expansion (2026-10-21 / 22)

The nine reference screenshots extend the original brief. Full capability coverage and delivery order: [FEATURE_EXPANSION.md](FEATURE_EXPANSION.md). The brief itself is unchanged. A further ten reference screenshots (App Store listing, Tools/Files/Notes/Media/Browser/VPN screens, paywall) are inventoried screen by screen, with a 48-row capability checklist, in [REFERENCE_FEATURE_INVENTORY.md](REFERENCE_FEATURE_INVENTORY.md).

**Owner confirmation, 2026-10-23:** “All features to pipeline including media.” All identified converters, PDF tools, notes and supporting file/cloud/browser/photo/VPN features remain included. Media is explicitly planned as F7a local playback, F7b library/playlists/background/resume, F7c audio extraction/MP3 conversion and F7d editable timestamped transcription/export. FEATURE_EXPANSION holds the acceptance checks and dependencies. This adds no new implementation or test claim and does not reorder the active document work.

**F1 initial slice is implemented; unit-tested on macOS and UI-tested on iPhone and iPad (Claude, 2026-10-22: 144 unit tests, 11 iPhone UI tests, the two document-tools tests on iPad, 0-warning Mac and iOS builds, en/fr/es screenshots inspected on both devices). Representative Mac screens and Tools extraction have now been exercised (2026-10-23) — see TEST_MATRIX:** select multiple documents, batch move/delete/label/duplicate, explicit-order merge, page extraction into new editable documents, and seven persistent color labels. See [the implementation checklist](superpowers/plans/2026-10-21-file-tools.md). Schema v4 is allocated to labels; future sync must use the next unused migration. **F1 is complete** as scoped: per-page splitting and selection-wide ZIP export both landed on 2026-10-22 (see TEST_MATRIX). Explicit compression presets with before/after sizes were never part of F1 and remain F2/F4. F2 is partly implemented (general file items, previews/details, ZIP extraction/creation and Photos/HEIC import); F3a text markup and F3b saved-mark controls are unit-tested and Simulator-verified on iPhone/iPad in en/fr/es; remaining native Mac checks are documented. F4 OCR/search/searchable PDF is implemented. F5–F9 remain planned; see FEATURE_EXPANSION and the current handoff.
