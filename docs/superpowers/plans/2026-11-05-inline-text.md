# Inline Text Editing Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development or executing-plans. Work inside the existing shared checkout; no commits/staging because the tree contains other owners’ unfinished work.

**Goal:** Implement the owner’s 2026-11-05 request: place, type and format text directly on paper, with no text-entry modal.
**Architecture:** Reuse TextBox JSON objects, guarded LibraryStore writes, DocumentModel history and PageGeometry. Native UITextView/NSTextView owns caret and selection; a transient editor draft owns unsaved edits and serialized autosave. A floating SwiftUI toolbar acts on that draft, with move/resize restricted to explicit handles. Exclude the selected text object from the backing page render to avoid ghost text.
**Tech Stack:** Swift 6, SwiftUI, UIKit/AppKit, CoreText, SQLite.
**Spec:** Owner request in this chat; docs/CLEAN_NATIVE_DESIGN.md.

## Constraints and review focus
- Preserve old JSON without migration; default font Helvetica, regular, nonitalic.
- Text caret survives toolbar actions and IME composition; typing never starts object dragging.
- Geometry maps source to page to viewport, including crop/quarter-turn and zoom.
- Failed writes retain draft and prevent silent dismissal; serialize autosaves and flush on exit/background.
- Floating controls stay within visible page intersection; keyboard changes must not shrink the underlying paper and relocate the editing target.
- English/French/Spanish via L10n, accessible controls and resize/move alternatives.

## Tasks
- [x] 1. Add tests for legacy decoding, style roundtrip, guarded updates and rendered/exported font traits. Add TextBox.FontFamily (sans/serif/monospaced), isBold/isItalic and postScriptFontName, defaulted backward-compatible decoding. Extend placeText/updateText parameters with defaults. Add renderer excludingObjectIDs default empty to bitmap/thumbnail/layers. Preserve text whitespace for inline writes through an explicit option, without changing old call behavior.
- [x] 2. Add DocumentModel.saveInlineText(_:replacing:on:undoManager:) -> PageObject using existing guarded mutations and history; delete empty existing text explicitly through a guarded path. Tests pin creation/update/frame/style/undo and conflict behavior.
- [x] 3. Add InlineTextSession and native editor view. Draft selection, caret focus, debounced serialized save and retry. Add page placement overlay and floating toolbar (font, size, color, bold, italic, alignment, delete, overflow with move/resize controls). Transform editor with PageGeometry; restrict dragging to controls. Remove text modal entry points and keep image overlay behavior. Center main icon tools, horizontal scrolling at narrow widths.
- [x] 4. Add/update iOS interaction tests for tap placement/immediate typing, formatting, deselection, existing-text selection, movement/resize, undo/redo and relaunch; save-failure tests and geometry unit coverage. Build Mac and iOS, run unit suite and native Mac disposable-library checks. Record actual outcomes and unrun limitations in TEST_MATRIX; release claims.

## Execution record
- Existing text model lacks font traits; additive default-decoded fields are required for requested export fidelity. Formatting applies to the entire text box (existing model has uniform styling), preserving caret range.

- Owner follow-up: More belongs directly beside Text Box on all platforms; shared dropdown retains existing PDF editing/page-management actions.


## File map

`Sources/PaperNestUI/InlineTextSession.swift`, `InlineNativeTextView.swift`, `InlineTextOverlay.swift`, `WindowTextEditGuard.swift`; integration in `DocumentView.swift`, `DocumentModel.swift`, `RootView.swift`, `AppEnvironment.swift`, `PaperNestCommands.swift`, `NotebookPageSheet.swift`, `MovableMarksOverlay.swift`, `PageImageView.swift`, `ThumbnailCache.swift` and `Apps/Mac/Sources/PaperNestMacApp.swift`. Additive model/storage/render support in `Sources/PaperNestCore/PageObjects.swift`, `Sources/PaperNestStore/TextBoxes.swift`, `Sources/PaperNestRender/PageRenderer.swift`. L10n/en/fr/es, AppUITests and focused InlineTextStyle/Store/Session/Workflow, TextBoxRender/Export tests. Existing text-sheet type remains defined for compatibility, but editor creation/editing no longer presents it.


Final review added explicit failed-draft recovery: Retry, Save as New Text Box (preserves the conflicting object), Copy Draft Text and confirmed Discard Unsaved Changes. Recovery remains reachable in a top banner if another window removes the selected page. Session tests cover pending-write coordination, copy-only undo/redo, retained drafts on missing pages and nonmutating discard. Discard waits for already-started writes; it cannot undo an earlier successful commit.

Viewport correction: the page-frame preference remained at zero on iPhone while the keyboard scrolled the actual page. Replaced it with direct geometry observation in global coordinates, translating the actual safe content viewport into page-local space. GeometryReader already excludes toolbars/keyboard; subtracting ancestor safe-area insets again incorrectly emptied the viewport. A UI assertion guards recovery controls below the main toolbar.

Owner follow-up during verification: improve unreliable lasso selection. Preserve native PencilKit drawing/selection on unchanged and pending model refreshes; avoid redundant tool assignments. Mac accepts loop-boundary ink, three-view-point tolerance and clicking one stroke, while preserving whole-stroke scope and PageGeometry. Validate with actual iOS canvas tests, Mac geometry tests, native movement/history and reopen flows. Files: InkCanvas.swift, MacInkCanvas.swift, focused coordinator/Mac tests, AppUITests, localized help and a Canvas test scheme in project.yml. This follow-up is separately tracked in TEST_MATRIX.

## Mixed-content lasso clarification

Owner clarified that one selection must include handwriting, text boxes and images, and that notebooks should open with Lasso active. Shared `PageSelectionGeometry.swift` and `PageSelectionOverlay.swift` now own freehand/rectangle/tap selection, Select All, a small contextual selection toolbar and atomic group movement. `DocumentView.swift` defaults loaded notebooks to Lasso, retains PDF default mode and opens existing inline text/image controls from selection. Localized settings replace the old ink-only explanation.

`DocumentModel.moveSelection` and the optional `InkEditStore.applyInkChanges(expectedPage:)` guard preserve all selected objects or reject the whole stale gesture. `PageRenderer.renderSelection` renders transparent preview layers with existing geometry; originals and stored objects remain intact. `PageSelectionGeometryTests`, `MixedSelectionWorkflowTests`, `SelectionRenderTests` and AppUITests cover geometry, clipping, atomic movement/history, rendering and real mixed-content gestures/relaunch. Review fixed click-induced crop snapping and late-preview duplication. Main file map additionally includes InkEditStore, PageRenderer, project.yml UI-test Core/Store dependencies and synthetic fixture source. See TEST_MATRIX for real outcomes and remaining limits.

Freehand follow-up: preserve the actual drawn loop after release rather than replacing it with rectangular bounds. `PageSelectionContour` stores relative source-space vertices; selection drawing and movement hit testing use the same contour. Tests distinguish concave loops from their enclosing rectangles and cover movement/Undo/zoom/rotation. Rectangle and Select All remain explicit alternatives. See the latest TEST_MATRIX entry for exact verification and its limits.
