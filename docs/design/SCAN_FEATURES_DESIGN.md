# Scan Studio — Feature Design

**Status:** Design handoff only. No implementation is included in this slice.

**Intent:** Make Scan feel like a focused document studio: fast to capture, clear to review, and powerful enough to prepare a clean multi-page document before it enters the library.

## Product direction

The existing scanner already supports camera capture, automatic/manual shutter, photo import, edge detection, per-capture Keep/Delete, multi-page review, crop points, rotation, enhancement, filters, reorder, duplicate, and delete. The next design pass should make those capabilities easier to discover and add a small number of high-value scanner features without turning the screen into a settings panel.

The supplied iPhone reference establishes the visual language:

- Camera capture is edge-to-edge, dark, and glanceable.
- The mode selector sits above the shutter.
- The page count and latest thumbnail sit beside the shutter.
- Review is a light editing workspace with a large page preview, a filmstrip, preset filters, and a compact bottom tool bar.

## Feature set

### 1. Capture modes

Use a segmented control with four modes:

| Mode | Purpose | Capture behavior |
| --- | --- | --- |
| Document | Receipts, forms, typed pages, notes | Detects edges, corrects perspective, enables Auto capture |
| Whiteboard | Large boards and wall notes | Finds a wide rectangle, favors full-board framing, uses a high-contrast cleanup preset |
| Photo | Preserve the entire camera frame | No edge crop, no Auto capture |
| ID / Card | Small cards and licenses | Detects a compact rectangle and offers front/back pairing |

The selected mode should be visible as a single pill control. Do not expose four equal-weight buttons across a narrow phone; use a horizontally scrollable segmented control or a compact mode menu when text size requires it.

Mode changes affect the next capture only. They do not rewrite already captured pages.

### 2. Capture controls

Top bar:

```text
Cancel                 [Document ▾]       Flash   More
```

Bottom capture area:

```text
[latest page / 3]                 [ shutter ]       [Auto]
                 Document · Whiteboard · Photo · ID
```

Add these discoverable controls to More:

- Import from Photos
- Use System Scanner
- Camera orientation hint when the device is held sideways
- Scan settings

Scan settings should be a small sheet, not a second full screen. It contains only defaults that affect future captures: default mode, default filter, and whether Auto capture starts on entry.

### 3. Capture feedback

When a document is detected, show a thin accent outline and a short state label near the outline:

- “Move closer” when the page is too small
- “Hold steady” when corners are moving
- “Ready” when Auto capture can fire

Keep these messages transient and subordinate to the page. They should never cover text on the document or compete with the shutter.

After every capture, preserve the current Keep/Delete decision screen. The user must always know whether a page is in the accepted queue.

### 4. Review workspace

The review screen is the main feature expansion. Design it as a page studio rather than a generic form.

Phone layout:

```text
Cancel                         Edit                 Save
[Document name                         ]

                 [ large page preview ]

[1] [2] [3] [+]       page filmstrip

Original  Auto  Enhanced  B&W  High Contrast  Cleanup

Crop      Rotate      Filters      Cleanup      More
```

The preview remains the visual priority. The filmstrip is always reachable without opening a menu. The selected page has an accent outline and a clear page number.

iPad layout:

```text
┌──────────────┬──────────────────────────┬───────────────┐
│ Page filmstrip│     selected preview    │ Page tools    │
│               │                          │               │
│ 1  2  3  +    │                          │ Cleanup       │
│               │                          │ Crop          │
│               │                          │ Rotate        │
│               │                          │ Filters       │
└──────────────┴──────────────────────────┴───────────────┘
```

Use the current wide review arrangement as the structural baseline. On accessibility text sizes, stack the workspace and keep the tool strip horizontally scrollable.

### 5. Filter presets

The filter row should use named presets with a small thumbnail preview:

- Original
- Auto
- Enhanced
- Grayscale
- Black & White
- High Contrast

Only one preset is selected per page. The selected preset is shown with the accent border and a short name below the thumbnail. “Cleanup” is separate because it represents multiple adjustments, not just a tonal preset.

### 6. Cleanup tool

Cleanup opens a compact bottom sheet on iPhone and an inline inspector on iPad. It contains three clearly named controls:

- Remove shadows — reduce gray areas caused by uneven lighting
- Whiten background — lift paper toward white without removing ink
- Sharpen text — improve legibility for typed pages

Show a before/after preview toggle at the top of the panel. Use “Apply to this page” as the default action and place “Apply to all pages” behind a clearly labeled secondary action. Never silently apply a cleanup change to every page.

The Cleanup tool should expose a single preset button for common use:

```text
Cleanup
  [Before / After]
  Remove shadows       [slider]
  Whiten background    [slider]
  Sharpen text         [slider]

  Apply to this page
  Apply to all pages
```

### 7. Batch page actions

Add multi-select to the filmstrip through More → Select Pages. In selection mode, the bottom bar becomes:

```text
3 selected       Filter     Cleanup     Duplicate     Delete
```

Batch actions:

- Apply a filter to all selected pages
- Apply Cleanup to all selected pages
- Delete selected pages
- Duplicate selected pages
- Move selected pages as a group

The selection count must remain visible. Destructive Delete requires a confirmation only when more than one page is selected.

### 8. ID / Card pairing

When ID / Card mode is selected, the capture screen changes its page-count label to “Front” and “Back”. After the front is kept, show a lightweight prompt:

```text
Front saved
Capture the back of the card, or continue with front only.

[Scan back]     [Continue]
```

The review screen groups the pair as one page set but still allows either side to be edited independently. This is a design target for a later phase; it should not block the first cleanup release.

### 9. Save and destination

Keep the existing name field, but make the destination visible before final save:

```text
Document name
Biology notes

Save to
PaperNest Library  >
```

The destination row opens the existing import-location workflow. The final action remains a single Save button. Do not add a second “Export” action to the Scan review screen; exporting is a post-save document action.

## Interaction rules

- Captured pages remain drafts until the user taps Keep.
- Editing a page never changes the original camera bytes.
- Switching pages preserves each page’s edits.
- Returning to the camera preserves the accepted queue and the current mode.
- Save is disabled when there are no accepted pages or when a render is still in progress.
- Every interactive control needs a readable label, a stable accessibility identifier, and an accessibility value for selected/on/off states.
- All user-visible copy must be localized in English, French, and Spanish.

## Platform behavior

### iPhone

Prioritize one-handed capture, a horizontal filmstrip, and bottom sheets. Keep the shutter visually dominant. At compact widths, put less-frequent actions in More.

### iPad

Use the three-column review studio. Keep the page list and tool inspector visible while editing. Avoid presenting every tool as a modal sheet when there is room for an inline inspector.

### Mac

The Mac does not provide camera capture in this product. The Scan entry point should not appear as an active camera action there. Imported images can still use the same review concepts if a future import-review workflow exposes them.

## Phased delivery for implementation

### Phase 1 — strongest near-term slice

- Add the filter preset row: Original, Auto, Enhanced, Grayscale, Black & White, High Contrast.
- Add Cleanup with page-only and apply-to-all choices.
- Add clear before/after preview treatment.
- Preserve current capture and save behavior.

### Phase 2 — batch editing

- Add multi-select in the filmstrip.
- Add batch filter, cleanup, duplicate, move, and delete actions.
- Add selection-state accessibility and destructive-action confirmation.

### Phase 3 — capture expansion

- Add Whiteboard mode.
- Add ID / Card mode and front/back pairing.
- Add the small Scan settings sheet.

## Design acceptance checklist

- The capture screen still reads as a camera first, not a settings screen.
- The selected scan mode is obvious at a glance.
- A first-time user can find filters and Cleanup without opening More.
- A user can tell which pages are accepted, selected, edited, or pending.
- Apply-to-all actions are explicit and reversible before Save.
- The same hierarchy works in English, French, Spanish, and accessibility text sizes.
- The design follows the existing Clean & Native rules and the supplied `iphone-scan-library` reference.
