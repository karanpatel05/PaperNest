# Approved redesign implementation — November 7, 2026

Implemented in the existing shared PaperNest checkout, with separate Home/library, editor and scanner agents and root integration. Existing persistence, immutable library assets, document operations and subscription authority remain in place. No database migration, replacement app, staging or commits.

## Changes

- Home and libraries: compact Scan/Import and Tools hierarchy, actual recent/favorite content, collection navigation, notebook cover grid, independent Notes/Documents layout preferences and no unsupported Shared/sync claims.
- Editor: multiple session-local document tabs; retained document model, text session, undo manager and zoom; close/quit protection for unsaved tool drafts; compact icon-only tools for PDFs and notebooks; hideable page thumbnails; default-visible hideable PDF inspector on iPad/Mac. Signature, forms and page management use the inspector; iPhone retains compact sheets. Compact pages fit the available width with vertical scrolling; inline text temporarily reclaims thumbnail/palette space while preserving the user’s thumbnail preference.
- Scanner: AVFoundation capture, Vision edge detection, automatic/manual capture, illumination control, Photos import, interruption/permission handling and native VisionKit fallback. Review supports multipage selection, crop corners/perspective correction, rotation, filters, automatic enhancement, zoom/pan, duplicate/reorder/delete, naming and the existing durable import/folder workflow.
- Supporting surfaces: real-product Pro plan cards, accountless Profile presentation and grouped Export styling. No invented prices, purchase states, account photos or sync information. Every new label is localized in English, French and Spanish.

## Principal files

Home/library: `LibraryHome.swift`, `LibraryView.swift`, `NotebookCover.swift`.

Editor: `DocumentWorkspace.swift`, `DocumentWindowClose.swift`, `DocumentView.swift`, `EditorToolNavigation.swift`, `SignatureSheet.swift`, `PDFFormSheet.swift`, `DocumentPagesSheet.swift`, `InlineTextSession.swift`, `InlineTextOverlay.swift`, `WindowTextEditGuard.swift`.

Scanner: `ScannerCamera.swift`, `ScannerCapturePolicy.swift`, `ScannerPage.swift`, `ScannerWorkspaceView.swift`, `ScannerCornerEditor.swift`, `ScannerZoomPreview.swift`.

Integration/support: `RootView.swift`, `SubscriptionViews.swift`, `ExportSheet.swift`, `Localization.swift`, en/fr/es resources, `project.yml` (scanner renderer test membership only). Tests include dedicated library, workspace, tabs, scanner renderer/capture policy and window draft guards.

## Verification

Actual commands, failed intermediate runs, fixes and final outcomes are recorded in `TEST_MATRIX.md`. Testing uses disposable synthetic libraries, never the owner's documents.

- Full package suite: 739 passed. After the last compact-only UI changes, the 215 UI unit tests passed again; other package modules were unchanged.
- macOS app and iOS Simulator targets build. Final Mac build and final iPhone six-test interaction run exited 0.
- iPad: Home/library routing, notebook creation/reopening, tabs, scanner review/save/reopen, PDF form filled-copy save/reopen, signature save/place/undo/redo/reopen, and editor notebook/PDF workflows passed. Editor PDF layouts exercised in English, French and Spanish.
- iPhone: Home/library routing, notebook creation/reopening, tabs, Profile/paywall and nonrepeating welcome passed. Final six-test run passed inline text with keyboard in French and Spanish accessibilityXXXL, notebook/PDF editor workflows in en/fr/es, and scanner review/edit/save/reopen. Scanner renderer tests: 4 passed.
- Native Mac disposable-library interaction: navigation, thumbnails, anchored Pen settings, signature drawing/save/place/history, retained tabs, close-warning cancellation, page duplicate/undo and Profile/paywall dismissal verified. Test app closed.
- Apple local StoreKit on iOS27: all3 tests passed (including both billing retry/grace cases). Verifies trial eligibility/purchase, cancellation, expiry/refund, pending approval and restoration. iOS26.5 could not initialize the test service; that failed run is recorded explicitly.

Retained real test screenshots are in `docs/screenshots/approved-2026-11-07/`.

## Remaining limitations and external setup

- Physical camera permissions, interrupted capture, rotation/edge alignment, automatic capture in varied lighting and physical Apple Pencil behavior need device verification. Simulator review/processing tests do not validate camera hardware.
- Scanner exposes supported document capture only. Book/ID/Whiteboard modes are not decorative substitutes. OCR and searchable-PDF export remain available through the existing document editor/export pipeline after import, not a new scanner-review OCR flow.
- Scanner editing is a transient capture draft. Saving imports the processed images; the original uncorrected camera capture is not a durable separately editable asset. Canceling review/destination discards that transient capture; there is no crash-recovery scan draft store.
- Tabs are window/session state, not a new persistence store. Closing a tab never deletes its saved document. Automatic restoration of the whole tab set after app restart is not implemented.
- App Store Connect must supply the real monthly/yearly product identifiers and configured seven-day introductory offer, plus valid privacy/terms/support URLs in the existing subscription configuration. The development build correctly withholds purchasing when those values/products are unavailable. No real subscription transaction was performed.
- Vault/cloud collaboration and full Goodnotes/Acrobat feature parity remain separate work; no unsupported features are advertised as completed. Full VoiceOver/contrast auditing and every hardware/window-size combination remain outside the executed checks.
