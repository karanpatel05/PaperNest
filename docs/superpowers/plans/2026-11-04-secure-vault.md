# Secure Vault — separate follow-up project

Requested by the owner on 2026-11-04; planning only in this redesign. No new chat, repository or workspace is created.

## Goal and boundary
Implement a real encrypted Vault inside PaperNest before exposing a Vault tab. Keep ordinary library files and notebooks unchanged. Reuse SQLite as metadata authority; do not make a second truth store. A hidden folder or biometric-only UI gate is not an encrypted vault.

## Work order
1. Threat model and recovery design: device theft, unlocked-device access, backups, key loss, account changes, screenshots and preview caches. Decide whether recovery is supported and how a user verifies it before moving originals.
2. Backend design owned by the core workstream: per-vault or per-asset authenticated encryption, versioned envelope, Keychain/Secure Enclave compatible key wrapping, atomic encrypted-file writes before metadata commits, and explicit migration/rollback strategy. Audit every cleartext derivative including OCR, thumbnails, search index, export and temporary files.
3. Import/copy/move semantics: preserve originals until encrypted assets and metadata have committed and been verified. A failed move must leave a readable source. Define restore, trash and purge rules.
4. Native unlock/lock UI on iPhone, iPad and Mac, biometric fallback, auto-lock on background/timeout, accessible recovery UI, no secrets in logs. Add the fifth Vault destination only when functional.
5. Export/share deliberately creates a cleartext copy with user intent; clean up temporary copies. Sync is a separate dependency, never inferred from local encryption.
6. Tests: wrong/missing keys, modified ciphertext, interrupted writes, storage exhaustion, cancellation, biometric lockout, device restart, key rotation, backup/restore and recovery. Independent security review before release.

## Acceptance
No data loss during conversion or interrupted moves; locked content cannot be recovered through normal preview/search/export paths; recovery limitations are explained before storing the first item. Audit outcomes and device tests are required before claiming security.
