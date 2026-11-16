# PaperNest: project instructions

For the owner-assigned **Qwen small-model queue**, start with `QWEN.md` → `docs/QWEN_HANDOFF.md` → `docs/qwen/PROGRESS.md` and the current task card. Read only Current claims from `docs/SESSION_HANDOFF.md` for coordination; the compact handoff replaces the full-history read for this queue. Other sessions start by reading `docs/SESSION_HANDOFF.md` and `docs/IMPLEMENTATION_PLAN.md`. The product brief is `CLAUDE_CODE_PROMPT.md`. Leave it unchanged.

Design work: follow `docs/CLEAN_NATIVE_DESIGN.md` and the owner's mockups in `docs/design/mockups/`. Claude and Codex share this working tree; check "Who is editing what" at the top of `docs/SESSION_HANDOFF.md` before editing UI files.

## Verify

```bash
./scripts/test.sh                 # all tests (Swift Testing)
./scripts/build-mac-app.sh        # dev PaperNest.app; prints its path (under ~/Library/Caches/PaperNest)
./scripts/run-mac-app.sh /tmp/pn-dev   # build + open with a seeded throwaway library; never test against a real library
```

- Build output and built `.app` bundles live in `~/Library/Caches/PaperNest/build-<hash>` (`scripts/env.sh`), because the checkout is on an iCloud-synced Desktop. iCloud re-tags bundles after signing, which breaks `codesign --verify`. Use `scripts/swift.sh <cmd>` instead of bare `swift build`/`swift run`, and never commit or sync `.build`.
- iOS: `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`, and `scripts/build-ios-sim-app.sh` for a Simulator app. `scripts/swift.sh run papernest-seed <lib> <files…>` seeds a library. Debug launch args: `-PaperNestDebugOpenItem <name>`, `-PaperNestDebugShowExport YES`, `-PaperNestDebugShowCrop YES`.
- Sanitizers: `./scripts/test.sh --sanitize=thread` (Xcode only).
- iOS UI tests: `./scripts/ui-test-ios.sh` (XCUITest, headless). Use it to verify interactions; static screenshots don't count as interaction tests. Give interactive views an `accessibilityIdentifier` and an `accessibilityValue` that tests can assert.
- If Xcode is installed but its license isn't accepted, prefix the commands with `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.
- Under Command Line Tools only, `scripts/test.sh` adds `-F`/rpath flags and `-disable-cross-import-overlays`. Without them Swift Testing fails to import.
- Record real command outcomes in `docs/TEST_MATRIX.md`. Never mark unrun checks as passed.

## Conventions

- Swift 6 language mode with strict concurrency. Keep builds warning-free.
- `LibraryStore` (SQLite) is the only authority for metadata. Assets are immutable and content-addressed (SHA-256). Write the file durably *before* any row references it. Don't add a second store or cache that acts as truth.
- A mutating store call commits before it returns. UI state changes only after the commit, so an edit never appears saved before it's durable.
- Page coordinates: `PageGeometry` is the only mapping. Ink, text and OCR live in upright, uncropped source space with a top-left origin. Never write ad-hoc flips or rotations in drawing code.
- Originals are never modified. Edits are `PageTransform`s with history.
- All user-visible strings go through `L10n` (`Sources/PaperNestUI/Localization.swift`) with keys in en/fr/es `.lproj`. `LocalizationTests` fails on missing or unused keys and on mismatched format arguments.
- In SwiftUI, never pass a string literal to `Text`/`Button`, since literals are looked up in the main bundle. Pass `L10n` strings, or use `Text(verbatim:)` for non-language text.
- In views that import SwiftUI (and in tests that import PDFKit), write `PaperNestCore.LibraryItem`, because SwiftUI also declares a `LibraryItem` type.
- Keep a run of chained modifiers to about a dozen. A debug build keeps every link of a chain on the stack until the function returns, and a device's main thread has 1 MB where the Mac has 8: as one chain `DocumentView.body` needed 885 KB and crashed a real iPad on opening a document. Split a long chain into functions that each take the view so far and add a run of modifiers, as `DocumentView.body` does. That changes nothing but the stack; moving a run into a `ViewModifier` or a `View` of its own saves more, but it then re-evaluates on its own, so check what relied on the whole body refreshing. Simulator builds link with a device-sized stack (`project.yml`), so a UI test that opens the screen fails the way a device would.
- Tests use synthetic fixtures (`Tests/Support/SyntheticDocuments.swift`), never real documents.
- Mocks belong only in tests and previews. No fake sync indicators, simulated purchases or fabricated OCR.
- iOS-only code goes behind `#if os(iOS)`. Compile it for the iOS Simulator before calling it done.
- Check layouts on iPhone width (compact) in en/fr/es. Pop-up option menus truncate French and Spanish values, so iOS forms use inline option rows.
- Keyboard shortcuts must not clash with system ones (⌘E is "Use Selection for Find"). UIKit logs clashes at launch under `UIKit:MenuBuilder`.
- The Xcode project is generated from `project.yml`. Edit that file, never the generated project.
