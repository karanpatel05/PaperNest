# Encrypted PDF export (Set Password) — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Ledger row 27 is Partial — protected PDFs *import*, but nothing can write one. Yesterday's compression slice had to refuse protected PDFs outright, which made the gap concrete. Give the exporter an optional password so a PDF can be written that requires it to open.
**Architecture:** `CGPDFContext` takes `kCGPDFContextUserPassword` / `kCGPDFContextOwnerPassword` in its info dictionary, and `PDFDocument.write(to:withOptions:)` takes the same two as options. The password is a parameter of `export`, **not** a field of `ExportOptions`.
**Tech Stack:** Swift 6, Core Graphics, PDFKit, Swift Testing; no dependencies.
**Spec:** Backend only, my lane. Codex is on native UI polish in `PaperNestUI`; nothing here touches it.

## What the encryption actually is — measured before designing
Probed on this machine, reading the `/Encrypt` dictionary out of the raw bytes. **Both** `CGPDFContext` and `PDFDocument.write(to:withOptions:)` produce the same thing:

```
/Encrypt  /V 4  /R 4  /Length 128  /AESV2  /StmF /StdCF  /EncryptMetadata true
```

- `/AESV2` is **AES-128 in CBC mode**. This is *not* RC4, which was the thing worth refusing over.
- It is revision 4, **not** revision 6 (AES-256, PDF 2.0). Apple's APIs do not expose R6.
- The weakness of R4 is its key derivation, which is MD5-based and fast, so a weak password falls to an offline brute-force attack. **The strength is the password, not the cipher.**
- Verified to actually protect: the written file opens locked, the wrong password is rejected, the right one unlocks it, and the text is intact afterwards.

**What may be claimed:** "encrypted with AES-128; anyone with the password can open it." **What may not:** "secure", "military-grade", or any suggestion that a weak password is safe. The wording belongs in the brief for whoever builds the screen.

## Constraints and review focus
- **Set both the user and the owner password to the same value.** In the standard security handler a document opens with *either*. Leaving the owner password empty means it opens with an empty owner password, which would defeat the user password completely. A test asserts an empty password does not open the file.
- **The password is a parameter, never part of `ExportOptions`.** Options are settings a UI may persist; a password is a secret that must not be stored, hashed into a settings value, or logged. `ExportOptions` is `Hashable` and already a candidate for last-used persistence.
- **Pass-through re-writes the file after the context closes, and that would drop the encryption.** `replaceWithSourcePages` writes the assembled document to a staged file; without the password on that write the final file arrives unprotected while the caller believes it is protected. This is the same "assembling fresh strips protection" failure found in compression yesterday. A test covers an untouched page exported with a password.
- **A password on a format that cannot carry one is refused**, not ignored. Silently writing an unprotected JPEG, TXT or DOCX when the caller asked for protection is exactly the false promise this project forbids.
- No UI. A Set Password action is the screen owner's work and must not appear until the wording above is right.

## Task 1 — write an encrypted PDF
- [x] Failing tests: the file requires the password; the wrong password is rejected and the right one works; an **empty** password does not open it; without a password nothing is encrypted.
- [x] `ExportError.passwordNotSupported` for non-PDF formats, refused before anything is written.
- [x] `export(…password:)` threading into the `CGPDFContext` info dictionary.

## Task 2 — keep it encrypted through pass-through
- [x] Failing test: a document with an untouched PDF page exported with a password is still encrypted, and still has its link once unlocked.
- [x] Carry the password into `replaceWithSourcePages`' staged write.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX with the exact handler, update row 27 and the brief, release the claim.

## Execution ledger
- Baseline: 385 tests passing, 0 warnings, Mac and iOS builds clean.

## Outcome
397 tests, 0 warnings, Mac and iOS builds clean. The probe decided the design: had it come back RC4, the honest answer would have been to refuse the feature and say why. It came back AES-128, which is sound, so the slice went ahead with wording that matches what it actually is. A test now pins that claim to the written bytes.

## Found after the first green run
- **A mixed document came back with its drawn pages blank and its title gone.** `replaceWithSourcePages` reopens the file the context wrote, which is encrypted and therefore locked, and copies the non-passed-through pages out of it. The single-page test passed because its one page was the passed-through one. `drawn` is now unlocked first. Third instance of "a locked or dead document yields blank pages" in two days.
- **ASCII, not Latin-1.** `"été-Ñandú-2026"` failed to write although every character is Latin-1, so the guard is `allSatisfy(\.isASCII)`. This is a real restriction for the French and Spanish builds and is in the brief.
- **An empty password** passed every guard and would have been written as both passwords, producing a file that opens with nothing. Refused.
- **Only the first 32 bytes are honoured**, pinned by a test so the documented limit cannot quietly go stale.
