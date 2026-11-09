# Approved PaperNest redesign implementation plan

> **For agentic workers:** Use superpowers:subagent-driven-development. Owner authorized phased implementation with multiple agents on November 7.

**Goal:** Implement the approved reference-driven Home, library, editor, scanner and supporting surfaces in the existing app.
**Architecture:** Keep LibraryStore, DocumentModel, PageGeometry, StoreKit and all existing durable operations. View composition and session-local document tabs sit above existing models. Existing dirty work is the baseline, never reset or stage it.
**Tech Stack:** Swift 6, SwiftUI, PencilKit, Vision, AVFoundation, PDFKit, StoreKit.
**Spec:** Owner's Cross-Platform Showcase and docs/design/approved-2026-11-07/{studio-board,library-board}.png, plus CLEAN_NATIVE_DESIGN. Images are layout references: illustrative counts, document content and price placeholders never enter production.

## Global constraints
- Same checkout; no new workspace/app, no commits without scoped ownership. No changes to CLAUDE_CODE_PROMPT.md.
- Native adaptive lavender tokens and exact project logo. Preserve localized accessibility identifiers.
- English/French/Spanish L10n; root coordinates shared localization writes.
- No fake sync, purchases, accounts, OCR or capability tiles. Vault remains deferred.
- Scanner custom capture must preserve native fallback and never claim real-device verification from simulator tests.
- Only root runs shared builds/tests; workers request checks and supply new tests. Root records actual results.

## Review focus
- Switching/closing tabs while inline text has pending edits must not lose text.
- Notebook and scan routing must remain distinct; no duplicates of brand/Home heading.
- Compact widths, accessibility text and long French/Spanish labels must remain usable.
- Scanner permission/interruption/cancel/empty capture must retain existing files and not import partial failures silently.
- Existing PDF/notes editing, Pro guards, undo and export paths remain authoritative.

### Task 1: Home and libraries
Files: LibraryHome.swift, LibraryView.swift (except ImportPresentation modifier), new notebook cover components; dedicated Home/library UI tests.
- [x] Inspect existing behavior and approved board.
- [x] Implement compact reference layout, tools between Scan/Import and Recent, notebook cover grid, document rows and folder navigation using actual data.
- [x] Preserve actions, context menus and accessibility; add interaction regression coverage.
- [x] Root builds/tests and independent review.

### Task 2: Editor workspace and controls
Files: DocumentView.swift, new editor-only components, SignatureSheet.swift, PDFFormSheet.swift, DocumentPagesSheet.swift; dedicated editor UI tests. Root owns RootView/tabs.
- [x] Audit toolbar, thumbnails and sheets before edits.
- [x] Implement compact icon-only toolbar for PDFs AND notebooks, hideable thumbnails, bottom floating palette, context settings, default-visible right inspector.
- [x] Move signature/form/page tool content into right inspector on Mac/iPad while retaining iPhone sheets and existing operations/guards. Avoid duplicate dismiss behavior and preserve error state.
- [x] Add focused regression tests and request builds/review.

### Task 3: Scanner capture and review
Files: DocumentCameraView.swift, new scanner files, dedicated scanner tests. Do not edit LibraryView; report integration API to root.
- [x] Audit native capture, durable import and image processing.
- [x] Implement full-screen custom capture with AVFoundation preview, permissions/interruption handling, shutter, flash, import, document detection, multipage review; retain native scanner fallback.
- [x] Implement scan review with top thumbnails, selected page, rotate/filter/crop using supported processing, name and save via existing .scanned outcome. Avoid unsupported pretend modes.
- [x] Provide integration and meaningful tests; clearly report physical-device checks remaining.

### Task 4: Session document tabs and supporting surfaces
Files: RootView.swift, new DocumentWorkspace.swift/session tab model, Theme.swift if needed, SubscriptionViews.swift, ExportSheet.swift, shared localization.
- [x] Add multiple open notebook/PDF tabs, independent retained DocumentView state, close/select/reopen without duplicating models or losing inline edits.
- [x] Restyle Profile/Pro and Export using existing product data, state and actions.
- [x] Integrate scanner into existing capture presentation and preserve current save/location workflow.
- [x] Add tab state/interaction tests; build Mac/iOS and run relevant unit/UI regressions.

### Task 5: Integration verification and review
- [x] Review scoped diffs against pre-task snapshots and approved references.
- [x] Run unit suite, Mac and iOS builds, representative UI workflows and layout inspections.
- [x] Fix failures, record exact outcomes/unrun device checks in TEST_MATRIX, release claims.
