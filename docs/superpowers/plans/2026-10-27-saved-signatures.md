# Saved signatures — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Row 23, *visual fill & sign, saved signatures, initials, checkmarks*, is Planned. Checkmarks already exist as symbol stamps, which are **generated shapes**. A signature is different in kind: ink a person drew once, kept, and placed again on any page of any document.

## What this is, and what it is not — the whole honesty question
A saved signature is **a picture of a handwritten signature**. It is not a cryptographic signature. It proves nothing about who placed it, anyone holding the file can copy the image out and put it on another, and it carries no certificate, no timestamp and no tamper-evidence.

That is not a caveat to add later; it decides the vocabulary. Nothing in the engine, the brief, the spec or any future screen may say "signed", "verified", "authenticated" or "secure". The honest word is **placed**. This goes in `CODEX_BRIEF.md` and `PRODUCT_SPEC.md` as part of the slice, not after it.

## Architecture
A signature is stored as ink in **its own unit box**, not in the coordinates of the page it was drawn on. Normalising at capture makes placement a pure scale-and-translate into any target rectangle, on any page size, with no memory of where it came from. Schema **v9** adds a `signatures` table; the handoff records v8 as the last one used.

**Aspect ratio is preserved on placement.** A signature stretched to fill a rectangle is a different shape from the one the person drew — a visual lie about their hand, and the kind of thing that looks obviously wrong on a contract. It is fitted inside the target and centred, letterboxing whichever way it needs to.

## Constraints and review focus
- Strokes are ordinary `InkStroke`s, so a placed signature is editable, erasable, undoable and exported exactly like any other ink. No new drawing path.
- **A signature with no strokes is refused.** Saving an empty one would offer the user something that places nothing.
- Capture normalises by the ink's own bounding box, so the surrounding blank page does not become part of the signature.
- Placement never changes the stored signature; one signature placed twice gives two independent sets of strokes.
- No UI. Drawing one and choosing where it goes is the screen owner's work.

## Task 1 — the model and its geometry
- [x] Failing tests: capture normalises strokes into a unit box by their own bounds; placing into a rect puts every point inside it; aspect ratio survives, so a wide signature in a square target is letterboxed rather than stretched; the same signature on two page sizes lands proportionally identically; an empty signature is refused.
- [x] `SavedSignature` with capture and placement.

## Task 2 — keeping it
- [x] Failing tests: a signature round-trips through the store with its strokes intact; listing returns what was saved; deleting removes it.
- [x] Schema **v9** and the store API.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX, update row 23, put the vocabulary in CODEX_BRIEF and PRODUCT_SPEC, release the claim, commit.

## Execution ledger
- Baseline: 438 tests passing, 0 warnings, Mac and iOS builds clean, committed as `60c7d15`. Schema v8 is the last migration.

## Outcome
448 tests, 0 warnings, Mac and iOS builds clean. The aspect-ratio test earned the slice: normalising each axis to 0...1 separately is the obvious way to write it and is wrong, squaring up a 4:1 signature at capture. A test that only checked "the ink lands inside the box" would have passed.
