# Symbol stamps

User delegated the next feature. Builder choice: checkmark, cross and five-point star as one ink object each, using the existing native SwiftUI placement sheet. This is a symbol-stamp slice; text/status labels, custom stamp images and reusable signatures remain later work. No migration or dependency.

## Implementation
- Core: extend the existing ink generator with stamp presets, keeping geometric shapes and stamps in separate picker lists. Bound to the dragged rectangle; triplicate sharp vertices for PencilKit compatibility. Reject degenerate rectangles/styles.
- UI: reuse ShapeAnnotationSheet with an explicit stamp mode, localized titles/help, default checkmark, dedicated More → Stamp entry. Preserve existing shape behavior and exact-page store guards. Stamp undo action gets its own localized title.
- Tests first: cropped/rotated and reversed geometry for all stamp kinds; sharp-corner PencilKit round trips; persistence/export/history through the real model; native localized save/cancel/reopen.
- Verify full suite and Mac build; iPhone/iPad en/fr/es workflows, inspect screenshots. One fresh independent review; fix actionable findings with regressions. Record exact scope and unrun checks.
- Update handoff/roadmap and commit only owned changes. Preserve concurrent Claude work. No push.

## Ledger
- Started from clean tracked implementation; shared handoff claim recorded before code. Prior feature baseline: 283 passing tests. User's standing preference is to choose the next feature and proceed without reconfirmation.

- RED: `/private/tmp/papernest-stamps-red.log` missing stamp cases/list APIs before implementation. GREEN: `-focused.log`, 6 tests across Core/Store/UI; expanded parameter cases verify every stamp after crop/rotation/reversed drag, PencilKit corner sampling and real model PDF export/reopen/mixed-page undo/redo.
- Implementation reuses one placement sheet and one guarded store/model path; no new persistence API or schema. Default stamp box is centered at 35–65% page coordinates. Sheet mode defaults to ordinary shapes so existing callers retain behavior.
- Full unit/Mac build and sequential iPhone/iPad localized UI verification started. Fresh reviewer dispatched read-only while device checks run. No overlap with Claude engine files or Qwen-reserved sheets.

- Full suite 284 PASS; Mac build PASS. Fresh independent review: no findings. Claude has a disjoint automatic-recognition engine claim; preserve its files/sections, and do not stage the entire shared handoff/test matrix.

- iPhone localized flow PASS en/fr/es; all three screenshots inspected and saved. iPad running sequentially. No implementation changes needed after review or phone verification.

- COMPLETE: iPhone and iPad en/fr/es stamp workflows PASS; six screenshots inspected/copied. No review findings or post-verification implementation changes. Existing shapes remain isolated in their original picker and default correctly in native tests. Native Mac interaction and real-device/accessibility/system-picker/slider checks remain explicitly unrun.
- Commit owned paths/hunks only under “Add editable symbol stamps with preview placement”; no push. Release simulator/feature claims. Claude automatic-recognition files and shared-doc sections stay outside this commit.
