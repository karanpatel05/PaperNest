# Unified Home, Scan and Notes Studio implementation plan

**Goal:** Apply the owner's November 4 screenshots to the existing SwiftUI application.
**Architecture:** Reuse LibraryModel, DocumentModel, SQLite, immutable assets and PageGeometry. Reuse VisionKit capture and the existing document editor for scan review. Custom notebook tools drive PencilKit and the existing Mac canvas.
**Execution:** In place, explicitly requested by owner; no alternate workspace or app. Preserve existing dirty changes. No commits requested.

## Tasks
- [x] Extend Theme with lavender semantic surfaces and accessible dark variants.
- [x] Replace Home quick actions with greeting/search, Recent/Favorites/Shared, real content and collections, and honest local-storage status. Keep rename/move/delete/export paths.
- [x] Make Notes and Documents navigation filter real item kinds; keep scan/import/create reachable. Vault separately planned per owner's reply.
- [x] Route successful scan imports into the durable existing editor; refine page strip and floating editing tools. Preserve VisionKit controls and permissions.
- [x] Add custom notebook tool selection and floating history/color/width controls; connect iOS and Mac tools without changing persisted ink representation.
- [x] Build Mac/iOS, run units and focused UI flows, review diffs and document actual results and remaining capabilities.

## Constraints and review focus
No migration or fabricated cloud/shared/folder data. Strings localized en/fr/es. Empty libraries, favorites beyond the recent slice, long labels/accessibility text, background save, and page-switch ink must remain safe. Native camera remains until a replacement can match permission/interruption and perspective behavior. Do not expose identical fake scan modes or lossy brush types. Vault, sync, audio/AI/study and advanced brushes require separately scoped implementation.

## Ledger
Audit: existing code supplies PDF OCR/text-layer export, blank/lined/grid notebooks, ink and object persistence, page history, crop/filter/contrast, text/image editing. No connected account/sync, shared service or Vault. Existing modifications preserved. Owner requests separate secure Vault project.

Review: independent read-only review caught a stale document path when choosing sidebar Notes; fixed by clearing the path. A proposed Home-import issue was retracted because currentFolderID already guards nil selection. Follow-up static review found no additional important issues.
Validation discovery: initial ink test queried the wrong AX type; corrected using observed ScrollView hierarchy. Later tool-row expansion hid the canvas after adding directly accessible additional tools; bounded the Divider height and added a usable-canvas-height assertion. Largest-text screenshot found fragmented brand and oversized tabs; stacked brand/controls/filters and accessibility navigation menu address it. These findings required runtime/visual checking beyond compilation.

Additional runtime findings: iPad settings Form needed an explicit scrollable popover height. Wide Home recent navigation must push into the existing detail stack without changing split selection; the added reopen assertion exercises this route after process relaunch.

Validation: 647 unit tests passed; Mac/iOS builds passed; focused iPhone and iPad navigation/locale/ink checks passed after the documented fixes. Physical camera/Pencil, VoiceOver and native Mac interactions remain unrun. Full requested feature parity remains explicitly incomplete in `docs/UNIFIED_STUDIO_REDESIGN.md`.
