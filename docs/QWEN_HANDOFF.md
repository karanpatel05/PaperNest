# Qwen handoff — 2026-10-24

## Start and resume

**Assignment:** two small interface improvements to existing annotation sheets. Implement Q1, then Q2. Stop after the final checks; the wider feature pipeline is not assigned to this model.

| Order | Card | Deliverable |
|---|---|---|
| Q1 | [Q1_SAVED_MARK_SELECTION.md](qwen/Q1_SAVED_MARK_SELECTION.md) | Select All / Deselect All saved ink before recolor or removal |
| Q2 | [Q2_TEXT_LINE_SELECTION.md](qwen/Q2_TEXT_LINE_SELECTION.md) | Select All / Deselect All recognized text lines before annotation |

Read [PROGRESS.md](qwen/PROGRESS.md) first on every restart. Read only the current card and its named source files. Use `rg` to locate symbols; read the matching function, not the whole repository/history. The existing 52 KB session handoff is background; only its Current claims section is needed for coordination.

The owner authorized routine implementation and testing of this queue. No need to ask which feature to choose, which label to use, or whether to continue from Q1 to Q2. Preserve existing project conventions from AGENTS.md/CLAUDE.md. Both tasks reuse the existing localized labels, data model and save operations.

## Known starting state

- Repo: `/Users/karanpatel/Desktop/PaperNest`; branch `document-tools-ocr-and-file-items`; HEAD at preparation: `3d25653`; no remote.
- Prior audit/F3a/F3b work is **uncommitted**, including new files. Keep it. A dirty checkout is expected.
- Last completed verification: **235 unit tests**, Mac build, iPhone/iPad en/fr/es markup workflows passed. This is historical evidence, not a pass for your future edits.
- Real saved ink, per-line annotation, colors, recolor/remove, undo, OCR, persistence and export already work. Do not rebuild them.
- The next-feature turn was interrupted after read-only exploration. No notebook implementation is in progress. No app test/build or Qwen worker was launched by this handoff.

## Working rules

1. Check `git status --short`; inspect the top claims section. Record your actual model/runtime in PROGRESS and claim only the current card's files. If another worker actively owns them, stop instead of overwriting.
2. Before editing an existing file, keep a copy under a new `/tmp/papernest-qwen-backup-<unique-name>/` and record its path. Do not use `git restore` to undo your edits: that would also remove prior work.
3. Work inline, one task and one failing behavior at a time. No helper-agent orchestration or dependency installation is needed.
4. Swift 6; native SwiftUI forms and semantic colors. Use existing `L10n.selectAll` and `L10n.deselectAll`. Do not add English literals or duplicate localization keys.
5. Selection is local view state. Only existing Apply Color, Remove Selected or Apply operations may save. Do not call the store, change revision numbers, or register undo in selection handlers.
6. Do not weaken tests, bypass stale-snapshot checks, or replace the existing loading/error/undo logic to make a new control work.
7. Keep logs outside the checkout. Read concise failure excerpts. After each test run, update PROGRESS with command, result and exact next action. A timeout or unavailable simulator is not a pass.
8. Only use disposable synthetic libraries named by the cards. Run one UI seed script at a time: the script resets shared `/tmp` test libraries.
9. If two attempted fixes leave the same failure, document it and ask for help. Preserve your work and existing code; do not continue into the next task with broken checks.

## Final verification after both cards

Run sequentially, capture logs, check exit codes:

```bash
cd /Users/karanpatel/Desktop/PaperNest
mkdir -p /tmp/papernest-qwen
./scripts/test.sh > /tmp/papernest-qwen/unit-final.log 2>&1
./scripts/build-mac-app.sh > /tmp/papernest-qwen/mac-final.log 2>&1
./scripts/ui-test-ios.sh 63992C10-33B4-4CE3-91C3-EE23ECC595A5 -only-testing:PaperNest-iOSUITests/AppUITests/testSavedMarkupBulkSelection -only-testing:PaperNest-iOSUITests/AppUITests/testTextAnnotationBulkSelection -only-testing:PaperNest-iOSUITests/AppUITests/testSavedMarkupSupportsColorsSelectionRemovalAndRelaunch > /tmp/papernest-qwen/iphone-final.log 2>&1
./scripts/ui-test-ios.sh 62328381-19FB-400A-A8FC-4F4AD13EB5C4 -only-testing:PaperNest-iOSUITests/AppUITests/testSavedMarkupBulkSelection -only-testing:PaperNest-iOSUITests/AppUITests/testTextAnnotationBulkSelection -only-testing:PaperNest-iOSUITests/AppUITests/testMarkupWithFingerDrawingSavesAStroke > /tmp/papernest-qwen/ipad-final.log 2>&1
git diff --check
```

Run each command separately and inspect its result before proceeding. Passing unit tests do not prove a UI test ran. Verify the named test cases appear in the logs (a typo can select zero tests). Inspect saved en/fr/es screenshots if the agent supports images; otherwise record visual inspection unrun. Native Mac interaction remains unverified by a build.

Update PROGRESS, add an accurate short entry to TEST_MATRIX, and release your claim with completed/pending work in SESSION_HANDOFF. Leave all changes uncommitted. Ask Claude/Codex to review the diff before integration. Do not wait for review to accurately record finished tests.

## Work reserved for a stronger-model pass

Word-level OCR selection; notebook creation and entitlement policy; text-object/shape editing; cross-window undo; schema/migrations; archive security; PDF editing/redaction/conversion; CloudKit; app lock/payments; media playback architecture and transcription. These remain in the main pipeline, not this autonomous queue.

## Capacity and runtime note for the owner

Assumption: “Qwen 9B” means **Qwen3.5-9B**, not a different fine-tune. The [official model card](https://huggingface.co/Qwen/Qwen3.5-9B) lists 9B parameters, vision input and a native 262,144-token context. The [Ollama listing](https://ollama.com/library/qwen3.5:9b) provides tool/thinking support and quantized packages; total runtime memory also includes context and other overhead. The configured server context may be much smaller than the model maximum.

My engineering recommendation, not a measured PaperNest benchmark: give it local UI logic, existing API wiring, localization and tightly specified tests. A long advertised context does not establish reliable autonomous architecture or migration work. This queue intentionally has one production view file per task, no new engine API and explicit acceptance tests.

`ollama list` on 2026-10-24 showed `qwen3.5:4b` (3.3 GB) and `gpt-oss:latest`, but no 9B model in that local Ollama server. Other runtimes were not inventoried. No model was installed, launched or switched. Record the model actually used; do not report the installed 4B as 9B.

[Qwen Code](https://qwenlm.github.io/qwen-code-docs/en/users/features/memory/) loads a root QWEN.md as project context. Other agent hosts may require opening this file explicitly. Plain model chat does not autonomously read files or execute tests without an agent/tool host.
