# Test matrix

## 2026-10-29 UTC — Final opaque-toolbar light iPad largest-text check

- `/private/tmp/papernest-opaque-nav-ipad-light-large.log`: **passed, exit 0**, 73.282 seconds, 900-second bound. Final toolbar source on light iPad: sidebar width assertion, largest-text position slider, Thick selection, native color popover, save and saved markup row. Existing assertions unchanged.
- Exported `docs/screenshots/opaque-light-*-ipad.png`; screenshots not visually inspected this pass. No passing full audit claimed. Final phone dark/localized and native Mac/VoiceOver/device checks remain unrun. No source/backend edits, fresh unit/Mac builds, staging or commits. Simulator remains light; no pending process. Weekly usage was 96% consumed at start.

## 2026-10-29 UTC — Recovered opaque-toolbar iPhone verification

- Recovered the completed bounded run after usage interruption: `/private/tmp/papernest-opaque-nav-phone-large.log` **passed, exit 0**, 66.992 seconds under 900-second timeout. Final opaque-toolbar source on light iPhone at largest text: position slider, Thick width selection, native color picker, save and saved-markup verification all passed. No rerun needed.
- Exported three screenshots as `docs/screenshots/opaque-nav-*-iphone.png`; width screenshot inspected: toolbar title/actions and selected Thick row visible, scroll-edge content remains clipped as expected during scrolling. This is not a passing accessibility-audit claim. iPad light/final largest-text and final phone dark/localized checks remain unrun.
- Documentation/evidence only; no fresh unit/Mac tests, source/backend edits, staging or commits. Previous 502-test/Mac results remain historical. No pending processes or claims. Weekly usage 95% consumed at recovery; handoff saved.

## 2026-10-29 UTC — Shape/Stamp opaque navigation background

- `ShapeAnnotationSheet.swift` iOS navigation now requests a visible opaque `secondarySystemBackground`. Purpose: stable Cancel/Add backing while Form content scrolls beneath navigation. No strings/actions or backend changes; macOS unaffected by the conditional modifiers.
- `/private/tmp/papernest-opaque-navigation-audits.log`: **both audits still failed, exit 65**, 900-second bound. Initial audit unchanged: 19 Dynamic Type + 2 clipped-Style contrast activities. Scrolled audit decreased from 13 contrast activities to 9; the four Cancel/Add activities disappeared. Remaining cropped chooser content still fails. No assertion or issue filter changes. This is a toolbar improvement, not a passing accessibility audit.
- Activity associations exported in `docs/screenshots/opaque-nav-scrolled-issues.json`. Inspected full screenshot `opaque-nav-shape-dark-ipad.png` and selected remaining issue crops; opaque backing removes chooser text behind the toolbar while below-edge obscured content remains. `/private/tmp/papernest-opaque-nav-unit.log`: **502 tests passed, exit 0** (64 UI + 143 Store + 125 Import + 122 Export + 48 Core). `/private/tmp/papernest-opaque-nav-mac.log`: **passed, exit 0**; no compiler warnings/errors in either log, both bounded to 600 seconds. `/private/tmp/papernest-opaque-nav-localized.log`: **passed, exit 0**, 90.407 seconds, 900-second bound: dark iPad en/fr/es shape/stamp selection/cancel and Comments editor navigation.
- Restored iPad light. Final source not checked on iPhone, light mode or largest text; native Mac interaction/VoiceOver/device checks remain unrun. No files staged or committed.

## 2026-10-29 UTC — Scrolled audit evidence mapped completely

- Reviewed all 11 available element crops from the 13 saved contrast activities in `visible-style-activity-associations.json`, plus `fully-visible-shape-style-dark-ipad.png`. Activity numbers match `visible-style-issue-N.png`: 1/8 Cancel, 2/9 Add; 4/5 blurred first-row shape labels, 6 Line, 7 Arrow; 11/12 blurred first-row stamp labels, 13 Star. Activities 3/10 have no element screenshot and are not assigned a label. Twelve activities say Contrast failed, one (12) Contrast nearly passed. Four console error lines were grouped reports, not a count of affected elements.
- Full Shape image shows Style fully visible but chooser rows scrolled into the translucent navigation/scroll-edge region. This explains where the blurred crops come from, not whether the accessibility audit is a false positive. Visible Cancel/Add findings and obscured chooser-label findings must be investigated separately. No sampled solid-colour ratio is a substitute for runtime contrast across these composited states.
- Next targeted experiment: inspect the sheet navigation/scroll-edge background treatment against both initial and scrolled audits, and retain chooser accessibility/scroll reachability. Do not recolour the selected tile based on the earlier incorrect attachment association; do not suppress issues. Initial clipped-Style finding remains open.
- Evidence review only: no new tests/builds, source changes, simulator changes, staging or commits. Existing audit results remain failed; native Mac, VoiceOver and device checks remain unrun.

## 2026-10-29 UTC — Correct audit association and visible-Style diagnostic

- **Correction to the two preceding contrast reviews:** `xcresulttool get test-results activities` associates the original dark audit's two contrast failures with **Style**, both using the same clipped-heading payload. Rectangle/Add were neighbouring exported attachments, incorrectly paired by list position. Prior pixel calculations concern unrelated crops, not the failing elements. Saved exact activity associations in `docs/screenshots/dark-audit-contrast-activity-associations.json`; inspected corrected crop `dark-audit-style-contrast-corrected.png`. No app palette change made on the incorrect attribution.
- Added separate `testVisibleAnnotationStyleContrast`, keeping the original initial-viewport audit unchanged. It scrolls the Form left margin, asserts Style is fully within an inset visible viewport and hittable, captures a screenshot, then audits contrast/clipping. No issue suppression; final version continues after findings to collect Shape and Stamp. Test-only change, English, ordinary-size dark iPad.
- First run `/private/tmp/papernest-visible-style-dark.log`: **failed, exit 65**, 20.224 seconds; stopped after Shape contrast failure. Its actual activity-linked crop is Cancel (saved `visible-style-dark-contrast-failure.png`). Final collection run `/private/tmp/papernest-visible-style-dark-all.log`: **failed, exit 65**, 35.749 seconds, four error lines; activity tree has repeated issue activities. Fully-visible Style assertions completed on both sheets. Saved `visible-style-activity-associations.json` and available element crops `visible-style-issue-*.png`; inspected first two (Cancel, Add). Other issue crops remain to inspect before attributing all failures. Both runs bounded to 900 seconds.
- This does not establish a passing contrast audit, nor justify suppressing the initial clipped-Style finding. Next inspect the remaining activity-linked crops and the scrolled toolbar backgrounds; do not use export-list adjacency. iPad restored light. No app/backend edits or fresh unit/Mac runs. No staging/commits.

## 2026-10-29 UTC — Codex contrast evidence review (association corrected below)

**Correction, 09:35 UTC:** Rectangle/Add were neighbouring attachments, not the contrast failures. The activity tree links both contrast issues to the clipped Style heading. Pixel calculations below describe unrelated crops and must not guide fixes.

- Inspected the saved dark Rectangle/Add element crops and the full Shape audit screenshot. PIL RGB histogram: Rectangle dominant background `(59,60,71)`, solid text `(255,255,255)`; Add dominant background `(37,37,39)`, solid accent `(165,176,255)`. Standard sRGB relative-luminance calculation gives approximately **10.92:1** and **7.47:1** for those specific pairs. This samples solid screenshot pixels only, excludes antialias edges and alternate states, and is **not** a replacement for the failed accessibility audit or evidence of a false positive.
- Source inspection: chooser selected fill uses `Theme.accent.opacity(0.12)`, title inherits plain button text, Add uses native toolbar styling; dark Theme accent is `0xA5B0FF`, matching the crop. No palette change justified solely by these crops. Next compare issue-to-element attachment association and runtime audit state, including any text-size/state transitions; retain all failure assertions. Full screenshot still shows Style at lower viewport boundary; do not dismiss its light-mode finding.
- Evidence-only review; no tests/builds rerun, no source/backend edits, no staging or commits. Existing 21-finding dark audit remains failed. Usage was 87% consumed at start; handoff kept current.

## 2026-10-29 UTC — Codex current dark iPad audit findings

**Correction, 09:35 UTC:** The counts remain valid; the Rectangle/Add attribution below was wrong. Both contrast findings belong to Style. Use the activity-tree associations, not exported-list adjacency.

- `/private/tmp/papernest-final-dark-audit.log`: **failed, exit 65**, existing four-sheet audit under 900-second bound. Current dark iPad source: **21 findings**, 19 “Dynamic Type font sizes are partially unsupported” and 2 “Contrast nearly passed”; no clipping findings. No suppression or expected-failure filters. Interaction successes do not imply audit success.
- Exported attachments to `/private/tmp/papernest-final-dark-audit-evidence`. Inspected both contrast element screenshots: selected Rectangle title and Add button, retained as `docs/screenshots/dark-audit-rectangle-contrast.png` and `dark-audit-add-contrast.png`. These are concrete contrast targets; do not assume all current findings concern toolbars. The prior light-mode Style finding remains unresolved; absence in this dark run does not close it.
- Restored iPad light. No source/test/backend edits or fresh unit/Mac build. Native Mac/VoiceOver/device checks not run. Nothing staged or committed.

## 2026-10-29 UTC — Codex iPad offscreen Thick tap investigation

- Unchanged dark iPad rerun `/private/tmp/papernest-dark-ipad-reproduce.log` reproduced the missing `shape-width-4` failure after tapping, exit 65, 51.074 seconds. Original recording frames inspected and retained as `docs/screenshots/dark-ipad-thick-offscreen-before.png` and `dark-ipad-thick-sheet-dismissing.png`: Thick was below the sheet's visible area, then the sheet dismissed. The helper trusted `isHittable` and assumed the final collection view was the Form; logged drag bounds instead matched the sidebar.
- Test-only `reveal` helper now excludes named Sidebar/Pages collections, intersects Form/screen/navigation bounds, requires the whole target inside that viewport plus hittability, and scrolls slowly with endpoint hold along the Form's left margin. Selection, picker and saved-row assertions unchanged. No app/backend code or user-facing strings changed.
- Failed experiments retained: `/private/tmp/papernest-dark-ipad-visible-control.log` (containment with old collection order), `/private/tmp/papernest-dark-ipad-form-selection.log` (correct collection but right-edge drag), `/private/tmp/papernest-dark-ipad-form-center.log` (centre overlaps interactive preview); all exit 65. Right-edge repeated drags left content unchanged; centre run left Position partially below the sheet. Final left-margin `/private/tmp/papernest-dark-ipad-form-margin.log` **passed, exit 0**, 74.871 seconds: slider, Thick, real system color popover, save and saved markup row. All runs bounded to 900 seconds.
- Final iPad width screenshot `docs/screenshots/form-margin-readable-large-text-width-ipad.png` inspected: Thick fully visible and selected; sheet stays open. Position/picker screenshots also exported. Restored iPad light. iPhone light largest-text helper regression `/private/tmp/papernest-form-margin-phone.log` **passed, exit 0**, 66.595 seconds, also bounded to 900 seconds; full slider/width/picker/save/saved-markup flow. Final helper not rerun on iPad light or iPhone dark; earlier results on those combinations used the preceding helper. No fresh unit/Mac runs for test-only change; full audit/native/VoiceOver/device gaps remain open. Nothing staged or committed.

## 2026-10-29 UTC — Codex dark iPad largest-text failure

- `/private/tmp/papernest-final-dark-large-ipad.log`: **failed, exit 65**, 52.001 seconds, bounded to 900 seconds. Existing `testLargeTextShapeSlidersAndSystemColorPicker` on final source, dark iPad Air 13 M4. Sidebar check and start-X slider interaction completed; failure at AppUITests.swift:1305 querying `shape-width-4` after tapping Thick: “Failed to get matching snapshot: No matches found”. System picker and save/Manage Markup checks were **not reached**. Root cause not established; do not call this a verified app defect or a harmless test flake.
- Exported attachments to `/private/tmp/papernest-final-dark-large-ipad-shots`; hierarchy copied to `/private/tmp/papernest-dark-large-ipad-failure-hierarchy.txt`. Position screenshot retained at `docs/screenshots/dark-large-ipad-failure-6195F497-3557-417A-8739-095EA0658DDE.png` (not visually inspected this pass). Next: compare the failed hierarchy/recording and reveal helper's scrolling at the Thick selection; preserve the assertion and reproduce before changing code.
- Restored iPad light. No source/test/backend edits, no new unit/Mac runs, nothing staged or committed. Prior light iPad and dark phone successes do not close this dark iPad failure. Usage was 89% consumed at the start; preserved handoff for continuation.

## 2026-10-29 UTC — Codex final iPhone dark-mode annotation verification

- `/private/tmp/papernest-final-dark-phone.log`: **2 passed, exit 0**, 156.647 seconds under a 900-second bound. Existing localized annotation test passed English/French/Spanish shape/stamp selection/cancel and Comments editor navigation. Existing largest-text test passed English start-X slider, Thick width selection, actual system color picker interaction, shape save and saved markup row verification. Final source, iPhone 17 Pro, dark appearance.
- Exported 12 screenshots as `docs/screenshots/final-dark-*-iphone.png`. Inspected Spanish Comments, English largest-text width and system picker: ordinary Comments labels/help fit; largest-text width choices and selected checkmark readable; actual native picker visible. Content scrolls beneath the fixed toolbar at largest size; this pass does not resolve the separate toolbar Dynamic Type/contrast audit findings. Restored iPhone to light.
- No app/test/backend edits. No fresh unit suite or Mac build for this verification-only pass. Full audit, localized largest-text flows, native Mac interaction, VoiceOver, injected disk I/O failure and physical camera remain unrun here. No files staged or committed.

## 2026-10-29 UTC — Codex final annotation dark-mode regression

- `/private/tmp/papernest-comments-final-dark-ipad.log`: existing `testAnnotationStyleLayoutInAllLanguages` **passed, exit 0**, 91.121 seconds, under a 900-second bound. iPad Air 13 M4 in dark mode, ordinary text, English/French/Spanish: shape/stamp chooser selection and cancellation plus Comments add/editor/cancel navigation. Final Comments wrapping and two-column chooser source exercised; no source or test edits.
- Exported nine screenshots as `docs/screenshots/final-dark-readable-*-ipad.png`. Visually inspected French Comments, Spanish Shape and English Stamp: title/help readable, chooser labels fit, selection checkmark visible. Style remains below the initial viewport; this is not evidence resolving its audit finding. Restored iPad to light appearance.
- No fresh unit/Mac build (verification-only pass); previous 502-test/build results are historical. Full accessibility audit, largest text, iPhone dark mode, native Mac interaction, VoiceOver and physical camera not run here. Desktop-control tools remain unavailable. Existing audit failures remain open. Backend untouched; nothing staged or committed.

## 2026-10-28 — Codex Add Comment clipping investigation

- Repeated audit finding was on the Add Comment title. First experiment put vertical fixed-size wrapping on the title inside Label: `/private/tmp/papernest-comment-title-audit.log` still reported Text clipped, exit 65. Replaced that with an explicit first-baseline HStack, decorative icon hidden from accessibility, and wrapping localized title; retained the button, identifier, 44-point minimum and save availability rules.
- `/private/tmp/papernest-comment-row-audit.log`: overall **failed, exit 65**, but Add Comment clipping no longer reported. Toolbar contrast/Dynamic Type and other-sheet failures remain, with no audit suppression. Backend untouched.
- `/private/tmp/papernest-comment-row-ipad.log`: **1 passed, 1 failed overall, exit 65**. The four-sheet audit retained 27 findings (toolbar contrast/Dynamic Type and Style heading contrast), but no Add Comment clipping. The existing English/French/Spanish annotation-style and Comments editor navigation flow passed in 88.213 seconds. Both simulator runs bounded to 900 seconds; no issue filters or weakened assertions.
- `/private/tmp/papernest-comment-row-unit.log`: **502 tests passed, exit 0**; `/private/tmp/papernest-comment-row-mac.log`: **build passed, exit 0**. Both bounded to 600 seconds, no compiler warnings/errors. Saved and visually inspected `docs/screenshots/comments-wrapping-iphone.png` and `docs/screenshots/comments-wrapping-fr-ipad.png`: ordinary-size labels/help fit. Final change checked in light mode; no dark-mode, VoiceOver, native Mac interaction, physical camera, or maximum-size screenshot claim. No files staged or committed.

## 2026-10-28 — Final single-column dashboard phone check

- `/private/tmp/papernest-dashboard-ax-phone-final.log`: **1 passed, exit 0**, 900-second timeout. Final grid source passes largest-text phone branding/navigation assertions and opens notebook creation. Screenshot `docs/screenshots/dashboard-single-column-largest-iphone.png` exported and inspected: branding and Note label fit; other actions require scrolling. English/light only; no full accessibility audit or localized maximum-type claim. No source changes or repeat unit/Mac builds in this verification-only pass. Remaining failures and native/device gaps unchanged. Nothing staged/committed.

## 2026-10-28 — Codex sidebar-root dashboard regressions

- No source edits; checking final sidebar preference placement. Phone `/private/tmp/papernest-sidebar-regression-phone.log`: **2 passed, exit 0**, dashboard create/reopen and layout in en/fr/es plus largest-text notebook entry and compact navigation. 900-second bound. Screenshots exported as `sidebar-regression-*-iphone.png`; largest-text Home inspected.
- Dark iPad `/private/tmp/papernest-sidebar-regression-ipad.log`: **2 passed, exit 0**, same en/fr/es dashboard and maximum-type notebook entry. Exported `sidebar-regression-*-ipad.png`. Screenshot review found a visual regression despite passing interactions: the now-wider sidebar left two accessibility-size action columns narrow enough to hyphenate Notebook.
- Fixed only `LibraryHome.swift` quick-action grid: a single flexible column at accessibility sizes, existing ordinary-size layouts retained. Final `/private/tmp/papernest-dashboard-ax-single-column.log`: largest-type dark iPad test **passed, exit 0**; inspected `dashboard-single-column-largest-ipad.png`, New Notebook fits on one line with readable hint. `/private/tmp/papernest-dashboard-ax-unit.log`: **502 passed**, exit 0 (64 UI + 143 Store + 125 Import + 122 Export + 48 Core); `/private/tmp/papernest-dashboard-ax-mac.log`: passed, exit 0. No compiler warnings/errors. Unit/Mac bounded to 600 seconds; UI to 900. iPad restored to light.
- Final single-column source not rerun in French/Spanish, phone, or native Mac interaction; localized phone/iPad tests above preceded that small change. No passing full audit claimed. Remaining contrast/Dynamic Type/Comments clipping, landscape, native VoiceOver/two-window and camera gaps remain. No files staged/committed.

## 2026-10-28 — Codex large-text sidebar width restored

- The width preference was attached to the nested List after the dashboard introduced a ScrollViewReader. Moved `navigationSplitViewColumnWidth` to the outer sidebar ScrollViewReader in `RootView.swift`; unchanged min/ideal values, no new strings or backend changes. The existing >=400-point test was kept unchanged.
- `/private/tmp/papernest-sidebar-root-ipad.log`: **passed, exit 0**, 80.158 seconds, 900-second bound. Full largest-type iPad flow now passes: sidebar width assertion, start-X slider, Thick width, real system color picker/popover dismissal, save and saved stroke in Manage Markup. Exported `sidebar-root-*-ipad.png`; position screenshot inspected and confirms a wider sidebar with All Documents on one line. Light mode, English only for this final source change.
- `/private/tmp/papernest-sidebar-root-unit.log`: **502 tests passed**, exit 0 (64 UI + 143 Store + 125 Import + 122 Export + 48 Core), no compiler warnings/errors. Count includes Claude's concurrent backend additions; Codex did not edit them. `/private/tmp/papernest-sidebar-root-mac.log` passed, exit 0, no compiler warnings/errors. Both bounded to 600 seconds.
- Prior final-helper ordinary en/fr/es iPad Notes regression passed before moving the width preference. Final-source phone, ordinary-size/dark/localized sidebar and native Mac interaction not rerun; no passing full audit claimed. Existing toolbar contrast/Dynamic Type, Add Comment clipping, iPad Style viewport, native VoiceOver/two-window and camera gaps remain. No files staged or committed.


## 2026-10-28 — Codex held-drag iPad regression

- Final helper revision checked with existing largest-text and en/fr/es Notes tests under 900-second timeout: `/private/tmp/papernest-held-drag-ipad.log`. Largest-text flow **failed before reaching the shape sheet**: sidebar width 320 points vs existing minimum 400 at AppUITests.swift:1269. No assertion weakened; system sidebar constraint/readability needs investigation. This does not test the final helper at largest type on iPad. Recovered final result: ordinary en/fr/es Notes regression PASSED; **1 passed, 1 failed overall**, exit 65. This was before the RootView correction below. Screenshots exported as `held-drag-notebook-tool-bar-*-ipad.png`.

## 2026-10-28 — Codex largest-type shape flow and toolbar test scrolling

- Existing iPhone `testLargeTextShapeSlidersAndSystemColorPicker` rerun under 900-second timeout: `/private/tmp/papernest-large-shape-resume.log` **failed, exit 65**, at `revealEditorTool` for Manage Markup. It successfully adjusted start-X, selected Thick, changed the actual system picker color and saved before failing. The earlier width-selection failure did not reproduce.
- Log shows 16 alternating fixed 257-point toolbar drags overshooting the target at maximum Dynamic Type. Test helper now uses the clipped distance with bounded drag length; existing full-visibility/hittability assertions remain. No app or backend code changed. First proportional-distance rerun `/private/tmp/papernest-large-shape-scroll-fix.log` still failed the largest-type flow at the same helper: drags of 80–120 points still alternated across the target. That run passed the ordinary-size en/fr/es Notes toolbar regression (1 passed, 1 failed overall). Final helper requests slow velocity and a 0.3-second endpoint hold to stop scrolling momentum. `/private/tmp/papernest-large-shape-scroll-held.log` **passed, exit 0**: largest-type slider, Thick selection, actual system color picker, saved shape and Manage Markup row verification, 71.654 seconds. Existing visibility/hittability checks remain. Final-version ordinary-type multilingual regression and iPad were not rerun; the earlier ordinary-size pass used proportional distance without the endpoint hold. No app source changed, so unit/Mac commands were not repeated for this test-helper-only revision; previous 496-test/Mac results are historical, not new runs. Failure-run screenshots retained as `resumed-*-iphone.png` (width screenshot inspected); final passing-run screenshots exported as `verified-*-iphone.png`. Broader audit contrast/Dynamic Type/Add Comment clipping findings, native Mac/VoiceOver/two-window checks and real camera remain open. No files staged or committed.

## 2026-10-28 — Codex shape/stamp chooser width

- Prior iPad screenshot showed English Rectangle hyphenated in a three-column adaptive grid. Ordinary-size chooser now uses two flexible columns on all platforms; accessibility sizes retain the existing full-width rows. No label, action, backend or localization changes.
- Recovered final bounded results after the usage interruption: `/private/tmp/papernest-chooser-unit.log` passed 496 tests, exit 0; `/private/tmp/papernest-chooser-mac.log` passed, exit 0, no compiler warnings/errors. `/private/tmp/papernest-chooser-ipad.log` passed the localized interaction test in en/fr/es, exit 0. Exported screenshots as `docs/screenshots/chooser-readable-*-ipad.png` and inspected all three Shape screenshots: Rectangle/Rectángulo now fit on one line. This was light mode, ordinary type. Matching iPhone `/private/tmp/papernest-chooser-phone.log` passed, exit 0: en/fr/es shape/stamp selection, cancel and Comments editor navigation. Screenshots exported as `chooser-readable-*-iphone.png`; Spanish Shape inspected with all four labels fitting. Dark mode and accessibility-size chooser were not rerun for this width change. Nothing staged or committed. No claim that the wider audit is resolved; toolbar Dynamic Type/contrast, Add Comment clipping and iPad Style viewport finding remain open.

## 2026-10-28 — Codex annotation text contrast continuation

- Applied explicit `Color.primary` to Shape/Stamp help and Style heading, plus Manage Markup Saved Marks heading, empty state and help. The preceding Comments pass demonstrated that hierarchical `.primary` inherits the Form footer color; explicit system primary text avoids it and adapts to dark mode. No strings, operations or backend files changed.
- `./scripts/test.sh`: `/private/tmp/papernest-sheet-contrast-unit.log`, exit 0, **496 passed** (64 UI + 143 Store + 121 Import + 120 Export + 48 Core), no compiler warnings/errors. Mac build `/private/tmp/papernest-sheet-contrast-mac.log`: exit 0, no compiler warnings/errors. Both bounded to 600 seconds.
- iPhone existing four-sheet accessibility audit: `/private/tmp/papernest-sheet-contrast-phone.log`, **failed overall, exit 65**, bounded to 900 seconds. Changed text no longer reports contrast failures. Remaining contrast findings are toolbar Cancel/Add/Done buttons; Dynamic Type findings and Add Comment clipping remain. No issue filters or suppression added. Ordinary-size Shape and Manage Markup screenshots inspected; four screens retained as `docs/screenshots/contrast-accessibility-audit-editor-*-iphone.png`.
- iPad dark run `/private/tmp/papernest-sheet-contrast-ipad.log`: **1 passed, 1 failed**, exit 65. `testAnnotationStyleLayoutInAllLanguages` passed en/fr/es shape/stamp selection, cancel and Comments editor navigation. Four-sheet audit still fails: Shape Style contrast, Dynamic Type findings and Add Comment clipping remain. Shape screenshot shows Style partially below the sheet viewport; the report is retained, not dismissed as a false positive. Ordinary-size English Rectangle also hyphenates in the three-column chooser. These need follow-up layout/scroll investigation. Screenshots exported before pruning as `contrast-*-ipad.png`; inspected English Shape and French Comments (dark appearance confirmed). iPad restored to light. Native Mac interaction, VoiceOver, physical camera and two-window conflicts remain unrun. Tools redesign remains pending. Nothing staged or committed.

## 2026-10-28 — Codex resumed verification and Comments contrast

- Usage check allowed ordinary work. Shared index empty; Claude backend files left untouched. No native desktop-control tools exposed in this session. Bounded device listing `/private/tmp/papernest-resume-devices.log` exited 0 and found only the Mac and simulators, no physical iPhone/iPad. Native Mac interaction, VoiceOver, two-window conflicts and real camera remain unrun.
- Baseline `./scripts/test.sh`, bounded to 600 seconds: `/private/tmp/papernest-resume-unit.log`, exit 0, **496 tests passed** (64 UI, 143 Store, 121 Import, 120 Export, 48 Core). No compiler warnings/errors in log. Mac build `/private/tmp/papernest-resume-mac.log`, exit 0. These ran before the two comment text-style changes below.
- Existing four-sheet iPhone audit, 900-second bound: `/private/tmp/papernest-resume-annotation-audit.log`, **failed, exit 65**. Shapes/stamps: Dynamic Type and contrast findings; Comments: Add Comment potential clipping at larger sizes, Done Dynamic Type/contrast, empty-state/help contrast; markup manager: Done Dynamic Type and multiple contrast findings. No audit issues suppressed. `Test-PaperNest-iOS-2026.10.28_02-20-38--0500.xcresult`; attachments exported to `/private/tmp/papernest-resume-audit-shots` before pruning. Four ordinary-size screens saved as `docs/screenshots/resume-accessibility-audit-editor-*-iphone.png`; Comments screenshot inspected. Ordinary-size visibility does not clear the large-type clipping finding.
- First correction: Comments empty-state and privacy footer used hierarchical primary text contrast. `/private/tmp/papernest-resume-comments-contrast.log` still failed (exit 65), but the empty-state finding disappeared. Footer contrast remained, so its style now uses explicit `Color.primary` rather than an inherited hierarchical style. Final audit `/private/tmp/papernest-resume-comments-final.log` **failed overall, exit 65**, but neither the empty-state nor privacy-footer contrast finding remains. Comments still has Add Comment clipping and Done Dynamic Type/contrast findings; other sheets remain failing. Final Mac build `/private/tmp/papernest-resume-comments-final-mac.log` passed with no compiler warnings/errors. Final screenshot saved as `docs/screenshots/resume-comments-contrast-iphone.png`. No iPad/dark/localized rerun for this two-style correction; no claim those checks passed. No issues suppressed. Nothing staged or committed. `/private/tmp/papernest-resume-comments-unit.log` passed 496 tests, no compiler warnings/errors; `/private/tmp/papernest-resume-comments-mac.log` passed. These two checks precede the final explicit-color adjustment.


## 2026-10-27 — Codex Notes toolbar and first-launch welcome

- Notes actions now appear side by side in a labeled horizontal scrolling row; main actions do not require More. Rotate/filter retain parameter menus. Existing localized labels reused. Toolbar remains when empty so Add Notebook Page/Undo stay available. Compact page viewer receives drawing state.
- Notes phone: `/private/tmp/papernest-note-bar-phone-final.log`, **passed**, exit 0: en/fr/es direct Shape save, Undo/Redo, Add Page/cancel, Comments, delete last page, Undo and add again. First run `/private/tmp/papernest-note-bar-phone.log` failed on offscreen hittability; helper fixed to check geometry before dragging inside the row. Initial English screenshot saved/inspected. Final result bundle was pruned before its localized screenshots could be exported; those images are not claimed reviewed.
- Notes iPad initial `/private/tmp/papernest-note-bar-ipad.log`: **1 failed, 1 passed**, exit 65. Imported-document shape/history passed. Notebook test failed revealing Comments because the reported scroll frame includes the sidebar; helper now clips gestures to the editor column. Rerun pending.
- Welcome: native one-screen introduction, persistent Get started, no account/permission demand; en/fr/es copy, Mac-specific import wording. Existing UI tests bypass via debug-only flag; welcome tests use isolated persistent keys.
- Current-tree `./scripts/test.sh`: `/private/tmp/papernest-welcome-unit.log`, **423 passed**, exit 0 (64 UI, 127 Store, 89 Import, 101 Export, 42 Core); Mac build `/private/tmp/papernest-welcome-mac.log` passed exit 0. No Swift compiler warnings/errors. Claude's concurrent backend additions account for count changes; Codex changed no backend. Welcome simulator checks pending.
- Welcome phone first run `/private/tmp/papernest-welcome-phone.log` failed: an identifier on the outer container propagated to the button and ScrollView, hiding their test identifiers. Removed that container identifier. `/private/tmp/papernest-welcome-phone-final.log`: **2 tests passed**, exit 0, localized first-launch/continue/relaunch and French largest-type continue. Screenshot review prompted smaller illustration spacing and clipping at the safe-area edge; final polish rerun pending.
- `/private/tmp/papernest-welcome-notes-ipad-final.log`: **2 welcome tests passed, 1 Notes test failed**, exit 65. Welcome en/fr/es persistence and largest French type passed in dark mode; screenshots exported. Notes completed English but the French selector used the localized system label “Sidebar”, so dragging again landed outside the editor. Changed it to locate the sidebar by the stable Home button identifier; rerun pending.
- Final welcome phone polish `/private/tmp/papernest-welcome-phone-polished.log`: **2 passed**, exit 0. Inspected en/fr/es and maximum French type screenshots: English/Spanish full intro fits, French third feature requires scrolling, CTA stays fixed; scrolled text now clips below the status area. Final Mac compile `/private/tmp/papernest-welcome-mac-polished.log` passed, no Swift warnings/errors. `/private/tmp/papernest-welcome-unit-final.log` again passed **423 tests** after localized copy changes. Standard Xcode AppIntents metadata/OS-version diagnostics remain toolchain messages, not Swift compiler warnings.
- Fresh read-only reviews: Notes empty-page toolbar loss fixed and covered by deletion/undo workflow. Welcome Mac subtitle no longer mentions camera scanning in French/Spanish. No additional concrete review findings.
- Final iPad `/private/tmp/papernest-notes-ipad-localized.log`: **2 passed**, exit 0. Full Notes workflow passed in en/fr/es (direct tools, scroll both directions, shape save, history, page creation/cancel, Comments, last-page deletion and recovery); final clipped welcome remains usable at maximum French type in dark mode. The two intermediate iPad Notes failures above are resolved by a locale-independent sidebar selector plus viewport-aware gestures. Saved toolbar screenshots in en/fr/es; inspected French plus earlier English layout. Welcome screenshots inspected in all three languages on both devices and maximum French type; iPad restored to light.
- Scope: focused regressions, not a complete app suite or accessibility audit. No files staged or committed.
- Native Mac interaction, VoiceOver, new largest-type Notes audit, real Pencil/camera, prior rotation and annotation-audit failures are not cleared by these runs.


## Premium reference redesign — Codex, 2026-10-27 (implemented; open verification findings)

- Owner deferred Vault and VPN to the next version. No protection UI or fake states added. Live dashboard uses real summaries and existing notebook/import/folder flows.
- First Mac build passed, exit 0: `/private/tmp/papernest-premium-build.log`. Later navigation changes still being checked.
- Full unit command `/private/tmp/papernest-premium-unit.log` exited 1: UI 64, Store 123, Import 77, Core 42 passed; Export ran 89 with two assertions failing in Claude’s active `aMixedDocumentExportedWithAPasswordKeepsEveryPage` at EncryptedExportTests:161/163 (drawn second-page text and title missing). Backend left untouched; this is not a green full run.
- After Claude’s backend fix, `/private/tmp/papernest-premium-unit-final.log` passed 397 tests. Following the accessibility-layout revision and newer shared-tree backend changes, `/private/tmp/papernest-premium-unit-accessible.log` passed **411 tests** (64 UI + 126 Store + 86 Import + 93 Export + 42 Core), exit 0, no compiler warnings/errors.
- Initial phone run: localized notebook creation/reopening and grid/list/crop/export passed; Home Recent failed because the new VStack did not expose a containing accessibility element. Added `.accessibilityElement(children: .contain)`. Xcode subsequently stalled in post-test `simctl diagnose`; interrupted only this run/diagnostic child (exit 75). Later runs use `-collect-test-diagnostics never` plus 900-second timeout; no test failures are suppressed.
- `/private/tmp/papernest-premium-phone-final.log`: **5 tests passed**, exit 0. Recent opening/See All, grid/list → rotate/crop/export, en/fr/es dashboard notebook creation/reopening, actual folder creation, and largest-type notebook entry. `/private/tmp/papernest-premium-ipad.log`: **4 passed**, exit 0, dark mode: same localized dashboard flow, folder creation, largest-type entry, and Home → Favorites → Home → same Favorites plus multi-character global search. Screenshots inspected in all three languages.
- Screenshot review found poor largest-text phone branding/tab wrapping despite the interaction test passing. Revised header to stacked text/settings, bottom navigation to a full-width menu at accessibility sizes, shortened localized compact action labels, made decorative action icons fixed-size, replaced the large-type Recent segmented picker with a menu, and hid large-type sidebar badges to free label width. New phone regression assertion rejects a fragmented multi-line brand. Final phone rerun `/private/tmp/papernest-premium-phone-accessible.log` passed both localized dashboard and largest-type tests, exit 0; inspected and replaced screenshots. Brand now fits on one line; compact en/fr/es action labels fit. Final Mac build `/private/tmp/papernest-premium-mac-accessible.log` passed, exit 0, no Swift compiler warnings/errors.
- Read-only independent review found retained Home selection, search field destruction after the first character, and missing dashboard drop/paste import. Fixed with an explicit sidebar binding, search submission into All Documents, and dashboard drop/paste handlers. Native Mac drop/paste interaction remains unrun.


### Final coverage and limits

- `/private/tmp/papernest-premium-ipad-accessible.log` passed the largest-type interaction and an initial rotation smoke check. **Do not count that initial rotation check as landscape coverage:** screenshot inspection showed portrait. Strengthened the test to rotate after launch and assert actual window dimensions. `/private/tmp/papernest-premium-ipad-landscape.log` then **failed**, exit 65: app remained 1024×1366 after requesting landscape. Both source and built Info.plist allow all four iPad orientations. Cause remains unresolved; no orientation entitlement or fullscreen workaround was added. `testPremiumLandscapeDashboard` remains an unsuppressed regression check. Screenshot retained as `premium-home-rotation-attempt-ipad.png`, not advertised as landscape.
- Final iPad largest-type screenshot shows readable dashboard controls and an adaptive Recent menu; **sidebar “All Documents” still hyphenates awkwardly** in the system-constrained column, even with badges removed. Not claimed fixed. Phone maximum-type header and bottom navigation no longer fragment their words. These are visual/interaction checks, not a passing full accessibility audit.
- Saved/inspected `docs/screenshots/premium-home-{en,fr,es}-{iphone,ipad}.png`, matching library images and both largest-type images. Phone light, iPad dark. iPad appearance restored to light. No real documents or invented production folders/users were used.
- Native Mac build is verified; native Mac clicking, keyboard shortcut/focus/hover behavior, drag/paste interaction, VoiceOver, Reduce Motion/Transparency interaction, narrow multitasking windows and real camera capture remain unrun. Computer-use tools are still unavailable. Existing annotation audit failures and the prior Thick-width test failure remain open in the preceding audit record.
- Reference differences are deliberate where no service exists: owner deferred Vault/VPN; no fake profile/avatar, Shared collaborators or encrypted storage. Note action opens the real notebook editor, not a new rich-text service. Native camera remains VisionKit; Mac has no camera shortcut without a capture implementation. Folder names/data stay user-owned; no sample folders are seeded. Global search uses the native search field, without a new ⌘K command. The entire reference brief is **not claimed complete**.
- All changes left uncommitted and unstaged. Review findings resolved in UI only; Claude’s backend changes untouched. Build/test timeouts: 600 seconds units/Mac, 900 seconds XCUITest. Xcode logs its existing AppIntents metadata and OS-build diagnostics; no Swift compiler warnings found in the final builds.

## UI readability polish — Codex, 2026-10-26 (superseded by reference redesign; open audit findings)

- UI-only: adaptive shape/stamp chooser at ordinary sizes, full-width stroke-width rows at accessibility sizes, primary-contrast wrapping help and Add Comment text, wider text-first iPad sidebar at accessibility sizes. Existing L10n en/fr/es strings reused; no backend changes.
- Full unit suite **360 passed** (64 UI + 123 Store + 77 Import + 54 Export + 42 Core), exit 0, no compiler warnings/errors: `/private/tmp/papernest-polish-unit-final.log`. Mac build exit 0, no compiler warnings: `/private/tmp/papernest-polish-mac.log`. Both bounded to 600 seconds.
- Localized shape/stamp/comment flows passed on phone (light) and iPad (dark), en/fr/es. Reviewed source units and Mac build also passed: `papernest-polish-unit-reviewed.log`, `papernest-polish-mac-reviewed.log`.
- `/private/tmp/papernest-polish-ipad.log` failed overall: the unsuppressed four-sheet accessibility audit still flags Dynamic Type, Style contrast and comment clipping. The largest-type flow reached Line width but lost the sheet after tapping Thick; cause not resolved, and that flow is **not passed**. Its slider screenshot confirms wider text-first sidebar labels. Keep this separate from later dashboard tests. New reference redesign supersedes colors; native Mac/VoiceOver and real-device camera are still unrun. Nothing staged or committed.

## Text to PDF — Claude, 2026-10-26

Half of ledger row 33, and the reference converter's "Text to PDF". A `.txt` was kept as an opaque file item — previewable and shareable, but with no pages, so it could not be annotated, cropped, reordered or exported. `TextToPDF.render` lays it out with CoreText and `DocumentImporter.importTextAsDocument` puts the result through the ordinary import path, so it becomes a normal document. No schema change, no new strings.

- **Pagination is real, not estimated, and that is the point of the slice.** `CTFramesetter` breaks the lines and `CTFrameGetVisibleStringRange` reports how much of the string each page actually consumed. Estimating by character count falls apart as soon as a line wraps, and whatever runs past the bottom of the frame is silently lost — a conversion that looks clean and is not. `textLongerThanAPageBreaksAcrossPagesWithNothingLost` probes lines 1, 50, 99, 100, 101, 150 and 200 **by number** across the break, so a dropped line is obvious rather than plausible.
- A line wider than the page wraps rather than clipping — all 80 occurrences of the probe word survive — and a single unbreakable 400-character word still appears, so CoreText's character fallback is exercised rather than assumed.
- **The pages carry real text, not a picture of it**, proved by extracting it back with `PDFTextExtractor` from the vector-PDF indexing slice. A converted document is therefore searchable by its own words with no recognition involved, which `theConvertedDocumentIsSearchableByItsOwnWords` asserts alongside `recognition(for:) == nil`. That round trip is the strongest available evidence that nothing was dropped.
- **Conversion is explicit.** Importing a `.txt` still stores it as a file item exactly as before; `importingATextFileNormallyStillKeepsItAsAFile` pins that, because keeping a file as the bytes it arrived with is the right default and existing behaviour depends on it.
- Empty or whitespace-only text is refused with `ImportError.empty` rather than producing a blank one-page document, and the refusal leaves nothing in the library.
- Test-first reds: 16 × missing `TextToPDF`, then 8 × missing `importTextAsDocument`. A missing `import PaperNestCore` was corrected before the green run. Greens: `green-txt2pdf.log` (7), `green-txtconv2.log` (12).
- **Final full suite: 360 passed** (64 UI + 123 Store + 77 Import + 54 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-txt2pdf.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED.
- **Not run / not claimed:** **no UI offers the conversion** — there is no "Text to PDF" action in any screen, so this is not user-reachable. No independent reviewer pass; no native Mac, iOS interaction or real-device check. Helvetica at 11pt on A4 with 54pt margins is hard-coded: no font, size, paper or margin choice, and no right-to-left or vertical-script handling has been tested beyond the Cyrillic and Japanese strings in `accentsAndNonLatinTextSurvive`. DOCX, XLSX and PPTX to PDF are not here; they need a real Office renderer and belong to the F5 decision.
- Plan: `docs/superpowers/plans/2026-10-26-text-to-pdf.md`. Nothing committed.

## SQLite text truncation at a NUL — Claude, 2026-10-26

The finding from the DOCX slice, fixed. `SQLiteDatabase.bind` passed `-1` to `sqlite3_bind_text`, and `Statement.text` read with `String(cString:)`, so **both directions stopped at the first NUL** and one unprintable character took the rest of the string with it, silently. Both now use explicit byte counts.

- **The blast radius was narrowed before choosing a fix**, rather than patching the call site that happened to surface it: item and folder names are already sanitized at the edge (`LibraryModels.swift:118` filters control characters); `original_filename` comes from a filesystem where NUL cannot occur; and a recognition result travels as JSON, where a NUL is the escape `\u0000` and survives. What was genuinely reachable was text from recognition or a PDF flowing into `search_index.content`, which made a document **silently and partly unsearchable**.
- **Fixed the mechanism, not that one path.** `-1` plus `String(cString:)` is a trap for every text column anyone adds next, and the store is meant to be the single authority for metadata — one that does not return what it was given undermines that. `sqlite3_column_bytes` is called after `sqlite3_column_text`, which is the order that fixes the column's type and so its length.
- **The open question was whether FTS5 tolerates a NUL in content, and the test decided it rather than a guess.** It does: `wordsAfterANULAreStillFindable` passes, so `unicode61` treats it as a separator and the word after it indexes normally. The planned fallback — sanitizing indexed text at the edge, following the precedent names set — is therefore **not** needed, and no lossy cleanup was added that nothing requires.
- Test-first red, unusually legible: `red-nul.log` shows `"Before\u{0}After" → "Before"`, with round-trip, searchability and reopen-persistence failing while the ordinary-text control passed — which is what showed the defect was narrow rather than a general text regression. Green: `green-nul.log` (4 tests).
- **Final full suite: 348 passed** (64 UI + 123 Store + 65 Import + 54 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-nul.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. **This is the point of that run:** the change sits in the hot path of every text read and write — names, OCR, comments, tags, migrations, the search index, localization parity, the pixel-probe export checks — and nothing moved. Four focused tests would not have been evidence that it is safe.
- **Not run / not claimed:** no independent reviewer pass. No existing library has been opened with the new read path, only libraries created during the tests, so a migration-era database with unusual bytes is unexercised; nothing in the change is schema-dependent, but that is reasoning rather than a test. No native Mac, iOS interaction or real-device check. A NUL can now be stored, so anything that later renders stored text should strip control characters at its own edge the way the DOCX writer does — that is presentation, not storage.

## Basic DOCX export — Claude, 2026-10-26

F4's last export deliverable ("TXT and basic DOCX") and half of ledger row 34. A `.docx` is a ZIP of XML parts, so this writes the three a word processor needs — `[Content_Types].xml`, `_rels/.rels`, `word/document.xml` — through the existing `ZipWriter` rather than adding a dependency. Text follows the plain-text writer's precedence: recognition first, then the text a digital PDF carries; one paragraph per recognized line, an explicit page break between pages. **Basic means the words in a real Word file, not layout**: tables, columns and positioned images stay F5 rather than being approximated.

- **Escaping is the correctness story.** Recognized text is whatever was printed on the paper, so an ampersand is ordinary; one unescaped `&` or `<` yields a file no word processor can open. `ampersandsAndAnglesAreEscapedSoTheFileStillParses` feeds it `Tom & Jerry <b> "quoted" 5 > 3` and then parses the output with `XMLParser`. Characters XML 1.0 forbids are dropped rather than written, since one would make the whole document unreadable.
- Structure is verified **independently of the writer**: `/usr/bin/unzip` lists the parts and extracts them, and `XMLParser` parses `word/document.xml`, `[Content_Types].xml` and `_rels/.rels`. Same refusal as TXT: a document with no text throws `noTextToExport` instead of producing an empty Word file.
- Test-first red: 4 × missing `ExportFormat.docx`. Green: `green-docx3.log` (8 tests).
- **A finding in the store, recorded not fixed.** `SQLiteDatabase.bind` calls `sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)` at `SQLite.swift:170`. Length `-1` makes the C API read to the NUL terminator, so **any string containing a NUL is silently truncated on the way into the database.** Found because a control-character test fed text through `indexEmbeddedText` and the text arrived as `Before` instead of `Before\0After\1End`. Not changed here: storing raw NULs in text columns is not obviously better than dropping them, item names are already sanitized deliberately (`cleansControlCharactersAndEmptyNames`), and changing bind semantics mid-feature would touch every text column. Worth a decision of its own. The test now uses the path where the escaper genuinely matters — a recognition result travels as JSON in `page_recognition`, where a NUL is the escape `\u0000`, survives storage and decodes back — so the drop behaviour is really exercised.
- **A build failure of my own making, worth knowing about.** The first run died on `codesign: invalid or unsupported format for signature` for `PaperNestImportTests.xctest`, with no compile error and no concurrent build. The bundle had been corrupted when I killed `swift-test` mid-build during the Vision deadlock investigation hours earlier, in the build cache both sessions share. Removing that one bundle fixed it. Killing a build here leaves debris that resurfaces later looking unrelated.
- **Final full suite: 344 passed** (64 UI + 119 Store + 65 Import + 54 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-docx.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED.
- **Not run / not claimed — the important one: nobody has opened the file in a word processor.** Structure is checked by `unzip` and `XMLParser`, which proves it is a well-formed OOXML package, **not** that Word, Pages or Google Docs renders it. That is whole-app verification and is recorded as owed in `docs/CODEX_BRIEF.md`; this must not be offered in any screen until someone has opened one. Also not here: no UI (no DOCX tile), no independent reviewer pass, no native Mac or iOS interaction check. Ink, text boxes and page comments are not exported; only recognized and embedded text is. Layout, fonts, styles, headers, images and tables are absent by design.
- Plan: `docs/superpowers/plans/2026-10-26-docx-export.md`. Nothing committed.

## App verification backlog — Codex, 2026-10-26 (first pass; open findings)

- Read CODEX_BRIEF, current ownership/claims and Vision trap before editing. No backend files changed; no staging or commit. Manual recognition in `DocumentModel` now awaits `recognizeOnADedicatedThread` instead of calling synchronous Vision on MainActor. Source inspection confirmed the blocking call; no before/after latency measurement is claimed.
- Full `./scripts/test.sh`: **336 passed** (64 UI + 119 Store + 65 Import + 46 Export + 42 Core), exit 0, no compiler warning/error matches. Log `/private/tmp/papernest-audit-unit.log`. `./scripts/build-mac-app.sh`: exit 0, no compiler warnings, `/private/tmp/papernest-audit-mac.log`. Both ran under 600-second process-group timeouts.
- **iPhone 17 Pro, dark mode: 3 interaction tests passed**, exit 0: `/private/tmp/papernest-audit-phone2.log`, xcresult `Test-PaperNest-iOS-2026.10.26_13-29-53--0500.xcresult`. Largest accessibility text category (`UICTContentSizeCategoryAccessibilityXXXL`) verified visually; notebook creation, shape start-X slider changes its accessible value, system custom-colour grid selection changes the sheet value, shape saves and appears in Manage Markup. Manual Recognize Text → content search also passes (not a latency benchmark).
- **Failed-save UI observed:** a second SQLite connection holds `BEGIN IMMEDIATE` on a unique disposable library. Shape save shows the localized error after the real database timeout, keeps the ellipse draft, and retry after rollback saves exactly one markup row. This is database contention, **not injected disk I/O failure**; disk-full/unwritable-file behavior remains unrun. No production failure hooks or backend changes were added.
- Initial iPhone run failed because the test matched `Close` while UIKit exposed `close`. Captured hierarchy established the cause; corrected to a case-insensitive match, then tested actual colour selection and dismissal. Initial log `/private/tmp/papernest-audit-phone.log`, exit 65. Not an application defect. Xcode emits an AppIntents metadata-extraction warning (no framework dependency) and OS-build parsing diagnostics; no Swift compiler warnings.
- Three iPhone screenshots saved under `docs/screenshots/audit-*-iphone.png`; inspected large-text slider, selected system colour and failure alert. Initial iPad run `/private/tmp/papernest-audit-ipad.log` exits 65: failed-save/retry passes, large-text test fails locating an offscreen menu entry (test must scroll), and automated audit **fails Dynamic Type** on the native Shape toolbar Add button. Audit attachment says the user cannot change this element's font size; its element screenshot shows Add. The audit stopped at the first surface, so the other sheets were not audited in that run. Investigation and full finding collection are in progress; this is not a passing accessibility check.
- **Expanded iPad automated audit remains failing:** `/private/tmp/papernest-audit-ipad2.log` collected all four surfaces rather than stopping at the first failure. Findings: Shape Add/Cancel Dynamic Type; Stamp Add/Cancel and placement-help Dynamic Type, Style contrast and a clipping flag; Comments Done Dynamic Type, Add Comment contrast/clipping; Manage Markup Done Dynamic Type. These are audit findings requiring triage, not a VoiceOver certification. Normal-size screenshots show readable content; some flags concern scroll-boundary content, so do not assume every flag is visible truncation. Evidence: `docs/screenshots/audit-accessibility-audit-editor-*-ipad.png` and xcresult attachments. No audit issue filter or expected-failure suppression was added.
- A controlled typography experiment set Shape/Stamp toolbar buttons to `.font(.body)`; `/private/tmp/papernest-audit-ipad3.log` still reported toolbar Dynamic Type failures. **Rejected and reverted**, so no unsupported typography fix remains. The large-text iPad automation also needed to scroll inside the visible menu viewport (not the offscreen Manage Markup row), and to select the presented Form rather than the background Pages collection. Final control rerun passed; see below.
- **Current-tree recheck after Claude’s backend additions:** 360 unit tests pass (64 UI + 123 Store + 77 Import + 54 Export + 42 Core), exit 0, no compiler warnings/errors: `/private/tmp/papernest-audit-unit-final.log`. Mac build also exit 0, no compiler warnings: `/private/tmp/papernest-audit-mac-final.log`. Both bounded to 600 seconds. These are build/unit outcomes, not a passing accessibility audit.
- iPad custom-picker run `/private/tmp/papernest-audit-ipad-controls.log` reached and adjusted the slider, selected azure from the system grid, then failed trying to tap an AX `close` control that is not visually present in the iPad popover. The screenshot and hierarchy confirm a `PopoverDismissRegion`; test updated to dismiss by tapping outside the popover on iPad, retaining close-button dismissal on iPhone. **Final iPad control rerun passed**, exit 0: `/private/tmp/papernest-audit-ipad-controls-final.log`, xcresult `Test-PaperNest-iOS-2026.10.26_19-03-52--0500.xcresult`. This covers the largest text category in dark mode, menu/form scrolling, changed start-X slider value, actual system colour selection, popover dismissal, save and the resulting markup row. Three iPad screenshots (including the earlier passing failure/retry flow) saved as `audit-*-ipad.png` and inspected. Simulator appearance restored to light after testing.
- Scope limits: these new interactions are **English only**; the older en/fr/es flows were not rerun here. Start-X slider was driven, not all four endpoint sliders. Largest-type coverage is notebook creation and shape/custom-picker navigation, not every recent sheet. Text-markup, notebook-page insertion and comment-editor accessibility still need their own passes. The four-sheet automated audit is intentionally unsuppressed and currently fails; do not report the full XCUITest suite as green.
- **Additional visual finding:** at the largest text category, iPad sidebar labels wrap into short word fragments in the narrow sidebar (visible behind the sheet in the final screenshots). This is a readability issue to address in the next design pass; it was not changed here.
- **Blocked / not run:** no computer-use tools available to this session, so native Mac annotation interaction, VoiceOver listening/navigation and native two-window conflict interaction have not been performed. A successful Mac build does not close these checks. `xcrun xctrace list devices` found only the Mac and simulators, no attached physical iPhone/iPad; real camera capture and M1 gate remain blocked on a device/provisioning. Other save-failure surfaces and injected disk I/O failure still unrun. No new feature surfaces added before this backlog pass.

## Text export (TXT) — Claude, 2026-10-26

F4's outstanding TXT deliverable and row 34's "PDF to Text". A document's words could be searched inside PaperNest but never got out: every export was a PDF or an image. `ExportFormat` gains `.txt`, `ExportError` gains `.noTextToExport`, and a new `TextExport.swift` writes one section per page. No schema change, no new strings.

- **Text comes from the best source the page really has**, never invented: current completed recognition first, because those lines keep their structure, then the text a digital PDF already carries, read back through new `LibraryStore.embeddedText(for:)` and `PageRenderer.embeddedText(for:)` (placed beside the existing `recognizedLines(for:)` so the exporter reaches stored text through the renderer rather than holding its own store reference). `recognizedLinesWinWhenAPageHasBoth` pins the precedence.
- **Pages are separated by a form feed (U+000C)**, the conventional ASCII page break. A worded separator such as "Page 2" would need a localized string in a file another session owns, and would turn a machine-readable file into one in a particular language.
- **A document with no text anywhere is refused** with `noTextToExport` rather than writing a file of nothing but separators and calling it a successful export of an empty document. The throw happens before the write and `export`'s own `catch` removes the directory, so a refusal leaves nothing behind.
- Only text that is **current for the page** can appear: `recognizedLines(for:)` refuses a result from an older revision, and a page's embedded text is cleared when its content is replaced. `rescanningAPageTakesItsOldTextAway` proves the second half, so a rescanned page cannot export words describing paper it no longer shows.
- **Cross-lane surface checked before claiming, not assumed.** Adding to a public `CaseIterable` enum is how one would accidentally change another session's UI. Verified: nothing iterates `ExportFormat.allCases`; the export sheet's format tiles are hand-written one per format, so no tile appears by itself; `contentType(for:)` derives from the file extension, so a `.txt` maps to plain text without help; and `ExportError` is not referenced anywhere in `PaperNestUI`. Both new cases therefore break nothing and surface nowhere.
- Test-first reds: 8 × missing `embeddedText`, then 4 × missing `ExportFormat.txt` and 2 × missing `ExportError.noTextToExport`. Greens: `green-readback.log` (4 store), `green-textexport.log` (7 export).
- **Final full suite: 336 passed** (64 UI + 119 Store + 65 Import + 46 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-textexport.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. Nothing was left in the temporary root.
- **A real limitation, stated rather than hidden:** embedded PDF text is stored normalized for the search index, so its whitespace is collapsed and such a page exports as **one paragraph rather than its original lines**. Good enough to get the words out; not the page's layout. Fixing it means extracting at export time with `PDFTextExtractor`, which lives in `PaperNestImport` — a module `PaperNestExport` does not depend on, so it needs a layout decision (likely the Recognition module ARCHITECTURE already plans) rather than a quick import.
- **Not run / not claimed:** **no UI** — there is no TXT tile in the export sheet, so this is not user-reachable, and a tile should not appear until it works. No independent reviewer pass; no native Mac, iOS interaction or real-device check. DOCX is deliberately not here: it needs a real container writer and validation by opening the result in an external editor. Ink, text boxes and page comments are not exported as text; only recognized and embedded text is.
- Plan: `docs/superpowers/plans/2026-10-26-text-export.md`. Nothing committed.

## File compression — Claude, 2026-10-26

Finishes the gap F2d left: a photo kept as a *file item* could not be reduced at all, which is the everyday "get it under a size limit" case. `LibraryStore.originalByteCount(of:)` now also reads `file_items.byte_count`, so one API sizes both kinds of item, and `Exporter.compress(fileNamed:data:preset:)` re-encodes image bytes through the existing `downsample`/`encode` helpers and returns the same `CompressionResult`. No second way to express a preset, no schema change, no new strings.

- **A file it cannot reduce is refused, not mangled.** Non-image bytes throw `CompressionError.unsupportedFormat`, and every step that can fail runs *before* a temporary directory exists, so a refusal writes nothing. Both are tested.
- **A loose file has no page size**, so a preset's dpi cannot apply; the presets gained a pixel target instead (2400/1600/1200 on the longest edge). Aspect ratio is asserted to within 2%, so nothing is cropped to hit a size.
- The honesty contract is tested as a property rather than a lucky fixture: `originalByteCount` matches the input, `savedByteCount` is never negative, and `isSmaller` always agrees with the byte comparison. Most photos arrive already compressed, so the larger-output branch is the common one; the document-level `anAlreadyCompactOriginalReportsNoSavingRatherThanAFakeOne` covers it concretely.
- Test-first reds: the file-item size test failed returning 0 while the deleted-file guard already passed; then `CompressionError` was missing. Greens: `green-filesize.log` (8 store), `green-filecompress2.log` (13 export).
- **A test defect of mine, fixed in the test rather than the code.** `aRefusedFileLeavesNoTemporaryDirectoryBehind` counted `PaperNestExport-*` entries in the **shared** process-wide temporary root while sibling tests created and removed their own there in parallel, so it measured them rather than itself. `Exporter(renderer:temporaryRoot:)` accepts a root, so the test now owns one. This is the second time that shared root has caused a false failure — see the trap note in SESSION_HANDOFF.
- **Final full suite: 325 passed** (64 UI + 115 Store + 65 Import + 39 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-filecompress.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. Nothing was left in the temporary root.
- **Not run / not claimed:** **nothing here is user-reachable** — there is no Compress action in any screen, so this produces bytes and numbers for a UI that does not exist yet, and it should not ship until that UI shows the real before/after rather than a promise. No independent reviewer pass; no native Mac, iOS interaction or real-device check. Only image files are reducible: a PDF *file item* is refused, because shrinking one means rasterizing pages, which would destroy selectable text exactly as it would for a document. Replacing a stored file with its reduced copy, or saving the copy as a new item, is a separate decision and is not done here. Folder and archive compression remain.
- Plan: `docs/superpowers/plans/2026-10-26-file-compression.md`. Nothing committed.

## Compression presets (F2d) — Claude, 2026-10-26

Size reduction on purpose, with measured before-and-after bytes. Row 35 was Partial because export quality tiers existed but nothing was presented as compression and no size was ever compared. `CompressionPreset` (`light`/`strong`/`smallest`) maps to explicit dpi and JPEG quality; `Exporter.compress` writes the PDF and returns a `CompressionResult`; `LibraryStore.originalByteCount(of:)` supplies the "before" — the originals the live pages are made of, a shared original counted once, deliberately **not** the size of a previous export, whose size would depend on the settings it was made with. Engine only: no UI, no schema change, no new strings.

- **The honesty behaviour is the point of this slice, and it is tested both ways.** Re-encoding an already-compact original makes it *larger*; `anAlreadyCompactOriginalReportsNoSavingRatherThanAFakeOne` asserts the output really is bigger as a precondition, then that `isSmaller == false` and `savedByteCount == 0`. A negative saving is never dressed up as a positive one. `reportsTheSavingItActuallyMade` checks the saving equals the measured difference when there is one.
- **A vector PDF cannot be shrunk by this path, by design.** `pdfSource` passes vector pages through untouched, because rasterizing text to save bytes destroys both quality and selectable text. `aVectorPDFKeepsItsTextInsteadOfBeingRasterizedToSaveBytes` asserts the text is still extractable from both pages at the `smallest` preset. This was not "fixed" by rasterizing.
- **`PDFImageQuality`'s cases are deliberately unchanged.** It is `CaseIterable` and drives the export sheet's picker, so a fourth case would have appeared in that UI unbidden. An internal `RasterQuality` carries a preset's dpi and quality, `PDFImageQuality` gained a computed `rasterQuality`, and an internal `export(…rasterQuality:…)` overload threads it to the private PDF path. The public API and the picker are untouched.
- Test-first reds: 12 × missing `originalByteCount`, then missing `CompressionPreset`/`CompressionResult`. Greens: `green-itemsize.log` (6 store), `green-compress.log` (7 export).
- Coverage: a document's size equals its original's; a shared original counted once; two originals add up; a deleted page and a document in Recently Deleted excluded; a template-page notebook reports zero; a stronger preset really produces a smaller file and `smallest` smaller still; the output is a valid PDF keeping every page; compression leaves `modified_at`, page revisions and the originals untouched; the output directory is removable and leaves nothing behind.
- **Final full suite: 317 passed** (64 UI + 113 Store + 65 Import + 33 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-compress.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. The run re-checked the exporter's temporary root and found nothing left behind.
- **Not run / not claimed:** no UI, so nothing is user-reachable yet — a Compress action belongs with whoever owns the sheets, and it must not ship until it shows these real numbers. No independent reviewer pass; no native Mac, iOS interaction, real-device, VoiceOver or Dynamic Type check. `originalByteCount(of:)` covers **page-based items only**: a general file item keeps its size on its own payload and is not counted, so compressing a stored photo or PDF *file* remains to do. Image-format output (JPEG/PNG presets) and folder/archive compression are not part of this.
- Plan: `docs/superpowers/plans/2026-10-26-compression-presets.md`. Nothing committed.

## Automatic text recognition — Claude, 2026-10-26

Text is now read without being asked. Previously nothing was searchable by its contents until the user opened **More → Recognize Text** page by page, and a rescanned page kept its old, wrong text. Built in the shape of `EmbeddedTextIndexer`: `LibraryStore.pagesNeedingRecognition(engineVersion:limit:)` names the work, `AutomaticTextRecognizer` (actor, batched, cancellable) does it, and `LibrarySession` runs it after the library is ready and after each change, coalesced. No schema change (`page_recognition` already carried `source_revision`, `status` and `engine_version`) and no new strings. The existing render → recognize → `saveRecognition` path is reused, so recognition itself is unchanged.

- Work is decided from stored state, not a queue, so a pass is interruptible and resumable: a page qualifies with no result, a `source_revision` that no longer matches (a rescan), a `pending` result, or a different `engineVersion`. A **failed** result for the same paper and engine is left alone, so an unreadable page is not retried every launch — a rescan or an engine change earns another attempt.
- **Pages that already carry their own text are skipped.** A non-empty `pdfText` row means a digital PDF's real words are already indexed, and recognizing a raster of those words would be worse; an *empty* marker (a scan with no text layer) is exactly the OCR case. This is what the previous slice's marker made possible, and **the launch order is load-bearing**: embedded text runs before recognition, with a test that fails if it does not.
- Test-first reds: `red-task1.log`-equivalent runs failed on the missing `pagesNeedingRecognition` and `AutomaticTextRecognizer` APIs; the launch test failed on the renamed `backgroundTextWork`. Greens: `green-recog-task1.log` (11 store), `green-recog-task2.log` (6 pass), `green-recog-launch.log` (3 launch).
- **A deadlock I introduced, found and fixed — worth reading before touching Vision.** The first full run **hung for four hours**. Two targets had passed, then `PaperNestImportTests` froze with no compiler or test process doing work. A `/usr/bin/sample` of the stuck process showed five of the new tests simultaneously inside `AutomaticTextRecognizer.recognizeMissing`, all parked in `semaphore_wait_trap` under `-[VNControlledCapacityTasksQueue dispatchSyncByPreservingQueueCapacity:]`. **Vision's task queue dispatches synchronously**, so `recognize(_:)` parks the thread it is called on until Vision has capacity; called from an actor that is a Swift concurrency cooperative thread, of which there are about one per core, and enough concurrent recognitions park every one — including the threads Vision needs to finish the work the others wait on. The existing Vision tests never hit it because their `@Test` functions are **synchronous** and run on ordinary threads.
- The first hypothesis was tested and **rejected**: a 6-way concurrent regression passed in 1.2 s on this 8-core machine, because two threads stayed free to drain Vision. Two experiments settled it — the Import target run with `--no-parallel` passed 65 tests in 4.17 s, and raising the regression to **16 concurrent passes** reproduced the hang deterministically. Fix is the root cause, not the symptom: `TextRecognizer.recognizeOnADedicatedThread(_:)` runs the blocking call on its own serial queue, off the cooperative pool. Marking the suite `.serialized` was deliberately **not** done; it would have hidden this in tests while leaving production able to park the pool. Evidence: 16 concurrent passes went from an indefinite hang to 2.703 s, and the original failing scenario (Import target, parallel) passes 65 tests in 3.245 s.
- **Final full suite: 304 passed** (64 UI + 107 Store + 65 Import + 26 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-recog2.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. The run re-checked the exporter's temporary root and found nothing left behind. The Core target reports one more test than the previous slice's run because Codex's committed stamps work grew `ShapeAnnotation` from four kinds to seven, which its parameterized geometry test covers; nothing here touched Core.
- **Still blocking the main thread, and not mine to change:** `DocumentModel.recognizeText(on:)` calls the synchronous `recognize(_:)` on the MainActor, so manual recognition stalls the UI for as long as Vision takes. It cannot deadlock the way the pass did, but it should adopt `recognizeOnADedicatedThread(_:)`. That file belongs to whoever owns `DocumentModel.swift` next.
- **Not run / not claimed:** no independent reviewer pass; no XCUITest for automatic recognition on iPhone or iPad; no native Mac or real-device check; no VoiceOver, Dynamic Type or sanitizer run. **The cost of a first-launch sweep over a large library is unmeasured** — the pass is low priority, batched and resumable, but OCR of hundreds of unread pages has not been timed. The user language override and the recognition status surface are deliberately out of scope.
- Plan: `docs/superpowers/plans/2026-10-26-automatic-recognition.md`. Nothing committed.

## Symbol stamps — Codex, 2026-10-26

- Checkmark, cross and five-point star presets save as one ink object per stamp. Reuses exact Page snapshot validation, history, Manage Markup and export; schema unchanged. Native sheet has a dedicated Stamp mode and separate preset list; ordinary Shape mode retains its default rectangle.
- Test-first RED: `/private/tmp/papernest-stamps-red.log` (missing presets/list APIs). Focused GREEN: `-focused.log` (6 tests with expanded parameter cases): all presets under crop/quarter-turns/reversed drags; invalid narrow boxes; PencilKit corner preservation; real model save/reopen/PDF pixel output and page-add/stamp mixed undo/redo.
- Full suite **284 tests passed** (62 UI + 96 Store + 58 Import + 26 Export + 42 Core), no compiler warning/error matches: `/private/tmp/papernest-stamps-unit.log`. Mac build passed: `-mac.log`.
- Fresh independent read-only review found no concrete issues.
- iPhone 17 Pro localized workflow **passed en/fr/es**: `/private/tmp/papernest-stamps-phone.log`, xcresult `Test-PaperNest-iOS-2026.10.26_07-40-43--0500.xcresult`. Checks ordinary Shape mode still defaults to rectangle, Stamp defaults to checkmark, cancellation leaves no ink, all stamp selectors, actual drag coordinate change, color selection, save, undo/redo and relaunch persistence. Three screenshots inspected/saved as `docs/screenshots/stamp-placement-*-iphone.png`; labels/actions fit and star placement matches its preview. iPad Air 13-inch (M4) passed the same en/fr/es workflow: `/private/tmp/papernest-stamps-ipad.log`, xcresult `Test-PaperNest-iOS-2026.10.26_07-46-09--0500.xcresult`. Three iPad screenshots inspected/saved as `stamp-placement-*-ipad.png`; labels and preview fit, style controls are reached by scrolling. No implementation changes after the passing full suite or review. The complete device suites were not repeated.
- Scope: symbol stamps only, not text/status stamps or custom-image stamps. No native Mac stamp interaction, real-device Pencil, VoiceOver/large type, system custom-picker/endpoint-slider interaction, new sanitizer or image-specific export pixel test claimed; shared export rendering is reused and PDF output is tested.


## Shared-asset backup fix — Claude, 2026-10-25

`SettingsView.startBackup` and `BulkExportModel.start` resolved a file item's original with a hardcoded `kind: .file`, while the audited preview path resolves the asset record's own kind. `assets` is keyed by SHA-256 and its insert is `ON CONFLICT(id) DO UPDATE SET availability = 'local'`, so the row keeps the kind of whichever import arrived first, and `AssetFileStore.url(for:kind:)` names the file from that kind. A file item sharing an original stored as a PDF therefore resolved to a `.bin` that was never written. `LibraryBackup` reads each entry with `Data(contentsOf:)` and its `catch` deletes the working directory and rethrows, so **one such item failed the entire Settings backup and the entire bulk ZIP export**, not just its own entry. This was the regression the handoff asked for before touching those paths.

- Test-first red: `red-assetkind.log` — new `SharedAssetBackupTests` failed on both paths because the export never became ready (`model.output` and `model.backupOutput` both nil). The scenario is built with the public `createFileItem` taking an asset staged as `.pdf`, the same construction the existing `previewResolvesTheRecordedKindOfASharedAsset` test uses, so it is reachable rather than hypothetical.
- Fix: a single `LibraryStore.originalURL(for:)` that resolves the record's kind and throws `assetMissing` when there is no row, with both call sites using it. A resolver rather than two corrected call sites, because the bug was two sites diverging from one correct one. Green: `green-assetkind.log`.
- **A sweep confirmed these were the only two.** Every remaining `assets.url(...)` / `assets.read(...)` / `assets.remove(...)` call in `Sources` now takes its kind from a record or a database row: `LibraryStore` lines 73, 292, 853, 860, 873 and 933, `EmbeddedTextIndexer`, and `FileItemViews`. No hardcoded asset kind remains in the codebase.
- **A mistake of mine, and what it exposed.** My two new tests produced `ExportOutput`s without removing their temporary files, which broke the pre-existing `cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind`: it asserts that `exporter.temporaryRoot` — the process-wide system temp directory — holds no `PaperNestExport-*` entry. Only the full suite caught this; my focused run passed. Fixed by deferring `removeTemporaryFiles()` in both tests. The run after that still failed, on four stale directories left by the two pre-fix runs; removing them made the suite green. Worth knowing: **that test fails on residue from any earlier crashed or failed run**, because it asserts on shared global state rather than on directories the test itself created. Not changed here, since it is not my test, but it is a real fragility.
- **Final full suite: 283 passed** (62 UI + 96 Store + 58 Import + 26 Export + 41 Core), exit 0, **0 warnings**, 0 failures: `verify-assetkind3.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. The same run re-checked the temporary root afterwards and found **0 leftover export directories**, so the cleanup is verified rather than assumed.
- **Not run / not claimed:** no independent reviewer pass; no native Mac or iOS interaction check of Settings backup or the bulk export sheet (both are driven here through their models, as the existing bulk-export tests do); no real-device, VoiceOver or Dynamic Type run. No schema, localization or layout change.
- **Still open, deliberately.** The underlying first-writer-wins kind is unchanged: the same bytes arriving under two kinds still produce two physical files (`<sha>.pdf` and `<sha>.bin`), so content-addressed dedup is defeated across kinds and the second file is only swept once the row is gone. Every reader is now consistent, so this is storage waste rather than a correctness bug. Fixing it properly means either making `assets.kind` authoritative on conflict or naming files by hash alone, which is a file-layout change and a larger slice than this.

## Vector PDF text indexing — Claude, 2026-10-25

Digital (vector) PDFs are now findable by their own body text, not only by their title. A fourth `search_index` field, `pdfText`, sits beside `title`, `ocr` and `text`; no migration (FTS5, `field` unconstrained, index derived and rebuildable), schema stays v7, and no new user-visible strings. Indexed text is deliberately **not** keyed to `page.revision`: the words come from the immutable original, so a crop, rotation or ink stroke leaves them true. Only `replacePageContent` (the single page-content write path, which rescan undo and redo both re-enter) clears them.

- Test-first, API-missing reds: `red-task1.log` (16 × missing `indexEmbeddedText`, 2 × missing `pagesMissingEmbeddedText`), `red-task2.log` (missing `EmbeddedTextIndexer`, then 4 genuine behavioral failures: rescan did not clear the old words or requeue the page, and duplication did not carry them). Batch and URL extractor APIs also run red on argument labels before implementation. Greens: `green-task1.log`, `green-task2.log`, `green-launch.log`, `green-batch.log`, `green-url.log`. Logs are session-local under this session's scratchpad, not `/private/tmp`.
- **Final full suite (after the performance fix): 281 passed** (60 UI + 96 Store + 58 Import + 26 Export + 41 Core), exit 0, **0 compiler warnings**: `verify-final.log`. That is the measured 259-test baseline plus exactly the 22 tests added here (10 Store, 11 Import, 1 UI). The run included Codex's uncommitted shape-annotation work, so it is not a clean-tree baseline.
- **Final Mac build passed** (`scripts/build-mac-app.sh`, exit 0, 0 warnings) and **iOS Simulator build of `PaperNestUI` passed** (`xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator'`, BUILD SUCCEEDED).
- Coverage: per-page extraction from a vector PDF; no text from a scanned page, an out-of-range index or non-PDF bytes; several pages read in one parse; reading an original off disk and a missing file; body words found by `search` when the title does not match; an empty marker row recorded for a page with no text layer, which answers no search and stops the page being read again; a write rejected when the page no longer shows the content the text came from; reindexing replacing rather than accumulating; indexing leaving `modified_at` and `revision` untouched; a missing page rejected; rescan clearing the old words and requeueing the page; a look-only edit keeping words findable; duplicate/merge/extract carrying the text and the marker; delete removing it with `integrityCheck` clean; a second indexer pass over a scanned PDF having nothing to do; image pages left alone; and opening a library making its digital PDFs findable while launch still completes first.
- A new `scannedPDF` fixture (raster content, no text layer) was added to `Tests/Support/SyntheticDocuments.swift`, so "looked, found nothing" is distinguishable from "not looked at".
- Originals are read off disk through the asset record's own kind (the pattern `FileKind.prepareTemporaryCopy` uses), so PDFKit memory-maps them and indexing a large PDF does not hold the whole file in memory. **The memory behavior is reasoned and mapped, not measured**; no large-PDF performance run was done.
- **Measured and fixed a stall on the store actor.** The first version of `pagesMissingEmbeddedText` used a correlated `NOT EXISTS` against `search_index`, whose `page_id` is an `UNINDEXED` FTS5 column, so the check scanned the whole index once per page. Probed on a 2,000-page library (200 documents × 10 PDF pages): **0.300 s with everything already indexed**. That query runs on the store actor from `didChange()`, which has ~29 call sites including ink and undo, so it blocked user edits on every stroke. Reading the already-checked set once instead — `p.id NOT IN (SELECT page_id FROM search_index WHERE field = ? AND page_id IS NOT NULL)` — brings it to **0.0019 s (155× faster)**; the all-missing case went 0.0455 s → 0.0022 s. The `page_id IS NOT NULL` is required: title rows carry a NULL page id, and a single NULL inside `NOT IN` makes the whole query match nothing. The probe was a throwaway, so these numbers are **not** reproduced by `./scripts/test.sh`.
- Two follow-ups from self-review, both fixed with the measurement above: pages whose original is not on this device are no longer fetched at all (a `JOIN assets ... availability = 'local'`), so 50-plus `remoteOnly` pages at the front of the sort order cannot starve every local PDF behind them once sync exists; and `PDFTextExtractor.text(at:)` now returns nil when a file cannot be opened, distinct from opening it and finding no text, so an unreadable original is retried on a later pass instead of being marked permanently checked.
- Library changes arriving during a pass are coalesced into one further pass rather than queueing one each, so a burst of strokes costs one indexed lookup that finds nothing to do.
- **Not run / not claimed:** no independent reviewer pass. Author self-review plus one advisory review found the store-actor stall, the starvation case and the unopenable-file case above; all three are fixed, and no second pass was made over the fixes. Also: no XCUITest for searching by PDF contents on iPhone or iPad; no native Mac interaction check; no real-device, VoiceOver, Dynamic Type, dark-mode or sanitizer run; no localization change, so no new layout checks. The `LibrarySession` launch hook is covered by one unit test that awaits the pass; it has not been observed in a running app.
- **Known limitation, inherited from recognized text:** a soft-deleted page's words stay findable until the next launch purges them, because `search()` filters deleted items but not deleted pages. This matches existing `ocr` behavior and was not changed here.
- Plan: `docs/superpowers/plans/2026-10-25-pdf-text-indexing.md`. Nothing committed or pushed.

## Shape annotations — Codex, 2026-10-25

- Integration recheck on 2026-10-26 after Claude’s independent commits: **283 tests passed** (62 UI + 96 Store + 58 Import + 26 Export + 41 Core), no compiler warning/error matches. `/private/tmp/papernest-shapes-integration-final.log`; Mac build passed in `-integration-mac.log`. Shape production code is unchanged from the verified device runs.

- Outlined rectangles, ellipses, lines and arrows save as one editable ink object. Native sheet has drag preview, accessible endpoint sliders, preset/custom color and widths 1/2/4 points; exact Page snapshot and active parent guard the atomic save. No migration (schema stays v7).
- Test-first API failures: `/private/tmp/papernest-shapes-{core,store,model}-red.log`. Focused green: `-focused.log`; crop/rotation/reversed endpoints, invalid geometry/style, stale/deleted parent, reopen, PDF raster output and mixed page-creation/shape undo/redo.
- Mixed history regression first failed in `-history-red.log`; notebook insertion undo now compares semantic page columns, exact objects/OCR/order/deletion stamp, ignoring only cache revision and modified_at after fully undone ink. Existing external-edit conflict coverage retained.
- First full suite caught French colon spacing; corrected four strings to nonbreaking spaces. Initial corrected suite passed 258 tests and Mac build passed.
- Fresh independent review found PencilKit smoothing of sparse corners. Reproduced in `-pencil-red.log`, fixed generated rectangle/arrow control vertices, focused green in `-pencil-green.log`. Rotated/scaled round-trip checks enforce outline deviation <0.5 source point and visits to every corner. One fix pass, no re-review.
- Visual QA caught a false-positive initial phone flow: default arrow remained while the form scrolled. Added localized coordinate accessibility values and a position-change assertion; UI RED in `-drag-red.log`. Priority alone also failed; expanded the gesture frame to match the preview row and offset coordinates back to the centered paper. Position now changes and screenshot confirms the requested direction. Margin scrolling in the test avoids the intentional drawing surface.
- Imported-document history regression RED in `-doc-history-red.log` proved the menu had only exposed history on notebooks. Both document More menus now expose the existing history actions. New imported-PDF add/undo/redo flow included in final device runs. Initial iPad run was deliberately interrupted to replace obsolete gesture code (not a pass).
- Final combined suite: **276 tests passed** (59 UI + 96 Store + 54 Import + 26 Export + 41 Core), including Claude’s concurrently added vector-PDF indexing coverage. Shape-only state previously passed 259 tests. `/private/tmp/papernest-shapes-unit-final.log`; final Mac build passed in `-mac-final.log`. An intermediate combined run hit Claude’s intentionally unfinished indexer API (`-combined-inflight.log`); no unrelated code was changed to fix that.
- Final iPhone 17 Pro: **2 UI tests passed** — localized shape flow en/fr/es plus imported-document add/undo/redo. Position-change assertion, all four kind selectors, cancel-without-save, color selection, saved-mark count, undo/redo and relaunch persistence. Log: `/private/tmp/papernest-shapes-phone-final.log`; xcresult `Test-PaperNest-iOS-2026.10.25_23-06-37--0500.xcresult`. Three screenshots inspected and saved at `docs/screenshots/shape-placement-*-iphone.png`; title/actions and localized labels fit, dragged arrow points in the requested direction.
- Final iPad Air 13-inch (M4): localized shape flow **passed en/fr/es** in `/private/tmp/papernest-shapes-ipad-placement-final.log`, xcresult `Test-PaperNest-iOS-2026.10.25_23-16-30--0500.xcresult`. Three screenshots inspected/saved as `shape-placement-*-ipad.png`. The prior run (`-ipad-final.log`, xcresult `23-12-36`) passed imported-document add/undo/redo and existing finger drawing/history/relaunch; its shape flow failed only because test scrolling used the screen margin outside the centered sheet. Corrected the test to use the form margin beside the preview, then repeated only the affected localized flow. Phone final predates this test-only coordinate correction; all production shape code is the same. No full device suite repetition is claimed.
- Verification limits: Native Mac shape interaction, system custom-picker/endpoint-slider interaction, real-device Apple Pencil, VoiceOver, large Dynamic Type, dark mode and sanitizer checks remain unrun. Image export uses the existing shared ink renderer; the new shape-specific pixel test exercises PDF output.


## Page comments — Codex, 2026-10-25

- New private page comments use schema v7 (widens page_objects kind constraint). Add/edit/delete, exact-object guarded undo/redo, duplicate/reopen persistence; explicitly excluded from PDF/image exports. Existing ink/text/image rows preserved.
- Test-first logs: `/private/tmp/papernest-comments-store-red.log`, `-model-red.log` (missing APIs). Focused green: `-focused.log` (5 store + 2 model tests), covering valid/corrupt migration, text limits, deleted parent/page, stale edit/undo and restored-ID collision, duplication/reopen and PDF export privacy.
- Final full suite: **254 tests passed** (57 UI + 85 Store + 47 Import + 26 Export + 39 Core), no warning/error matches: `/private/tmp/papernest-comments-unit-final.log`. Final Mac build passed: `-mac-final.log`.
- Independent review found mixed comment/page undo invalidation and draft loss in the conflict recovery instructions. Mixed history reproduced red (`-mixed-red.log`); fixed private comment persistence to preserve the rendered page row while touching item modification time. Draft model regression first failed on missing API (`-draft-red.log`); explicit Save as New Comment now preserves both versions. Both regressions green (`-review-green.log`), then full suite passed. No second reviewer pass claimed.
- Initial iPhone UI test reached relaunch but failed a cursor-position assumption: text was inserted at the caret instead of appended. Corrected test captures the actual edited text and asserts exact persistence.
- Final iPhone localized flow passed in en/fr/es: `/private/tmp/papernest-comments-phone-final.log`, xcresult `Test-PaperNest-iOS-2026.10.25_12-41-50--0500.xcresult`. Exercises blank-save disabled, create, edit cancellation, saved edit, deletion, undo/redo and relaunch persistence. All three editor screenshots inspected; title/actions and export notice fit above keyboard (`docs/screenshots/page-comment-editor-*-iphone.png`).
- iPad Air 13-inch (M4) localized flow passed in en/fr/es: `/private/tmp/papernest-comments-ipad.log`, xcresult `Test-PaperNest-iOS-2026.10.25_17-42-16--0500.xcresult`. Same create/edit/cancel/delete/history/relaunch coverage; three editor screenshots inspected (`docs/screenshots/page-comment-editor-*-ipad.png`), labels/controls and wrapped export notice fit above keyboard.
- Native Mac interaction, real-device checks, large Dynamic Type/VoiceOver, and injected I/O failure UI not run. Stale-draft conflict and Save as New are model-tested; no native multiwindow conflict UI pass claimed. Focused UI flows only; complete existing UI suite not rerun. Xcode OS-build parsing diagnostics appeared but both final UI runs report TEST SUCCEEDED.

## Additional notebook pages — Codex, 2026-10-25

Notebooks now offer Add Notebook Page in the existing add-pages menu. Blank/lined/grid A4 paper defaults to the selected template; insert after selection or append without one. Selection changes after the store commit. Cancel writes nothing; save failures keep the form open. Undo/redo validates the page row, objects, OCR and surrounding order atomically, preserves newer edits, and clears obsolete history on conflicts. No migration or dependency changes.

- Checkpoint `7444b4d` saved all preceding work after **236 passing tests** (`/private/tmp/papernest-checkpoint-tests.log`).
- Test-first store/model failures: `/private/tmp/papernest-pages-red.log`, `-model-red.log`; focused green: `-store-green.log`, `-model-green.log`.
- Fresh reviewer found rapid native Undo→Redo discarded an unarmed inverse. Reproduced four failed assertions in `/private/tmp/papernest-pages-history-red.log`; fixed by serializing native requests and invalidating queued requests on conflict. Focused green: `-history-green.log`. Regression tests cover immediate undo/redo/undo and conflict with a queued redo.
- Review follow-up reproduced mixed delete/notebook history ending with two pages rather than one (`/private/tmp/papernest-pages-mixed-red.log`). All document history callbacks now share the serial queue; mixed regression passed (`-mixed-green.log`).
- Fresh page edits now await pending history; new-edit race reproduced and fixed (`/private/tmp/papernest-pages-new-edit-red.log`, `-new-edit-green.log`).
- Final independent review: no remaining actionable data-loss or regression issues found; reviewer did not edit files or run tests.
- Final full unit suite: **245 passed** (53 UI + 80 Store + 47 Import + 26 Export + 39 Core), no compiler warning/error matches. `/private/tmp/papernest-pages-unit-final.log`. Covers all paper templates; empty/middle/end insertion; invalid notebook/anchor; deleted/purged/conflicting states; undo/redo; reopening; two-page PDF export; localization parity.
- Final Mac build passed: `/private/tmp/papernest-pages-mac-final.log`. Native Mac sheet and keyboard interaction remain unrun.
- First iPhone UI attempt failed because the test targeted More rather than the compact editor’s separate Add Pages menu. Investigation also found compact history controls missing; added them. Corrected iPhone run passed the add/cancel/default-paper/undo/redo/relaunch flow in en/fr/es (`/private/tmp/papernest-pages-phone.log`). Screenshots `docs/screenshots/notebook-add-page-*-iphone.png` inspected: titles, controls and wrapped Spanish footer fit.
- Initial iPad Air 13-inch (M4) flow passed in en/fr/es: `/private/tmp/papernest-pages-ipad.log`, xcresult `Test-PaperNest-iOS-2026.10.25_06-18-45--0500.xcresult`. All three new-sheet screenshots inspected; labels/controls/footer fit (`docs/screenshots/notebook-add-page-*-ipad.png`).
- iPhone rerun after native rapid undo/redo fix passed in en/fr/es: `/private/tmp/papernest-pages-phone-final.log`, xcresult `Test-PaperNest-iOS-2026.10.25_06-21-26--0500.xcresult`. This run preceded the later shared-history queue and fresh-edit wait.
- iPad shared-history regression passed **2/2**: existing PencilKit drawing/undo/redo/reopen (41.720 s) plus notebook flow in en/fr/es; `/private/tmp/papernest-pages-ipad-final.log`, xcresult `Test-PaperNest-iOS-2026.10.25_06-24-11--0500.xcresult`. This build includes shared history serialization and precedes fresh-edit waiting.
- Final-source iPhone 17 Pro check passed in en/fr/es (130.101 s, zero failures): `/private/tmp/papernest-pages-phone-verified.log`, xcresult `Test-PaperNest-iOS-2026.10.25_06-27-55--0500.xcresult`. Includes all review fixes and fresh-edit waiting. Xcode emitted OS-build parsing diagnostics; tests succeeded.
- Not claimed: full existing UI suite, real-device Pencil/camera, VoiceOver, large Dynamic Type, native Mac interaction, or injected storage-failure UI. Store/model failures are covered; save-error form retention is implemented.

## Notebook creation — Codex, 2026-10-24

Implemented Tools → New Notebook: enter a name, choose blank/lined/grid paper, and create one A4 template page. The item is stored as a notebook in the current folder (root from home), created atomically through the existing store API, and opened after dismissing the creation sheet. Empty names disable Create; double submission/dismissal during save is disabled; errors leave the form open. No schema changes or new dependencies. Existing editor/ink/render/export paths are reused.

- Test-first evidence: `/private/tmp/papernest-notebook-red.log` failed on the missing `LibraryModel.createNotebook` API. Initial sheet compile failed on the Section header/footer initializer and was corrected.
- Full unit suite: **236 tests passed** (48 UI + 76 Store + 47 Import + 26 Export + 39 Core), no compiler warnings. `/private/tmp/papernest-notebook-unit.log`. New parameterized test covers all three templates, normalized name, folder, reopen, valid one-page PDF export, and store integrity.
- Mac build passed, no compiler warnings: `/private/tmp/papernest-notebook-mac.log`. Native Mac sheet interaction not run.
- iPhone 17 Pro: notebook create/relaunch and existing Tools merge tests both passed; `/private/tmp/papernest-notebook-phone.log`. iPad Air 13-inch M4: notebook create/relaunch passed; `/private/tmp/papernest-notebook-ipad.log`. Both report TEST SUCCEEDED.
- Localization key/format checks passed for en/fr/es. French/Spanish visual layout and accessibility-size screenshots are not newly verified. Real Pencil drawing on the new page, cancellation/storage-failure UI, and native Mac interaction are not claimed tested in this slice.
- Scope remains partial for full notebooks: adding more template pages, planners, text/image editing and notebook-specific navigation remain follow-ups. No subscription limits introduced.
- Source: new NotebookCreationSheet.swift; LibraryModel.swift; ToolsSheet.swift; Localization.swift and en/fr/es strings; new NotebookCreationTests.swift; appended AppUITests notebook test. Qwen-reserved sheets untouched. Author review completed; no independent reviewer was available in this session. Nothing committed or pushed.

## F3b — markup colors and saved-mark controls (Codex, 2026-10-24)

- Final full unit suite **passed 235 tests** (47 UI + 76 Store + 47 Import + 26 Export + 39 Core), no compiler warnings. `/tmp/papernest-f3b-unit-final2.log`. Initial implementation passed 233; API tests first ran red in `-store-red.log` and `-model-red.log`, focused green in `-store-green.log`. A test-only `try` placement compile error in `-unit-final.log` was corrected before the passing final run.
- New coverage: custom color validation, atomic recolor/removal, exact page/object snapshot rejection, empty/duplicate/non-ink/foreign-page selections, deleted-parent protection, preserving other ink/text/OCR, undo/redo through both operations, reopen, and actual recolored pixels in exported PDF.
- Independent review found two issues: ink undo/redo bypassed snapshot checks; the open manager did not observe changes from other windows. Fixed with atomic `applyInkChanges` guards (including IDs expected absent anywhere in the library), conflict refresh/error and invalid undo-history clearing, plus manager reload on `session.changeToken` with cancellation/request guards. Three conflict scenarios were reproduced red then passed green: `/tmp/papernest-f3b-conflict-red.log`, `-conflict-green.log`. Store tests also verify no partial writes, foreign-ID collisions and coexistence with unrelated edits. Independent follow-up could not finish due to the reviewer's usage limit; author review and regression tests were completed.
- Final Mac build **passed**, no compiler warnings: `/tmp/papernest-f3b-mac-final.log`. Native Mac manager interaction remains **unrun**.
- iPhone 17 Pro: initial annotation regression + manager/color workflow **passed 2/2** (101.350 s and 210.299 s): `/tmp/papernest-f3b-phone.log`, xcresult `Test-PaperNest-iOS-2026.10.24_06-34-22--0500.xcresult`. After review fixes, manager/color workflow **passed again** (210.014 s) in en/fr/es: `/tmp/papernest-f3b-phone-final.log`, xcresult `Test-PaperNest-iOS-2026.10.24_06-42-00--0500.xcresult`. Exercises real OCR, green preset, selecting/closing without a write, blue recolor, preserving the other mark, removal to empty and persistence after relaunch.
- iPad Air 13-inch (M4): **passed 2/2**, existing PencilKit drawing/undo/redo/reopen (43.974 s) and new manager/color workflow in en/fr/es (258.476 s). `/tmp/papernest-f3b-ipad.log`, xcresult `Test-PaperNest-iOS-2026.10.24_12-00-54--0500.xcresult`. Manager screenshots inspected in all three languages: labels fit and selection outline aligns; lower actions are reached by scrolling in the native form. Evidence: `docs/screenshots/markup-manager-*-ipad.png`. Initial iPhone manager and annotation-color screenshots in en/fr/es inspected: titles/labels fit; dashed selection outlines align with the intended mark. Final-run manager screenshots were also inspected and saved under `docs/screenshots/markup-manager-*-iphone.png`; annotation color-layout evidence is `docs/screenshots/markup-colors-*-iphone.png`.
- A native sRGB conversion probe on Mac returned valid `[0, 1, 0, 1]` for Display-P3 green. This is a color-boundary check, not a manual custom-picker UI pass. Custom colors are unit-tested; system custom-picker interaction and native two-window refresh remain **unrun**. No real-device, VoiceOver, large Dynamic Type, dark-mode or sanitizer pass is claimed for F3b. Focused UI coverage only; the complete iPhone suite was not repeated for F3b.

## F3a — recognized-line text markup (Codex, 2026-10-23)

- `./scripts/test.sh`: **228 passed** (45 + 72 + 47 + 26 + 38), no failures or compiler warnings. `/tmp/papernest-markup-unit-final.log`. Nine new tests cover source geometry for all three styles, narrow/thin boxes, invalid coordinates, stale/replaced OCR rejection, atomic invalid-selection failure, OCR currency through ink changes, undo/redo, reopen and a pixel check on a cropped/rotated PDF export with searchable text intact. New API tests were run red before implementation. The reviewer’s renderer regression was also run red/green: 0.1-point underline/strike disappeared and 1.2-point marks expanded to 1.25. Constant-width pens now draw one path at their exact width; variable-width freehand batching is unchanged. Four parameterized bitmap cases check visibility, thickness and containment. Logs: `/tmp/papernest-markup-width-red.log` and `/tmp/papernest-markup-width-green.log`.
- `./scripts/build-mac-app.sh`: **passed**, no compiler warnings; `/tmp/papernest-markup-mac-final.log`. New native Mac annotation UI has **not** been manually exercised.
- iPhone 17 Pro: `testRecognizedLinesCanBeMarkedAndKeptAfterRelaunch` **passed** (101.028 s). Real OCR → highlight (en), underline (fr), strikethrough (es), cancel without adding ink, and persistence after each relaunch. `/tmp/papernest-markup-phone.log`; xcresult `Test-PaperNest-iOS-2026.10.23_14-44-30--0500.xcresult`. Picker screenshots in all three languages inspected: no clipped controls/text. Saved highlight and combined marks visually inspected. Evidence: `docs/screenshots/text-markup-*-iphone.png`.
- iPad Air 13-inch (M4): annotation workflow **passed** (102.302 s) and existing PencilKit drawing/undo/redo regression **passed** (2/2 total). `/tmp/papernest-markup-ipad.log`; xcresult `Test-PaperNest-iOS-2026.10.23_20-27-49--0500.xcresult`. Picker screenshots in en/fr/es and the combined saved marks inspected; controls fit, saved marks align with the text. Evidence: `docs/screenshots/text-markup-*-ipad.png`. Final follow-up after the exact-width renderer fix also **passed 2/2**, annotation workflow 104.814 s: `/tmp/papernest-markup-ipad-final.log`, xcresult `Test-PaperNest-iOS-2026.10.23_20-33-46--0500.xcresult`. Saved iPad evidence files now come from that final run; the final combined marks were visually rechecked.
- Full iPhone suite was run earlier for the audit (17 passed, 1 skipped); it was not repeated after F3a. The focused iPad follow-up compiles the final iOS code; the earlier iPhone run predates only the shared exact-width rendering fix. No real-device, VoiceOver, Dynamic Type, dark-mode annotation or new sanitizer check is claimed.
- Independent review resumed after a usage-limit interruption and identified the exact-width renderer issue above. The fix has a passing regression; independent follow-up reported no remaining actionable findings. Author review checked the source-space mapping, exact OCR snapshot identity, transaction boundary, undo registration, duplicate-save guard and localized strings.


## Mac audit and file-preview follow-up (Codex, 2026-10-23)

- `./scripts/test.sh`: **219 passed** (44 + 68 + 46 + 26 + 35), no compiler warnings; `/tmp/papernest-oct23-unit.log`. Includes a red/green regression for a file item sharing an asset stored as PDF. Temporary copies now resolve the asset record’s kind instead of assuming `.bin`.
- `./scripts/build-mac-app.sh`: **passed**, no compiler warnings; `/tmp/papernest-oct23-mac.log`. Subsequent Mac Tools/footer and raw-file save changes also built; `/tmp/papernest-oct23-mac-tools.log`, `/tmp/papernest-oct23-mac-file-save.log`.
- Full iPhone 17 Pro UI run: **17 passed, 1 skipped, 0 failures**; `/tmp/papernest-oct23-phone.log`, xcresult `Test-PaperNest-iOS-2026.10.23_05-19-08--0500.xcresult` in cache `build-17de0868e51d`. This full run predates the final Tools footer and writable-type changes; focused follow-up **passed 3/3** (file preview, Export save dialog, Tools merge); `/tmp/papernest-oct23-focused-final.log`, xcresult `Test-PaperNest-iOS-2026.10.23_14-37-14--0500.xcresult`.
- Native Mac interaction used only `/tmp/papernest-mac-audit-20261022`. Library grid and document preview viewed. Hidden layout-picker label fixes a narrow vertically wrapped label while preserving accessibility. Export previously hung in an AttributeGraph cycle; isolating the form identified `ViewThatFits`. Mac now uses a stable horizontal row. Export opened, saved a valid one-page PDF, reopened and switched to JPEG.
- Mac Tools initially retained Done over the pushed document picker, hiding Continue. Moving each Mac action into its own content footer fixed it: Continue disabled without selection, enabled after selecting, then extraction of page 2 produced and opened a new one-page document.
- Mac QuickLook displayed actual synthetic en/fr/es text; Info showed type, filename, size and dates; closing Info preserved preview; Done dismissed it. Save a Copy initially wrote text bytes as `.pdf` because `ExportedFile` advertised only PDF/image/ZIP. Advertising raw `.data` with the caller-supplied type now saves `.txt`; `cmp` confirmed byte equality. Settings window viewed with live counts, storage, language and About. Backup action not yet exercised on Mac.
- Earlier focused iPad preview/error checks: **2/2 passed**; `/tmp/papernest-preview-ipad-final.log`. iPhone screenshots inspected for actual text and French error/dismissal.
- Still unverified: Mac fr/es layouts, full Mac import/crop/reorder/keyboard flows, sandboxed panel permissions, external app interoperability, real camera/Pencil. Native UI-control tools became unavailable before the remaining Mac checks; do not infer a pass from a build.


## File tools — F1 initial slice (2026-10-22)

- `./scripts/test.sh`: **144 tests passed**, zero failures; no Swift compiler warnings. Logs: `/tmp/papernest-file-tools-unit-final.log`. New suites: `ColorLabelTests`, `DocumentCompositionTests`, `LibraryReloadTests`; workflow `composedDocumentsExportInOrderAfterTheSourcesAreDeleted` verifies a real PDF export after merge/extract/duplicate and deleting all sources.
- `./scripts/build-mac-app.sh`: **passed** on the final code, zero Swift compiler warnings. Log: `/tmp/papernest-file-tools-mac-final.log`. Mac UI interaction/visual checks remain unrun.
- `./scripts/ui-test-ios.sh 63992C10-33B4-4CE3-91C3-EE23ECC595A5`: **11 passed, 1 skipped** (iPad-only Pencil), zero failures. Includes existing folder/crop/settings/export/navigation/filter tests plus two new file-tool workflows. Log: `/tmp/papernest-file-tools-ui-full.log`; xcresult `Test-PaperNest-iOS-2026.10.22_05-54-02--0500.xcresult` under the cache's `xcodeproj/Logs/Test`.
- After review fixes, both new phone workflows **passed again**, including the added checks for Blue while selecting and Done after delete-all. Log: `/tmp/papernest-file-tools-ui-final.log`; xcresult `Test-PaperNest-iOS-2026.10.22_05-59-53--0500.xcresult`.
- Final short-title/selection-border layout rerun and focused iPad workflow: **pending** at this checkpoint. Logs will be `/tmp/papernest-file-tools-layout-final.log` and `/tmp/papernest-file-tools-ipad.log`.

Coverage: v3→v4 migration, persistent/removable labels, atomic batch rollback; distinct fresh object/page/item IDs, source order and explicit merge order, labels, name deduplication, missing/deleted/wrong-owner selections, missing files/asset rows/remote-only bytes, late SQLite failure rollback, independent mutable content and lifetime after deleting originals, current/stale OCR and index remapping. No OCR engine is claimed. UI covers duplicate/merge/extract/relaunch, keep-originals, merge reorder and cancel, empty-page selection disabling Create, plus en/fr/es screens.

Found during verification: the initial UI test expected Export to remain visible after opening a long-named result; iOS put it in overflow. SQLite and the AX hierarchy confirmed save/open succeeded; the test now asserts page thumbnails. Review regression demonstrated canceled/outdated reloads could publish stale rows; generation/scope/search checks now reject them. Screenshot QA found crowded French/Spanish sheet titles and selected-grid borders touching metadata; titles are shortened and borders now surround previews. Toolchain logs emit AppIntents metadata warnings and Simulator diagnostics; these are not Swift compiler warnings. No new device, sanitizer, camera or native Mac interaction test is claimed.


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
| F2c: Photos import, HEIC, and two test defects (Claude, 2026-10-22 17:25–18:40) | `./scripts/test.sh`: **passed, 218 tests** (43 + 68 + 46 + 26 + 35), 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 17 passed, Markup skipped, twice in a row** after the fix described below. **HEIC, verified before claimed.** Photos from the system library are almost always HEIC and the sniffer did not know it, so a picked photo would have been kept as an opaque file rather than an editable page. ImageIO was checked first on this machine — it writes HEIC, reads it back as `public.heic`, and keeps dpi — and only then was `AssetKind.heic` added. Detection is by content (`ftyp` box plus a HEIF-with-HEVC brand); `avif` shares the container and is deliberately **not** claimed. Completeness is checked by walking the top-level box chain, because the format has no end marker and ImageIO decodes a truncated file without complaint. **Schema v6** widens `assets.kind` through the same rebuild path as v5; sync now has to take **v7 or later**, and the three documents that named an older number were corrected. `HEICImportTests` ×6: the platform really round-trips HEIC; a 600×900 photo at 300 dpi becomes a 144×216 pt page; the type comes from the bytes even when the file is named `notes.txt`; a truncated HEIC is rejected rather than imported part-blank; an `avif` brand is not claimed; and a HEIC page renders landscape. **Photos import.** `LibraryModel.importPhotos` makes **one document per photo** — a photo of a receipt is a document, not a page of some other one — reports a photo it cannot read while still importing the rest, and lands them in the folder on screen. `PhotoImportTests` ×3 cover all three. The picker itself is `PhotosPicker` on the Tools screen: it is the system's own UI driven by the user, so the UI test asserts the entry point exists and the unit tests cover everything after it, rather than pretending to drive it. **Not built:** video from Photos, which needs a streaming transfer representation instead of loading whole items into memory. **Two test defects fixed, both found by running rather than assuming.** (1) `cancellingTheBackupLeavesNothingBehind` observed progress and then cancelled, which a small library can win by finishing first; it failed about **one full run in two**. The export is now held at page three until the cancel has been issued, and three consecutive full runs are clean. (2) `testFilterStripAndTitleMenu` looked the title menu up as `buttons["Crop target"]` with a `staticTexts` fallback, but the button is labelled `"Crop target, Actions Menu"` and the StaticText is not reliably present — it had been **passing on luck** and failed once the device was restarted. It now matches by label prefix with an existence check, the same fix already applied to the recognition test. **Environment note, not a product failure.** One UI run before the fix showed three unrelated failures including *"Simulator device failed to launch com.example.papernest. No such process"*; all three passed after `simctl shutdown` and a clean boot. The app had been launched manually through `simctl` earlier in the session. Restart the device before investigating a spread of unrelated UI failures. |
| F2b finished: archiving a selection, files included (Claude, 2026-10-22 16:45–17:20) | `./scripts/test.sh`: **passed, 209 tests** (40 + 68 + 40 + 26 + 35), 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 17 passed, Markup skipped**. An archive entry can now be a **document** (rendered to PDF as the app shows it) or a **file** (copied byte for byte under the name it came in with): `LibraryExportEntry` and `Exporter.exportArchive`, with `exportLibrary` kept as a wrapper so existing callers are unchanged. Progress counts pages for documents and one unit per file, so a mixed selection still reports sensibly. **Two real gaps closed, both found by asking what a selection containing a file would do:** (1) **Export as ZIP… silently skipped file items** — the action was gated on `pageCount > 0`, so selecting a video and a document archived only the document; (2) **the Settings backup dropped every file** for the same reason, which made "Export All Documents" a backup that quietly left things out. Both now include files, and the footer in en/fr/es says so instead of promising documents only. The Tools screen's archive picker accepts file items too, while merge, extract and split still refuse them. New `BulkExportTests`: a mixed selection produces `Notes.txt` and `Letter.pdf` **in selection order**, the text file comes back **byte for byte** (not re-encoded) and the PDF still holds its text; a selection of only files still produces an archive, where before it failed with `noPages`; and the Settings backup carries both kinds. A selection of only **page-less documents** is still an error rather than an empty archive. **Not built:** compression presets with before-and-after sizes (reference row 35) — this is archive creation, not size reduction; RAR creation, which the owner's screenshots do not ask for. **Not verified:** the Mac; an archive larger than the 2 GiB default budget. |
| F2b: reading archives, and F2a preview completion (Claude and Codex, 2026-10-22 15:20–16:40) | **Both agents were in the tree at once for part of this; see the note under this row.** Final combined state: `./scripts/test.sh` **passed, 206 tests** (37 + 68 + 40 + 26 + 35), 0 failures, 0 compiler warnings; `./scripts/build-mac-app.sh` and the iOS Simulator build **passed, 0 warnings**; `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro) **TEST SUCCEEDED — 17 passed, Markup skipped**. **Claude — ZIP extraction.** New `ZipReader` (PaperNestImport) parses the central directory, inflates method 8 through `Compression`, verifies CRC-32, and refuses what it cannot open safely. `ZipReaderTests` ×9 use adversarial fixtures: **path traversal in five shapes** (`../escape.txt`, `/etc/passwd`, `notes/../../escape.txt`, a backslash form and a drive letter), a **real symlink** archive from `/usr/bin/zip --symlinks`, a **real encrypted** archive from `zip -P`, an **expansion-ratio bomb**, a **total-size budget**, CRC corruption, and a file that is not an archive at all. Every refusal leaves the destination absent, checked in each test. `LibraryModel.extractArchive` unpacks into a folder named after the item, sending each extracted file through the page importer first and keeping anything else as a file item; `ArchiveExtractionTests` ×3 prove a PDF inside an archive becomes a real one-page document, a `.txt` beside it stays a file with its bytes intact, the archive itself is kept, and an encrypted or fake archive adds **nothing** — no folder, no items — while showing a plain message. **Codex — file previews finished.** Three real defects in the preview Claude had written the hour before: the `QLPreviewItem` getters needed `nonisolated` under strict concurrency; a presentation modifier on the empty List sections of `LibraryHomeSections` **did not present at all**, so Recent now routes through a root-owned `FilePreviewPresentation`; and the temporary copy was being deleted in `onDisappear`, which is wrong because a child presentation can cover the parent — it is now owned by a `PreparedFileCopy` that cleans up on release, and Show Info reuses the preview's copy instead of making a second. Codex also added `testMissingFilePreviewCanBeClosedInEveryLanguage`, which checks a **failed** preview can still be dismissed in en, fr and es — the original could trap the user in a full-screen cover with no way out. **Process failure, recorded on purpose.** Claude ran `git add -A` in the shared checkout while Codex was mid-slice, so commit `5abebea` contains Codex's in-flight preview helper and Recent routing under a message describing only Claude's version. Codex recorded the same event from its side. The commit stands; the handoff now carries a work division and the rule that staging is by explicit path. **Not verified:** the Mac (unchanged — still never viewed); RAR, which is not implemented; archives larger than the default 2 GiB budget; extraction on a real device. |
| F2a step 3: QuickLook preview for file items (Claude, 2026-10-22 15:25–16:05) | Tapping a file now opens it with the system's own preview instead of a row of metadata; **Show Info** keeps the details sheet, in the ⋯ menu. `./scripts/test.sh`: **passed, 191 tests**, 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings** — the Mac path compiles `QLPreviewView` from QuickLookUI, the iOS path `QLPreviewController`. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 16 passed, Markup skipped**; the rewritten `testAFileItemPreviewsAndShowsItsTypeSizeAndACopy` taps the file, waits for the preview, dismisses it, then opens Show Info and checks the original name and Save a Copy. Same test on the **iPad Air 13-inch (M4): passed** (21.1 s). **QuickLook supplies its own Done button only when it presents itself**; here SwiftUI owns the presentation, so the dismissal is ours (`file-preview-done`). iOS uses a full-screen cover, the Mac a sheet with Done and Show Info beneath the preview. **Fixed in passing: a temporary-file leak.** `FileKind.temporaryCopy` wrote a copy into a new directory under the system temporary directory for Share and Save a Copy, and nothing ever removed it — every details sheet left one behind. Both the details and preview sheets now discard it on dismiss (`FileKind.discardTemporaryCopy`). **Environment flake, recorded rather than hidden:** the first run of this test failed with *"PaperNestUITests-Runner encountered an error (Early unexpected exit, operation never finished bootstrapping — the test runner exited with code 0 before establishing connection)"*. The same test passed on an immediate rerun and in two later full runs. Nothing in the app changed between them; this is the Simulator's runner-bootstrap flake, not a product failure. **Not verified:** the Mac preview on screen (`QLPreviewView` compiles and is wired, but the Mac UI has still never been viewed); preview of a large video or an Office document; French and Spanish on this screen. |
| F2a step 2: files in the library (Claude, 2026-10-22 13:50–15:10) | **Any file can now be kept, shown and copied back out.** `./scripts/test.sh`: **passed, 191 tests** (31 + 68 + 31 + 26 + 35), 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 16 passed, Markup skipped**; the new `testAFileItemShowsItsTypeAndSizeAndOffersACopy` also **passed on the iPad Air 13-inch (M4)** (13.6 s). **Streaming import:** `AssetFileStore.store(contentsOf:kind:originalFilename:)` copies and SHA-256-hashes in one pass with a 1 MiB buffer, so a large video never has to be held in memory. `StreamingAssetTests` ×5: a file spanning several buffers plus a partial one hashes identically to the whole-file path; the streaming and in-memory stores agree and deduplicate to one file on disk; a damaged stored file is replaced rather than trusted; a missing source leaves no staging file behind; an empty file still round-trips. **Import:** `FileItemImporter` sniffs the type through the file's own `contentTypeKey`, reads under `NSFileCoordinator` with security-scoped access, and creates the item. `FileItemImportTests` ×6 cover any type, folders, duplicate names, content-addressed deduplication with each item keeping its own filename, and a missing file leaving nothing behind. **A dynamic UTI is never stored:** the system invents one for an unknown extension, and it means nothing on another device or after sync, so such files are recorded as `public.data` — found by a test that expected the honest value. **UI:** the library's Import now offers every type and falls back to a file item when something cannot become pages (Add Pages and Replace Page stay restricted to PDF/JPEG/PNG); a file tile shows a type-derived symbol and its size where a document shows its page count; tapping a file opens a details sheet with kind, original name, size, dates, Share and Save a Copy, which copies from the asset file rather than loading it. The seeder has the same fallback, so `papernest-seed` can seed a file item. **Contract change, deliberate:** importing a `.txt` used to fail with "unsupported type". It now becomes a file item, and the M1 gate test `importEditRelaunchAndExportKeepsPagesAndOrientation` was updated to assert the new behaviour (4 items, one of kind `.file`, no error) rather than the old. **Also:** a `LabeledContent` row is one accessibility element labelled "<label>, <value>" — match it by prefix or substring, not by the value alone. **Not built:** QuickLook preview (the owner chose it; the details sheet is the stand-in until then), Photos import, a system Inbox, ZIP/RAR, and compression presets. **Not verified:** the Mac, and a genuinely large file on a device. |
| F2a step 1: schema v5 and file items in the store (Claude, 2026-10-22 12:40–13:40) | `./scripts/test.sh`: **passed, 180 tests** (31 + 63 + 25 + 26 + 35), 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone): **TEST SUCCEEDED — 15 passed, Markup skipped** (no UI in this step). **A data-loss trap was found and proved before any code was written.** The design called for widening two CHECK constraints, which SQLite can only do by rebuilding the tables. With `PRAGMA foreign_keys = ON` — which this store sets — `DROP TABLE items` performs an implicit delete that **cascades into `pages`**. A standalone sqlite3 experiment confirmed it: *pages before: 2 → pages after: 0*, items intact. Written as first sketched, the v5 migration would have silently emptied every document in a user's library on upgrade. `Schema.Migration` now carries `rebuildsTables`, and `LibraryStore.migrate` runs those migrations with foreign keys off and verifies them with `PRAGMA foreign_key_check` inside the transaction before the version bump, restoring enforcement with a `defer`; a dangling reference throws `StoreError.migrationBrokeReferences` and rolls the migration back. **Schema v5:** `items.kind` and `assets.kind` rebuilt to accept `'file'`, plus a `file_items` table (item_id, asset_id, uti, original_filename, byte_count). New `FileItemMigrationTests` ×3: a v4 library with a folder, two documents, **two pages**, a tag, a color label, an asset and a search row survives the upgrade with every row intact and `foreign_key_check` clean; the rebuilt tables accept `'file'` and still reject nonsense kinds; and **a library upgraded from v4 is byte-identical in `sqlite_master` to one created fresh at v5**, so later migrations cannot diverge between them. **Store API:** `createFileItem`, `filePayload`, `ItemSummary.file`, `ItemKind.file`, `AssetKind.file` (extension `bin`), `FilePayload`. New `FileItemTests` ×6: a file keeps its bytes, name and UTI across a reopen and reports no pages; files share folders, favorites, color labels, search, trash and restore with documents; **the asset sweep keeps bytes a file item still references** — the hazard the design named — when a document that shared the same content-addressed bytes is permanently deleted; duplicating a file shares the bytes and outlives the original; merge, split and extract refuse file items with `invalidOrder` and change nothing; and storage usage counts a file's bytes while adding no pages. The page importer now rejects uninterpretable bytes explicitly rather than falling through. **Not built yet (F2a step 2):** streaming import for large files, QuickLook previews and thumbnails, the details sheet, library cells for file items, and share/save-a-copy. Nothing in the UI shows a file item yet. |
| F4b: searchable PDF export (Claude, 2026-10-22 11:45–12:30) | `./scripts/test.sh`: **passed, 171 tests** (31 + 54 + 25 + 26 + 35), 0 failures, 0 compiler warnings. Exported PDFs now carry each page's recognized text as an invisible layer, so a scan can be searched and its words selected in any reader. `ExportOptions.includesRecognizedText` (default on) controls it; `PageRenderer.recognizedLines(for:)` applies the same currency rule as search, so only a `.completed` result matching the page's revision is written. New `SearchablePDFTests` ×7, all reading the exported file back with PDFKit: the words are extractable; **"Quarterly" lands where it was read** — 10% from the left and 8% from the top, within 2–3 points — and the full line spans the 60% of the page width it was recognized at, within 5%; the layer is **invisible** (a pixel sweep across the text band matches an export made without it); the option off writes nothing; pending, failed and older-revision results are not exported; a vector PDF keeps its own selectable text without any recognition; and a **cropped, 90°-rotated page still places its text on the paper**. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 15 passed, Markup skipped** (no UI change in this slice). **Two bugs found and fixed while testing:** (1) placing a line by its page-space bounding box squeezed a rotated page's text into a sliver — only the letter "R" of "Rotated words" survived extraction; the layer is now drawn in **source space** with the page transform concatenated onto the CTM, so crop and rotation are handled by the geometry rather than by hand. (2) `CTLineDraw` overrides `CGContext.textMatrix` from the line's own runs, so the horizontal stretch was silently dropped and every line exported at its natural width (0.38 of the page instead of 0.60); the stretch now goes on the CTM. **Also worth knowing:** swift-testing reports a failure when an optional inside a `#expect` expression is nil, even when the overall condition is true — bind `pdf.page(at:)?.string` to a local first. **Not verified:** opening an exported file in Preview, Acrobat or Files (structural checks and PDFKit extraction only); a real photographed scan; the Mac. **Not built:** a UI toggle for the text layer (it is always on when current text exists), and text extraction from vector PDFs into the search index. |
| F4a: text recognition and search inside pages (Claude, 2026-10-22 10:15–11:40) | `./scripts/test.sh`: **passed, 164 tests** (31 + 54 + 25 + 19 + 35), 0 failures, 0 compiler warnings. New `TextRecognizer` (Vision, on device, `VNRecognizeTextRequest`, accurate level, en-US/fr-FR/es-ES filtered against `supportedRecognitionLanguages()` so no unsupported language is claimed) and `PageRenderer.renderSourceForRecognition`, which renders the **upright, uncropped, unfiltered** source — text is read from the paper, not from the current view of it. `TextRecognitionTests` ×5 run real recognition on synthetic printed pages: the words come back in reading order; boxes use a **top-left origin** in source space (Vision's bottom-left is flipped in exactly one place) and are **not** inflated to `NormalizedRect.minimumSide`, for which `NormalizedRect.exact` was added; a blank page yields nothing; an unsupported language throws; and a crop + rotation + grayscale leave the recognized text and its boxes unchanged. `LibraryStore.saveRecognition` now keeps `search_index` in step in the same transaction, indexing only a `.completed` result whose `sourceRevision` matches the page — so Codex's existing "stale result cannot become current" test still holds — and `replacePageContent` drops a page's OCR rows, because a rescan puts different paper on the page. `RecognitionSearchTests` ×6 and `RecognitionWorkflowTests` ×2 cover: a word only the page carries finds the document, re-running replaces rather than appends, an unfinished result leaves nothing findable, accents fold, deletion removes the text, a stale result is kept but unfindable, recognition for a missing page is rejected, the text survives a relaunch, **rotation keeps it findable** and **a rescan does not**. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 15 passed, Markup skipped**, including the new `testRecognizeTextMakesAWordOnThePageSearchable` (22.4 s: opens a 3-page sample, runs Recognize Text from the overflow menu, returns to the library, types "Quarterly" — a word printed on page 1 and absent from the title — and finds the document). Same test on the **iPad Air 13-inch (M4): passed** (21.7 s). **Found while testing:** the iPhone document toolbar has **no ⋯ menu at all** (only iPad and Mac do), so the action was unreachable on the main scanning device; it now sits in each layout's one overflow menu — the bottom bar's ⋯ on iPhone, the toolbar's ⋯ on iPad and Mac. Also: SwiftUI menu items do not expose `accessibilityIdentifier` to XCUITest, so menu entries are matched by label, as the rest of this suite already did. **Not verified:** recognition on a real photographed scan (synthetic printed pages only); handwriting (Vision's printed-text path only); the Mac; performance on a long document (no numbers taken); the French and Spanish menu entries on screen. **Not built yet in F4:** searchable-PDF export, a recognition status/progress surface outside the open menu, automatic recognition after a scan, and re-recognition prompts after a rescan. |
| Tools screen (Claude, 2026-10-22 09:40–10:05) | One home for the tools that work, reached from a wrench button in the library toolbar (every platform) and the iPhone home's toolbar. `Sources/PaperNestUI/ToolsSheet.swift`: a **Create** group (Scan, Import…) and a **Documents** group (Merge Documents, Extract Pages, Split into Pages, Export as ZIP…), each document tool pushing a picker that enforces its own rule — merge needs two or more, split only offers documents with more than one page, and rows a tool cannot use are shown disabled with their page count rather than hidden. Picked order is preserved, so a merge starts in the order the user tapped. **No placeholder tiles:** every tile runs today. `./scripts/test.sh`: **passed, 151 tests**, 0 failures, 0 warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 14 passed, Markup skipped**, including the new `testToolsScreenPicksTwoDocumentsAndMergesThem` (29.6 s: Tools → Merge → picks one document and checks Continue is **disabled**, picks the second and checks it is enabled → names the result → the merged document opens → relaunch finds `Tools merged, 2 pages` with both originals intact). `scripts/ui-test-ios.sh 62328381-…` (iPad Air 13-inch M4): **TEST SUCCEEDED** (26.6 s). New disposable library `/tmp/papernest-tools-screen-library`, seeded in `scripts/ui-test-ios.sh`. **Found and fixed during the run:** the Tools entry was first a third large button in `CaptureActions`, which pushed the Folders section's **+** off the iPhone home and broke `testAFolderMadeInTheSidebarHoldsAMovedDocument`; it moved to the toolbar and that test passes again. Screenshots `docs/screenshots/f1-tools-screen-{en,fr,es}.png`, captured with a new screenshot hook `-PaperNestDebugShowTools YES`: **French and Spanish were inspected and fit** — "Fusionner des documents" and "Combinar documentos" wrap to two lines inside their tiles, "Exportar como ZIP…" fits on one line, and Scan is correctly disabled with no Simulator camera. **Not verified:** the Tools screen on the Mac (never viewed); the picker's own layout in fr/es (only the tile grid was captured); VoiceOver. |
| F1 follow-up: export a selection as one ZIP (Claude, 2026-10-22 09:00–09:35) | `./scripts/test.sh`: **passed, 151 tests** (29 + 48 + 20 + 19 + 35), 0 failures, 0 compiler warnings. The archive writer needed no change — `Exporter.exportLibrary(_:archiveName:)`, already used by the Settings backup, takes any item list — so the new code is `BulkExportModel`/`BulkExportSheet` and the menu entry. New `BulkExportTests` ×3: (1) the archive holds **only** the chosen documents, **in selection order** (`unzip -Z1` → `B.pdf`, `A.pdf`, not library order), skipping a page-less document selected between them; the extracted PDFs have the right page counts and text (PDFKit); the library is byte-for-byte unchanged afterwards; and `finish()` deletes the temporary archive and returns to idle. (2) Cancelling returns to idle at once, never becomes ready afterwards, and leaves no `PaperNestExport-…` directory behind. (3) An empty selection never starts an export, and a selection whose documents all have no pages **fails** instead of writing an empty archive. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 13 passed, Markup skipped**, including the new `testDocumentToolsBulkExportMakesOneArchiveFromTheSelection` (16.4 s: Select → Select All → ⋯ → Export as ZIP… → waits for the "Ready: <size>" status and the Save button → Done returns to the library). `scripts/ui-test-ios.sh 62328381-…` (iPad Air 13-inch M4): **TEST SUCCEEDED**, bulk export (15.2 s) and split (21.2 s). The UI test reads the split test's library without changing it, which the unit test above independently proves. **Not verified:** the Save panel and Share sheet destinations for this archive (the single-document equivalents are covered by `testExportSaveOpensTheSaveDialog…`); the French and Spanish sheet on screen; the Mac. **Deliberately not claimed:** this is archive creation, not file-size reduction — explicit compression presets with before/after sizes remain F2/F4. |
| F1 follow-up: split a document into one document per page (Claude, 2026-10-22 08:20–08:55) | `./scripts/test.sh`: **passed, 148 tests** (26 + 48 + 20 + 19 + 35), 0 failures, 0 compiler warnings. New `DocumentSplitTests` ×4, written before the implementation: (1) one document per live page in stored order, after a reorder, keeping the source's folder and color and leaving the source's pages and name untouched — and identical caller-supplied names still land as distinct siblings (`Lease 2/3/4`); (2) soft-deleted pages are skipped, page objects are copied with fresh IDs and the same payload, and the parts stay readable after the original is permanently deleted (reopened store, `integrityCheck` clean); (3) empty, missing and recently-deleted sources are rejected with nothing created; (4) a synthetic `page_objects` trigger failing on the **last** page rolls back the two documents already created — `items`, `pages`, `page_objects`, `search_index` and `assets` row counts unchanged — and the same split then succeeds. `./scripts/build-mac-app.sh` and `xcodebuild -scheme PaperNestUI … iOS Simulator build`: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 12 passed, Markup skipped**, including the new `testDocumentToolsSplitMakesOneDocumentPerPageAndKeepsTheSource` (23.9 s: splits a 3-page document from its ⋯ menu, finds `Split target — Page 1`, relaunches, finds all three parts and the untouched 3-page original, and checks that Split is **disabled** on a one-page document). `scripts/ui-test-ios.sh 62328381-…` (iPad Air 13-inch M4): **TEST SUCCEEDED**, the split test (21.0 s) and the merge/extract test (56.7 s). The UI test seeds a new disposable library `/tmp/papernest-file-tools-split-library` from `Samples/multilingual-letter.pdf` (3 pages), added to `scripts/ui-test-ios.sh`. **Not verified:** the French and Spanish menu labels were not looked at on screen (they are plain menu rows; `LocalizationTests` covers key and format-argument parity); splitting on the Mac; splitting a very large document (no performance numbers taken). |
| F1 document tools (select, duplicate, merge, extract, color labels) — verification of the uncommitted slice, Claude, 2026-10-22 06:03–06:25 | `./scripts/test.sh`: **passed, 144 tests** (20 + 44 + 19 + 26 + 35), 0 failures, 0 compiler warnings. New suites: `DocumentCompositionTests` (selection and stored page order, fresh identities, color kept by duplicate/extract and dropped by merge, copies outlive permanently deleted originals, a missing or `remoteOnly` asset aborts, a late `page_objects` failure leaves all 8 tables row-for-row unchanged and `integrityCheck` clean, missing or deleted destination folders rejected, unfinished or stale recognition cannot become current), `ColorLabelTests` (relaunch, all-or-nothing batch, v3 → v4 migration), `LibraryReloadTests` (an outdated reload cannot publish rows into a newer selection), and workflow `composedDocumentsExportInOrderAfterTheSourcesAreDeleted`. `./scripts/build-mac-app.sh` and `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro, iOS 26.5): **TEST SUCCEEDED — 11 passed, the iPad Markup test skipped as designed**, including `testDocumentToolsDuplicateMergeExtractAndKeepOriginals` (59.2 s) and `testDocumentToolsLocalizedSelectionOrderAndCancellation` (92.5 s). **All nine en/fr/es screenshots were exported from the result bundle and looked at** (selection bar, merge sheet, extract sheet): no truncation anywhere, saved as `docs/screenshots/f1-tools-{selection,merge,extract}-{en,fr,es}.png`. Spanish is the tightest selection bar ("Selección: 2 · Deseleccionar todo · Más" spans nearly the full width at the default text size); `ViewThatFits` stacks it when it no longer fits. **iPad Air 13-inch (M4), iOS 26.5: both new tests failed at first, on iPhone-specific assertions; fixed at the owner's request and now passing (see the end of this row).** (1) `…KeepOriginals` line 356 waits for `page-thumbnail-1`, which only exists in the compact-width `PageScroller` (`DocumentView.swift:632`); the iPad uses the regular-width page column. The merge itself worked: the app hierarchy captured at the failure shows the document open with the navigation bar titled "Combined test" and All Documents at 3. (2) `…LocalizedSelectionOrderAndCancellation` line 426 compares the `minY` of two app-wide `staticTexts` matches and got 556.0 for both. On iPad the merge sheet is a *form* sheet, so the library grid stays visible behind it, and 556 pt is exactly where the two grid tile labels sit, side by side — so the query matched the grid, not the sheet. **Unexplained, and worth a VoiceOver check:** `ItemCell` is `.accessibilityElement(children: .ignore)`, so those tile name texts should not be exposed as separate elements at all. If they are, selection-mode tiles may read as fragments to VoiceOver, which would be an app bug. A frame extracted from the test's own screen recording at t = 21.5 s showed the sheet itself was correct: row 1 "Crop target 2", row 2 "Crop target", with the up/down arrows disabled at the ends. The assertions pass on iPhone only because the page sheet covers the library. **Fix applied** (Claude, 06:28–06:40, on the owner's instruction, taking `AppUITests.swift` and `DocumentToolsSheet.swift` from Codex): the test now waits for the new document's navigation bar (`Combined test`, then `Combined test — Pages`) instead of `page-thumbnail-1`, and each merge row's name `Text` carries an `accessibilityIdentifier` `merge-row-<n>` that the test matches instead of the bare name. **Re-verified after the fix:** `./scripts/test.sh` **144 tests passed**, 0 warnings; `./scripts/build-mac-app.sh` and the iOS Simulator build **0 warnings**; `scripts/ui-test-ios.sh 63992C10-…` (iPhone) **TEST SUCCEEDED, 11 passed + Markup skipped**; `scripts/ui-test-ios.sh 62328381-… -only-testing:…` (iPad) **TEST SUCCEEDED, both tests passed** (58.2 s and 86.1 s). That iPad run was the first to exercise **extraction, and the French and Spanish flows, on iPad**; its nine screenshots are `docs/screenshots/f1-tools-ipad-*.png` and show no truncation (the iPad sidebar wraps "Supprimés récemment" and "Eliminados recientemente" onto two lines, which is fine). **Still open:** it is unexplained why the grid's tile name texts were matchable at all, since `ItemCell` is `.accessibilityElement(children: .ignore)`; the fixed test no longer depends on it, but selection mode deserves a VoiceOver check. **Still not verified:** the whole feature on the Mac (never viewed, see the manual checklist); a long document name in the merge and selection UI (every fixture is "Crop target"); a failed save keeping the sheet open (code-inspected only: `DocumentToolsSheet.create()` sets `failed = true` and does not dismiss). **Design nit:** the extract sheet's per-page checkmark is plain black, while every other selection indicator uses `Theme.accent` blue (`DocumentToolsSheet.swift:97`, visible in all three languages). |
| Pass 7: Apple Pencil on iPad, first slice (Claude, 21:45–22:50) | `./scripts/test.sh`: **passed, 128 tests** (new: `InkRenderTests` ×3: pen ink follows rotation and crop and the content-only render omits it; highlighter multiplies over the page; per-point width. `InkExportTests` ×2: PDF keeps selectable text and draws the ink; JPEG of a transparent page keeps black ink. `ObjectChangeTests`: one gesture = one transaction and one revision bump; a bad object aborts the whole change. `InkConversionTests` ×2: PencilKit round trip on a rotated, 1.5× page keeps position, width profile, tool and color. Workflow `inkChangesUndoRedoAndSurviveRelaunch`). `scripts/ui-test-ios.sh 63992C10-…` (iPhone): **passed, 9; the iPad Markup test skipped as designed**. **iPad Air 13-inch (M4), iOS 26.5: `testMarkupWithFingerDrawingSavesAStroke` passed** (finger drag draws nothing while Pencil-only; with Draw with Finger one stroke is saved; still there after leaving Markup and after a relaunch). Screenshot `design-7-ipad-ink-rendered-en.png`: the saved stroke renders at 30–70 % × 50–55 % of the page, exactly where it was dragged, and in the thumbnail. Mac and iOS builds: 0 warnings. **Review fixes (23:00–23:20):** (1) the canvas clears its undo history on *every* reload, not only on page switch, so an undo after a zoom can't save old-scale strokes; (2) a race: SwiftUI refreshed the canvas before a stroke was saved, so it reloaded empty (stroke flickered out, undo wiped); diagnosed with logs, fixed by tracking the states the canvas has sent; (3) objects are filtered to the shown page. **Opening Markup writes nothing** (iPad, `-PaperNestDebugShowMarkup YES`: page revision and the stroke's `modified_at` unchanged in SQLite). Screenshot `design-7-ipad-markup-en.png`: Markup and Draw with Finger in the toolbar, the system tool palette at the bottom. **Undo follow-up (23:20–23:45):** logs showed a stroke's undo step was recorded but nothing ever undid it: SwiftUI's Edit menu takes ⌘Z (not the canvas), and the palette's Undo stayed **disabled** because PencilKit refreshes it from undo-manager notifications. Now each ink change is one step in the **document's** undo history (`DocumentModel.changeInk` inverse), PencilKit's own registration is off, and the canvas's `PaletteUndoManager` forwards undo/redo and relays the document's notifications. The zoom buttons are hidden while marking up (the palette covered them: the test's "Zoom In" tap hit the color picker). **iPad test passed:** palette Undo → 0 strokes, Redo → 1; after a pinch-zoom (canvas size checked) Undo → 0, Redo → 1; persistence as before. **Not verified:** ⌘Z itself (a ⌘Z injected by XCUITest never reached the app's undo in the Simulator, also before these changes); the Edit menu route should apply, check on a device. **Not verified:** Apple Pencil itself (needs a real iPad), the palette's eraser and lasso by hand. |
| Design pass 4 (document view), Claude, 21:10–21:30 | `./scripts/test.sh`: **passed, 119 tests**. `scripts/ui-test-ios.sh 63992C10-…`: **passed, 9 UI tests** (new `testFilterStripAndTitleMenu`: the strip's Grayscale tile applies and becomes selected, Original restores; the title menu adds then removes Favorites). `build-mac-app.sh` and the iOS build: passed, 0 warnings. Tapped through on iPhone: the title menu shows Rename… / Add to Favorites / Export…, and Add to Favorites set `is_favorite = 1` in SQLite. **First iPad check** (iPad Air 13-inch M4, iOS 26.5, screenshots only): library (sidebar counts and folders, 4-column grid, sort and layout controls) and document (title ▾ at the leading edge, rotate/crop/filter centered, Export and ⋯ trailing, page column with `+`). Screenshots `docs/screenshots/design-4-*`. **Not verified:** the Mac document window; iPad interactions (screenshots only); the selected-page border (system highlight remains). |
| Design pass 3 (Export sheet), Claude, 20:50–21:00 | `./scripts/test.sh`: **passed, 119 tests** (LocalizationTests cover the 7 new keys). `scripts/ui-test-ios.sh 63992C10-…`: **passed, 8 UI tests**. New: `testExportTilesSelectOneAtATimeAndCopyConfirms` (JPEG then Range then All each take their own tap inside Form rows; Copy → "Copied to the clipboard.") and `testExportSaveOpensTheSaveDialogAndClosingItKeepsTheExport` (Export → system "Save as" dialog → drag it closed → the ready footer still offers Save… and Share…). `build-mac-app.sh` and the iOS build: passed, 0 warnings. Screenshots `docs/screenshots/design-3-*`: fr (top), es (Export To), dark + largest accessibility text in fr (Pages tiles stack), en with a 5-page JPEG ZIP (Copy dimmed, note shown). **Found and fixed:** the rows' rounded corners clipped the selected tile's border (row edges are now inset); a wrapped French/Spanish label made one tile taller (tiles in a row now share a height). **Not verified:** the Mac sheet (never viewed), Share's system sheet contents, and pasting what Copy put on the clipboard into another app. |
| Design pass 2 (library, sidebar, iPhone home), Claude, 19:00–20:30 | `./scripts/test.sh`: **passed, 119 tests** (+3 `FolderTests`, +1 workflow test for folders/sort/import-into-folder). `scripts/ui-test-ios.sh 63992C10-…`: **passed, 6 UI tests**. New: `testAFolderMadeInTheSidebarHoldsAMovedDocument` (create a folder in the sidebar, move a document in from its ⋯ menu, check "1 item", delete the folder, document kept) and `testHomeRecentOpensADocumentAndSeeAllShowsTheGrid`. Existing tests updated for the iPhone home launch screen. `build-mac-app.sh` and the iOS Simulator build: passed, 0 warnings. Tapped through in the Simulator: Import from the home opens the picker, and the file lands in the library root (checked in SQLite). Screenshots `docs/screenshots/design-2-*` (library and home in en/fr/es/dark, sidebar): no truncation. **Found and fixed:** (1) buttons in a List row lost their styles (Scan looked enabled without a camera), so they moved to a section header; (2) the row's rounded corner clipped the first Recent card's date, so the Recent row is a header too; (3) on iPhone, setting the split-view selection and the library path together dropped the path (diagnosed with logs), so documents from Recent push over the home. **In-document pickers rechecked after moving the library's file importer to the root (an ancestor of every document view):** Replace Page with File… from a document opened via Recent replaced page 1 in place (3 → 5 pages, 1 history row, no new document), and Add Pages… from a document opened via All Documents added 3 pages (1 → 4, no new document), both checked in SQLite. **Not verified:** the Mac and iPad layouts; on the Mac, File > Import… and Page > Replace Page with File… after the importer move (same ancestor setup, never viewed); the camera paths (no device). |
| Combined tree: rescan + Codex's Clean & Native pass 1 (run by Claude, 18:52–19:00) | `./scripts/test.sh`: **passed, 115 tests**. `scripts/ui-test-ios.sh 63992C10-…`: **passed, 4 UI tests** (crop drag, Settings + backup, sidebar navigation, and Codex's new grid/list layout switch). |
| `./scripts/test.sh` (Xcode 27.1), after the atomic-rescan fix | **Passed: 115 tests** (20 + 26 + 17 + 17 + 35), 0 failures, 0 warnings. `scripts/ui-test-ios.sh 63992C10-…`: **3 UI tests passed**. `build-mac-app.sh` and the `PaperNestUI` iOS Simulator build: passed, 0 warnings. |
| Replace Page with File… in the owner's Simulator (iPhone 17 Pro, iOS 26.5), Xcode-built app | **Passed.** Page 2 of 3 replaced by the 3-page `multilingual-letter.pdf`: page 2 kept its place and selection, the 2 extra pages followed it (5 pages). SQLite: 1 `page_content_history` row holding the old content. Cancelling the picker (document menu and library Import) shows no alert and changes nothing. **Found and fixed on the way:** (1) replace silently became *add* (the `fileImporter` binding cleared the picker purpose before `onCompletion` ran); (2) the hand-assembled dev bundle lacked an entitlements section, so every picked file failed with "Could not resolve bookmark… permission" — `build-ios-sim-app.sh` now builds the Xcode project's app; (3) replace and extra-page insert were two commits — now one transaction (`replacePage`, nested savepoints). Undo was not exercised on the device (shake); it is covered by `LibraryWorkflowTests`. |
| `./scripts/test.sh` (Xcode 27.1), after rescan | **Passed: 111 tests** (17 + 17 + 18 + 24 + 35), 0 failures, 0 warnings. UI tests: 3 passed. |
| Rescan / replace in the owner's Simulator (iPhone 17 Pro, iOS 26.5) | The Add/Replace menu shows Scan Pages and Rescan Page **disabled** (no document camera, as intended), plus Add Pages… and Replace Page with File…; the file picker opens. **Picking failed:** "Could not resolve bookmark… you don't have permission" for files Claude copied into the simulator's Files storage from the Mac (the file provider never indexed them), so the app received nothing and the library was unchanged (checked in SQLite). Found and fixed: picker failures were silently ignored; they now show "couldn't be read". |
| `./scripts/test.sh` (Xcode 27.1), after Settings | **Passed: 107 tests** (17 + 17 + 17 + 21 + 35), 0 failures, 0 warnings |
| `scripts/ui-test-ios.sh 63992C10-…` after Settings | **Passed: 3 UI tests** (`AppUITests`: crop drag, Settings + backup, sidebar navigation), 0 warnings |
| Settings on iPhone 17 Pro (iOS 26.5), tapped through by Claude in the owner's attached Simulator | Shows 6 documents / 8 pages / 696 KB. **Export All produced `PaperNest Backup 2026-10-21.zip`; `unzip -t` OK; 6 PDFs. The cropped page is 221 × 311 pt (edit kept) and the rotated page 792 × 612.** French layout fits ("Prêt : 132 ko", Partager… / Enregistrer… / Terminé). Screenshots in `docs/screenshots/iphone-settings-*.png`. The Mac Settings window builds but has not been viewed. |
| `./scripts/test.sh` (Xcode 27.1), after the crop tool and the sidebar change | **Passed: 103 tests** (14 + 17 + 17 + 20 + 35), 0 failures, 0 warnings |
| `scripts/ui-test-ios.sh 63992C10-…` (XCUITest, iPhone 17 Pro, iOS 26.5) | **Passed: 2 UI tests**, 0 warnings: the crop drag test and a sidebar-navigation smoke test. The app also runs on iOS 26.5. |
| `scripts/ui-test-ios.sh` (XCUITest, iOS 27.1 Simulator, headless) | **Passed: `AppUITests`**, 0 warnings. Opens the crop editor, drags the top-left corner (value reads about 70% × 75%), taps Done, reopens, and finds the same crop saved. It also proved a Simulator app can open a library seeded on the Mac (`-PaperNestLibraryPath /tmp/…`). |
| `./scripts/test.sh` (Xcode 27.1) | **Passed: 87 tests** (run as 5 per-target processes: 13 + 16 + 20 + 29 + 9), 0 failures, 0 warnings |
| `./scripts/test.sh --sanitize=thread` (Xcode) | **Passed, 4 runs, 0 ThreadSanitizer reports.** `libclang_rt.tsan_osx_dynamic.dylib` confirmed linked into the test bundles with `otool -L`. |
| `./scripts/test.sh --sanitize=address` (Xcode) | **Passed, 1 run, 0 AddressSanitizer reports.** `libclang_rt.asan_osx_dynamic.dylib` confirmed linked. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **Passed**, 0 errors, 0 warnings. This was the first iOS compile of the shared code, including the VisionKit camera wrapper. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` | **Passed**, 0 errors, 0 warnings |
| `xcodegen generate` (XcodeGen 2.46.0) | **Passed**: `PaperNest.xcodeproj` with the `PaperNest-iOS` and `PaperNest-macOS` targets |
| `xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'generic/platform=iOS Simulator' build` | **Passed**, 0 compiler warnings. The bundle has ID `com.example.papernest`, MinimumOSVersion 17.0, UIDeviceFamily 1,2, the en/fr/es lproj folders, `PrivacyInfo.xcprivacy` and the UI resource bundle. |
| `xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-macOS -destination 'platform=macOS' build` | **Passed**, 0 compiler warnings. Same bundle ID, LSMinimumSystemVersion 14.0, sandbox and user-selected-file entitlements, `codesign --verify --strict` OK. |
| `./scripts/build-ios-sim-app.sh` | **Passed**: builds the Xcode project's `PaperNest-iOS` app (`com.example.papernest`), installed and launched on the simulator |
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
| Rescan / replace | `PageReplacementTests`, `LibraryWorkflowTests` | Replacing keeps ID, sort key and position, bumps the revision and returns the previous content; reversing restores it exactly. **A replaced original survives permanently deleting another item and is swept only after the next launch's purge.** Missing pages and missing originals fail without changes. **A rescan with extra pages is one transaction: if an extra page fails to insert, nothing changes; revert/reapply restore it whole.** Model: a password-protected replacement file asks again after a wrong password, then replaces; a locked PDF added after a page lands right there once unlocked. Workflow: rescanning page 2 of 3 with a 2-page capture puts the extra page after it, keeps the grayscale filter and resets the rotation; undo/redo; relaunch; export order. |
| Settings / backup | `StorageUsageTests`, `LibraryBackupTests`, `AppUITests` | Live document/page counts exclude Recently Deleted and deleted pages; space used includes originals. The backup is one valid ZIP with a PDF per document under unique, sanitized names; edits (rotation) are kept; empty documents are skipped; nothing to export is an error; **cancelling leaves no files**. UI test: open Settings from the overflow menu, run the backup, close. |
| Crop | `CropMappingTests`, `CropFrameTests`, `LibraryWorkflowTests`, `RenderTests`, `PDFExportTests`, `AppUITests` | Crop ↔ editor rectangle round-trips for every rotation. Source top-left maps to top-right after a clockwise turn. A rectangle drawn on an upside-down page selects the right source half. Drag math: corners beat edges, edges clamp to the page, edges can't cross or go below the 5% minimum, moving keeps the size. **A crop of a rotated page is undoable/redoable, re-applying the same crop isn't a new edit, and it survives relaunch and exports at the cropped size, landscape, with the marker top-right.** **Found in review and fixed:** a filtered PDF page with a tight (25%) crop failed to render at 3072 px and to export to Letter/A4 (`outputTooLarge`), because the whole page was rasterized at the crop's resolution. Only the crop region is rasterized now; tests cover both paths. |
| Localization | `LocalizationTests` | Every key used exists in en/fr/es. Identical key sets and format arguments. No unused keys. Plurals (French 0/1 singular). French typography. |
| Workflow (view models) | `LibraryWorkflowTests` | **M1 gate on the Mac import path:** import PDF, EXIF photo, locked PDF (wrong password, then right) and an unsupported file. Rotate, move, delete, **undo and redo** (delete and rotate round trips). Drop the session (quit), reopen, then export: order, rotation and text preserved. Recently Deleted flow. Search. Newer-library message. |

### Simulator verified (iPhone, screenshots only)

Device: a dedicated "PaperNest iPhone Duo" simulator (iOS 27.1). It was recreated on 2026-10-21 after all iOS 27.1 simulators disappeared from the machine for reasons outside this session. It's the only device type the installed iOS 27.1 runtime supports, so **no iPad simulator was available** and the iPad layout is not verified. The library was seeded from `Samples/` with `papernest-seed` (the real importer). Screens were opened with debug-only launch arguments (`-PaperNestDebugOpenItem`, `-PaperNestDebugShowExport`) and captured with `xcrun simctl io … screenshot --display=primary`. **No taps or gestures were exercised.** Screenshots are in `docs/screenshots/`.

| Screen | Result |
|---|---|
| Empty library (en) | Correct title, search field, empty-state message, Import button. Scan is disabled because the Simulator has no document camera (intended fallback). |
| Library grid (en, fr) | All six samples render. The EXIF-6 photo is upright, the transparent PNG shows ink on white, and the protected PDF shows its unlocked content. "1 page · Oct 20, 2026" / "1 page · 20 oct. 2026". |
| Document (en, es) | **Found and fixed:** the page strip took half the iPhone width and the actions were hidden in an overflow menu. iPhone now shows the page full width, a thumbnail scroller, and the actions in the bottom toolbar. |
| Export sheet (en, fr, es) | **Found and fixed:** a 440-pt minimum width clipped the sheet on iPhone, and the option values truncated in French and Spanish ("Toutes…pages", "Tamañ…original"). It now uses inline option rows on iOS; the Mac keeps pop-up menus. |
| Crop editor (en, fr) | Opens over the uncropped page with a dimmed outside, frame, thirds guide and corner handles, Reset disabled at full crop. **Found and fixed:** the white frame and handles were invisible over white paper; they now have dark underlays. Checked with a page cropped by `papernest-seed --crop`. The drag is exercised by `AppUITests` (see above). |
| Cropped page in the document view | The app renders the seeded crop correctly: the marker and the rule are at the expected positions. |
| Launch log | **Found and fixed:** ⌘E for Export clashed with the system "Use Selection for Find" shortcut. Export is now ⇧⌘E. |

### Not covered by automated tests yet

- SwiftUI interaction beyond the crop editor. `PaperNest-iOSUITests` covers only crop so far, and the Mac has no UI tests.
- iPad layout (no compatible simulator runtime) and real devices
- Performance at 1/20/100 pages (no measurements taken; no numbers are claimed)
- Storage-full and low-memory behavior

## Open issue: an unexplained navigation glitch on iPhone (2026-10-21)

The first tap on a library thumbnail after launching on the owner's iPhone 17 Pro simulator (iOS 26.5) switched the scope to Favorites instead of opening the document. After that, Back → All Documents left navigation stuck. Root cause not identified. It could not be reproduced in three later attempts with the same sequence, or by the UI test.
- **Change made:** the sidebar selection is now optional (`LibraryModel.sidebarSelection`), as NavigationSplitView expects on iPhone, where it clears the selection when the user goes back. Unit test added.
- **Not proven to fix the glitch:** the UI smoke test passes with both the old and new binding.
- **If it recurs:** capture the exact tap timing (it happened right after a fresh install and launch) and check whether the sidebar list is hit-testable under the pushed library.

Also found by tapping and fixed: the crop sheet's title was black on the dark canvas. The sheet now uses dark appearance on iOS.

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
| Crop: Page > Crop… (⌘K), drag corners/edges/inside, Reset, Done, then undo/redo, export | Mac | Not run (on iPhone, the corner drag → Done → saved path is covered by `AppUITests`) |
| Export sheet: each format, page ranges, save panel, share menu, file opens in Preview | Mac | Not run |
| French and Spanish UI (`-AppleLanguages "(fr)"`): no truncation in sidebar, toolbar, export sheet | Mac | Not run |
| VoiceOver: grid cells read name + page count; page thumbnails read "Page n of m" | Mac | Not run |
| Sandboxed build (`--sandbox`): import via panel and drop, export via save panel | Mac | Not run |
| Tap through on iPhone: open a document, rotate, filter, Pages sheet reorder, export and save | iPhone (Simulator) | Not run: no taps were exercised |
| iPad split layout, keyboard shortcuts | iPad | **Blocked**: the installed runtime has no iPad simulator; needs an iPad runtime or device |
| Physical camera capture: multi-page scan, cancel, permission denied; Scan Pages and Rescan Page | iPhone | **Blocked**: needs a device and signing (team ID) |
| Replace Page with File… end to end (pick a file, page replaced, undo) | iPhone Simulator, Mac | **iPhone Simulator: passed** (see above; undo covered by tests only). **Mac: not run** (Page > Replace Page with File…) |
| Apple Pencil feel: latency, palm rejection, pressure, hover, Draw with Finger off by default | iPad + Apple Pencil (real device) | **Not run: needs a real iPad and Apple Pencil.** The first slice is built and Simulator-tested with finger drawing (see pass 7 above) |
| Document tools: Select, Duplicate, Merge Documents, Extract Pages, Color Label, Move to Folder, bulk Delete | Mac | **Not run**: the Mac build compiles the selection bar and the tools sheet, but no one has viewed them |
| Document tools: duplicate, select, color label, merge, extract, in en/fr/es | iPad (Simulator) | **Passed** on an iPad Air 13-inch (M4), iOS 26.5, after the test fix: `scripts/ui-test-ios.sh 62328381-… -only-testing:PaperNest-iOSUITests/AppUITests/testDocumentTools…` — both tests, 58.2 s and 86.1 s. Screenshots `docs/screenshots/f1-tools-ipad-*`. |
| Two-device iCloud sync | iPhone + iPad/Mac | Not applicable until M2 |
| Exported PDF/JPEG/PNG/ZIP open in Preview, Acrobat, Files | All | Automated structural checks passed. Not opened in external apps. |

## Performance log

No measurements yet. Record device, OS, document size (1/20/100 pages), elapsed time, peak memory and responsiveness notes here when they're taken.

## Tools screen continuation verification — 2026-10-24

The resumed chat referenced the old DOCS PRO checkout and unfinished Tools toolbar verification. The current checkout is Desktop/PaperNest; the existing 2026-10-23 Tools fixes were preserved. No application source changes were needed in this continuation.

- Full `./scripts/test.sh`: 235 tests passed (47 + 76 + 47 + 26 + 39); no compiler warning/error matches in the log. Log: `/private/tmp/papernest-tools-resume-tests.log`.
- iPhone 17 Pro: `testToolsScreenPicksTwoDocumentsAndMergesThem` and `testAFolderMadeInTheSidebarHoldsAMovedDocument` both passed, 0 failures; `TEST SUCCEEDED`. Log: `/private/tmp/papernest-tools-resume-ui.log`. Result: cache `build-17de0868e51d/xcodeproj/Logs/Test/Test-PaperNest-iOS-2026.10.24_13-10-01--0500.xcresult`.
- This run covers Tools merge and the folder regression on iPhone. It does not newly verify iPad, Mac UI, all Tools actions, or real camera access. Xcode emitted operating-system-build parsing diagnostics after the successful tests.
- Existing work and Qwen reservations remain intact. No commit or push. No test process remains active from this continuation.

## PDF pass-through on export — 2026-10-26 (Claude, backend)

An unedited imported PDF page is now copied from its source file instead of being
redrawn, so its links and annotations survive export. Pages that *have* been
changed keep going down the drawing path.

- Full `./scripts/test.sh`: **371 tests passed** (64 + 123 + 77 + 65 + 42), **0 warnings**.
  Log: `scratchpad/suite.log` (session scratchpad).
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings — built and signed
  `~/Library/Caches/PaperNest/build-17de0868e51d/dist/PaperNest.app`.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.
- 11 tests in `PDFPassThroughTests`, all passed: a link survives with its URL; a
  form widget survives with its `/T` name; title and creator are preserved; text
  and page count unchanged; a cropped page is redrawn and loses its annotations
  (the honest trade, pinned); Letter paper redraws every page; a mixed document
  keeps order and treats each page on its own; a passed-through page does not
  disturb a drawn OCR layer on its neighbour; the export carries the source's
  form dictionary; compressing an unedited page still keeps its link; a page
  getting a recognised-text layer is redrawn.

### What this does **not** establish

- **Interactive form fields are not verified, and ledger row 24 stays Planned.**
  The widget and its name survive, read back through PDFKit. Read back through
  Core Graphics, the exported file has **no** catalog `AcroForm` — and neither
  does the synthetic fixture, because PDFKit writes a widget's `/T` without
  building a form dictionary. So nothing here shows a real form staying
  fillable in another reader. That needs a hand-built fixture with a real
  `/AcroForm`.
- **Behaviour change to note:** compressing an unedited PDF now keeps its links,
  because the page is copied rather than drawn.
- **Pre-existing limitation found while measuring, not introduced here:**
  compression cannot shrink a scanned PDF. An unedited PDF page is never
  re-encoded, so every preset returns it as it was — 8521 bytes copied against
  8531 drawn, identical at `.light` and `.smallest`. It reports no saving rather
  than a fake one.
- No UI was involved; this is export-path logic only. Nothing committed.

## Compressing a scanned PDF — 2026-10-26 (Claude, backend)

Compression can now shrink a PDF whose pages are photographs. A `.pdfPage`
carrying no text of its own is re-encoded as a JPEG at the preset, and the
re-encode is kept **only when it is smaller than the page already is**.

- Full `./scripts/test.sh`: **378 tests passed** (64 + 123 + 77 + 72 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings — built and signed
  `~/Library/Caches/PaperNest/build-17de0868e51d/dist/PaperNest.app`.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured, on a 1600×2000 raster inside a 612×792 page

| source | original | plain export | light | strong | smallest |
|---|---|---|---|---|---|
| scan | 193,043 | 193,103 | 193,103 | 113,235 (−41%) | 56,430 (−71%) |
| digital text PDF | 8,007 | 8,044 | 8,044 | 8,044 | 8,044 |
| blank page | 2,140 | 2,207 | 2,207 | 2,207 | 2,207 |

Seven new tests in `CompressionTests`: a scanned PDF gets smaller at Smallest;
a stronger preset shrinks it further and keeps both pages; the compressed file
differs from a plain export (so the page really is re-encoded, not copied); a
preset that would enlarge the page leaves it alone; a blank page is not
rasterized into something larger (with a precondition asserting the fixture
really is text-free, so the test cannot pass for the wrong reason); a cropped
scanned page is re-encoded **and keeps its crop**; a page too large to
rasterize is left alone rather than failing the export. The two existing guards
still pass — `aVectorPDFKeepsItsTextInsteadOfBeingRasterizedToSaveBytes` and
`anAlreadyCompactOriginalReportsNoSavingRatherThanAFakeOne`.

### A regression caught before it shipped

The first working version rasterized every text-free page at the preset's dpi.
Light is 300 dpi, which **upsamples** a scan of lower resolution: it produced
**416,360 bytes from a 193,043-byte page** — a "compression" that more than
doubled the file, where the old code had simply copied the page. A re-encode is
now measured against the page it would replace, per page, by writing the copied
page alone into a document. Light therefore falls back to copying.
`aPresetThatWouldEnlargeAScannedPageLeavesItAlone` pins it.

### Two more bugs the fixtures found

- **A protected PDF came back as a blank page reported as a 99% saving.** A
  locked document hands back no text, so `carriesText` is false and every page
  looks like a scan; the locked `CGPDFDocument` then draws nothing and the
  white page beats any budget — **845 bytes from 8,110, one grey level**. The
  output also had its encryption stripped. Compression now refuses an
  encrypted or locked PDF outright, which also covers an owner password that
  restricts copying: assembling the output fresh drops that restriction, and
  handing back an unrestricted copy is not ours to do. **Documents are
  unaffected** — the importer stores a decrypted copy and verifies it.
- **A rotated page was distorted.** Sizing the re-encoded page from PDFKit's
  media box ignores `/Rotate`, so a landscape phone scan (portrait media box,
  `/Rotate 90`) had 792×612 of content squeezed into a portrait page: the
  input rendered 396×306 and the output 306×396. The size now comes from
  `PageGeometry.uprightPDFSize` of the crop box.

### What this does **not** do

- **Only image-only scans compress.** A page with text is never rasterized,
  because that destroys every word for a reader, a search and an export. Most
  scanner apps — Notes, Adobe Scan, ScanSnap — embed an invisible OCR layer,
  and that counts as text here, so **those PDFs still will not compress**. This
  bounds how often the feature helps, and it is not a tunable threshold: any
  text at all means the page is left alone.
- **Light rarely helps a scan**, for the upsampling reason above. The savings
  are at Strong and Smallest.
- A page too large to rasterize (over 100M pixels) is left alone rather than
  failing the export — now covered by a test using an 8000pt-square page, about
  1.1 billion pixels at Light's 300 dpi.
- A page that already needs pixel processing (filter, brightness, contrast) is
  excluded from the measurement, because the ordinary path rasterizes it at the
  same quality anyway and measuring would rasterize it twice for identical
  bytes. Its behaviour is unchanged by this slice.
- Only synthetic fixtures were used. **No PDF from a real scanner app has been
  compressed**, so the OCR-layer claim above is reasoned from the rule, not
  measured on a real file.
- No UI: there is still no Compress action in any screen, so none of this is
  user-reachable. Whoever adds one owns showing these real before/after bytes.
- Nothing committed.

## Compressing a PDF kept as a file — 2026-10-27 (Claude, backend)

`compress(fileNamed:data:preset:)` used to refuse a PDF outright. It now
reduces one page by page: pages that carry text are copied untouched, pages
that do not are re-encoded at the preset and kept only when they beat the page
they would replace.

- Full `./scripts/test.sh`: **385 tests passed** (64 + 123 + 77 + 79 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured, on a loose PDF file

| source | original | light | strong | smallest |
|---|---|---|---|---|
| 1600×2000 scan in a 612×792 page | 193,043 | 193,092 | 111,920 (−42%) | 55,115 (−71%) |
| digital text PDF | 8,007 | 8,028 | 8,028 | 8,028 |

Seven new tests in `FileCompressionTests`: a scanned PDF file is reduced rather
than refused (with the output page rendered and checked for content, and a size
floor); a digital PDF keeps its text and reports no saving; pages keep their
order; a preset that would enlarge the file leaves its pages alone; an
encrypted PDF is refused rather than returned blank; a restricted PDF is
refused rather than stripped of its restrictions, leaving no directory behind;
a rotated scanned page keeps its orientation. Both existing refusal guards
still pass — non-image, non-PDF bytes throw `unsupportedFormat` and leave no
directory behind.

### A bug my own test failed to catch

The first version returned **869 bytes from a 193 KB scan** and the test passed,
because it asserted only `isSmaller` — and a blank page is the smallest file of
all. The re-encoded page was built in a one-page `PDFDocument` that was a local
variable, so it was deallocated on return; **a copied `PDFPage` is read lazily
from the document it came from**, and the page serialized empty. The rebuilt
documents are now held until the output has been serialized. This is the same
trap recorded for the pass-through slice, written down there and then walked
into here.

The test now renders the output page and asserts it has more than 8 distinct
grey levels, plus a floor of 10% of the original size. Either assertion fails
at 869 bytes.

### What this does **not** do

- **Only image-only scans benefit.** A page with text is never rasterized. Most
  scanner apps embed an invisible OCR layer, which counts as text, so most real
  PDFs will report no saving. This is the usual answer for PDFs, not the
  exception.
- **Light usually does nothing to a scan** — 300 dpi upsamples most of them, so
  the re-encode is discarded.
- Only synthetic fixtures. **No PDF from a real scanner app has been compressed.**
- **A password-protected or restricted PDF cannot be compressed at all**, by
  choice. Preserving an owner's restrictions through a rebuild is unsolved, so
  it is refused rather than quietly stripped.
- Replacing the stored file with its reduced copy is still a separate decision,
  not taken here. Folder and archive compression remain.
- No UI: there is still no Compress action in any screen.
- Nothing committed.

## Encrypted PDF export — Set Password, row 27 — 2026-10-27 (Claude, backend)

`Exporter.export` takes an optional password and writes a PDF that requires it
to open. Row 27 goes from "no encrypted export" to an engine that has one.

- Full `./scripts/test.sh`: **397 tests passed** (64 + 123 + 77 + 91 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### What the encryption is — measured, not assumed

Read out of the `/Encrypt` dictionary in the written bytes. Both `CGPDFContext`
and `PDFDocument.write(to:withOptions:)` produce the same thing:

```
/Encrypt  /V 4  /R 4  /Length 128  /AESV2  /StmF /StdCF  /EncryptMetadata true
```

- `/AESV2` is **AES-128 in CBC mode**. **Not RC4** — which was the outcome that
  would have made this dishonest to ship at all.
- Revision 4, **not** revision 6 (AES-256, PDF 2.0). Apple's APIs do not expose
  revision 6.
- Revision 4's key derivation is MD5-based and fast, so **the strength is the
  password**, not the cipher. A short password falls to an offline attack.
- A test reads the bytes back and fails if the handler stops being AES, so the
  documented claim cannot quietly become false after an OS update.

**Sayable:** "encrypted with AES-128", "needs this password to open".
**Not sayable:** "secure", "military-grade", or anything implying a weak
password is safe. This wording is in `docs/CODEX_BRIEF.md` for whoever builds
the screen.

### Eleven tests in `EncryptedExportTests`

The file needs the password to open, rejects a wrong one and opens with the
right one with its text intact; an **empty** password does not open it; without
a password nothing is encrypted; an untouched (passed-through) page still
arrives encrypted and still has its link; a **mixed** document keeps every page
and its title; a document with **no** untouched page is encrypted by the
context itself; the handler is AES; a password is refused for JPEG, PNG, TXT
and DOCX; an empty password is refused; a non-ASCII password is refused; and
only the first 32 bytes of a password are honoured.

### Password limits — measured, and they affect the French and Spanish builds

- **ASCII only.** `"été-Ñandú-2026"` failed to write *even though every
  character is Latin-1*, and PDFKit refused `"contraseña-密码-1"` outright. So
  Latin-1 is not the boundary in practice, and non-ASCII is refused up front
  with `ExportError.passwordNotRepresentable` rather than surfacing later as a
  write error. An accented password is a realistic thing for an fr/es user to
  type, so the screen has to say what is allowed before they type it.
- **Only the first 32 bytes count.** A 32-character prefix opens a file written
  with a 44-character password. The full password still works, so this is a
  documentation point rather than a failure — but a longer passphrase is not
  stronger. A test pins it.

### Three traps this had to avoid

- **The owner password matters.** A PDF opens with *either* password. Setting
  only the user password leaves an empty owner password, which opens the file
  regardless — protection that is not protection. Both are set to the same
  value, and a test asserts an empty password fails.
- **Pass-through re-writes the finished file and would have dropped the
  encryption.** `writePDF` encrypts through the context, then pass-through
  assembles the document in PDFKit and writes it to a staged file that replaces
  the encrypted one. The password is re-applied on that write. Same shape as
  compression stripping an owner's restrictions, found yesterday.
- **The reopened file is locked, and a locked document yields blank pages.**
  `replaceWithSourcePages` reopens the encrypted file and copies every page
  that did not pass through out of it. A **mixed** document came back with its
  drawn page blank and **its title gone**, while the passed-through page looked
  perfect — so the single-page test passed and hid it. `drawn` is now unlocked
  before anything is copied. This is the third instance of this same shape in
  two days.

### What this does **not** do

- **No UI.** There is no Set Password action in any screen, so this is not
  user-reachable. It must not appear until the wording above is right.
- **Permissions are not settable** — only whether a password is needed to open.
  No print/copy flags.
- **No non-ASCII password**, which is a real restriction for fr/es users.
- **No password recovery.** A lost password is a lost file. Whoever builds the
  screen owns saying so before the file is written.
- A password-protected PDF still **cannot be compressed** (refused, 2026-10-27),
  so offering both actions needs an explanation rather than a silent failure.
- Not opened in Preview, Acrobat or any other reader — PDFKit and raw-byte
  checks only.
- Nothing committed.

## A digital PDF's text keeps its lines on export — 2026-10-27 (Claude, backend)

TXT and DOCX export read a digital PDF's text from the page's own file instead
of from the search index.

- Full `./scripts/test.sh`: **399 tests passed** (64 + 123 + 77 + 93 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Two faults, one cause

The recorded limitation was that embedded PDF text exported as **one run-on
paragraph**, because `LibraryStore.embeddedText` returns what was indexed for
FTS, normalized for matching. In DOCX that meant a whole page in a single
`<w:p>` — the layout a Word export exists to carry, discarded at the last step.

Writing the test exposed a second fault nobody had recorded: the index is
written by a **background pass**, so a PDF exported soon after import had no
indexed text and the export was refused as `noTextToExport` — for a document
whose every word was sitting in the file. Reading the page's own file fixes
both, and the text is current by construction, since `page.content` names the
asset the page shows now.

The earlier note said this needed `PDFTextExtractor` moved so
`PaperNestExport` could reach it. It did not: `PDFPage.string` gives the lines,
and `PaperNestExport` already opens source PDFs with PDFKit for pass-through.
No module graph change.

### The existing tests were asserting on fiction

Every embedded-text export test seeded the search index with text that was **not
in the PDF** — indexing "Council tax notice for 2026" against a page whose text
was "Council tax notice", or "First page words" against a page reading "One".
They tested the path from index to file, never that a real digital PDF's words
come out. Two of them asserted a document had *no* text while importing a PDF
that plainly had some, and passed only because nothing had been indexed.

They now put the text in the PDF, and the two "no text" tests use a scan, which
genuinely carries none. Same intent, honest fixtures.

### What this does **not** do

- The search index keeps its normalized copy, which is correct for matching.
  Nothing in search changed.
- A cropped page still exports the whole page's text. A crop is a display
  transform, not a redaction — true of the indexed copy too.
- **Still nobody has opened a .docx in a word processor.** Unchanged and still
  owed.
- No UI for either format.
- Nothing committed.

### The shared temporary root bit again

`cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind` failed once during this
work, on residue — one `PaperNestExport-…` directory left by *my own* failing
test earlier in the session. A test that expects a refusal and instead receives
an `ExportOutput` has no `defer` to clean it up, so it leaks. Verified by
listing the directory and matching the UUID before re-running, rather than
assuming. Worth knowing when writing refusal tests.

## Permanent redaction, engine — row 26 — 2026-10-27 (Claude, backend)

Redaction that removes content rather than covering it. Engine only: there is
no screen and no orchestration, because `DocumentModel` is Codex's file.

- Full `./scripts/test.sh`: **406 tests passed** (64 + 126 + 81 + 93 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The design question, answered by the code

The worry was that redaction conflicts with "originals are never modified". It
does not. The library already supports *deleting* an original, which is a
different thing: `replacePageContent` files the old content in
`page_content_history`, and `sweepOrphanAssets` deletes any asset referenced by
no page, history row, file item or placed image. So redaction is render →
replace → forget that page's history → sweep. A redaction-only export path was
the alternative and is the weaker promise; it is not needed.

`replacePageContent` already deletes the page's `ocr` and `pdfText` rows from
`search_index`, so redacted words stop answering searches the moment the
content changes. That part was already right.

### Seven tests, written to fail for a redaction that only looks right

Four on the bytes (`PageRedactionTests`): the redacted words are not in the
output at all; the pixels where they were are black across the whole band while
the rest of the page survives; redacting no rectangles is refused rather than
silently rewriting the page; a scanned page redacts too. Three on the library
(`RedactionStoreTests`): forgetting the history lets the original be swept; a
**shared** original is kept and `isAssetReferenced` says so; the recognised
words are deleted rather than merely unindexed.

### Three limits, each one load-bearing

- **A digital PDF loses selectable text across the whole page**, not only the
  redacted part. Text under a painted rectangle survives any amount of drawing
  on top, so the only honest mechanism is to flatten the page to pixels. The
  page becomes a picture of itself and stops being searchable.
- **A shared original cannot be deleted.** Assets are content-addressed, so two
  pages of identical paper share one; if another page still shows it, the sweep
  correctly keeps it and the content stays reachable through that page.
  `isAssetReferenced` exists so a caller can find this out *before* promising
  anything.
- **Deleting a file does not scrub the disk.** The bytes may persist until
  overwritten, and on a copy-on-write filesystem that is not controllable from
  here. Nothing may say "securely erased" or "unrecoverable".

### What this does **not** do

- **No UI and no orchestration.** Nothing calls `PageRedaction` yet. The
  wording a screen must carry is in `docs/CODEX_BRIEF.md`.
- **Ink, comments and stamps under a rectangle are untouched.** They are
  separate rows; a note containing the redacted thing survives.
- `sweepOrphanAssets` has a one-hour grace period by default, so an original
  survives until the next sweep unless the caller asks for none. Stated rather
  than changed.
- PNG, chosen so a lossy encode cannot leave ringing around a painted edge —
  reasoned, not measured against a recovery tool.
- Nothing committed.

## WebP import — row 32 — 2026-10-27 (Claude, backend)

The row carried a standing instruction: *add WEBP only after codec
verification.* The verification came first and decided the shape of the work.

- Full `./scripts/test.sh`: **411 tests passed** (64 + 126 + 86 + 93 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### What ImageIO actually supports

```
CGImageSourceCopyTypeIdentifiers      → includes org.webmproject.webp
CGImageDestinationCopyTypeIdentifiers → no webp entry
CGImageDestinationCreateWithData(…webp…) → nil
```

**It decodes WebP and cannot encode it.** So:

- Importing a `.webp` is supportable, and now works.
- **Converting *to* WebP is not possible with system frameworks.** That is
  settled, not pending: it needs a third-party encoder (libwebp) and the
  licensing and binary-size decision that comes with one. Row 32 says so now
  rather than leaving a to-do that looks small.
- A WebP fixture cannot be generated at runtime, which is why
  `SyntheticDocuments.webPImage()` is a 50-byte literal rather than drawn. It
  was produced once with Pillow, outside the build.

### Five tests

WebP bytes are recognised; other RIFF files (WAV, AVI) are **not** claimed as
WebP; a `.webp` imports as one image page stored under its own kind with a
`webp` extension; the fixture decodes to the right pixels — its top-left
quadrant red and the rest white, so the test proves a real decode rather than
mere acceptance; and an imported WebP prepares as an image for rendering and
export.

### A wrong assumption, caught by the test

I recorded in the plan that `AssetKind` is a plain string enum needing no
migration. That was wrong: `assets.kind` carries a SQL `CHECK` constraint, and
the import failed with *CHECK constraint failed: kind IN ('pdf','jpeg','png',
'heic','file')*. **Schema v8** widens it, following the v6 migration that added
HEIC exactly. The next migration must be v9.

`PageCommentTests` asserted `schemaVersion() == 7` literally; it now uses
`Schema.latestVersion`, as the three other version assertions already did, so
it stops being a tripwire for every future migration. That file is Codex's
area — the change is one line and mechanical, noted here and in the handoff.

### What this does **not** do

- **No WebP output of any kind**, and no UI change: import simply accepts one
  more type.
- **Animated WebP decodes to its first frame.** That is not animation support
  and must not be described as such.
- Only the 16×16 literal was tried. **No photograph-sized or animated WebP, and
  no file from a real camera or website, has been imported.**
- Nothing committed.

## Native Mac run — 2026-10-27 (Claude, manual)

The first native Mac interaction actually performed in this project. Previous
entries recorded it as unrun and blocked: Codex has no computer-use tools, and
this session's app-access request had been denied twice. It was granted today,
for `com.example.papernest.dev`.

Run against a **throwaway library** at `/tmp/papernest-dev-library`, seeded
fresh from `Samples/` by `scripts/run-mac-app.sh` — 7 documents (oio,
whiteboard-300dpi, transparent-ink, receipt-portrait-exif6, rotated-page,
password-protected and one more). No real library was opened.

### Verified by doing it

- **Home screen** renders with the library: sidebar (Home; Library with All
  Documents 7, Favorites, Recently Deleted; Folders) and a Recent grid whose
  thumbnails draw. **No Scan card on Mac**, which is correct — there is no
  document camera — leaving New Notebook, Import… and New Folder.
- **A document opens and renders** (transparent-ink), with a native toolbar
  exposed as named accessibility elements: Back, Rotate Right, Crop, Filters,
  Export…, More, Zoom Out, Zoom to Fit, Zoom In, Hide Sidebar, and an "Add or
  Replace Pages" control.
- **The menu bar exists and is app-specific:** PaperNest, File, Edit, View,
  **Page**, Window, Help. Page holds Rotate Left, Rotate Right, Replace Page
  with File…, Crop…, Move Page Up, Move Page Down, Revert to Original, Delete
  Page.
- **A menu command works end to end.** Page ▸ Rotate Right applied the quarter
  turn — content moved as expected and **both the canvas and the sidebar
  thumbnail re-rendered** — and Page ▸ Revert to Original restored it. The
  library was left as seeded.
- **The export sheet opens** with PDF / JPEG / PNG, All Pages / Current Page /
  Range, Paper Size and Image Quality, matching iOS.

### The "launched but no window" scare — diagnosed, and the script is fine

Recorded first as a possible fault in `scripts/run-mac-app.sh`: it exited 0 and
reported the app opened, the process was alive, and yet there was **no window**;
`app_list_windows` returned empty twice, including after an explicit relaunch.
Running the binary directly produced a window at once, which made the script
look guilty.

**It is not the script.** Reproduced and tested:

| Launch | Window? |
|---|---|
| `open -n` from a foreground shell, warm bundle | yes, at once |
| `open -n` after a rebuild and re-sign | yes, at once |
| `open -n` from a **backgrounded** task | yes, at once |
| full script, **fresh library**, backgrounded | yes — but `is_off_space: true` |

The last run is the answer. The window **is** created, on a regular desktop
Space; `app_bring_to_current_space` then refused with the reason: *the current
Space is a full-screen app, and a window cannot be moved into a full-screen
Space.* So the app launches correctly and its window lands on a desktop Space
that is not the one being looked at — which from the front looks exactly like
"launched, no window". A screenshot of that window by id shows it healthy, with
the seeded library listed.

Three hypotheses were tested and **disproved** on the way: the `open -n` launch
method, a cold signature after rebuild, and launching from a detached shell with
no GUI session. Each one produced a window immediately.

Not proven: the very first attempts returned an *empty* window list rather than
reporting an off-Space window. That is consistent with the same cause, before
the window could be enumerated, but it was not reproduced and is not claimed.

**If the Mac app seems not to launch:** check a regular desktop Space (Mission
Control, or click the Dock icon) before suspecting the build or the script.

### Not done

- **No export was completed on Mac.** The sheet was opened and closed; the
  file-writing path was exercised on iPhone instead (below).
- **VoiceOver, Dynamic Type, the two-window conflict pass and localized (fr/es)
  Mac runs remain unrun.** This entry does not close those.
- No markup, shapes, stamps or comments were exercised on Mac.
- Only one document of the seven was opened.

### Same build, same day, on iOS

The iOS Simulator build from this tree was also run by hand: on **iPhone 17
Pro**, Home and the document editor render and **an export completed** — all 5
pages as PDF at Original Size, which is the pass-through path, producing a real
file the system save sheet previewed, reported as "Ready: 35 KB"; nothing was
saved. On **iPad Air 13-inch (M4)**, the three-column layout renders and
creating a grid notebook saved and opened with the template drawing correctly.
On both, Scan is correctly disabled and the export sheet offers only PDF/JPEG/
PNG — no TXT, DOCX, Compress, Set Password or Redact — which matches the
"engine exists, no UI" notes rather than contradicting them.

## Redaction as an operation — row 26 — 2026-10-27 (Claude, backend)

The redaction engine landed this morning and **nothing called it**. Composing
the steps is now one operation, so a caller cannot do three of the four and
believe the job is done.

- Full `./scripts/test.sh`: **415 tests passed** (64 + 127 + 89 + 93 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Why it is one call and not four

Rendering alone leaves the original in the library. Replacing the content alone
leaves the recognised words in `page_recognition`. Forgetting the undo history
alone leaves the file on disk. `PageRedactor.redact` does all of it: render,
stage the asset durably, `replacePageContent`, `deleteRecognition`,
`forgetReplacedContent`, then delete the original if nothing else shows it.

### Two decisions about not misleading the caller

- **`originalStillInLibrary` is named so the unsafe answer is `true`.** Assets
  are content-addressed, so two pages of identical paper share one file.
  Redacting one page cannot delete it and the words stay reachable through the
  other page. A caller has to read that flag before claiming anything, and the
  naming puts the dangerous case where it will be noticed.
- **`deleteAssetIfUnreferenced` is targeted, not a sweep.** `sweepOrphanAssets`
  has a one-hour grace period protecting assets staged but not yet referenced;
  calling it with no grace period to collect one file could take another
  operation's freshly staged bytes. The new call touches one asset and refuses
  if anything still points at it. **Row before file**, as the sweep does: a
  crash between leaves an orphan file the sweep collects, while the other order
  would leave a row pointing at nothing.

### Four new tests

The unreferenced asset is deleted — row *and* file — while a referenced one is
refused and kept; after redacting, the page shows the new image, the words do
not answer searches, the recognition row is gone and the original file is off
disk; a **shared** original survives and the outcome says so, with the second
document's paper still present; and the page keeps its id, sort key, crop and
source size.

### What this does **not** do

- **Still no UI.** `DocumentView`/`DocumentModel` are Codex's, and the wording
  any screen must carry is in `docs/CODEX_BRIEF.md`.
- Ink, comments and stamps under a rectangle are untouched — separate rows.
- A digital PDF still loses selectable text across the whole page: flattening
  is the mechanism.
- **It does not scrub the disk.** Deleting a file unlinks it; the bytes may
  persist until overwritten. Nothing may say "securely erased".
- Nothing committed.

### A warning-free build is part of done

The first green run passed every test but raised **4 warnings** — unnecessary
`await`/`try` markers (`store.assets` is not isolated) and an unused
`transaction` result. Fixed before claiming the slice, and the final run is
back to 0 across tests and both builds.

## HEIC export — row 32 — 2026-10-27 (Claude, backend)

Row 32's remaining half. HEIC *import* landed in F2c; writing one has never
been possible, so an exported photo was a JPEG about three times larger than
it needed to be.

- Full `./scripts/test.sh`: **420 tests passed** (64 + 127 + 89 + 98 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured before anything was written

The WebP slice earlier today found ImageIO's support can be **asymmetric** —
it reads WebP and cannot write it — so HEIC was checked the same way instead of
being assumed from the import note:

```
CGImageDestinationCopyTypeIdentifiers → public.heic, public.heics
CGImageSourceCopyTypeIdentifiers      → public.heic, public.heics, public.heif
```

Symmetric. The same 1600×2000 page, same quality setting:

| format | bytes |
|---|---|
| HEIC | 94,742 |
| PNG | 209,699 |
| JPEG | 284,377 |

About a third of the JPEG, round-tripping to the same dimensions, with the
requested 200 dpi coming back as 200.

### The trap, and the test that catches it

`writeImages` chose its type with `options.format == .jpeg ? .jpeg : .png`. A
new case falls into that `else`, so HEIC export would have written **PNG bytes
into a file named `.heic`** — a lie on disk that every filename-based check
would have passed. The switch is now exhaustive, and
`theFileIsReallyHEICAndNotPNGWearingTheExtension` reads the written bytes back
and asserts `CGImageSourceGetType` is `public.heic`. The name is not the
evidence.

### Six tests

The bytes really are HEIC; it decodes back at the requested resolution with its
dpi intact; it is less than half the size of the same page as PNG; PDF, JPEG
and PNG are each unchanged; and several pages still package as a ZIP holding
`.heic` entries.

### What this does **not** do

- **No UI tile**, as with every format added this way. `ExportFormat` is
  `CaseIterable` but **nothing iterates `allCases`** (checked, as when TXT and
  DOCX were added); the sheet's tiles are hand-written and `contentType(for:)`
  derives from the extension, so no screen changed.
- **Compatibility is the real cost and it is not a footnote.** Exporting exists
  to send a file somewhere, and HEIC is the format most likely to reach
  somewhere that cannot open it — older systems, many Windows installs, web
  upload forms. **JPEG stays the default**, and the wording any tile must carry
  is in `docs/CODEX_BRIEF.md`.
- **Nobody has opened one of these files anywhere but this machine.** The
  engine is tested; the format's real-world reception is not.
- Nothing committed.

## Compression output format — row 35 — 2026-10-27 (Claude, backend)

Row 35 named two remainders. This takes the first: `compress(fileNamed:data:
preset:)` hardcoded JPEG, giving up most of the available saving now that HEIC
is in and measured.

- Full `./scripts/test.sh`: **423 tests passed** (64 + 127 + 89 + 101 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### JPEG stays the default, deliberately

Compression exists to make a file easier to **send**. Handing back a HEIC the
recipient cannot open is a worse outcome than a larger JPEG that works, so the
caller opts in rather than being upgraded silently. `CompressionFormat` carries
that reasoning where the choice is made, and the wording any screen needs is in
`docs/CODEX_BRIEF.md` — the warning matters more here than for export, because
compressing is usually the step right before sending.

### Three tests

The default output is still JPEG, checked by reading the bytes back rather than
the filename; asking for HEIC gives a real HEIC — `CGImageSourceGetType` says
`public.heic` — and a materially smaller file than the same photo as JPEG at
the same preset; and bytes that are not a re-encodable image are still refused,
whatever format was asked for, with nothing written.

### What this does **not** do

- **A PDF file item ignores the format entirely**, because HEIC is not a PDF
  image filter. Its behaviour is unchanged: pages carrying text are copied,
  text-free pages re-encoded, none of it HEIC.
- **No UI.** Nothing offers the choice.
- **Folder/archive compression, row 35's other remainder, is deliberately not
  done here.** It needs an honest "before" for each entry, and for a document
  that is the originals it is made of — which live in the store, and `Exporter`
  has no store. Doing it properly means the caller passing those counts in,
  which is a design question worth its own slice rather than a guess bolted on.
  Written down rather than quietly skipped.
- Nothing committed.

## A document's outline — row 36 — 2026-10-27 (Claude, backend)

Row 36's **navigation** half, for one explicitly named format: a PDF's own
table of contents. Not user-created bookmarks, which need storage and a screen.

- Full `./scripts/test.sh`: **428 tests passed** (64 + 127 + 94 + 101 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Verified before designing

An outline written with `PDFOutline`, serialized and reopened, comes back with
its labels and page indices intact, and a PDF with no outline returns
`outlineRoot == nil` — so "this file has no contents page" is distinguishable
from "nobody looked". That is what made a synthetic fixture possible, which is
what decides whether this can be tested honestly at all.

### The part that is not bookkeeping

A PDF's outline points at pages of **that file**. A PaperNest document is a
list of pages that may have been reordered, cropped, deleted, or drawn from
several PDFs at once. So every entry is resolved through the document's current
pages by (asset, source index), never by trusting the index:

- **An entry whose page was deleted is dropped.** An outline leading somewhere
  the document no longer has is worse than no outline.
- **Two merged PDFs each keep their own contents page**, resolving to their own
  pages.
- **Entries keep the order and nesting their author wrote**, because that is
  what a table of contents is. If the pages were reordered the outline will not
  ascend through the document — a true description of the file rather than
  something quietly re-sorted. A child whose parent was dropped keeps its own
  depth for the same reason.

### Five tests

Titles come back in the author's order with the right pages and nesting
(`[0, 1, 0, 0]`, so flattening fails the test); a PDF without an outline yields
none rather than failing; an entry whose page was deleted is dropped, with an
assertion that no returned entry points outside the document's pages; a
document built from two outlined PDFs yields both; and a scan contributes
nothing.

### What this does **not** do

- **PDF only.** Nothing here claims EPUB or any other book format, and row 36
  keeps its condition that formats be named explicitly.
- **User-created bookmarks and reading mode remain Planned.**
- Read-only: no schema change, nothing stored or cached, so the outline cannot
  describe paper a page no longer shows.
- **No UI.** Reading the outline is the engine; presenting it is the screen
  owner's work.
- Only synthetic fixtures — **no real book or scanned PDF with a publisher's
  outline has been read.**

## Compressing an archive — row 35 — 2026-10-27 (Claude, backend)

Row 35's last remainder, which closes the row's engine work. `exportArchive`
packed a selection into one ZIP and could not make any of it smaller; ZIP's own
deflate does nearly nothing to a PDF or a JPEG.

- Full `./scripts/test.sh`: **433 tests passed** (64 + 127 + 94 + 106 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The design question that deferred this, and its answer

The earlier slice left this alone because a `CompressionResult` needs an honest
"before", and for a document that is the originals it is made of — which live
in the store `Exporter` cannot see. Threading those in made the API ugly.

**The answer was not to invent a before at all.** `exportArchive(…preset:)`
returns the ordinary `ExportOutput`. The caller already knows what it had and
can compare; nothing fabricates a baseline, and no store dependency appears.

### Two rules, each with a test

- **Nothing is dropped.** An archive missing a file is data loss that stays
  invisible until someone looks for it, so anything that cannot be compressed
  goes in as it was. The test packs a scanned document, a `.txt`, a `.mov` and
  a `.png`, and counts four entries with the preset and four without.
- **Nothing is grown.** A re-encode that came out bigger is discarded and the
  original kept — so "compress" can legitimately produce an archive the same
  size as the plain one, which the already-compact-PNG test pins.

### Five tests

An archive of scans is smaller with a preset; nothing is dropped from a mixed
selection; a non-image file comes back **byte-identical** after a round trip
through the archive; an already-compact image is not grown; and without a
preset the archive is unchanged, entry list included.

### What this does **not** do

- **A re-encoded image changes extension** — a `.png` can come back as `.jpg`
  inside the archive. That is a real change to what someone gets back, so it is
  stated in `LibraryExportEntry`'s own documentation and in `CODEX_BRIEF.md`
  rather than left to be discovered.
- **Non-image files are never re-encoded**, preserving the promise the entry
  type already made: re-encoding someone's video or spreadsheet would be a lie
  about what they got back.
- **No UI.** Nothing offers an archive preset.
- Synthetic fixtures only; no real multi-gigabyte selection has been archived,
  so nothing is known about time or memory at that scale.

## Word-level text boxes — row 20 — 2026-10-27 (Claude, backend)

Markup worked on whole recognised lines, so highlighting one word highlighted
the sentence around it. Recognition was the reason: a `RecognizedLine` carried
one box and nothing smaller.

- Full `./scripts/test.sh`: **438 tests passed** (64 + 127 + 99 + 106 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured before building

Vision was asked directly, on a page reading `Invoice total 1234 EUR`:

```
line              x=0.080 w=0.412
  "Invoice"       x=0.080 w=0.129
  "total"         x=0.213 w=0.087
  "1234"          x=0.305 w=0.096
  "EUR"           x=0.405 w=0.087
```

Ordered, non-overlapping, and the last word ends exactly at the line's right
edge (0.405 + 0.087 = 0.492 = 0.080 + 0.412). That is what justified building
it rather than approximating by dividing the line box on character count, which
drifts on any proportional font and would put a highlight over the wrong ink.

### Existing stored results

`page_recognition` holds results written before this field existed.
`RecognizedLine` now has a hand-written `init(from:)` that decodes a missing
`words` as empty, so those results still load and a reader falls back to the
line. **Nothing is recomputed behind the user's back, and no migration was
needed** — recognition is JSON, not columns. A test decodes real old-shape JSON
and asserts no words are invented.

### Five tests

Words come back in reading order and each word's text is part of its line;
every word box sits inside its line's box with positive size; words do not
overlap; old JSON decodes with no words; and words survive an encode/decode
round trip.

### What this does **not** do

- **No UI.** Selecting a word is the screen owner's work; this gives it
  something to select. Row 20's selection interface, moving or resizing marks
  outside PencilKit, and semantic annotation objects all remain planned.
- **A word Vision will not box is dropped, not faked.** The only box available
  to invent from is the line's, and a highlight drawn there would cover text
  the user did not select. So `words` can hold fewer entries than the line has
  words, and a caller must expect that.
- Only synthetic English text was recognised. **No handwriting, no real scan,
  and no French or Spanish line has been checked for word boxes.**

## Saved signatures — row 23 — 2026-10-27 (Claude, backend)

Ink a person drew once, kept, and placeable again on any page. Checkmarks
already existed as symbol stamps, which are *generated shapes*; this is
different in kind.

- Full `./scripts/test.sh`: **448 tests passed** (64 + 131 + 99 + 106 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### What this is, stated before anything else

A saved signature is **a picture of a handwritten signature**. It is not a
cryptographic signature: no certificate, no timestamp, no tamper-evidence, it
proves nothing about who placed it, and anyone holding the file can copy the
image onto another document. **Nothing may say "signed", "verified",
"authenticated" or "secure" — the honest verb is "placed".** That wording is in
the type's own documentation, in `CODEX_BRIEF.md` and in `PRODUCT_SPEC.md`,
because it decides vocabulary rather than being a caveat to add afterwards.

### A design fault the test caught

The first version normalised captured ink into a **unit box** — each axis
scaled to 0...1 independently. That destroys the signature's shape: a 4:1
signature came out square before placement ever saw it, and the aspect-ratio
test failed with *"aspect became 1.0, not 4"*. Both axes are now divided by the
**same** number, the longer side of the ink's bounds, so the shape is part of
what is stored. Had the test only checked that placed ink lands inside its
target, this would have shipped looking subtly wrong on every document.

### Ten tests

**Model (6):** capture normalises by the ink's own bounds and keeps its
proportion; an empty signature is refused; placing puts every point inside the
target; aspect survives placement, so a wide signature in a square target is
letterboxed rather than stretched; the same placement on two page sizes is
proportionally identical; placing does not change the stored signature.

**Store (4):** a signature round-trips with its ink intact; saving the same id
again replaces rather than duplicates; deleting removes only that one;
signatures outlive reopening the library, at the current schema version.

### What this does **not** do

- **Schema is now v9; the next migration must be v10.**
- **No UI.** Drawing a signature and choosing where it goes is the screen
  owner's work. Initials and typed fill-in from row 23 are not built.
- Placed strokes are ordinary ink, so they are editable, erasable, undoable and
  exported like any other ink — and equally removable by anyone with the file.
- Nothing committed to a page by this slice: it produces strokes, and saving
  them onto a page goes through the existing ink APIs.

## Filling a PDF form — row 24 — 2026-10-27 (Claude, backend)

The Tools screen's *Fill Form*. Row 24 had stayed Planned because PaperNest
writes no document-level AcroForm and the synthetic fixture had none either,
so nothing was known about real forms.

- Full `./scripts/test.sh`: **455 tests passed** (64 + 131 + 99 + 113 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Two probes unblocked it

1. **A real AcroForm can be hand-built.** PDFKit cannot create one, so the
   fixture is raw PDF bytes with computed xref offsets: catalog
   `/AcroForm << /Fields [...] >>` and `/FT /Tx` widgets. Core Graphics reads
   it as `[("customer", "")]` — a genuine form, not a loose widget.
2. **PDFKit preserves an AcroForm it did not create.** Setting
   `widgetStringValue` and writing gives, read back through Core Graphics:
   `[("customer", "Jane Appleseed")]`.

The earlier conclusion — *PaperNest writes no AcroForm* — remains true and is a
different statement from *PDFKit cannot keep one*. Both are now recorded so
neither gets mistaken for the other again.

**Every assertion goes through Core Graphics, never PDFKit**, because PDFKit
reports a `fieldName` whether or not the document has a form, which misled this
project once already.

### Seven tests

A real form reports its field names, values and types; a PDF with no form
reports none; a filled value is in the written file's AcroForm as another
reader would see it; filling a field the form does not have is **refused**;
filling a form-less PDF is refused; other fields are left alone; and the field
is still a field afterwards.

### What this does **not** do

- **Only text fields can be filled.** Checkboxes and choice fields are
  *reported* with `isFillable == false` rather than hidden, so a caller can say
  "this form has parts I cannot fill" instead of implying the form is complete.
  Appearance-state handling is not built.
- **Filling does not flatten.** The field stays a field and the next reader can
  change it. The result must not be described as locked or final.
- **PaperNest still writes no AcroForm of its own**, so a form can be filled
  but not created, and a PDF exported from PaperNest has no fields to fill.
- **No UI**, and no real-world form — only the hand-built fixture — has been
  filled. A form from a government or bank website is untested.

## Ticking a box, and the hang that came with it — row 24 — 2026-10-27 (Claude, backend)

Checkboxes join text fields in `PDFForm`. Partway through, the suite stopped
finishing at all — and the cause turned out to predate this change.

- Full `./scripts/test.sh`: **460 tests passed** (64 + 131 + 99 + 118 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Checkboxes, probed before they were designed

Setting `buttonWidgetState = .onState` makes PDFKit write **both** `/V` and
`/AS`, as names, using the widget's **own** on-state name rather than an
assumed `/Yes`. Measured on the fixture: before `V=[""] AS=["—"]`, after
`V=["/Yes"] AS=["/Yes"]`, and reopened `state=1`.

So `FormValue` is typed — `.text(String)` or `.checked(Bool)` — instead of a
bare string. Text offered for a checkbox, or a tick for a text field, is
**refused** (`FormError.wrongKind`) rather than coerced: writing "true" into a
name field, or ticking a box because some string was non-empty, is a guess
about what was meant. Kinds are checked up front, so a refusal leaves the file
untouched instead of half filled. `FormField.isCheckbox` says which is which.

Four new tests: a tick is visible to another reader (`/V` and `/AS` read as
names through Core Graphics); a box can be left unticked; a mismatched kind is
refused; and a refusal writes nothing at all.

### The hang, and what actually caused it

`./scripts/test.sh --filter PDFFormTests` never returned. Build finished, then
no test output at all, killed at the watchdog. `/usr/bin/sample` of the stuck
process put every thread in the same place:

    PDFForm.filled -> PDFPage.lazilyLoadAnnotations
      -> PDFAnnotationTextWidget init -> getFontFromAppearanceString
      -> NSFont fontWithName: -> CoreText -> TAutoActivationManager
      -> XTypeXPCClient XTCopyFontProviders
      -> __NSXPCCONNECTION_IS_WAITING_FOR_A_SYNCHRONOUS_REPLY__ -> mach_msg2_trap

Reading a page's annotations makes PDFKit build each widget, and building one
makes it resolve the font named in the field's `/DA` — `/Helv`, the AcroForm
abbreviation, which is not a real PostScript name, so CoreText goes looking for
it over **synchronous XPC**.

**Three guesses were wrong and are recorded so they are not made again:**

- *A wedged font daemon.* `fontd` and `fontworker` were both alive, and a
  standalone binary resolved the same name promptly: `NSFont(name: "Helv")`
  → nil in 0.009s, `"Helvetica"` → 0.001s.
- *The checkbox change.* `git diff` touched only `fields(in:)`. The hanging
  line is unchanged since commit `10a49b2`, and the three tests that passed at
  that commit hang too.
- *"Several at once."* The first regression test ran 8 concurrent fills on
  plain `Thread`s and **passed with no fix at all**, in 0.066s. That reading
  was wrong, and a test that cannot fail is worth nothing.

The variable is Swift concurrency's **cooperative pool**, and only that:

| 8 concurrent `filled` calls | result |
| --- | --- |
| on plain `Thread`s | all finish, 0.066s |
| in a `withTaskGroup` | hangs; not one task finishes |

The sample says which story it is: 9 threads, 9 lazy annotation loads, 9
threads each waiting on **its own** unanswered reply, and **0** lock-contention
frames. Nine independent stuck calls, not one stuck call with eight waiters.

**The fix is one `NSLock` in `PDFForm`**, held across the whole PDFKit stretch
of both `fields(in:)` and `filled(_:with:)`, so that path is entered one caller
at a time. Verified against the harshest case rather than assumed: with the
lock the task-group probe finishes all 8 in 0.066s, and the command that hung
forever passed **5 runs in a row** (12 tests, ~0.08s each). A dedicated thread
would also have worked — the plain-thread result proves it — but the lock is
smaller, and one-at-a-time is exactly what was measured to be enough. Neither
method calls the other, so a non-recursive lock is safe.

`manyFillsAtOnceAllFinish` now pins this with a task group, which is the only
shape that reproduces it.

### What this does **not** do

- **If that lock is removed, the test hangs rather than fails.** It cannot be
  helped: a thread stuck in `mach_msg` never reaches a cancellation point, so
  no `.timeLimit` fires, and the starved pool cannot run the harness either. A
  hang at `manyFillsAtOnceAllFinish` is the warning; the comment there says so.
- **Corrected — the first version of this entry got the blast radius wrong.**
  It said `PDFPage.copy()` in `Compression.swift` and `Exporter.swift` was the
  same exposed path, and that nothing in the product fans out anyway. Both
  claims were guesses from a grep, and both are wrong. The app fans out
  heavily: **87 `Task {}` / `.task {}` sites across 21 files in
  `PaperNestUI`**, which is exactly why this matters. And the trap is narrower
  than `PDFPage`. Probed at 16 concurrent callers each, on the form fixture:

  | concurrent PDFKit work | result |
  | --- | --- |
  | `page.annotations` | **hangs**, no caller finishes |
  | `page.copy()` | all finish |
  | `page.string` | all finish |
  | `outlineRoot` | all finish |

  So **reading `.annotations` is the trigger** — that is what instantiates the
  widget objects and resolves their `/DA` font. Copying a page, reading its
  text and reading the outline do not. `PDFForm` is the only code in `Sources`
  that reads `.annotations` (`PDFForm.swift:59` and `:88`), so the lock covers
  the product and not merely the test. `PageRenderer`, the hot path, is pure
  Core Graphics — `CGPDFDocument` and `ctx.drawPDFPage`, which draws page
  content without annotations — so the library grid rendering many pages at
  once never enters it.
- **What is still unchecked:** only those four PDFKit calls were measured. If
  some other PDFKit path loads annotations implicitly, it would hang the same
  way and no test would catch it.
- **Why the pool cannot recover is not known.** It is inside CoreText and
  libFontRegistry, and nothing here claims an explanation — only what was
  measured.
- **Choice fields still cannot be filled**, and are reported with
  `isFillable == false`. Picking a value means picking from the options the
  form declares, which this does not read.
- **Still no UI, and still no real-world form.** Only the hand-built fixture
  has been filled or ticked. A form from a government or bank website is
  untested, and PaperNest writes no AcroForm of its own.

## A thumbnail of what a file item holds — row 8 — 2026-10-28 (Claude, backend)

Row 8 has said "generated grid/list thumbnails remain open" since 2026-10-22.
`FileThumbnail.image(at:boundedBy:scale:)` is the engine for them: the system's
Quick Look, asked for a picture of a file's contents.

- Full `./scripts/test.sh`: **466 tests passed** (64 + 131 + 105 + 118 + 48), **0 warnings**.
- The new suite run **5 times in parallel**: 6 tests, ~0.05s each, no hang and
  no orphaned helpers. Worth doing because this goes through a system XPC
  agent, the same family as the PDFKit trap found the day before.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured before anything was designed

1. **Ask only for `.thumbnail`, never `.icon`.** Asked for `.all`, Quick Look
   answers a file it cannot read with a generic **512×512 type icon**
   (`type=0`) — measured alike on a `.bin`, a file with no extension and an
   unknown extension. That icon is the symbol the grid already draws from
   `uti`, so returning it would dress a type symbol up as a preview of the
   contents. Asked only for `.thumbnail`, the same three files **error**
   instead, which is the honest answer. `aFileTheSystemCannotReadGivesNothingRatherThanAnIcon`
   is the guard, and the guard was **run rather than claimed**: set the
   representation types to `.all` and it fails with
   `Expectation failed: image == nil`, holding the icon. A guard nobody has
   seen fail is a claim, and the first commit of this slice only claimed it.
   `.lowQualityThumbnail` is also left out, because nothing here measured it —
   the first commit asked for it while every measurement and every line of
   these docs described `.thumbnail` alone.
2. **A missing file is distinguishable from an unpreviewable one.**
   `NSCocoaErrorDomain` 4 against `QLThumbnailErrorDomain` 0
   (`QLThumbnailError.Code.generationFailed`, so no magic number in the code).
   Collapsing them would hide a missing original behind a blank square, so the
   file's existence is checked here and only Quick Look's own code 0 becomes
   `nil`. Everything else — a cancelled or invalid request — is thrown.
3. **The size asked for is a box.** Fresh file per request: asked 120×400 →
   120×120, asked 400×120 → 120×120, asked 200×200 → 200×200, asked 64×64 at
   scale 2 → 128×128. So the picture fits inside and keeps the document's own
   proportions; the parameter is named `boundedBy` because of this, and a
   caller must lay out what comes back rather than what it asked for.

### The `.bin` problem, which is the whole reason this needs care

A stored asset is named `<sha256>.bin`, because `AssetKind.file` covers every
type. Quick Look decides what a file is from its extension and refuses `.bin`,
so pointing it at the asset's own path **always** answers `nil`. The URL has to
carry the real extension: `FilePayload.originalFilename` first, and when that
basename is unusable — `prepareTemporaryCopy` falls back to `<sha>.bin` for an
empty or `/` name — the item's recorded `uti` gives one through
`UTType(uti)?.preferredFilenameExtension` (`public.plain-text` → `txt`,
`org.openxmlformats.wordprocessingml.document` → `docx`).
`theRecordedTypeNamesTheFileWhenTheStoredNameCannot` writes the same bytes both
ways and gets `nil` from one and a picture from the other, so that is a
measurement rather than advice.

### What this does **not** do

- **No UI, so row 8 stays Partial.** Nothing calls this yet; the grid and list
  cells are Codex's. It also deliberately **does not stage files** — a second
  way to do that would compete with `FileKind.prepareTemporaryCopy`, which the
  full preview already uses.
- **Nothing is cached.** Every call asks the system again, so a grid that
  scrolls will re-ask for pictures it has already had. Quick Look has a cache
  of its own, which is why repeats are fast, but nothing here depends on that.
  A thumbnail cache of our own is unbuilt and undecided.
- **iOS behaviour is unmeasured.** It compiles for the Simulator and that is
  all that has been established. Which types Quick Look previews on iOS, and
  whether it previews the same ones as macOS, has not been run.
- **Few types have actually been tried.** `.txt` in the tests, and a `.docx`
  in a probe outside them (`type=2`, 485×792). Spreadsheets, presentations,
  video, audio and archives are untested, and nothing says the system can
  preview any particular one of them.
- **An item whose `uti` is `public.data` gets nothing** when its filename is
  also unusable: that type has no preferred extension, so there is no name to
  stage it under. Measured, and there is no honest way around it.
- **Concurrency is clean as far as it was pushed** — 16 concurrent requests in
  a standalone task group, plus 5 parallel suite runs — but this is a system
  XPC agent, and that is not proof for every type or load.

## How long a media file is, and what it calls itself — row 42 — 2026-10-28 (Claude, backend)

Row 42 (audio and video playback, audiobooks, playlists) was confirmed by the
owner on 2026-10-23. `MediaInspection.inspect(at:)` is the part a player needs
before it can draw anything: the file's own length, whether there is a picture
as well as sound, and what it calls itself. **Playing it is a view and is not
this.**

- Full `./scripts/test.sh`: **473 tests passed** (64 + 131 + 112 + 118 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The fixture is hand-built, and that was measured first

A **RIFF/WAVE file written by hand** is enough: 1.5 seconds of silence reads
back as 1.500, and 2.0 as 2.000. So there is no opaque audio blob in the
repository and no generated file whose length has to be taken on trust — the
same reasoning as the hand-built AcroForm PDF. A `LIST`/`INFO` chunk carries
the tags.

### Three findings that changed the design

1. **`asset.load(.commonMetadata)` is empty for a file whose tags are plainly
   there.** The obvious reader — load the common metadata, look for a title —
   finds *nothing* on this file. The items only come back through
   `AVMetadataItem.metadataItems(from:filteredByIdentifier:)` over
   `.metadata`, which does the per-format mapping and turns `caaf/info-title`
   into `.commonIdentifierTitle`. Measured both ways before a line was written.
2. **`.bin` fails here too, and so does a name with no extension at all.**
   The same playable bytes, measured four ways: `sound.wav` → 1.0s,
   `sound.bin` → `nil`, a name with no extension → `nil`, and — the one that
   refines the rule — **`sound.mp3` → 1.0s**, WAV bytes under an MP3 name.
   So AVFoundation does not demand a *correct* extension; it demands one it
   treats as media at all, and then reads the actual bytes. `.bin` and no
   extension are not media types, so it never looks.
   `theStoredAssetNameIsNotEnoughToReadIt` pins the `.bin` half.

   This is the *same* staging requirement `FileThumbnail` has, reached through
   completely different machinery, so the two engines agree — see "What a
   caller still has to do" below for what that actually requires of the UI.
3. **A missing file is distinguishable from a file that is not media** (−11800
   against −11828), so existence is checked here and only −11828 becomes
   `nil`. Both guards were **run rather than claimed**: breaking the
   classification makes `aFileThatIsNotMediaIsNotAnError` and
   `theStoredAssetNameIsNotEnoughToReadIt` fail with the real −11828 in hand.

### Only what could be measured is shipped

`duration`, `hasAudio`, `hasVideo`, `title`, `artist` — and nothing else.
**`albumName` and `artwork` were left out on purpose.** A WAV `IPRD` chunk for
the album is dropped by AVFoundation entirely — it does not even appear among
the raw items — and nothing hand-buildable here carries artwork, so both would
have been fields no run could demonstrate.

### What this does **not** do

- **Nothing plays.** No seek, speed, background audio, resume, playlists,
  shuffle, system controls or picture-in-picture — row 42 stays Planned, and
  this only clears its groundwork. Nothing calls `inspect` yet.
- **No file with a video track has been inspected.** `hasVideo` is measured
  only as `false`, on audio. A `true` from it is not yet backed by a run, and a
  video fixture needs a real encoder rather than hand-written bytes.
- **Artwork and album are not read at all**, as above. Row 42 asks for
  artwork; it needs a fixture in a format that can carry one.
- **One format has been read: WAV.** MP3, M4A, AAC, MOV and MP4 are untested
  here. The metadata path is format-independent by construction, but that is an
  argument rather than a measurement.
- **A file AVFoundation recognises but cannot parse is thrown, not reported as
  "not media".** Only −11828 was measured, so only −11828 is treated as an
  answer; a corrupt media file's code is unknown and would surface as an error.
- **`duration == nil` is unexercised.** No local file declared an indefinite
  length. It is `nil` rather than `0` so a wrong zero is never shown as a
  length.
- **iOS behaviour is unmeasured.** The Simulator build proves it compiles and
  nothing more. Whether AVFoundation reads the same formats and surfaces tags
  the same way on iOS has not been run.

### What a caller still has to do — and nobody does it yet

Both engines need a URL whose extension the system treats as media or as a
document. **The rule is not "the basename is unusable" — it is "the name's
extension does not name the item's `uti`."** That matters, because
`FileKind.prepareTemporaryCopy` falls back to `<sha>.bin` only for `""`, `.`,
`..` and `/`, and it never reads `uti` at all. So an `originalFilename` with
no extension, or with one that does not match the bytes, is staged under that
name — and a name with no extension was measured to give `nil` from both
engines.

So the `UTType(uti)?.preferredFilenameExtension` fallback that both engines
recommend **is implemented nowhere**: it lives in these notes and in
`theRecordedTypeNamesTheFileWhenTheStoredNameCannot`, not in the staging path
any screen uses. Wiring either engine to a screen means fixing that first.

### Fan-out

16 concurrent `inspect` calls in a task group — the way a playlist or a grid
would ask — returned all 16 titles. Worth running because this is the trap
class from the day before, though `AVAsset.load` suspends rather than blocks,
so a hang was never likely.

## Closing row 42's measurement gaps — row 42 — 2026-10-28 (Claude, backend)

The entry above shipped only what a hand-built WAV could demonstrate, which
left two honest holes: **`hasVideo == true` was never run** — a hard-coded
`false` would have passed every test — and album and artwork were left
unshipped because nothing could prove them. Both are now measured, so the
"does not do" list above is superseded on those three points.

- Full `./scripts/test.sh`: **476 tests passed** (64 + 131 + 115 + 118 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Two generated fixtures, and one API rejected on the way

- `SyntheticDocuments.videoClip` writes a few frames through `AVAssetWriter`
  with a pixel-buffer adaptor: a **1.3 KB** `.mov` that reads back as 0.600s
  with one video track and no audio. Hand-written bytes cannot make a real
  video track, and without one there is no honest way to test that a file
  reports having a picture. Still synthetic — flat grey frames, nobody's
  recording.
- `SyntheticDocuments.taggedAudio` transcodes `wavAudio` with an
  `AVAssetReader` into an `AVAssetWriter`: a **1.5 KB** `.m4a` whose title,
  artist, album and 174 bytes of artwork all come back. M4A because a RIFF
  file cannot hold these at all — AVFoundation drops a WAV `IPRD` album chunk
  without even listing it, and there is no standard place in one for a picture.
- **`AVAssetExportSession` was rejected**, although it was the first thing that
  worked in a probe. `exportAsynchronously`, `status` and `error` are all
  deprecated in macOS 15 while this package still supports macOS 14, so there
  is no version of it that compiles without warnings. The reader-to-writer
  transcode compiles clean and does the same job.

### What is now measured

- `hasVideo == true` and `hasAudio == false` on a real video track, and
  **the test was proven able to fail**: hard-coding `hasVideo: false` breaks
  `aVideoFileHasAPictureAsWellAsALength`, as hard-coding the error
  classification breaks the two "not media" guards.
- `albumName` and `artwork` round-trip. Artwork is handed back as **the bytes
  the file carries**, not decoded or re-rendered, so nothing is lost or
  invented on the way and the caller picks its own size.
- Tags that are absent from a format that *could* have held them stay `nil`:
  an M4A with only a title reports no album and no artwork rather than empty
  strings.
- A second format, and the first not written by hand: M4A as well as WAVE,
  plus QuickTime for the video.

### What this still does **not** do

- **Nothing plays.** No seek, speed, background audio, resume, playlists,
  shuffle, system controls or picture-in-picture. Nothing calls `inspect`.
  Row 42 stays Planned.
- **MP3 and MOV-with-audio are untested**, and so is anything with more than
  one track of a kind. Three container formats have been read (WAVE, M4A,
  QuickTime) out of the many a library will meet.
- **iOS behaviour is still unmeasured.** The Simulator build proves
  compilation. Whether the same formats read, and whether `AVAssetWriter`
  produces these fixtures there, has not been run.
- **The fixtures depend on the system's H.264 and AAC encoders.** They are
  generated at test time rather than checked in, which keeps binaries out of
  the repository but means these three tests need a machine with those
  encoders.
- **Artwork is not validated as an image.** The test asserts bytes came back,
  not that they decode — the file is asked what it carries, and that is all
  that is claimed.

## Row 43's codec review, answered by measurement — 2026-10-28 (Claude, backend)

Row 43 is "Convert media to MP3 / extract audio", and has said **"codec and
licensing review first"** since it was confirmed on 2026-10-23. This is that
review. **No engine was built and nothing in the app changed** — it is a
finding, recorded so the decision it forces is made with numbers rather than
recollection.

### What this machine can encode

`AudioFormatGetProperty(kAudioFormatProperty_EncodeFormatIDs)` returns **16**
formats:

    aac  aace aacf aacg aach aacl aacp alac apac flac opus lpcm alaw ulaw ilbc ima4

- **MP3 is not among them.** `kAudioFormatMPEGLayer3` is absent from the
  encode list.
- **MP3 *decoding* is available** — it is in the decode list. So a library can
  read an MP3 a user imports and cannot write one.
- AAC, Apple Lossless, FLAC, Opus and plain PCM can all be written.

`AVAssetWriter` agrees from the other side: constructing one with
`AVFileType.mp3` raises `NSInvalidArgumentException`, and the exception names
every type it *will* write — m4a, mp4, mov, caf, wav, aiff, aifc, 3gpp, amr
and the caption formats. No MP3.

### What that means for row 43

- **"Convert to MP3" cannot be built on Apple's frameworks.** It needs a
  third-party encoder bundled into the app, which is the licensing question the
  row anticipated — now a certainty rather than a worry.
- **"Extract audio" can be built today**, to M4A/AAC, or losslessly to Apple
  Lossless, FLAC or WAV. The transcode route is already proven in
  `SyntheticDocuments.taggedAudio`: `AVAssetReader` into `AVAssetWriter`,
  warning-free, and small.

**This is an owner decision and is deliberately left open**, because the two
answers lead to different work: ship "Extract audio" in a format the system
can write, or license an MP3 encoder and carry it in the app. Nothing should
be labelled "MP3" in any screen until that is settled.

### What this does **not** establish

- **One machine, one OS version.** The encoder list is what this Mac reports
  today. It is a strong signal about Apple's platforms but not a guarantee for
  every iOS device, and the same probe has not been run on iOS.
- **Nothing was extracted.** No audio has actually been pulled out of a video
  file; only the available encoders and container types were read.

## A placed image is painted and exported — row 21 — 2026-10-28 (Claude, backend)

**The owner narrowed the queue on 2026-10-28: documents and images only, leave
media alone.** Rows 42 and 43 stop where they are. Row 21 says "placed images
remain planned; models for text/image objects exist", and that was exactly the
state — `PageObject.Payload.image(PlacedImage)` existed, `page_objects` stored
it, and `isAssetReferenced` and `deleteUnreferencedAssetRows` already counted
it, so an asset under a placed image was never swept. **Nothing painted it, and
`PageRenderer.draw` did not even take one.**

- Full `./scripts/test.sh`: **482 tests passed** (64 + 131 + 119 + 120 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The trap it closes, which was a silent one

`PDFPassThrough.isUntouched` asked `hasInk`. An unedited PDF page at its
original paper size with a placed image and **no** ink satisfied every
condition, so export copied it straight from its source file — and the image,
which exists nowhere in that source, **was gone from the export without a
word**. No error, no warning, just a page missing what someone put on it.

The fix is not a `hasPlacedImage` flag beside `hasInk`. The parameter is now
`hasPaintedObjects`, because the condition that matters is "anything is painted
over this page": a text box or a stamp, both named in row 21 as coming, would
have walked into the same hole. `aPageCarryingAPlacedImageIsDrawnRatherThanCopied`
is the test, and it failed before the change.

### Order is the page's, not a rule about kinds

`draw` now takes `[PageLayer]` — `.ink` or `.image` — built from
`LibraryStore.objects(on:)`, which returns a page's objects in `zKey` order.
So an image placed over a stroke covers it and a stroke drawn over an image
covers that, whichever the page says came last. The easy wrong version, images
always painted last, **was tried**: it makes `inkDrawnOverAnImageCoversIt` fail.
That test had passed trivially while nothing drew images at all, which is why it
was worth breaking on purpose.

Only two places called `draw`, both in this lane, so the signature could change
rather than gaining a defaulted parameter that kept the old shape alive.

### Six tests, and what each would catch

The fixture image is white with a **red square across its top-left fifth**, so
every probe reads a point just inside the placed frame's corner — an image drawn
in the wrong place, at the wrong size, or flipped fails. It is painted on the
page; nothing is painted outside its frame; an image over ink covers it; ink
over an image covers that; `includingInk: false` still shows the image, because
the ink editor paints its own strokes and the page must not appear to lose the
image the moment someone draws; and it reaches both an exported PDF and an
exported PNG.

Two more cases were added after the first commit, because every test until
then used an **unrotated, uncropped page**, where several wrong orders of flip
and rotation give the right pixels anyway: one on a page the file itself
rotates a quarter turn, and one whose stamp is stored sideways and upright only
by its EXIF orientation, as a phone photo is. Removing the flip in
`drawPlacedImage` fails **7 of the 8 tests**, these two included, so they are
live guards — though it should be said plainly that they fail for the same
reason the flat case does rather than catching something it cannot.

### Corrected: how a screen would actually place one

The first commit's note here said placing reuses the imported image's asset
"which is what a screen would do". That is **not true**, and the correction
matters more than the claim did. The test gets its `AssetID` by importing the
stamp as a library item; a screen placing a photo from outside the library that
way would leave a stray item behind. And there is **no public API that stages an
asset and writes the object together**: `AssetFileStore.store` stages the file
durably, but inserting the asset row is private, and between staging and the
object being written `sweepOrphanAssets` could take the file away.

`saveObject` is also the *unguarded* write. Every other object kind has a
guarded one — ink has `applyInkChanges`, which checks the objects it expects;
comments have `setPageComment(replacing:)`; markup has `addTextMarkup`. A
guarded `placeImage` that stages the asset and writes the object in one
transaction is the next piece of store work, and it is what turns "the engine
draws a placed image" into "a screen can place one".

### What this does **not** do

- **No UI.** Nothing places an image yet — that is a screen, and screens are
  Codex's. Row 21 stays Partial. A caller would write a `PageObject` with an
  `.image` payload and a `zKey` above the existing ones.
- **No undo, no resize, no rotation.** `PlacedImage` carries an asset and a
  frame, and that is all it carries: no angle, no opacity, no crop. A placed
  image cannot be rotated because the model has nowhere to put the angle.
- **Text boxes and stamps are still not painted.** `.text` payloads are skipped
  in `layers`, as page comments are — deliberately, and the comment there says
  so, but it means row 21's other halves remain open.
- **A placed image whose asset is not on this device throws**, rather than being
  left out of the drawing. That is the honest choice — a page quietly missing
  part of itself is worse than one that says it cannot be drawn — but it means
  one unavailable overlay fails the whole page, and no test covers that path.
- **`PageRenderer.inkStrokes(for:)` still exists and is now used by nothing.**
  It is kept because Codex's editor may want it, with a doc comment saying not
  to draw from it; drawing from it is precisely how a placed image gets lost.
- **The image is stretched to fill its frame.** `drawPlacedImage` draws into
  the rectangle it is given, and every test places a square image in a square
  frame, so nothing here establishes what a mismatched aspect does — it will
  distort. Saved signatures letterbox instead (`SavedSignature.placed(in:on:)`);
  this does not, and which is wanted is a product question.
- **`includingInk: false` has changed meaning, and `ThumbnailCache` passes it.**
  It used to mean "no overlays", because ink was the only one; it now means
  what it says — no ink, placed images kept. Nothing can show one yet, since no
  screen places an image, so there is no live defect. But a caller that wanted
  the bare page needs a different flag, and `Sources/PaperNestUI/ThumbnailCache.swift`
  is the one to look at when images can be placed.
- **Redaction does not touch a placed image's own bytes.** `PageRedaction`
  flattens and repaints the page's *source* through `uprightSourceRaster`, so
  overlays are neither baked in twice nor removed. That is right for ink, and
  it means a placed image covering a redacted region still shows whatever it
  shows — the words are gone from the source, which is what redaction promises,
  but a picture carrying the same words is not redacted. Untested and
  unaddressed.
- **No sibling of the `hasInk` bug was found in this lane.** Everything that
  decides a page's original can be copied instead of drawn goes through
  `isUntouched`; `EmbeddedPageText` and `DocumentOutline` read a source for text
  and an outline rather than to copy it, and compression works on a finished PDF
  where overlays are already drawn in. The `case .ink` filters in
  `PaperNestUI` — `DocumentView`, `MarkupManagerSheet`, `InkCanvas` — are list
  and manager concerns rather than copy decisions, and they are Codex's to
  judge.

## Placing an image, safely — row 21 — 2026-10-28 (Claude, backend)

The entry above drew and exported a placed image, and then had to correct its
own advice: a screen could not safely *write* one. `AssetFileStore.store`
stages the file durably, but inserting the asset row was private, and between
staging and the object being saved `sweepOrphanAssets` was entitled to take the
file. `saveObject` was also the unguarded write, while every other object kind
has a guarded one. `LibraryStore.placeImage(_:on:frame:)` closes that.

- Full `./scripts/test.sh`: **492 tests passed** (64 + 139 + 121 + 120 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### One write

The asset row and the page object go in inside **one transaction**, following
`replacePageContent`: the caller stages the bytes (file written durably first),
and the store inserts the row. `aPlacedImageIsNotSweptAway` is the test that
matters, and it was **proven able to fail** — take `insertAssetRows` out, which
is exactly the naive stage-then-`saveObject` path the earlier note recommended,
and it throws because the sweep took the bytes, while
`placingAnImageWritesTheBytesAndTheRowTogether` fails for want of a row.

The order key is worked out **inside** the write from what the page holds at
that moment, so two placements in a row cannot claim the same place —
`twoImagesInARowBothLandInOrder` pins that. A new image lands on top of what is
already there, as putting something down does.

### Refused rather than stored

- **Bytes the renderer cannot decode as an image.** `AssetKind.isDrawableImage`
  is an exhaustive switch — jpeg, png, heic, webp yes; pdf and file no — so a
  new kind has to decide rather than inherit an answer. Offering a `.pdf`
  asset is `StoreError.invalidPlacement`. Without this the renderer would
  only find out when someone opened the page, by which time the object is
  saved and the page cannot be drawn at all.
- **A frame with no area**, or a non-finite one. `frame.width > 0` alone does
  not catch a NaN origin, so the origin is checked too.
- **A page that is gone, or whose item is deleted** — `pageNotFound`, the same
  guard `addShape` uses.

Each refusal writes **nothing**: the tests check that no object and no asset
row are left behind, so a refusal leaves unreferenced bytes for the sweeper
rather than a half-written placement.

### Three things a screen hits immediately, added after the first pass

The first version of this had twelve fewer tests and two real gaps, both found
by asking what a screen would do on its second call rather than its first.

1. **It returns the page as well as the object now.** Writing an object bumps
   the page's revision, and `addShape(to expected:)` compares the **whole**
   page — so a caller holding the `Page` it started with is refused.
   Confirmed rather than reasoned about: with the page from before the
   placement, `addShape` throws `pageObjectsChanged`; with the page
   `placeImage` returns, it succeeds. Without this, placing an image would
   break the very next edit someone made.
2. **The same image on two pages shares one copy.** The fixture staged unique
   bytes per placement — `"stamp bytes \(UUID())"` — which quietly hid the
   commonest real case: one logo or signature put on several pages. Content
   addressing gives those the same `AssetID`, so the asset row is written
   twice. `insertAssetRows` already handles that (`ON CONFLICT(id) DO UPDATE`),
   and it is now tested end to end: both placements land, removing one keeps
   the bytes because the other page still needs them, and only removing both
   lets them go. Placing a picture that is already a page's **own content** is
   covered too — deleting that placement must not sweep the page's content out
   from under it.
3. **Placing something does not stale what was read off the page.** The
   revision bump could have: `recognizedLines` only answers when
   `sourceRevision == page.revision`, so putting a signature on a scan might
   have dropped its searchable text from export. `bumpRevision` already
   carries a *current completed* result forward with the page, deliberately
   and with a comment saying why; there is now a test saying so from outside,
   because that is a feature-level promise and not an implementation detail.

### What this does **not** do

- **Still no UI.** Row 21 stays Partial. What exists now is the whole engine
  path — stage, place, draw, export — with nothing calling it.
- **No undo.** `placeImage` returns the `PageObject` it wrote, so a caller can
  undo by deleting that id, and `deletingAPlacedImageLetsItsBytesGo` shows the
  bytes then go with it. But there is no undo *entry*: the ink editor's
  `applyInkChanges` records an edit for the undo stack and this does not join
  it, so a placement and an ink stroke do not share one history.
- **No move, resize, rotate or re-layer after the fact.** Changing a placement
  means deleting the object and writing another, which is not the same thing
  and has no test.
- **The bytes in these tests are not images.** Nothing in this path decodes
  them — only the declared kind and the frame matter — so the store tests use
  plain bytes, as `DocumentSplitTests` does. Real images are drawn in
  `PlacedImageRenderTests`. It also keeps AVFoundation, which
  `PaperNestTestSupport` now links for the media fixtures, out of
  `PaperNestStoreTests`, which does not depend on that target.
- **Nothing checks the frame against the page.** A frame may sit entirely off
  the page; drawing clips it away and the object stays. That is deliberate — a
  caller may want an image hanging over an edge — but it means a placement can
  be invisible with no complaint.

## Text typed onto a page — row 21 — 2026-11-01 (Claude, backend)

The last piece of row 21 that had a model and no paint. `TextBox` existed in
Core and `page_objects` stored it; `layers` **skipped** `.text`, so nothing
drew it. It joins `PageLayer` now, which also means `hasPaintedObjects` covers
it without a new flag — the point of generalising that condition when placed
images needed it.

- Full `./scripts/test.sh`: **502 tests passed** (64 + 143 + 125 + 122 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### It is real text, and that is the whole decision

Drawn with CoreText into the export's PDF context, so the words come out as
**text operators rather than glyph outlines**: selectable, copyable and
searchable in the written file. A picture of text would look identical on
screen and be useless to a reader, so the test does not take it on trust —
`textInABoxIsRealTextInTheExportedPDF` reads the words back out with
`PDFDocument.page(at:)?.string`.

The flip is `drawSearchableText`'s and not a second idea of which way is up:
translate to the box's bottom edge in y-down source space, scale y by −1, and
`CTFrameDraw` then lays the first line against the box's **top** and runs down
the page.

### Six tests, and what each would catch

Text is painted inside its box and nowhere outside it; it starts at the **top**
of the box, which is the only one of these that catches an upside-down flip,
since text drawn the wrong way up is still dark pixels in the right box;
`.trailing` puts it at the right edge and not the left; an empty box paints
nothing; the words are real text in the exported PDF; and a page carrying only
a text box is **drawn rather than copied**, which is the trap that was losing
placed images.

The pixel probes scan a **region** rather than a point, because one sample can
land in the gap between two letters and report nothing about text that is
plainly there. The first version of that helper called `PixelProbe.pixel` per
sample, which redraws the whole image each time and took **a minute per test**;
it reads the bitmap once now and the suite is back to milliseconds.

### What this does **not** do

- **No UI.** Nothing lets anyone type on a page — row 21 stays Partial, with
  stickers and stamps still open. A caller writes a `PageObject` with a
  `.text` payload; there is no guarded `placeText` the way `placeImage` exists
  for images, so the asset-free path is the unguarded `saveObject`.
- **One font, Helvetica, hard-coded.** `TextBox` carries a size, a colour and
  an alignment and has nowhere to put a typeface, so nothing here chooses one
  and no other font has been tried.
- **Text longer than its box is clipped**, with nothing to say so. The frame
  path cuts it off; there is no ellipsis, no shrink-to-fit and no indication to
  a caller that some of what was typed is not shown.
- **The words do not reach the search index.** Someone's own typing is exactly
  what they would expect to find by searching, and it will not be found. That
  is a store question — a new `search_index` field and a migration — not a
  render one, and it is not done.
- **No wrapping test.** CoreText wraps inside the frame, but every test here
  uses one short line, so nothing establishes what a paragraph does.
- **iOS is unmeasured**, as for the other engines: the Simulator build proves
  it compiles. Whether Helvetica resolves the same way there has not been run.

## Typed text becomes findable — row 21 — 2026-11-02 (Claude, backend)

Text boxes paint and export as of yesterday, and the words went nowhere near
search — the first thing someone would notice about their own typing. They are
indexed now, on the same page write that saves them.

- Full `./scripts/test.sh`: **509 tests passed** (64 + 150 + 125 + 122 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The privacy test was worthless at first, and that is the finding here

A page comment is private. It is typed on the same page, by the same person,
into the same objects table, so `aPrivateCommentIsNeverFindable` is the test
that matters most in this slice. It **passed while the reindex was deliberately
changed to gather comments** — so it was proving nothing.

The reason is worth keeping: writing a comment does not bump the page's
revision, on purpose, so that an undone comment does not invalidate page
history. No bump means no reindex, so the comment was safe **by accident of
timing** rather than by the rule the test claimed to check. The test now saves
an ink stroke after the comment, which does bump the revision and rebuilds the
index while the comment is sitting on the page. Verified both ways round: it
passes as written, and making the reindex gather comments fails it.

So the promise rests on two independent facts, and only one of them was ever
tested before.

### No migration, checked rather than assumed

`search_index` is an FTS5 table whose `field` column is `UNINDEXED` and carries
no `CHECK`, and the index is derived and rebuildable — so a field value needs no
schema change. This was checked rather than assumed because `assets.kind` went
the other way earlier in this project: its `CHECK` constraint did need a
migration, and the plan that said otherwise was wrong.

### Corrected mid-slice: it is the field that already existed

A fifth field, `typed`, was written first. That was wrong.
`LibraryComposition` **already** gathered text boxes into a `text` row — but
only while duplicating, extracting or merging, which is why typing on an
ordinary page indexed nothing. A new name would have left a composed item
carrying the same words twice under two names, and it broke
`DocumentCompositionTests`, which counts the index rows an item owns. That
failure is what surfaced the existing field at all.

So this uses `text`, and composition's hand-rolled copy is **deleted**: the
objects it writes already go through `applyObjectChanges` → `bumpRevision` →
the reindex, which does the same "rebuild from the copy's own objects rather
than carry stale content or source IDs" that comment described, in one place
that also covers simply typing.

### Where it hooks, and what that costs

`bumpRevision` is called from exactly the three object-write paths and nothing
else, so it is the one place that means "this page's objects changed".

It therefore runs on **every** object write, an ink stroke included. The gather
asks for `kind = 'text'` rows only, rather than reading the page's objects
through `objects(on:)`: that would decode every stroke's JSON to discover the
page has no text boxes, costing one decode of everything per stroke through a
drawing session. What remains is one narrow query plus a delete and an insert
per write, which is not free and has not been measured under a real drawing
load.

`LibraryStore.decoder` went from `private` to internal so a second file can use
the configured instance rather than making its own.

### What this does **not** do

- **Seven tests, no UI.** Nothing types on a page yet, so in practice nothing
  is indexed through the app. Row 21 stays Partial.
- **No backfill.** A library whose text boxes predate this change will not find
  them until something writes that page's objects again. In practice no library
  has any, because nothing could create one until yesterday — but there is no
  pass to repair one, unlike `pdfText`, which has a backfill indexer.
- **Search answers with items, not pages.** `search(_:)` returns `[ItemID]`, so
  a hit says the document contains the words and not which page or which box.
- **The words are stored run together.** Several boxes on a page join with a
  space into one row, which is right for matching and is not the page's layout.
- **Nothing is indexed per word or position**, so there is no highlight-the-hit
  behaviour here, only "this document matches".

## A file item shows what it holds — row 8 UI — 2026-11-02 (Claude, UI by owner's direction)

The owner asked Claude to take UI while Codex is out of usage. `FileThumbnail`
shipped on 2026-10-28 with **nothing calling it**; the file details sheet now
shows a real picture of the file's contents where it showed the symbol for its
type.

- Full `./scripts/test.sh`: **511 tests passed** (0 warnings).
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.
- **`./scripts/ui-test-ios.sh` had not reported when this was committed.** It
  was started and was still running; the owner asked for the commit before it
  finished. **So the interaction run for this change is unverified**, and that
  is the one check this project asks for on UI work that the rest cannot stand
  in for. It is recorded here as unrun rather than assumed, and the result will
  be added when it lands.

### What limited the choice of slice at all

Codex has 193 uncommitted files, 14 of them in `PaperNestUI` and
`Apps/iOS/UITests`. For a file with uncommitted changes on both sides,
**whoever commits last silently reverts the other**, so every one of those is
off-limits — including `Localization.swift` and all three `Localizable.strings`.
**That rules out any UI work with new on-screen text**, which is why the Fill
Form, outline and compression screens were not candidates: this slice needed
**no new `L10n` keys**, and that is most of why it was the one available.

The library grid still shows the type symbol. That is one line,
`LibraryView.swift:570`, in a file Codex has open — left for whoever commits it
next rather than changed and lost.

### The fallback is the ordinary case

Most types have no preview, so the symbol stays most of the time. It is a
different claim rather than a worse thumbnail — "this is a spreadsheet" instead
of "this is what the spreadsheet looks like" — and the engine is still asked
only for a real rendering of the contents, never for the generic type icon the
system offers, because that icon *is* the symbol dressed up as a preview.

The header keeps a fixed 44-point box either way, so the row does not change
height when a thumbnail arrives after the copy is staged. The image stays
`accessibilityHidden`, as the symbol was, with the name and size beside it
carrying the meaning — so nothing VoiceOver reads has changed.

### It implements the fallback recorded on 2026-10-28 as "implemented nowhere"

`prepareTemporaryCopy` left a name with no extension exactly as it was, and the
system refuses to look inside such a file — measured then, and `nil` from both
the thumbnail and media engines. The staged copy now borrows the extension from
the item's recorded `uti`.

A name that **already** has an extension is left alone, even one that disagrees
with the recorded type. That copy is what the share sheet hands over, and
renaming someone's file to match its bytes is not that function's business —
`aNameThatAlreadyHasAnExtensionIsNotRewritten` pins that narrowing, and it
passed before the change as well as after, which is worth saying: it guards the
new behaviour from going further than intended rather than proving it.

### What this does **not** do

- **The interaction test is unrun**, as above. Nothing here has been driven in
  a running app.
- **No thumbnail in the library grid or list**, which is where most people
  would look for one.
- **Nothing is cached.** The sheet asks the system each time it opens. The
  staged copy it uses was already being made for sharing, so no file is copied
  twice, but a grid would need a cache this does not have.
- **A thumbnail for a large file still costs a full staged copy**, because the
  system needs a real file with a usable name and the stored asset is
  `<sha>.bin`.
- **No test asserts what is on screen.** The naming fix is covered, and the
  engine was covered in October; the view's own choice between picture and
  symbol is not, because the image is `accessibilityHidden` and so invisible to
  a UI test as well as to VoiceOver.

## iOS UI tests cannot run on this machine — 2026-11-02 (Claude)

**No interaction test has run since 2026-10-29.** This is an environment
failure, not a code one, and it is recorded because it means every UI change
from 2026-11-02 onwards is unverified in the one way this project says counts.

- `./scripts/ui-test-ios.sh` was started for the file-thumbnail change and sat
  for **4 hours 23 minutes with zero output**, no `xcodebuild` process beneath
  it, and was killed.
- The cause is its first real step. `xcrun simctl list devices available -j`
  **hangs**: killed at 60 seconds, 0 bytes written, nothing on stderr. The
  script selects a simulator that way before it echoes anything, which is why
  the log was empty rather than showing a failure.
- So CoreSimulator is wedged on this machine. Codex ran these tests
  successfully on 2026-10-29, so it has gone wrong since.

### What still works, and what does not

- **Unaffected:** `./scripts/test.sh` (511 tests, 0 warnings) and
  `./scripts/build-mac-app.sh`. Neither touches CoreSimulator.
- **Also unaffected:** `xcodebuild -scheme PaperNestUI -destination
  'generic/platform=iOS Simulator' build`, which succeeded today. A *generic*
  destination needs no device enumeration, so iOS **compilation** is still
  verifiable.
- **Blocked:** anything needing a booted simulator — `scripts/ui-test-ios.sh`,
  `scripts/run-mac-app.sh`'s iOS counterpart, screenshots, and every XCUITest.

### Not fixed

The usual remedy is to restart `com.apple.CoreSimulator.CoreSimulatorService`,
which would end any running simulator session. That is the owner's machine and
their call, so it has not been done. Until it is, UI work can be built and
compiled but its interactions cannot be driven, and nothing here should be
described as verified in the app.

## Why the iOS UI tests hang — the actual cause — 2026-11-02 (Claude)

The entry above said CoreSimulator was "wedged" and that the remedy was
restarting `CoreSimulatorService`. **That was a guess, and it was wrong.** The
service was restarted, came back on a new pid, and `simctl list` still hung —
so here is what it really is, found by taking the wrapper apart.

`.../Xcode.app/Contents/Developer/usr/bin/simctl` is a **bash wrapper**. It
reads the installed CoreSimulator version, compares it against the version it
expects, and if the installed one is older it runs:

    "${DEVELOPER_DIR}/usr/bin/xcodebuild" -runFirstLaunch

**synchronously, before exec'ing the real `simctl`.** That command installs
Xcode's system components and asks for an **administrator password**. Nothing
was there to answer it, so it waited — which is why the log stayed at zero
bytes for four and a half hours rather than printing an error.

Measured:

| | |
| --- | --- |
| installed CoreSimulator | **1174.9.2** |
| the `simctl` wrapper expects | **1174.21** |
| `xcodebuild -checkFirstLaunchStatus` | **exit 69** — components still need installing |
| Xcode | 27.2 |

So Xcode was updated and its first-launch component install was never
completed. Codex's last good run was 2026-10-29, which places the update
between then and now.

### The fix needs the owner, and cannot be done from here

    sudo xcodebuild -runFirstLaunch

It needs an administrator password, so no agent can run it. Opening Xcode once
and letting it install components does the same thing. **Until that happens,
every simulator-dependent check stays blocked** — `scripts/ui-test-ios.sh`,
screenshots, every XCUITest — and no UI change can honestly be called verified
in a running app.

### Two things this turned up on the way, worth knowing

- **`sample` on this machine's PATH is not macOS's.** It resolves to a Python
  script in `/Library/Frameworks/Python.framework/Versions/3.11/bin`, which
  fails with `ModuleNotFoundError`. Use `/usr/bin/sample` by full path — the
  PDFKit deadlock in October was only found because that call used the full
  path.
- **`grep` is a shell function wrapping `ugrep`.** It has already emitted
  `ugrep: warning:` in place of a plain grep error. Anything depending on exact
  grep behaviour should call `/usr/bin/grep`.

## Jump to a section by the document's own contents — row 36 — 2026-11-02 (Claude, UI)

`PageRenderer.outline(for:)` shipped on 2026-10-27 and nothing called it. The
editor's More menu now has **Contents**: the document's own table of contents,
with a tap jumping to that page.

- Full `./scripts/test.sh`: **513 tests passed** (0 warnings), `LocalizationTests`
  included — which is the check that the three new-key languages agree, that no
  key is unused, and that French typography is right.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.
- **No interaction test.** `scripts/ui-test-ios.sh` cannot run on this machine —
  see the entry above for why — so **nobody has opened this menu, tapped an
  entry or watched the page change.** That is the honest state of it.

### Read from the file, never rearranged

The entries are what the PDF declares, in the author's order and nesting. A
reordered document's contents will therefore not ascend, and that is deliberate:
it is a true description of the file, and sorting it here would invent an
answer the document does not give. The engine already drops entries whose page
was deleted, so an entry points at a page the document still shows.

### The one decision the sheet makes for itself

The sheet holds the outline it read when it opened. A page deleted *while* it is
open would otherwise select an id the document no longer has, leaving the editor
showing nothing — so `pageToSelect` returns nil for an entry whose page has
gone, and the two tests cover both halves: an entry opens the page it points at,
and one whose page has gone opens nothing while its siblings still work.

Nesting is indented but capped at four steps, so a deeply nested heading keeps a
readable text width on a phone.

### What this does **not** do

- **Nothing has been driven.** The menu item, the sheet, the empty state and
  the jump are all unexercised in a running app. The Mac app would still run
  (`scripts/run-mac-app.sh` needs no simulator) and was **not** used to check
  this; that route is open if the owner wants it driven before the simulator is
  fixed.
- **Only PDF outlines.** A notebook, a scan or an image has no outline to read,
  so the sheet correctly says the document carries none — but there is no
  user-made bookmark here, which is the other half of row 36 and still Planned.
- **No current-section highlight**, no jump-to-nearest-heading, and the sheet
  does not follow the page you are on.
- **A file that cannot be read shows "no contents"** rather than an error. For
  a navigation sheet that seemed better than an alert, but it does mean a
  damaged file and a plain one look alike here.
- **Depth beyond four levels is flattened visually** only — the entries are all
  still listed, in order.

## Driving the Mac app: two UI features verified, one bug found — 2026-11-02 (Claude)

The iOS UI tests cannot run here, but **the Mac app needs no simulator**. Both
UI features committed today were driven in it against a throwaway library
seeded with a generated 3-page PDF carrying a real outline and a plain-text
file item. This is the first interaction check since 2026-10-29.

- Full `./scripts/test.sh`: **513 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### Verified by looking at it

- **A file item shows its contents.** The details sheet's header shows a real
  Quick Look preview of the text file — a small page with its words on it — and
  not the blue type symbol. Zoomed in to be sure.
- **Contents lists the document's sections and jumps.** All three entries
  appeared in order, and pressing *Payment Schedule* dismissed the sheet,
  moved the editor to page 3 and selected page 3 in the sidebar.
- Incidentally: **Codex's first-launch welcome screen** appeared on a fresh
  library and dismissed on *Get started*, and stayed dismissed on relaunch.

### The bug this found, which no unit test could

The sheet first reported **"This document doesn't carry contents of its own."**
for a document that plainly had three. Traced rather than guessed:

| checked | result |
| --- | --- |
| the generated fixture on disk | outline root, **3 children**, destinations → pages 0,1,2 |
| the copy the library stored | same, **3 children** — import preserves it |
| `pages` rows in SQLite | three `pdfPage` rows on that asset, indices 0,1,2 |

So the file, the import and the engine's inputs were all correct. The fault was
mine, in the sheet: it took `[Page]` **at construction**. SwiftUI builds a
sheet's content when it is presented, so a sheet opened before the document's
pages had loaded kept an empty snapshot for ever and answered "no contents".
It now takes the `DocumentModel` and reads `model.pages` live, keyed on the
page count so a document still loading is read again when its pages arrive.

**This is exactly the failure the unit tests could not see** — they call the
engine and the one pure helper, neither of which knows when a sheet is built.

### Two things added to make it checkable at all

- **Contents is in the Mac menu bar**, at the top of the Page menu. The
  in-window More menu cannot be opened while the app is in the background, and
  the error said so. A document command belongs in the menu bar on macOS
  anyway. **Deliberately without a keyboard shortcut**: this project has been
  bitten by clashes with system ones, and the simulator that logs them cannot
  run today.
  Worth recording so nobody reads it as a defect: the menu item is **disabled
  while the app is in the background**, and the pre-existing *Crop…* was
  checked and behaves identically — it is how `@FocusedValue` works, not a
  fault in the new item.
- **`-PaperNestDebugShowOutline YES`**, beside the existing
  `-PaperNestDebugShowExport`, `…ShowCrop` and `…ShowMarkup` hooks. It opens
  the sheet at launch, which is both how this was driven in the background and
  how an XCUITest will reach it when the simulator works. **It is also what
  exposed the bug**, by getting to the sheet before the pages loaded.

### What this does **not** establish

- **Still no XCUITest.** Nothing is automated; this was a person-equivalent
  driving the app once. The hook above is in place for when `simctl` works.
- **Mac only.** The iPhone and iPad layouts of the Contents sheet, and its
  behaviour at large text sizes and in French and Spanish, are unchecked.
- **The empty state still cannot be told from a read failure.** A file whose
  outline cannot be read says "no contents", exactly as a file with none does.
  That is unchanged, and it is what made the bug above look like an ordinary
  answer.
- **One document, one outline shape.** Flat, three entries, one asset. Nested
  outlines, multi-source documents and deleted pages are covered by unit tests
  only.

## A Text Box tool, and where the other five asked-for tools stand — row 21 — 2026-11-02 (Claude)

The owner asked for six things: a text box, selecting handwriting and moving
it, an image tool, a highlighter, pencil controls and an eraser. **The survey
first, because most of the answer is not "build it" but "it exists, elsewhere".**

| asked for | where it actually stands |
| --- | --- |
| **Text box** | Engine was done; **the tool is built now**, below. |
| **Select handwriting, move it** | **Works on iOS** — PencilKit's lasso, and `InkConversion` applies `stroke.transform` on save, so a moved stroke persists moved. **Nothing on Mac.** |
| **Image tool** | Engine done (`placeImage`, drawing, export). **No UI on either platform.** |
| **Highlighter** | In the model (`InkStroke.Tool.highlighter`), drawn and exported; reachable on iOS through the PencilKit tool picker. **Not on Mac.** |
| **Pencil controls** | iOS only, PencilKit's own picker (width, colour, pen/pencil/marker). **Not on Mac.** |
| **Eraser** | iOS only, PencilKit's. **Not on Mac.** |

**The finding worth acting on: `InkCanvas` is `#if os(iOS)`, and so is the
Markup toggle. The Mac app has no drawing, no eraser and no lasso at all** —
four of the six requests are a single missing piece, a Mac drawing surface, and
PencilKit does not exist on macOS to supply it.

- Full `./scripts/test.sh`: **520 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### The text box tool

`LibraryStore.placeText` is the guarded way in, as `placeImage` is for
pictures — `saveObject` would take anything, and a box the renderer skips
leaves the page quietly missing what someone typed. Refused rather than
stored: empty or whitespace-only text, a frame with no area or a non-finite
one, a font size of zero, and a missing or deleted page. Each refusal writes
nothing. Seven store tests.

`DocumentModel.addTextBox` wraps it with the refresh and the undo
registration the other mark tools use, so **Undo works on a text box** — seen
working in the app. The same write rebuilds the page's search row, so the
words are findable the moment they are added.

**Verified by driving the Mac app**, not by inference: created a notebook,
opened *Text Box* from the notes tool bar, typed "Agreed at the meeting on
Tuesday", chose Center and red, pressed Add — the text appeared on the page in
red and centred, the sidebar thumbnail updated, and Undo became enabled.

It is in both More menus, the notebook tool row and the Page menu, with eight
new keys in English, French and Spanish. Alignment is a **segmented** control
rather than a pop-up, because French and Spanish truncate in pop-ups.

### What this does **not** do

- **A text box cannot be moved, resized or edited once added.** The frame is
  chosen by `addTextBox` — a band across the upper part of the page, its height
  growing with the font size. This is the biggest gap in the tool and the
  obvious next slice; the owner asked for "move it anywhere" about handwriting,
  and it applies here too.
- **Text longer than the frame is clipped**, silently, as it has been since
  the engine landed.
- **No image tool yet**, though its engine has been ready since 2026-10-28.
- **Nothing was added for the Mac's missing drawing surface**, which is what
  four of the six requests actually need.
- **No XCUITest** — the simulator still cannot run. This was driven by hand on
  Mac, once, in English, in dark mode. iPhone and iPad layouts, large text, and
  French and Spanish are unchecked.

## Correction: undo on a text box did not work — 2026-11-02 (Claude)

The entry above says, of the text box tool, "**Undo works on a text box** —
seen working in the app". **That was wrong, and the way it was wrong is worth
recording.** What I saw was the Undo *button become enabled*. Enabled is not
working, and I wrote down the stronger claim.

Pressing it would have shown "the markup changed" and left the text box on the
page. The editor's whole undo history runs through
`LibraryStore.applyInkChanges`, which guarded `case .ink = object.payload` and
answered `pageObjectsChanged` for anything else. Undoing an *added* text box
applies the inverse change — a delete of that object — so the guard refused it.

Proven before fixing: a store test applying exactly the inverse change the undo
path applies failed with `.pageObjectsChanged`.

### The fix

The guard now accepts the marks a page carries — ink, a text box, a placed
image — rather than ink alone. **A page comment is still refused**, and that is
deliberate: it is private, it has its own guarded path that leaves the page
revision alone, and it must not travel through the markup history.
`PageCommentWorkflowTests` and `InkEditTests` both still pass.

### Verified properly this time

In the running Mac app: made a notebook, added a text box reading "This should
vanish on undo", pressed **Undo** — the text disappeared from the page and from
the sidebar thumbnail, no error appeared, and Redo became enabled. That is the
check the first entry should have had.

- Full `./scripts/test.sh`: **521 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.

### What this does not change

A text box still **cannot be moved, resized or edited** once added — the next
slice, and the one the owner asked for. The image tool still has no UI, and the
Mac still has no drawing surface, which is what the highlighter, pencil
controls, eraser and lasso all actually need.

## A placed mark can be picked up and moved — row 21 — 2026-11-02 (Claude)

The gap the text box shipped with: a box could be added and never moved. A
text box or a placed image can now be dragged on the page, with undo.

- Full `./scripts/test.sh`: **526 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### Verified by dragging one

In the running Mac app: added a text box reading "DRAG ME" at the top of a
notebook page, dragged it to the bottom — it moved, the selection outline
followed it and the sidebar thumbnail updated — then pressed **Undo** and it
returned to the top with Redo enabled. Both halves seen, not inferred.

### How it is put together

`MovableMarksOverlay` sits over the rendered page and claims **only** the
rectangles those marks occupy, so scrolling, zooming and the iOS ink canvas
behave exactly as before, and it stands down entirely while the ink canvas is
up. It positions handles with the **same `sourceToView` transform the page was
drawn with** — the one the ink canvas already uses — rather than a second
guess at where a mark is.

The write goes through `applyInkChanges` with `saving: [moved]` and
`replacing: [original]`, so a drag is refused if the object changed underneath
it, and undo comes from the machinery everything else uses. That path only
accepts text and images here because **ink is moved by the drawing canvas's own
lasso** and a page comment has no frame — `moved(_:to:)` returns nil for both
rather than mangling them, and a test says so.

A dragged frame is clamped so its **origin** stays on the page. Hanging over an
edge is allowed, because that is a reasonable thing to want and drawing clips
it; being dragged entirely off and lost is not.

### What this does **not** do

- **No resizing.** There are no handles: a mark keeps the size it was created
  with. For a text box that matters, because text longer than its frame is
  still clipped silently.
- **No editing.** The words in a text box cannot be changed after it is added,
  and there is no delete from the page — only undo.
- **Ink is untouched.** Selecting and moving handwriting remains PencilKit's
  lasso on iOS, and still does not exist on Mac.
- **Mac only, by hand, once.** No XCUITest — the simulator still cannot run —
  so the drag is unexercised on iPhone and iPad, where a drag competes with
  scrolling in a way a mouse does not. That is the most likely place for this
  to behave differently, and it is untested.
- **No multiple selection**, no keyboard nudging, and the selection is not
  cleared by tapping the page.

## Drawing on a Mac — row 21 — 2026-11-02 (Claude)

macOS has no PencilKit, so the Mac had **no drawing, no eraser and no lasso at
all** — the single gap behind four of the six tools the owner asked for. This
is the first half of closing it: a canvas of our own, with a pen and a
highlighter, colour and width, saved as ordinary ink with undo.

- Full `./scripts/test.sh`: **531 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### Verified by drawing

In the running Mac app: made a notebook, turned on **Markup** (the toggle now
exists on Mac), drew a wavy pen stroke, then switched to **Highlighter**,
**Thick** and **yellow** and drew across it. Both appeared, the highlighter
translucent over the pen so the stroke beneath shows through. The pen stroke
survived quitting and relaunching the app, so it is stored as ink like any
other.

### The bug drawing it found

The first stroke **saved but vanished from the page** the moment the pointer
came up — it was in the sidebar thumbnail and nowhere else. The page is
rendered with `includesInk: !isMarkingUp`, which is right for iOS, where
PencilKit draws every stroke itself and the page underneath must not draw them
twice. The Mac canvas previews **only the stroke being drawn**, so the page has
to keep drawing the saved ones. Separated into `pageShowsInk`, with the reason
written down, because the two canvases genuinely need opposite things.

Nothing but driving it would have caught this: the stroke was saved correctly,
so every test passed.

### How it works

One drag, one stroke. Points are captured in view space and converted with the
**inverse of the transform the page was drawn with**, so a stroke lands where
the pointer was at any zoom and is stored in the same upright source space as
everything else. Five tests cover that geometry, including that **the same
place on screen at two different zooms is the same place on the page**, and
that a click without movement is kept as a dot rather than dropped.

Saving goes through `applyInkChanges`, so undo is the same machinery as
everything else.

### What this does **not** do

- **No eraser and no lasso.** Half the gap is still open: nothing on Mac
  selects, moves or rubs out ink. Moving a *text box or image* works (that is
  `MovableMarksOverlay`), but ink is untouched.
- **No pressure, so one width per stroke.** A drag gives position only. On iOS
  Apple Pencil varies the width within a stroke; on Mac it cannot, and that
  difference is real rather than hidden.
- **The widths are the shape tool's** — 1, 2 and 4 source points. "Thick" is
  thin for a highlighter; the sizes have not been tuned for drawing.
- **No smoothing.** Points are joined as straight segments, so a fast stroke
  looks angular where PencilKit would curve it.
- **No XCUITest**, as ever while the simulator is down. Driven by hand on Mac,
  once, with a mouse — not with a trackpad, and not at any zoom but the default.

### A trap worth knowing

`MacInkCanvas.stroke(…)` is a static on a SwiftUI `View`, which makes it
main-actor isolated. Calling it from a test **compiled** and then trapped at
runtime with signal 5. The same thing on `DocumentOutlineSheet.pageToSelect`
was caught at compile time instead. Mark such helpers `nonisolated` — the
failure mode is a crash in the test runner with no assertion message, which
reads like a broken test rather than an isolation problem.

## An Image tool — row 21 — 2026-11-03 (Claude)

The last of the six tools the owner asked for that had no UI at all.
`placeImage` has been ready since 2026-10-28 and nothing called it; **Image**
now sits beside Text Box in the editor and in the Page menu, picks an image
file, and puts it on the page.

- Full `./scripts/test.sh`: **537 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

The bytes are sniffed with the project's own `FileTypeSniffer.kind(of:)`, so
what gets stored is what the bytes **are** rather than what a filename claimed,
and a kind the renderer cannot draw is refused before anything is written. They
are staged durably and the row referencing them is written by `placeImage` in
the same transaction, so the housekeeping sweep cannot take the file in
between.

The frame **keeps the image's own proportions**, so a photo is not squashed into
a box: a 2:1 image comes out 2:1, measured. A sideways photo reports the size it
is *shown* at rather than the size it is stored at, because that is the shape the
frame has to match — the renderer decodes it upright, and
`aSidewaysPhotoReportsTheSizeItIsShownAt` pins the quarter turn. An image whose
size cannot be read still gets a usable frame rather than a zero-sized one the
renderer would skip. Seven tests.

Once placed it can be **dragged**, because `MovableMarksOverlay` already covers
placed images, and undo is registered like every other mark.

### What was verified, and what was not

- **Verified in the running Mac app:** the **Image** button exists in the
  notebook tool row and the editor menus, is disabled with no page selected,
  and is reachable.
- **Not verified:** the picker itself. A macOS open panel is modal and needs
  the app frontmost; background control cannot bring it forward, and no panel
  appeared or could be confirmed. **So the hand-off from "a file was picked" to
  "an image is on the page" has not been driven by anyone.** Everything either
  side of it is covered — the sniffing, the frame, the staging-and-row write,
  the drawing, the dragging and the undo — but that join is code nobody has
  run.

That is the honest state of it, and it is the place to look first if it
misbehaves.

### What this does **not** do

- **No resize.** A placed image keeps the size it was given, as a text box
  does; it can only be dragged.
- **No drag-and-drop onto the page**, and no paste — the picker is the only way
  in.
- **One image per pick.** Multiple selection is off.
- **No XCUITest**, as throughout while the simulator is down.

## An eraser on the Mac — row 21 — 2026-11-03 (Claude)

Drawing arrived on the Mac yesterday with no way to take a mark back except
Undo. **Markup** now reads **Pen | Highlighter | Eraser**, and dragging the
eraser over a stroke removes it.

- Full `./scripts/test.sh`: **543 tests passed**, **0 warnings**, all five
  targets green.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

The eraser is a **mode, not a mark**. `MacMarkupTool` is its own enum rather
than a case added to `InkStroke.Tool`, which is persisted — an eraser case in
the stored enum would invite a saved stroke that claims to be one. The drag
paints nothing: it collects points, converts them to source space, and asks
which ink objects it touched.

**Hit-testing is point-to-segment, in both directions.** A stroke is taken when
any of its points comes within `eraserRadius + width / 2` of a *segment* of the
eraser's path, or any eraser point comes that close to a segment of the stroke.
Measuring only between recorded points was the first implementation and it
was wrong: it missed the middle of a long straight stroke, whose two recorded
points are hundreds apart, and `theEraserTakesTheStrokeItCrosses` caught it. The
reverse direction covers a dot that falls between two samples of a fast flick
(`aFastFlickStillTakesADotBetweenItsSamples`). The reach is 8 source points
plus half the stroke's width, so a thick stroke is caught from further away
(`aThickStrokeIsReachedFromFurtherAway`) and the reach is the same on the page
at any zoom.

Removal goes through `applyInkChanges(on:saving:replacing:deleting:)`, the same
guarded write every other mark uses, as one undoable step named by `L10n`.
Eleven tests cover the geometry and the hit-testing, including
`theEraserNeverTakesATextBoxOrAnImage` — the filter matches `.ink` payloads
only, so a text box or an image sitting under the drag is not collateral.

While the eraser is selected the **width and colour controls are hidden**,
because neither means anything for it, and the preview stroke is a faint grey
instead of the pen's colour.

### Verified by driving the Mac app

Against a throwaway library (`/tmp/pn-erase`, since deleted), in a notebook with
two separate pen strokes one above the other:

- Switching to **Eraser** hid the width and colour rows, leaving the three
  tools.
- One drag down across the **upper** stroke only: **the upper stroke
  disappeared from the page and from the sidebar thumbnail, and the lower one
  stayed.** Both halves of that matter — an eraser that takes everything would
  also pass "the stroke is gone".
- **Undo brought it back**, both lines on the page and in the thumbnail, with
  Redo then enabled. The write is durable, not a view-state trick.

### What this does **not** do

- **Whole strokes only.** A stroke the eraser crosses goes *entirely*, rather
  than being split where it was crossed. Splitting means rewriting a stroke's
  points and deciding what becomes of the halves; a whole-stroke eraser is a
  behaviour people already know, but it is not what PencilKit does on iOS, so
  **the two platforms now erase differently** and nobody should read one as
  evidence about the other.
- **No eraser size.** 8 source points, chosen because aiming a mouse at a thin
  line is harder than aiming a finger. Unmeasured against anyone's hand.
- **No cursor change.** The pointer stays an arrow over the page, so the only
  sign of which tool is armed is the segmented control.
- **Nothing is erased on iOS by this.** PencilKit's own eraser is what iOS has,
  and it is untouched.
- **Still no lasso on Mac**, which is the last of the six tools the owner asked
  for: handwriting cannot be selected and moved there.
- **No XCUITest**, as throughout while the simulator is down — driven by hand
  on Mac, once, in English, in light mode.

## A lasso on the Mac — row 21 — 2026-11-03 (Claude)

The last of the six tools the owner asked for. Handwriting can now be selected
and moved on a Mac: **Markup** reads **Pen | Highlighter | Eraser | Lasso**, a
loop drawn round a stroke selects it, and dragging the selection moves the ink.

- Full `./scripts/test.sh`: **556 tests passed**, **0 warnings**, all five
  targets green.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

**The rule is "wholly enclosed".** Every point of a stroke has to fall inside
the loop, which is what drawing a circle round handwriting means, and it keeps
a loop from dragging off the neighbouring word by its tail. Point-in-polygon is
the even-odd rule, written out rather than handed to `CGPath`, so the loop is
**closed from its last point back to its first** here rather than by whoever
drew it — a drag ends where the pointer stopped, and nobody closes a lasso by
hand.

**The selection is held by `PageObjectID`, never by value.** The strokes are
read back from the model when the move commits. Holding the objects themselves
would have meant that selecting, moving, undoing and then moving again sends
stale points as `replacing:`, `applyInkChanges` refuses the write, and `try?`
swallows it — a drag that silently does nothing. That exact sequence was
driven in the app (below), because the geometry tests cannot reach it.

The move translates every point, keeps the object's **id**, so undo sees one
mark moved rather than one deleted and another added, and keeps each point's
`widthScale` and `time`, so pressure and timing recorded by an Apple Pencil
survive being moved on a Mac. The drag is converted through the page's own
transform — two points through the inverse and subtracted, shared now with
`MovableMarksOverlay` as `DocumentModel.sourceDelta` — so a **rotated** page
moves ink the way it looks. A hand-rolled divide-by-the-scale passes the zoom
test and fails that one, which is why both are pinned.

**A selection is clamped to stay wholly inside the part of the page that is
shown**, which is stricter than `clamped` is for a text box, and for a reason:
the lasso only takes a stroke it can enclose wholly, so handwriting with a tail
outside could never be selected again. The rectangle is `PageGeometry.cropRect`
rather than the whole source, because on a cropped page the canvas covers only
what the crop leaves, and ink dragged under the crop is as unreachable as ink
dragged off the page. Ignoring the crop's origin makes
`aSelectionCannotBeDraggedUnderTheCrop` fail, which is how that was checked. A selection already bigger than the page is left alone rather
than pinned. Fourteen tests. They failed to **build** before the API existed,
which is an error rather than a failure, and **four** were then proven red by
deliberately breaking the guard they cover: the closure, the whole-stroke rule,
the rotated transform and the crop's origin. The other ten were not shown
failing against wrong code, and three of those — `nothingSelectedHasNoBox`,
`translatingIsForInkOnly` and `aSelectionBiggerThanThePageCanStillBeMoved` —
would pass against a good deal of it.

### Verified by driving the Mac app

Against a throwaway library (`/tmp/pn-lasso`, since deleted), in a notebook with
two zigzag pen strokes:

- Switching to **Lasso** hid the width and colour rows, as the eraser does.
- A loop round the **upper** stroke drew a dashed box tight to that stroke and
  left the lower one unselected.
- Dragging from inside the box moved the upper stroke down and left; the lower
  one stayed, the dashed box followed the ink, and the sidebar thumbnail
  redrew. The ink is really moved, not previewed.
- **Undo** put it back, box and all.
- **Dragging the same selection a second time, after that undo, worked** — the
  stale-payload failure above.
- Switching back to **Pen** cleared the dashed box.
- **French and Spanish**, both launched and looked at: *Stylo | Surligneur |
  Gomme | Lasso* and *Lápiz | Marcador | Borrador | Lazo*, all four readable
  in the 420-point row, no truncation.

### Found while checking, and **not** caused by this

**The document toolbar's Redo button reads enabled after undo followed by a
fresh edit.** Reproduced with the pen alone — draw, Undo, draw, and Redo is
still blue — so it is not the lasso's doing. Pressing it changed nothing on the
page, and it then disabled itself.

**Run down and fixed** — see *The Undo button went dead on the stroke you had
just drawn*, below. It was the row's enabled state, not the history, and the
symptom was worse than a lit Redo: the **Undo** button was greyed out on the
mark someone had just drawn.

### What this does **not** do

- **No resize, no rotate, no delete, no copy of a selection.** It can be
  selected and dragged, nothing else.
- **No handles.** The dashed box is drawn but cannot be grabbed by a corner.
- **No lassoing text boxes or images.** Ink only — those move with Markup off,
  through `MovableMarksOverlay`, and the two never coexist.
- **No moving across pages**, and no cut and paste anywhere.
- **The original stays on screen during the drag.** The page renderer keeps
  drawing the ink where it still is until the commit lands, so the dragged
  outline and the original are both visible mid-drag. That is the honest cost
  of previewing in the canvas, and it was chosen over leaving a naked
  rectangle to drag.
- **Partly-enclosed strokes are simply not selected**, with no hint on screen
  saying why. A loop that catches nothing clears the selection.
- **No XCUITest**, as throughout while the simulator is down — driven by hand
  on Mac, once each in English, French and Spanish, in light mode.

## The Undo button went dead on the stroke you had just drawn — 2026-11-03 (Claude)

Found while checking the lasso, then run down on its own. Two earlier drafts of
that entry each got this wrong, which is why the sequence is written out here.

- Full `./scripts/test.sh`: **559 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What was wrong

After drawing a stroke, the editor's **Undo** button stayed greyed and
**Redo** stayed lit — the state from *before* the stroke. You could not undo
the mark you had just made, from the button.

`NotebookHistoryActions` reads `UndoManager.canUndo` and `canRedo`, which are
not observable SwiftUI state, so it re-reads them only when one of its own
inputs changes. It bumps a `revision` on `NSUndoManagerDidCloseUndoGroup`,
`…DidUndoChange` and `…DidRedoChange`. The last two fire; **the first does
not** for these registrations, because every ink edit registers its undo from
inside a `Task` rather than while handling an event, so there is no
event-grouped close for the undo manager to announce. Nothing told the row the
stroke had happened.

`DocumentModel.historyRevision` is the input it was missing: the model advances
it whenever it registers an undo, re-registers one during an undo, or clears
the stack after a failed write, and the row folds it into its `.id`. The model
is the only thing that knows it has touched the stack.

### How it was established, step by step

Everything below is one action per round trip — **a click and a screenshot in
the same batch is useless here**, because the undo runs on a `Task` and the
screenshot is taken before it lands. Two earlier passes were misread exactly
that way, and the first of them is the reason an earlier draft of the lasso
entry called this "a stale label" without evidence.

1. Draw A → Undo → page empty, Undo greyed, Redo lit. **Correct**, and it
   proves the notification path works for an undo.
2. Draw B → B is on the page, and the row **still** reads Undo greyed, Redo
   lit. That is the bug: the display never moved.
3. Press Redo → **A does not come back.** Only B is there, and the row corrects
   itself to Undo lit, Redo greyed. So the redo stack really had been cleared
   by the fresh edit, as `UndoManager` does; the lit Redo was stale, and the
   press changed nothing but the display.
4. **⌘Z undoes the stroke the greyed button refuses.** The keyboard goes
   through the responder chain and never consults the row. So the history was
   sound throughout and nothing was ever lost or misapplied — the fault was
   entirely in which buttons you were allowed to press.

### What was verified after the fix

- Three tests in `HistoryRevisionTests`, each watched failing first (the
  property did not exist): drawing advances the revision, **erasing and moving
  advance it too**, and undoing advances it further rather than going
  backwards. The first asserts `undo.canUndo` alongside, so it cannot pass by
  registering nothing.
- In the running Mac app, on a fresh notebook: drawing a stroke now leaves
  **Undo lit and Redo greyed**, and undo-then-draw-again — the original
  symptom — leaves Undo lit and Redo greyed as well.

### What this does **not** cover

- **The same `Task` registration is used for page transforms**, which bump the
  revision too, but rotate/crop/filter were not re-driven by hand. The tests
  cover ink only.
- **iOS was not driven**, as throughout while the simulator is down; it
  compiles, and the row is shared, so the phone and iPad toolbars should
  benefit identically — *should*, untested.
- **No XCUITest.** `notebook-undo` and `notebook-redo` have accessibility
  identifiers but no `accessibilityValue` saying whether they are enabled, so
  a test would have to assert on `isEnabled`.
- **The root cause is worked around rather than removed.** Registering inside
  an explicit `beginUndoGrouping`/`endUndoGrouping` would make the native
  notification fire by itself, and would be the smaller fix — but it changes
  undo grouping for every edit in the app, including the re-registration that
  runs *during* an undo, and that was not something to change late in a
  session on a hunch. Worth revisiting deliberately.

## The six tools, used together for the first time — 2026-11-03 (Claude)

The six the owner asked for were built one at a time over three days and had
never been exercised side by side. This is that pass, in one notebook on a
Mac, and the two faults it turned up — both fixed here.

- Full `./scripts/test.sh`: **567 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### 1. A text box or an image could never be taken off the page

**Manage Markup said "No marks on this page" with a text box plainly on it** —
and plainly in the sheet's own preview, two inches above those words. Its list
filtered to `.ink`, so the two tools that do not draw ink produced marks the
manager could not see. Nothing else offers a delete: the eraser is ink-only by
design, the lasso selects ink only, and the drag overlay moves without
removing. So once undo had moved on, **a text box or a placed image was on
that page permanently.** That is a worse fault than any of the polish items in
the entries above, and the pass found it in the first two minutes.

The gate was in the store: `editInk` refused anything but `.ink` outright.
Now:

- **Removing** accepts `.ink`, `.text` and `.image` — anything painted on the
  page.
- **A comment is still refused.** It is not painted on the page and has its
  own place to live; sweeping one away from a markup sheet would delete
  something the user cannot see from there.
- **Recolouring stays ink-only** and is **refused**, not skipped, for anything
  else, through a new `StoreError.cannotRecolor`: an image has no colour and a
  text box's colour is not what that picker means. The sheet disables **Apply
  Color** whenever the selection holds anything but ink, so the button never
  promises a refusal.

The sheet lists every painted mark, a text box under its own words rather than
as "Mark 3", and the selection preview outlines text and image frames as it
already did stroke bounds.

### 2. The highlighter drew a hairline

Pen and highlighter shared one row of widths — 1, 2 and 4 points. That is
right for a pen on an A4 page and useless for a highlighter: at **Thick** it
laid a 4-point yellow line *across* the words instead of a band behind them,
which a zoom of the page makes plain. It was not a highlighter in any sense a
user would recognise.

The width row now means different things to different tools: `width(for:)` on
`MacMarkupTool`, with the picker carrying a `MarkupWeight` (thin/medium/thick)
rather than a number. The pen keeps 1/2/4; the highlighter gets 12/20/30, so
its *thinnest* is wider than the pen's thickest and its middle step covers the
18-point line a text box defaults to. Choosing by weight rather than by number
also means switching back to the pen cannot leave a 30-point pen armed.

### What was verified, and how

Thirteen new tests in all, each watched failing first. Three were then proven
red by breaking the guard they cover: the highlighter widths (set back to the
pen's, and two tests fail), removing a text box, and recolouring one.

In the running Mac app, on a throwaway library (`/tmp/pn-six`, since deleted):

- A **new** highlighter stroke lays a proper yellow band behind a line of
  text, in the same frame as the old 4-point stroke still showing as a
  hairline on the line above. Old strokes keep the width they were saved with,
  which is correct and worth knowing.
- Manage Markup lists the text box **under its own words**, with Apply Color
  greyed and Remove Selected lit while it is the selection.
- **Remove Selected takes it off the page**, out of the list, out of the
  preview and out of the sidebar thumbnail — and **Undo puts it back**.

### Also found, and **not** fixed

- **The sheet outgrows the window.** With four marks on a 729-point-tall
  window, Apply Color and Remove Selected fall below the bottom edge; the
  scroll view is there, but synthetic scroll events would not move it, so
  **whether a real trackpad reaches them is unconfirmed**. Verified instead on
  a page with one mark. The sheet asks for `idealHeight: 680` and the Done
  button sits at the very bottom edge. Codex owns that layout.
- **A text box still cannot be edited.** Clicking and double-clicking a placed
  box does nothing but select it: its words, size, colour and alignment are
  fixed at the moment it is added. Now that it can at least be *removed*, this
  is a smaller hole than it was, but a typo still means delete and retype.
- **A text box's frame is taller than its text**, so the dashed selection box
  hangs below the words. The text does wrap rather than clip, which the
  earlier entry for text boxes did not establish.
- **The image picker is still undriven.** A macOS open panel is modal and
  background control cannot bring it forward.
- **Six tools, two homes.** Pen, highlighter, eraser and lasso live behind the
  Markup toggle; Text Box and Image sit in the toolbar and are unavailable
  while Markup is on. That is a coherence question for whoever owns the
  design, not a bug.

## A text box can be changed after it is placed — row 21 — 2026-11-03 (Claude)

The hole the previous entry's pass left open. A text box was **write-once**:
its words, size, colour and alignment were fixed the moment it was added, and
clicking or double-clicking it did nothing but select it. A typo meant
deleting the box and typing it again — and until the previous commit it could
not even be deleted.

- Full `./scripts/test.sh`: **573 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

**Double-click a box and it opens**, pre-filled with what is on the page, with
the sheet titled *Edit Text Box* and its button reading *Save*. The same sheet
adds and edits; `editing` tells it which.

`LibraryStore.updateText` is the way in, with **the same refusals as placing
one** — empty text, a zero or non-finite size, a frame with no area — because
an empty box is just as unusable the second time. It also refuses a payload
that is not a text box, so a stroke handed in here cannot be quietly turned
into text. The write is the **guarded** one, so a box someone else changed
first is refused rather than written over.

The box keeps its **id** and its place in the paint order, so undo sees one
box changed rather than one deleted and another added, and a mark does not
jump above its neighbours when it is edited. The same write rebuilds the
page's `text` index row, so the old words stop being findable as the new ones
start — pinned by a test, since search answering with text the page no longer
carries is the kind of thing nobody notices for months.

**Where it is stays where it is.** The origin and width it was dragged to are
kept, and only the height follows the type size, through
`DocumentModel.textBoxHeight(forFontSize:pageHeight:)` — shared with placing,
so a box does not change shape the first time someone touches it.

The sheet re-reads the box **by id** when Save is pressed rather than trusting
the copy it opened with: an undo in between would otherwise make the guarded
write refuse, and `try?` would hide it. If the box is gone entirely — undone,
or removed from the markup manager — it says so instead of resurrecting it.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-edit`, since deleted), with a box reading
"Pian in full":

- A **double click opens it**, pre-filled: the text, Size 18, Left, black.
- Changing the text, the size (18 → 30), the alignment (Left → Center) and the
  colour (black → red) and pressing **Save** shows all four on the page at
  once, with the frame grown taller and the sidebar thumbnail redrawn.
- **Undo restores every one of them**, frame height included.
- **Editing again straight after that undo works** — the stale-copy trap.
- **Dragging still works.** The double-click is a `highPriorityGesture` in
  front of the drag, which is the thing most likely to have broken moving, so
  it was checked rather than assumed.
- **English, French and Spanish**, all three launched and looked at:
  *Edit Text Box / Save*, *Modifier la zone de texte / Enregistrer*, *Editar el
  cuadro de texto / Guardar*. No truncation in the 460-point sheet.

### What this does **not** do

- **No editing in place.** The words are changed in a sheet, not typed on the
  page, and there is no caret or text selection on the page itself.
- **Still no resize or reflow by hand.** The width is whatever it was placed
  or dragged with; only the height follows the type size, and text longer than
  the box still runs past its bottom edge.
- **No font choice.** One typeface, as before.
- **A placed image cannot be edited**, because there is nothing to edit but
  its frame, and resizing is not built. Double-clicking one does nothing.
- **iOS is untested.** The overlay is shared, so a double *tap* should open
  the same sheet on a phone or iPad, and `accessibilityAction` offers it to
  VoiceOver — *should*: the simulator is still down and neither was driven.
- **No XCUITest**, as throughout.

## A mark can be resized by a corner — row 21 — 2026-11-03 (Claude)

A text box or a placed image kept whatever size it was given: it could be
moved, and since the last two commits removed and edited, but never made
bigger or smaller. Selecting one now puts a handle on each corner.

- Full `./scripts/test.sh`: **585 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

**The corner opposite the one dragged stays exactly where it is.** That is the
whole contract of a corner handle, and getting it wrong makes a box look like
it is running away from the pointer; all four corners are pinned by a test
that checks the anchor survives.

**An image keeps its proportions; a text box does not have any to keep.**
Squashing a photo is what the placing code went to trouble to avoid, so a
resize must not undo it. Which axis drives a locked resize is decided by
**whichever was dragged further**, so the gesture follows the pointer rather
than ignoring one direction, and at the edge of the page a locked image
**shrinks to fit rather than distorting** — the easy mistake there is to clamp
one side and leave the other, which is exactly the squashing the lock exists
to prevent.

Nothing shrinks below 16 source points in either direction — a negative width
draws nothing and leaves something on the page nobody can grab — and nothing
grows past the page, for the same reason a move is clamped. The write is the
same one a move uses, with its own undo name, so the Edit menu says which of
the two it is undoing.

### A regression this turn's checking found in **last** turn's commit

Dragging a corner needs the mark selected first, and **clicking a mark had
stopped selecting it**. `2cd5c8e` added opening-on-double-click as a
`TapGesture(count: 2)` beside the move gesture. A tap-count gesture waits to
see whether a second click is coming and **swallows the single click that
never becomes one** — as `highPriorityGesture` and, tested here, as
`simultaneousGesture` too. It was found by taking the tap gesture out and
watching selection come back, after guessing wrong once.

It is counted by hand now, inside the drag that already handles the first
click: a second click on the same mark within the system's own
`NSEvent.doubleClickInterval` opens it. Three tests cover the pairing. **That
commit's claim that double-clicking worked was true; what it did not say is
that single-clicking had stopped, because that run only checked the double
click and the drag.** A reminder that checking the thing you added is not the
same as checking what it sits next to.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-resize`, since deleted):

- **One click selects** and draws four corner handles.
- **Dragging the bottom-right handle inwards shrinks the box**, with the
  top-left corner staying exactly where it was.
- **Undo restores the old size.**
- **A double click still opens the editor**, and **dragging the middle still
  moves the mark** — the two things the gesture change could have broken.

### What this does **not** do

- **Corners only.** No edge handles, so a box cannot be made wider without
  also being made taller unless the drag happens to be horizontal.
- **No proportional resize for a text box**, and no modifier to lock or
  unlock: SwiftUI's drag gesture does not report modifier keys, so shift-drag
  would have to be read some other way. Images are locked, text is free, and
  that is the whole rule.
- **Text does not reflow to a resized box.** It still runs past the bottom
  edge if there is more of it than the box holds.
- **Pointer only.** The handles are `accessibilityHidden`, because four
  identically labelled stops would be worse for VoiceOver than none — but
  that leaves **no way to resize a mark without a mouse or a finger**, which
  is a gap, not a decision to be proud of.
- **The handles' targets overlap on a small mark.** Each is 22 view points
  across, so on a mark near the 16-point minimum they sit on top of one
  another and whichever is topmost wins.
- **iOS is untested**, as throughout while the simulator is down; the overlay
  is shared, so handles should appear there too.
- **Only the undo name is new text** (`Resize`), and it shows in the Edit
  menu rather than on screen, so the French and Spanish were not looked at
  this time — nothing in the sheet or the page changed.

## Recognition reads in the languages you choose — F4 — 2026-11-03 (Claude)

Taken from "Next for Claude" in the handoff. Recognition always asked Vision
for English, French and Spanish — whatever the document was and whoever was
reading it. Someone scanning German could not say so, and since Vision
**weights the list it is given**, the wrong list does not merely fail to help:
it makes the reading worse.

- Full `./scripts/test.sh`: **598 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

Settings now has a **Text Recognition** section listing every language this
device's Vision can read, named in the reader's own language. Nothing else is
offered: the supported set differs by OS version, and a row that cannot work
is a promise that cannot be kept.

`TextRecognizer.resolve(override:fallback:available:)` decides what to use. A
choice **replaces** the defaults rather than adding to them, for the weighting
reason above. The order chosen is kept, because that is the order Vision
weights. A choice this device cannot honour **at all** falls back to the
defaults rather than leaving recognition with an empty list that reads
nothing — and `unavailable` still carries the whole choice, so the screen says
*"This Mac cannot read Swahili (Kenya)"* instead of quietly reading something
else. Where nothing is readable the list comes back **empty rather than as a
guess**: reading a page in a language nobody asked for produces confident
nonsense, and `recognize` refuses an empty list outright.

Eight tests cover the resolution, with `available` passed in so they do not
depend on what this particular machine supports; two were proven red by
removing the fallback and the de-duplication. Five more cover the stored form,
which is a hand-rolled comma-separated string — a stray space or an empty
entry would reach Vision as an unreadable language and be reported back as the
reader's mistake.

**It also removes a duplication that was waiting to go wrong.**
`DocumentModel.recognizeText` built its recognizer from one constant and
recorded the languages from another, agreeing only because both started from
the same list. Both now come from one resolution. The automatic sweep was
built with the recognizer's own hard-coded default and now takes the same
choice.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-lang`, since deleted):

- The section lists the 28 languages this Mac's Vision reads, each named in
  the reader's language, none ticked to begin with.
- Ticking **German** stores `de-DE`; adding Italian and unticking German
  leaves `it-IT`, so order and removal both work.
- **End to end:** with Italian chosen, the existing recognitions were deleted
  and the app relaunched; the automatic sweep redid all three pages and
  recorded `["it-IT"]` in `page_recognition`. The choice reaches Vision, not
  just the defaults file.
- Storing a language this Mac cannot read shows **"This Mac cannot read
  Swahili (Kenya)."** with Italian still ticked and still used.
- **English, French and Spanish** all launched and looked at; the long footer
  wraps cleanly in each and the language names are localized. The French
  typography test caught a plain space before a colon in the footer, which is
  a narrow no-break space now.

### Fixed on the way: Settings grew to 1834 points tall

A row per language made the macOS Settings window **1834 points tall**, well
past any screen, because that Form sizes itself to its content. The list has a
height of its own and scrolls inside it; the window is 935 now. Seen only
because the window was opened and looked at — the tests would never have
caught it.

### A stale note corrected rather than acted on

The handoff said `DocumentModel.recognizeText(on:)` still called the blocking
`TextRecognizer.recognize(_:)` on the MainActor and should move to
`recognizeOnADedicatedThread(_:)`. **It does not** — both it and the automatic
sweep already use the dedicated thread; the fix landed and the note was never
updated. Checked rather than redone, and the note is removed.

### What this does **not** do

- **No per-document choice.** It is one setting for the whole app; a library
  with French and German documents in it gets both languages on every page or
  switches between them by hand.
- **Nothing is re-recognised when the choice changes.** Pages already read
  keep what they have until something else invalidates them — there is no
  "read these again" anywhere.
- **The accuracy claim in the footer is not measured here.** That more
  languages costs accuracy is Vision's documented behaviour, not something
  this slice benchmarked.
- **iOS is untested**, as throughout while the simulator is down. The section
  is cross-platform and the macOS-only scroll box is `#if os(macOS)`, so the
  iOS Form shows the rows inline — unseen.
- **No XCUITest.** The rows carry `recognition-language-<code>` identifiers
  for one, and the unavailable line carries its own.

## Three working export formats nobody could pick — 2026-11-03 (Claude)

From "Engine work waiting for a screen". `ExportFormat` has six cases and the
export sheet offered **three**: PDF, JPEG and PNG, written out as three tiles
by hand. TXT, HEIC and DOCX all worked in the engine, were unit-tested, and
could not be chosen by anyone.

- Full `./scripts/test.sh`: **604 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

The tile list is **data** now — `ExportSheet.offeredFormats` — and
`ExportFormatOfferTests` fails if it does not cover `ExportFormat.allCases`.
That is the part worth keeping: the next format added to the engine cannot
quietly reach no screen. Six tiles lay out three to a row so they do not
squeeze each other into slivers on a phone.

**A format that holds only the words shows no image options.** `keepsOnlyWords`
lives on `ExportFormat`, so the sheet and the engine cannot disagree about
which is which, and for TXT and DOCX the resolution, quality and packaging
controls are gone — a control that does nothing is worse than no control. In
their place, under the tiles, is what the format costs: *"This format keeps
the words, not the layout: no pictures, no ink, no marks and no page design. A
page with no text of its own is left out, and a document with none cannot be
exported this way."*

**A document with no text gets told so.** `ExportError.noTextToExport` used to
surface as the generic "export failed"; it now reads *"None of these pages
carry any text, so there is nothing to write. Recognize Text first, or export
as PDF or an image instead."* That is the likely case for scanned pages nobody
has recognised yet, and "failed" would send someone looking for a bug.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-exp`, since deleted):

- All six tiles appear: PDF, JPEG, PNG / HEIC, TXT, Word.
- **TXT** on a three-page letter: *Ready: 275 bytes*, which matches the three
  short lines the pages actually carry.
- **Word**: *Ready: 2 KB* — a `.docx` is a zip, so that is the right order.
- **HEIC**: *Ready: 76 KB* for three pages, packaged as a ZIP.
- Choosing TXT hides the image options and shows the caveat; choosing PDF puts
  its own options back.
- A **blank notebook** exported as TXT shows the new message in red rather
  than "export failed".
- **English, French and Spanish** all launched and looked at; both new strings
  wrap cleanly in each.

### Fixed while checking: the caveat did not render at first

It was written as a `Section { EmptyView() } footer: { … }`, and **SwiftUI
drops a Form section whose content is empty — footer and all**. The first run
in the app showed nothing between the tiles and Pages. It sits in the Format
section's own footer now, which is the better place regardless. Worth knowing:
a section that is only a footer does not exist.

### What this does **not** do

- **No password field.** `Exporter.export` takes one and `ExportError` has
  three careful cases for it — including that non-ASCII passwords cannot be
  written, which is a real problem for French and Spanish readers. **Still no
  way to set one**, so that engine remains unreachable.
- **The saved file's contents were not read back.** The sheet reported a
  plausible size for each format and the engines have their own unit tests,
  but the bytes that reached disk were not opened: the save panel is modal and
  background control cannot drive it, and saving into the real Downloads
  folder was not something to do on a check.
- **DOCX keeps one paragraph per line and no formatting**, as its engine
  always has; the caveat says so for both text formats.
- **iOS is untested**, as throughout while the simulator is down. The tile row
  uses `ViewThatFits` on iOS and a plain `HStack` on macOS, so the phone
  layout of six tiles in two rows is unseen.
- **No XCUITest.** Each tile carries `export-format-<format>` and the caveat
  carries `export-words-only-note`.

## A password on an exported PDF — row 27 — 2026-11-03 (Claude)

The engine has taken a password since 2026-10-27, with three carefully
written refusals and eleven tests including *an exported PDF with a password
needs it to open* and *the encryption is AES and not RC4*. **Nothing could
set one.** The last entry named this as the clearest remaining gap; this
closes it.

- Full `./scripts/test.sh`: **613 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

A **Password** section appears in the export sheet for PDF and for nothing
else — `ExportFormat.canCarryPassword`, on the format so the sheet and the
engine cannot disagree. Switching to TXT takes the section away.

**An empty field means no password**, not an empty one. The engine refuses
`""` outright, because written as both the user and the owner password it
produces a file that opens with nothing while the caller believes it is
protected — and an untouched field is the likeliest source of exactly that.

**A password the writer cannot store is caught where it is typed.** PDFKit
stores nothing outside ASCII — measured, not inferred: `"été-Ñandú-2026"` was
refused as well as `"contraseña-密码-1"`. The engine's own comment asks
whoever builds the screen to say so rather than reject the password with a
generic error, so the reason appears under the field as it is typed and
Export is disabled until it is fixed. That is a real limitation for French
and Spanish readers and it is now named in their own languages.

**A password longer than 32 bytes is flagged, not refused.** Revision 4 reads
the first 32; the whole password still opens the file, so refusing it would
be wrong — but someone typing a long passphrase believes all of it is
protecting them. The note says only the first 32 characters will be needed.

Every `ExportError` now maps to its own sentence rather than "export failed",
which also improves the no-text case from the previous entry.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-pw`, since deleted):

- The **Password** section and its footer appear for PDF and **disappear for
  TXT**, replaced by that format's own caveat.
- **English, French and Spanish** all launched and looked at: *Password /
  Password (optional)*, *Mot de passe / Mot de passe (facultatif)*,
  *Contraseña / Contraseña (opcional)*, each with its footer wrapping cleanly.

### What was **not** driven, and what was done instead

**Nothing was typed into the field.** Background control blocks typing into a
secure text field, which is the right restriction, and taking over the screen
needs an approval card that went unanswered through four attempts — so that
route was abandoned rather than retried into the ground.

What that left unexercised was the link between the two tested halves: the
value the sheet decides on reaching the exporter. **`ExportPasswordWorkflowTests`
closes it** by running the same value through the same call the sheet makes,
against a real library and a real exporter, and then opening the written file:

- a typed password leaves a file that is **locked**, refuses a wrong password
  and opens with the typed one;
- an untouched field leaves a file that is **neither locked nor encrypted** —
  the empty-password failure the engine refuses, seen from this side.

Proven red by making `passwordToUse` always return nil, which is exactly the
"sheet silently drops the password" failure worth fearing.

**What is still not covered:** the SwiftUI binding from a keystroke to
`@State password`, and the three messages — accented password, empty
password, 32 characters — which have **never been seen on screen**, only
checked as strings by `LocalizationTests`. An XCUITest is the natural way to
finish it: the field carries `export-password`, the problem line
`export-password-problem` and the length note `export-password-truncated`.

### Also: a red suite that was my own mess

The full run failed once on `cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind`,
which asserts no `PaperNestExport-*` directory is left in the temporary root.
The leftover was a **HEIC export from the previous entry's checks**, left at
"Ready" when the app was killed. Not a regression — but worth knowing that
this test reads the shared temporary directory, so driving the real app on
the same machine can turn it red.

### What this does **not** do

- **No password on anything but a PDF**, by design, and no owner/user
  distinction: one password both opens the file and owns it. No permission
  flags — printing, copying and annotating are not restricted separately.
- **The password is not kept anywhere**, which the footer says. There is no
  "remember this" and no keychain.
- **No strength meter and no confirmation field.** A typo in a password that
  is never shown again means a file nobody can open, and nothing warns about
  that.
- **iOS is untested**, as throughout while the simulator is down.

## Row 24 measured: an exported form keeps its boxes and loses its fields — 2026-11-03 (Claude)

Ledger row 24, *interactive PDF form fields preserved*, has read **Planned**
since 2026-10-26 with the note that an unedited page is now copied rather
than redrawn, *"so a field would survive"*. **That inference is wrong**, and
nobody had checked it: the existing pass-through test compares an exported
form against a source that has no form either, and says so in its own
comment.

- Full `./scripts/test.sh`: **616 tests passed**, **0 warnings**. No source
  changed — this slice is a measurement and three tests.

### What actually happens

Exporting a document whose single page carries a real catalog `AcroForm`:

- the **widget annotations survive** — both of them, on the page, where they
  were;
- the **`AcroForm` does not**. `PDFForm.fields(in:)` reads nothing from the
  exported file, and a value that was already filled in is gone with it.

So the export shows the field boxes exactly where they belong and not one of
them is a field any more. That is the worst shape this failure could take,
because it looks right: someone exporting a filled agreement gets a page that
still looks like a form and has lost the answers.

### Why, and what fixing it would take

Structural, not a slip. An `AcroForm` lives in the document **catalog**, not
on a page. Pass-through copies `PDFPage`s into a document that PDFKit then
writes, and **PDFKit exposes no way to carry a catalog dictionary across** —
there is no API for it, so no amount of care in `isUntouched` can help.

The honest fix is a different path: when **every** page of an export is
untouched, comes from one source asset, and is in that source's original
order, copy the source **file** wholesale instead of rebuilding a document.
That would keep the form, the links and the bookmarks together.
*(This also said "and the embedded fonts" — withdrawn 2026-11-04, never
measured.)* *(Written here as "and be faster" — **measured 2026-11-04 and that
part is wrong**; see the entry below.)* It needs exact guards — page count, order, asset
identity, no paper change, no text layer, no password — and it changes the
most-used export path, so it is its own slice and is **not** attempted here.

### What is pinned

Three tests, all passing, all written so that **fixing the loss makes them
fail**, with comments saying to rewrite rather than patch them:

- `anExportedFormKeepsItsBoxesAndLosesItsFields` — asserts the fixture really
  has a form first, then that two widgets survive and the form does not.
- `aFilledInValueGoesWithTheForm` — the value is read back from the source
  before the export, so the test cannot pass by the value never existing.
- `aPageThatHadToBeRedrawnLosesItsFormToo` — the other half of the boundary:
  a page redrawn for a different paper size could never keep a form, and
  that is now a measured fact rather than something found on a signature
  page.

Read back through **Core Graphics** throughout, never PDFKit, which reports a
`fieldName` for a widget whether or not the file has a form at all and has
misled this project once already.

### What this does **not** do

- **It does not fix anything.** Row 24 is not closer to working; it is
  closer to being honestly described.
- **One fixture, one page, one field of each kind.** Radio groups, `/Kids`
  hierarchies, signature fields and XFA are untested, and XFA almost
  certainly fares worse.
- **Nothing was checked in another reader.** "The form is gone" means Core
  Graphics finds no `AcroForm`; Acrobat's view of the same file was not
  sought.

## An unedited export is the file that was imported — row 24 fixed — 2026-11-04 (Claude)

Yesterday's entry measured the loss: exporting a page with a real `AcroForm`
kept the widget boxes and lost the form, so the page looked like a form and
was not one. The cause was structural — a form lives in the document
**catalog**, not on a page, and PDFKit cannot carry a catalog across when
pages are copied into a new document. This stops building a new document when
there is nothing to build.

- Full `./scripts/test.sh`: **634 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### The rule

`Exporter.wholeSourceAsset` answers one question: is this export simply the
file that was imported? It says yes only when **every** page is an untouched
page of **one** source file, in that file's **own order**, starting at its
first page — and the caller adds that the source has no more pages than the
export does, and that every page really was copied untouched. Then the source
bytes are written out as they are.

Each refusal is a way the copy would hand back something other than what was
asked for: another format, different paper, a password, a crop or rotation,
pages from two files, a subset, a reordering.

### What it buys

- **A form survives**, fields and filled-in values both. So do **links** and
  the **table of contents**, each with a test, and the outline keeps its
  nesting. A rebuild loses the outline entirely, which is pinned too — "the
  copy keeps the bookmarks" would be an empty sentence otherwise.
- **Embedded fonts were also claimed here and that claim is withdrawn.** A
  rebuild draws text as text and keeps it selectable, accents included, so
  there was no reason to think fonts were being lost; nothing was measured
  either way, and an unverified line is worse than a missing one.
- **The export is byte-identical to the import**, asserted as such rather
  than as "it works": anything less means something was rebuilt, and whatever
  was rebuilt can lose things no test thought to check.
- **Compression got honest.** Three compression tests failed the moment this
  landed, on `compressed <= plain` — because `plain` had become the pristine
  source and **the rebuild had been inflating files**. A preset is now allowed
  to hand the source back when no page could be re-encoded, which is both
  smaller and what the compression result already reported: no saving.

### It is not faster, which I had assumed out loud

The handoff and yesterday's entry both said this would "be faster". **It is
not.** Twenty vector pages, three runs each: **copy 0.016s, rebuild 0.013s** —
marginally *slower*, and both negligible.

The reason is plain once measured: the copy path still runs the whole page
loop and writes a placeholder document before throwing it away, because
deciding whether a page is untouched needs the same per-page work either way.
So this does strictly *more* than before for an unedited export. The gain is
correctness — forms, links, bookmarks and fonts surviving — and nothing else.
Said here because it was claimed before it was checked.

### What it costs, deliberately

- **A document handed back whole keeps the source's title and creator**, not
  this app's. Two tests asserted our creator on unedited exports and are
  rewritten: an *assembled* document carries it, one handed back whole does
  not. There is no version that keeps both — setting the metadata means
  writing through PDFKit, and **PDFKit refuses to write the AcroForm fixture
  back at all** (`write(to:)` returns false), which was measured, not assumed.
  Stamping this app as the creator of someone else's unmodified file is not
  obviously right anyway.
- **A password still costs the form**, because a protected file has to be
  written and writing it is the rebuild. Pinned by a test so the trade is
  known rather than discovered: you cannot have both today.

### The guard that nearly shipped untested

Breaking the per-page index check did **not** fail any test at first. The
subset case was caught by the first-page guard, and the deleted-page case by
the page-count guard — so the index check looked load-bearing and was not
proven to be. The case it alone catches is **a shuffle that keeps the first
page and the page count**: three pages exported as 1, 3, 2. Without it the
source comes back in the source's order and the reordering is silently
undone. Two tests now cover it, one on the predicate and one driving a real
export, and both fail when the check is removed.

### What this does **not** do

- **Nothing was driven in the app.** This is engine work with no surface of
  its own; the export sheet is unchanged.
- **One fixture family.** Radio groups, `/Kids` hierarchies, signature fields
  and XFA are still untested, and XFA probably fares worse.
- **No other reader's opinion.** "The form survives" means Core Graphics finds
  it and `PDFForm` reads its value back; Acrobat was not asked.
- **Encrypted sources are untouched by this.** A source that needs a password
  to open was already handled elsewhere and is not part of the copy path.
