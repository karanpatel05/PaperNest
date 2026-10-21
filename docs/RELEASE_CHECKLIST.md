# Release checklist

The first public release is iOS, iPadOS and macOS together, in English, French and Spanish, in the US and Canada. **Release is blocked** until every item below is checked with evidence in TEST_MATRIX.md. Uploading to TestFlight or submitting to the App Store needs your explicit authorization.

## Blockers

- [ ] Real bundle ID, team, App IDs and iCloud container (APPLE_SETUP.md)
- [ ] The iOS app compiles, runs in the Simulator, and passes real-device camera scanning
- [ ] The Mac app is built from the Xcode project with Hardened Runtime and App Sandbox, and is notarized for TestFlight
- [ ] M2 sync verified on two devices: create, rename, offline edit, conflict copy, delete/restore, account sign-out
- [ ] M3 notebooks verified, including Apple Pencil on hardware
- [ ] M4 OCR in en/fr/es checked against fixtures. Searchable PDF alignment and DOCX open in Word (or a compatible editor).
- [ ] M5 subscriptions: purchase, restore, renewal, expiry, refund/revocation, grace period. Local StoreKit tests plus sandbox. Results kept separate from live App Store checks.
- [ ] Support, privacy and terms URLs exist and are linked from the paywall and Settings
- [ ] French and Spanish reviewed by native speakers. Long French strings checked for truncation on iPhone SE-size screens.
- [ ] Accessibility audit: VoiceOver labels, Dynamic Type, contrast, keyboard navigation (iPad and Mac)
- [ ] Performance recorded for 1/20/100-page documents (device, time, peak memory)
- [ ] Storage-full, low-memory and interrupted-import recovery tested on device
- [ ] Privacy manifest and App Privacy answers confirmed. No document text or identifiers in logs.
- [ ] String Catalog migration done (or `.strings` kept deliberately)
- [ ] Third-party dependency and license list. Currently none (Apple frameworks and system SQLite only).

## Known limitations to disclose or fix

- Links, form fields and annotations inside imported PDFs may not survive export.
- PDFs whose author restricted copying or printing can't be imported.
- Black & White uses a global threshold, so unevenly lit photos may lose detail.
- Images without trustworthy resolution metadata are sized as 11-inch documents.
- Sync (when built) is eventual and uses the customer's iCloud storage. It isn't a backup.

## App Review preparation

- Review notes explaining the free and Pro features, how to reach the paywall, and that no account is needed
- Demo content: synthetic samples only (`Samples/`)
- No rewards for ratings and no sentiment-gated review prompts
- Screenshots in all three languages made from synthetic documents
