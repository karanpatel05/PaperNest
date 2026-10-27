# WebP import — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Row 32 (HEIC and WEBP) is Partial, with the standing instruction: *add WEBP only after codec verification.* This does the verification first and then adds exactly what it justifies.

## The verification, done before anything was written

Asked ImageIO on this platform what it supports:

```
CGImageSourceCopyTypeIdentifiers      → includes org.webmproject.webp
CGImageDestinationCopyTypeIdentifiers → no webp entry at all
```

So the support is **asymmetric**: ImageIO **decodes** WebP and **cannot encode** it. `CGImageDestinationCreateWithData` for `org.webmproject.webp` returns nil.

That settles two things at once:

- **Importing a `.webp` is supportable**, because import stores the original bytes and everything downstream decodes.
- **Converting *to* WebP is not possible** with system frameworks. It is not "planned pending work" — it needs a third-party encoder (libwebp) and the licensing and binary-size decision that comes with one. Row 32 should say so rather than leaving it as a to-do that looks small.

It also means a WebP fixture **cannot be generated at runtime**, which is why the test fixture is a 50-byte literal rather than drawn like the others.

## Constraints and review focus
- **Decode-only is enough for import and nothing more.** Nothing in the pipeline re-encodes an asset to its own kind: compression re-encodes to JPEG, export writes PDF/JPEG/PNG. Verified by reading those paths, not assumed.
- **The fixture has to prove a real decode**, not merely that nothing threw. The literal is a 16×16 lossless image whose top-left quadrant is red, so a test can assert the colours come back in the right places.
- **Sniffing must not over-claim.** A WebP file is a RIFF container: `RIFF` at 0, `WEBP` at 8. Other RIFF payloads (WAV, AVI) share the first four bytes and must not be claimed.
- `AssetKind` is a plain string enum stored in `assets.kind`, so a new case needs no migration; old rows are unaffected. The `.heic` case carries a comment recording what was verified about it, and `.webp` must carry the narrower truth about itself.
- Animated WebP exists. A multi-frame file decodes to its first frame through this path; that is not animation support and must not be described as such.

## Task 1 — recognise and import
- [x] Failing tests: a `.webp` imports as one image page; its colours decode correctly; the stored asset keeps a `webp` extension; RIFF bytes that are not WebP are not claimed.
- [x] `AssetKind.webp`, a `isWebP` sniff, and `.webp` in the importer's image case.
- [x] A `webPImage()` fixture, with a comment saying why it is a literal.

## Task 2 — verify and record
- [x] An imported WebP exports as PDF and as JPEG, since that is what makes it useful rather than merely stored.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build. **The iOS build matters here:** the probe ran on macOS, and the claim is per platform.
- [x] Record in TEST_MATRIX with the exact identifiers, update row 32 to say conversion *to* WebP needs a third-party encoder, release the claim.

## Execution ledger
- Baseline: 406 tests passing, 0 warnings, Mac and iOS builds clean.

## What the plan got wrong
The plan said `AssetKind` is a plain string enum needing no migration. `assets.kind` has a SQL `CHECK` constraint, so the first import failed outright. **Schema v8** widens it, copying the v6 migration that added HEIC. The next migration must be v9. Writing "no migration needed" into a plan does not make it so; the test is what settled it.
