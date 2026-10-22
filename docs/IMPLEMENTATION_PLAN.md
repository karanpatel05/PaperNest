# Implementation plan

Status labels: **Implemented** (code exists), **Automated tests passed**, **Simulator verified**, **Device verified**, **Blocked**, **Not started**. "Implemented" alone means unverified.

Last updated: 2026-10-20 (session 1).

## Milestone status

| Milestone | Gate | Status |
|---|---|---|
| M0 Foundation | Targets and modules exist, the adaptive shell is localized, every buildable target builds, a persistence round-trip test passes, build instructions are reproducible | **Met.** The Xcode project generated from `project.yml` (XcodeGen 2.46.0) builds `PaperNest-iOS` (Simulator) and `PaperNest-macOS` with 0 compiler warnings. Shared code also builds for iOS devices. Signed device builds wait on a development team. |
| M1 Local scan/import → export | A real scan can be saved, the app restarted, and the document reopened and exported without losing pages or orientation. Mac import is tested separately from mobile capture. | **Partly met.** The Mac import path passes the restart/reopen/export gate in automated tests (`LibraryWorkflowTests`). The iPhone library, document and export screens are Simulator verified (screenshots, no taps). Real camera capture is **Blocked** (needs a device and signing). Crop UI and rescan remain. The Mac UI has not been visually verified. |
| M2 Cross-device sync | A scan created on iPhone appears correctly on another device, survives relaunch, and conflicting edits are preserved | Not started (design in ARCHITECTURE.md). Needs an Apple Developer team and an iCloud container. |
| M3 Editable notebooks | Save/reopen/sync/export keeps stroke appearance, position, page order and text edits | Model and persistence for ink, text and images exist and are tested. Editor not started. |
| M4 OCR and remaining exports | en/fr/es fixtures produce correct output. PDF text alignment and DOCX structure are verified. | Not started. The recognition model, table and FTS index exist. Vision lists en-US, fr-FR and es-ES as supported (checked on macOS 26.6.2). |
| M5 Subscriptions | Local StoreKit/sandbox scenarios show correct entitlement behavior. Documents stay readable and exportable after expiry. | Not started (design in ARCHITECTURE.md). StoreKit configuration testing needs Xcode. |
| M6 Release hardening | Localization, accessibility, performance, storage pressure, privacy and release docs | Not started. The privacy manifest is drafted. |

## M0: Foundation

- [x] Inspected the environment: macOS 26.6.2, CLT 26.2 / Swift 6.2.3, no Xcode at the start. Xcode 27.1 appeared mid-session with its license not accepted.
- [x] Recorded architecture, storage/sync and platform decisions (ARCHITECTURE.md)
- [x] Swift package with Core/Store/Import/Render/Export/UI modules, test targets and a synthetic-fixture support target
- [x] Versioned SQLite schema (now v2) with migrations and refusal of newer schemas. Round-trip, interrupted-write, rollback and v1→v2 migration tests pass.
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
- [x] iOS: VisionKit document camera wrapper, Scan button, unsupported-device fallback, camera usage strings (en/fr/es). **Not compiled.**

Remaining (in order):
1. **Visual check of the Mac UI.** The owner declined Claude's control of the app, so the owner should run the manual checklist in TEST_MATRIX.md. The iPhone screens were checked in the Simulator, which led to fixes in the compact document layout, the export sheet and a shortcut clash.
2. **Crop UI: done on iPhone.** Automated tests cover the mapping (all rotations), the drag math, crop → undo/redo → relaunch → export, tight crops on filtered PDFs, and a Simulator UI test that drags a corner and checks the saved crop. Still open: a manual check of the Mac drag. VoiceOver users can reset a crop but not resize it (known limitation).
3. **Rescan a page: implemented** (2026-10-21). Replace in place, extra pages inserted after, look kept and geometry reset, undo/redo, v3 history so undo survives other deletions. Store and workflow tests pass. **Camera path: needs a device** (the Simulator has no document camera). **File path: verified in the Simulator** (replace in place, extras after, cancel is silent), after fixing replace-became-add and building the Simulator app from the Xcode project. Replace and insert are one transaction. **M3 note:** a rescanned page keeps its page objects (and transform history) in the old capture's source coordinates; when ink/text arrive, decide whether to keep, rescale or flag them on rescan.
4. Real-device camera capture for the M1 gate (needs signing). Simulator imports don't count as camera tests. Also: exercise taps in the Simulator (Pages sheet reorder, filters, export/save) and check iPad once an iPad runtime is installed.
5. Continuity Camera import on Mac (`ImportFromDevices` services menu), if feasible.
6. Adaptive black-and-white threshold for unevenly lit scans (the current Otsu threshold is global).
7. Folders UI (the model and store already exist and are tested).
8. ~~Settings screen~~ **done** (2026-10-21): storage, export-all backup, language, about; no login by design. Mac Settings window not yet viewed.

## Later milestones (summary)

- **M2:** CKSyncEngine adapter, v4 migration (`sync_state`, `outbox`, `tombstones`), asset upload/download with `remoteOnly` availability, conflict copies, account-change flow, sync status UI driven by real state. Two-device test plan in TEST_MATRIX.md.
- **M3:** notebook creation, templates (rendering exists), PencilKit adapter on iPad, mouse/trackpad ink on Mac, text boxes, image objects, the 3-notebook free limit hook.
- **M4:** Vision OCR (`VNRecognizeTextRequest`, automatic language detection plus user override), recognition status UI, search over OCR text and typed notes, searchable PDF (invisible text layer aligned through `PageGeometry`), TXT with page separators and empty-content warnings, a DOCX writer (both variants) validated by `unzip`/XML checks and opening in an external editor.
- **M5:** StoreKit 2 entitlement service, paywall with StoreKit-supplied prices, restore and manage, expiry behavior, local `.storekit` tests.
- **M6:** accessibility audit (VoiceOver, Dynamic Type, keyboard focus), 1/20/100-page performance runs with recorded numbers, storage-full handling, release docs.

## Known limitations (current code)

- Links, form fields and annotations inside imported PDFs may not survive export.
- Black & White uses a global threshold.
- Localization uses `.strings`/`.stringsdict`. Migrate to String Catalogs once Xcode tooling is available. French and Spanish need review by a native speaker.
- Page objects (ink and text) are stored as JSON. A compact binary encoding may be needed for very dense notebooks; measure in M3.
