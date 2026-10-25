# Additional notebook pages

Approved scope: add a single blank/lined/grid A4 page after selection (append without selection), notebooks only; select after commit; undo/redo with conflict checks; localized form with cancel and save errors. No schema changes.

Checkpoint: 7444b4d; 236 tests passed before commit.

Execution ledger
- Store: atomic active-parent/anchor validation, opaque snapshot for undo/redo; compare page row, objects, recognition and surrounding page order to reject stale edits.
- Model: register initial undo after insertion; native UndoManager requires synchronous reservation of the opposite stack entry during its callback. Ruling: reserve an unarmed inverse synchronously, arm it only after a successful store transition, and clear obsolete history on failure. Native keyboard/menu requests are serialized through a task chain; later requests read the token only after the preceding transition finishes. A failed transition invalidates queued requests. Busy state disables new sheet submissions and on-screen history controls.
- UI: native add-page sheet in the editor’s existing add menu; paper defaults to the selected template or blank.
- Verification: store and workflow tests first, full unit suite, Mac build, phone/iPad interactions, localized screenshots. Record unrun Mac interaction checks honestly.

- Review found native Undo→Redo could consume an unarmed slot and erase history. Reproduced with immediate calls (four failed assertions), fixed with serialization and generation invalidation, focused regression passed.
- First phone UI run exposed missing compact history controls and a test targeting More instead of the separate Add Pages menu. Both corrected.
- Review follow-up reproduced mixed delete/notebook history running out of order. All DocumentModel native history callbacks now share the serial queue and failure generation. Mixed undo/undo/redo/redo regression failed before and passed after the fix (`papernest-pages-mixed-red.log` / `-mixed-green.log`). Final unit/Mac and iPad notebook + existing drawing regression runs required after this fix.
- A fresh deletion racing queued notebook history reproduced a spurious conflict/lost undo. Fresh page mutation entrypoints now await pending history before reading selection or writing; gestures are retained. Regression failed before and passed after (`papernest-pages-new-edit-red.log` / `-new-edit-green.log`).
- Final independent read-only review found no remaining actionable data-loss or regression issues in the fixes. Final full suite: 245 passed; Mac build passed. Localized iPhone/iPad sheets inspected; all controls/labels fit. Native Mac interaction, real Pencil/camera, large type and injected storage-failure UI remain unrun.
- Completed: 245 tests, final Mac build, final-source iPhone localized notebook flow, iPad localized notebook flow plus drawing/undo/redo/reopen regression. Exact source timing and logs are in TEST_MATRIX. Separate local feature commit: "Add notebook template pages with guarded undo and redo"; no push. File claims released in SESSION_HANDOFF.
