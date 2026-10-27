# HEIC export — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Row 32 says "HEIC export remains planned". HEIC *import* landed in F2c; writing one has never been possible, so a photo exported from PaperNest is a JPEG about three times larger than it needs to be.

## The verification, done before anything was written
The WebP slice earlier today found support can be **asymmetric** — ImageIO reads WebP and cannot write it. So HEIC was measured the same way rather than assumed from the import note:

```
CGImageDestinationCopyTypeIdentifiers → includes public.heic, public.heics
CGImageSourceCopyTypeIdentifiers      → includes public.heic, public.heics, public.heif
```

Support is **symmetric**: ImageIO both reads and writes HEIC. Encoding the same 1600×2000 page, at the same quality setting:

| format | bytes |
|---|---|
| HEIC | 94,742 |
| PNG | 209,699 |
| JPEG | 284,377 |

So HEIC is about **a third of the JPEG** and under half the PNG, it round-trips to the same dimensions, and the dpi asked for (200) comes back as 200. That is the whole case for the feature, measured rather than claimed.

## Constraints and review focus
- **The one real cost is compatibility, and it must be said.** HEIC is an export format — the point of exporting is to send the file somewhere — and older systems, many Windows installs and plenty of web forms cannot open one. JPEG stays the safe default. Whoever adds the tile owns saying this; it goes in the brief.
- **`writeImages` picks `options.format == .jpeg ? .jpeg : .png`.** A new case falls into that `else` and would write **PNG bytes into a file named `.heic`** — a silent lie on disk. The switch has to become exhaustive, and a test has to read the written bytes back and check what they actually are, not what they are called.
- `ExportFormat` is `CaseIterable`, but **nothing iterates `allCases`** (checked, as when TXT and DOCX were added): the sheet's format tiles are hand-written, and `contentType(for:)` derives from the file extension, so `.heic` resolves on its own. Adding a case changes no screen.
- The existing `jpegQuality` knob is the lossy quality for HEIC too. No new option.
- **No UI**, as with every other format added this way. A HEIC tile must not appear until someone has opened one of these files somewhere that is not this machine.

## Task 1 — write a real HEIC
- [x] Failing tests: an exported `.heic` really is HEIC when its bytes are read back, not PNG wearing the extension; it decodes to the right size; it is materially smaller than the same page as PNG; the dpi asked for survives.
- [x] `ExportFormat.heic`, and an exhaustive type switch in `writeImages`.

## Task 2 — verify and record
- [x] Regression: PDF, JPEG and PNG exports are unchanged, and multi-page HEIC still packages as a ZIP.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX with the measured sizes, update row 32, put the compatibility wording in CODEX_BRIEF, release the claim.

## Execution ledger
- Baseline: 415 tests passing, 0 warnings, Mac and iOS builds clean.

## Outcome
420 tests, 0 warnings, Mac and iOS builds clean. Measuring first was again the thing that mattered: it settled that HEIC is symmetric where WebP was not, and gave the size figures that justify the format instead of a guess. The `.jpeg : .png` ternary was the real hazard — a filename-based test would have passed on PNG bytes in a `.heic` file.
