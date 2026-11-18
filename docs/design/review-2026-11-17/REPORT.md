# UI design-implementation review — 2026-11-17 (Claude)

Tested commit `a69cc18` in a detached worktree. It does not contain Codex's uncommitted Redact/scanner fixes. HEAD moved during the review (to `613e3a1` at commit time). Of the reviewed screens, only two changed after `a69cc18`. **Export** (`62deaeb`, `613e3a1`) gained a size line in the footer and a preview at the end of the sheet. **Notebook creation** (`ae9d080`, `ebe49fe`) gained more papers and saved templates. So the Export and template findings need a recheck at HEAD. `RedactEditor`, `SignatureSheet`, `PDFFormSheet`, `OCRPanel`, `RecognizedTextEditor`, `ScannerWorkspaceView`, `Theme`, `LibraryHome` and `SubscriptionViews` are **unchanged at HEAD**, so those findings stand. Evidence numbers refer to files in this folder. Raw logs and `.xcresult` bundles are in `~/Library/Caches/PaperNest/claude-ui-review-results/`. Commands and counts are in the top entry of `docs/TEST_MATRIX.md`.

## UI review result

- **Overall result:** Pass with issues
- **Features reviewed:**
  - Home
  - Notebook creation (templates)
  - Export with watermark and password
  - Redact
  - Compress
  - OCR panel and correction editor
  - Signature
  - PDF form fill
  - Page comments
  - Pro paywall gates
  - Scanner capture advice and scanner review
- **Platforms reviewed:**
  - iPhone 17 Pro and iPad Air 13-inch (M4) simulators, iOS 26.5.
  - Mac: built only. Interaction was blocked because screen access was declined.
- **Locales reviewed:**
  - en on both devices.
  - fr: iPhone XXXL screen pass; iPad interaction tests.
  - es: iPhone XXXL screen pass; iPad interaction tests.
- **Accessibility sizes reviewed:**
  - Default size.
  - Accessibility XXXL: iPhone fr and es screen passes, plus iPad reachability tests for French watermark and signature.
  - `performAccessibilityAudit` ran on every captured screen. That is an audit, not VoiceOver verification.
- **Appearance:** light on both devices; dark on iPhone (7 screens).

## Mismatches

| Severity | Feature/screen | Platform/state | Expected | Actual | Evidence | Fix |
|---|---|---|---|---|---|---|
| Major | Redact review | iPad Air 13 en light default; iPhone fr XXXL; iPhone en default (conditional warning) | Prompt: no inaccessible off-screen content. Claude R7 handoff note: "keep every warning the review shows on screen before Redact Page". Codex (08:24) judged below-viewport warnings not a finding, so this is the owner's call. | The preview takes about 60% of the sheet. iPad: second warning cut mid-line, third hidden. fr XXXL: no warning visible. iPhone en: "same original" warning hidden (it appeared only because the seed shared an asset). Redact Page is enabled throughout. | 01, 02, 04 | On regular width, put warnings beside the preview or use a large page sheet. Cap the preview at about 40% of height. Or keep Redact Page disabled until the warnings have been scrolled into view. (Codex) |
| Major | Export action bar | iPhone fr and es XXXL, light and dark | Prompt: controls fit without truncation; long FR/ES strings wrap. WATERMARK doc: "Verify long French and Spanish labels at accessibility text sizes". | fr "En-re…", "Co-pier", "Par-ta…"; es "Gua rd…", "Co-piar", "Co m…". The three pills fill about 25% of the screen. | 05, 06, 37 | At accessibility sizes, stack full-width rows (icon + label) without hyphenation. (Codex) |
| Major | Signature panel | iPhone fr XXXL | CLEAN_NATIVE 11-15: scrollable sections with a pinned footer, which still needs a usable content area. Prompt: no off-screen content. | The header ("Signa-ture", 2 lines) takes about 20% of the screen and the pinned hint + Place Signature about 45%, leaving a ~25% scroll strip. The name field and pad are not in the first view. | 07 | At accessibility sizes, let the footer scroll with the content and cap the header's type size. Share the helper with the OCR panel. (Codex) |
| Major | PDF form sheet | iPhone fr and es XXXL; en default | CLEAN_NATIVE 11-15 panel styling. Prompt: primary actions visible and real. | At XXXL, Save Filled Copy moves into a "…" overflow and the title disappears. At en default size, the title truncates to "Fill PDF Fo…". | 08, 09, 10 | Move Save Filled Copy to a pinned bottom action and use the compact icon/title/✕ header, as OCR and Signature do. (Codex) |
| Major | Scanner review | iPhone fr XXXL | Prompt: no clipping or overlap; Save reachable and readable. | Title "Modif…", Save "Enr…", name "Numérisation…", preset labels "O…/A…/Ni", zoom pill over the page, tool row clipped at the right. The audit counts 8 clipped texts. | 11 | Accessibility layout: Save as a full-width bottom button, preset tiles as a list or icon-only with VoiceOver labels, zoom pill below the preview, tools wrapping. (Codex) |
| Major | Dark filled actions | iPhone en dark | Prompt: semantic colours. WCAG contrast. | White text on #C5AEFF (1.93:1 by Codex's calculation) on OCR "Recognize 1 page" and Redact "Review". The audit flags both. | 32, 33 | Change the shared dark filled-action colour once in Theme (Codex used #6839D8 for Redact) instead of per screen. (Codex) |
| Major (known) | Redact actions | iPhone fr XXXL at HEAD | Prompt: labels fit | "Cav…", "Modi-fier le…" | 04 | Codex's uncommitted `RedactEditor.swift` change; Codex reports it verified at 13:30. Commit it. |
| Minor | OCR panel | iPhone fr XXXL | As Signature | Header 3 lines (~30%), footer ~20%. "Correct Text…" was not reached in 8 swipes. | 12 | Same helper as Signature. (Codex) |
| Minor | PDF form panel | iPad and iPhone en | CLEAN_NATIVE 11-15: "controls receive the same styling". FEATURE_UI_SAMPLES §2: human field labels and "N complete · M remaining". | Text Cancel and a header button with no icon. Labels are raw field names (`customer`, `approved`). No completion count. | 13, 10 | Chrome: Codex. Display names from the PDF alternate name (/TU) when present: Claude (backend). |
| Minor | Watermark preview | iPhone en | WATERMARK doc export sheet: Preview first; it updates immediately. | The preview sits below the presets and the mark toggle. After choosing a preset on iPhone it is out of view. | 14 | Move the preview above the presets, or pin a small live thumbnail. (Codex) |
| Minor | Password export | iPhone and iPad, light and dark | FEATURE_UI_SAMPLES §4: Password + Confirm. Readable warning. | A single field with no confirm. The warning "lose it and the file cannot be opened" fails the contrast audit. | 15, 34 | Add a Confirm field with a mismatch error; use secondary, not tertiary, text. (Codex) |
| Minor | Home See All | iPhone and iPad | Prompt: control sizes | Audit: hit area too small | audits/*home* | Minimum 44 pt hit area. (Codex) |
| Minor | Notebook templates | iPad en | FEATURE_UI_SAMPLES §7: small paper preview and page size per template | Text rows only. **Possibly superseded:** `ae9d080` added papers; not re-checked. | 16 | Add paper thumbnails. (Codex) |
| Minor | Scanner advice | iPad en (simulator) | FEATURE_UI_SAMPLES §6: advice near the page outline | Under the top bar (already noted by Claude, 2026-11-16) | 17 | Place it near the outline. (Codex) |
| Polish | Export bar | iPad en | Consistent control sizes | "Save to Files" wraps to 2 lines; Copy and Share stay on 1 | 18 | Shorter label or equal-height layout |
| Polish | Compress result | iPad en | Export: "the ways out are the buttons" (11-13) | An extra Compress step, then "Save…/Share…" | 19 | Align the labels and flow with Export |
| Polish | Paywall icons | iPad en | Consistent symbols | "Exports without the PaperNest mark" uses eye.slash, the Redact tool's glyph | 20, 21 | Use a distinct glyph |
| Polish | Redact marking | iPad/iPhone light | CLEAN_NATIVE visual language: light canvas, white paper | Near-black stage inside the light sheet | 22 | Use a semantic canvas colour |
| Polish | Redact review (scrolled) | iPhone en light | Readable title | The title turns white over the grey blur of the preview | 03 | Adjust the toolbar background or title colour |
| Polish | Notebook creation | iPhone fr XXXL | Prompt: no truncation | Large title "Nouveau ca…" | 23 | Inline title at accessibility sizes |
| Polish | Signature (dark) | iPhone en dark | Semantic surfaces | The Name field is pure black inside the dark purple card | 35 | Use the card's field colour |

**Not a mismatch:** free exports carry the PaperNest mark. The watermark doc says the mark is never forced, but the owner changed that policy on 2026-11-13 (`docs/PRO_SUBSCRIPTIONS.md`).

**Correctly absent at `a69cc18`:** review links, structured capture and clean-up assistant (both landed later), handwriting-to-text, presentation, audio notes, document assistant, Book scan mode, PDF copy/print restrictions.

**Landed later, not reviewed:** Compare (`5e73951`, `7c5ad32`); stationery papers (`ae9d080`, `bfa7dca`); saved templates (`ebe49fe`); receipt, business-card and invoice details (`7338677`, `d9dc1cd`); clean-up suggestions (`2510776`, `04b6ebe`); text stamps (`2e6aa94`); export size estimate and preview (`62deaeb`, `613e3a1`).

## Verified interactions

- **Original unchanged.** A watermarked Copy (Confidential), then Redact mark → Cancel. The page rows and every asset's SHA-256 were identical before and after, on iPad and iPhone (files 30, 31).
- **Export with watermark (iPad):**
  - None is the default; a preset fills its controls.
  - Placement, opacity and rotation change the preview.
  - Custom asks for text; a text format says it can't carry a watermark.
  - The PaperNest preset has no text to change, and its preview draws the real BrandMark (24).
  - Copy, Share and Save each export with the watermark; closing the sheet forgets it. Copy and closing also pass on iPhone.
  - French XXXL controls are reachable.
  - A free user keeps the mark until Pro.
- **Pro gates (iPad):** Redact and Compress open a paywall that names the feature (20).
- **Unavailable state:** "Subscriptions are unavailable right now" with Try Again and Continue with Free (21).
- **Redact:** mark → review → apply removes the line from the page and the library (iPad). Cancel writes nothing (iPad and iPhone).
- **OCR:**
  - Panel: language and range validation, then recognition in en/fr/es (iPad).
  - Correction: Cancel after a change asks first and saves nothing; the editor works in fr/es (iPad).
- **Form:** the filled copy reopens with its fields (iPad and iPhone).
- **Signature:** saved signature places, undo/redo work, and it survives reopening (iPad and iPhone). French XXXL is reachable (iPad).
- **Compress:** runs and honestly reports "cannot be made smaller" for a text PDF (19).
- **Document Tools:** process tools do real work (iPad).
- **Scanner:**
  - Review edits save and reopen; saving a scan opens Export, and closing it returns Home (iPad).
  - Advice shows in fr/es (iPad).
- **Home and library (iPad):**
  - Approved Home with recents and folders.
  - Notebook creation survives relaunch.
  - Comments edit/cancel/delete/undo/reopen in en/fr/es.
- **Screen passes:**
  - iPad en light: 13/13 after the test fix.
  - iPhone en light: 11/13. The two failures were the test's preset ID and a 20 s open timeout under load.
  - iPhone fr XXXL: 10/13.
  - iPhone es XXXL: 6/6.
  - iPhone en dark: 7/7.
- **Still failing, inconclusive:**
  - `OCRCorrectionUITests.testACorrectedWordIsSavedAndFindAnswersIt` on iPad, twice: "the OCR panel did not open". The same entry point opened the panel in 4 other iPad runs.
  - `WatermarkExportUITests.testWithoutProductsTheMarkStartsOff` on iPad, twice. This is a test defect: it centre-taps a Toggle row, which `PanelControls.flipSwitch` documents does nothing on iPad.
- **No verdict** (the runner restarted under load): `RedactUITests.testTheScreenInFrenchAndSpanish`, `ScannerFeedbackUITests.testTheAdviceFollowsWhatTheCameraSees`, `.testNothingFoundSaysNothing` on iPad.

## Unverified coverage

- **Mac:** no interaction (screen access declined). An offscreen render was not attempted.
- **Hardware and services:** physical iPhone/iPad, real camera capture, StoreKit purchase/restore, iCloud.
- **VoiceOver:** focus order and navigation were not run. The audits do not replace them.
- **iPad dark:** not run (Codex checked iPad dark Redact on 2026-11-17).
- **Phone dark:** Compress, Comments, paywall, notebook creation and scanner capture.
- **iPad XXXL screenshots:** none; only the French watermark and signature reachability tests passed.
- **iPad Spanish screenshots:** none; Spanish interaction tests passed for OCR panel, comments, OCR correction and scanner advice.
- **iPhone at default size:** Spanish, and French except inside the multi-language tests.
- **Exported files:** none opened in an external reader. The PaperNest mark was checked in the in-app preview, not in an exported file.
- **Landed after the tested commit:** Compare, stationery, saved templates, receipt details, clean-up suggestions, text stamps, export size/preview. Not reviewed; Export and template findings need a recheck at HEAD.

## Recommended next fixes

1. **Smallest next slice: the dark filled-action colour** (Codex, Theme). One shared change fixes at least two screens (OCR "Recognize 1 page", Redact "Review"), and Codex already has the Redact half measured and drafted.
2. **Accessibility-size panel chrome**, one shared helper: let the pinned footer scroll and cap header type at XXXL. This fixes Signature and OCR, and with the footer action it fixes the Form sheet (which also gets the compact header).
3. **Export action bar at XXXL:** a stacked layout.
4. **Redact warnings visibility:** decide first (owner), then apply the layout change.
5. **Scanner review accessibility layout.**
6. **Commit Codex's verified Redact action-label fix.**
7. **Minor items:** watermark preview position, password Confirm and contrast, See All hit area, form field display names (backend, Claude), template previews if still missing after `ae9d080`.
