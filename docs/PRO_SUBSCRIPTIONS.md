# PaperNest Pro and Profile

## Implementation

Home has a labeled Profile entry. Profile uses the existing library session and a process-wide StoreKit service; no user account, name, email or avatar is invented. The paywall uses semantic lavender surfaces, SF typography, an original SwiftUI paper illustration, scrolling plan cards, a close action and Continue with Free. All copy is in L10n/en/fr/es.

Only configured auto-renewable monthly/yearly products are offered. Prices come from Product.displayPrice; yearly pricing is the full annual charge. A seven-day trial is advertised only for a free introductory offer of exactly seven days/one week and a positive StoreKit eligibility response. Purchasing goes through Product.purchase; opening or dismissing the offer starts nothing. First-welcome presentation is persisted when shown (or eligibility is definitively unavailable), with transient load failures left pending for retry.

The service verifies current entitlements, transactions and renewal information, listens for transaction/status updates, refreshes on activation and periodically, and distinguishes Free, trial, active, canceled with access, expired and billing issue. Access is time-bounded; billing grace uses Apple's grace expiry, while billing retry alone grants none. No persisted isPro flag or production purchase simulation exists. Restore uses AppStore.sync. Manage opens Apple's subscription-management route.

Concurrent refreshes are coalesced with a fresh pass before waiting purchase/restore callers return. Notebook quota decisions and writes are serialized across windows. A verified upgrade resumes previously skipped background OCR.

## Free/Pro boundary

The existing pre-commercial build remains fully usable while ProductIDs is empty. This is not reported as Pro access and cannot charge anyone. Supplying real product IDs activates the Free/Pro checks:

**Boundary approved by the owner on 2026-11-13.** `Sources/PaperNestUI/ProFeature.swift` is the one list of what Pro unlocks; every check is `SubscriptionStore.allows(_:)` / `require(_:)` with a named feature, and the paywall's list is built from the same enum. A refusal opens the paywall with "Included in PaperNest Pro: <feature>" rather than an alert.

- Free: scan, import, the file library and ZIP; crop/rotate/filters; reading (find, select and copy text, links, Go to Page, bookmarks, print, night mode); pen, highlighter and eraser; ordinary PDF/JPEG/PNG export without a watermark; backup; three notebooks. Creating and duplicating notebooks both respect the allowance. Existing notebooks are never removed or made unreadable when the count exceeds three. Duplicating a page inside a document is free (it was gated before 2026-11-13; it is not on the approved Pro list).
- Pro (`ProFeature`): `notebooks` (more than three), `textRecognition` (OCR, including the background sweep), `textExport` (searchable PDF, TXT, DOCX), `passwordExport`, `pageTools` (merge, extract, split), `markup` (shapes, stamps, highlight/underline/strikethrough on text), `signature` (saving and placing), `forms` (saving a filled form). Compress and Redact join the list when their screens exist.
- Ads: the owner decided on 2026-11-13 that the free version will carry ads and Pro will not, then said to leave ads for now. Nothing is built; no ad SDK is in the app.
- Seeing it work before App Store Connect is set up: run the `PaperNest-Subscriptions` scheme from Xcode. It passes `-PaperNestDebugProProducts` (DEBUG builds only), which turns the boundary on against the local StoreKit test products in `Tests/Fixtures/PaperNest.storekit`, so the paywall shows test prices and a test purchase unlocks Pro. Release builds ignore the argument.
- Existing searchable originals and backups remain exportable. Expiration does not strip recognition, destroy annotations, alter originals or delete user content. A premium operation already in flight is allowed to finish.
- Cloud sync is not implemented and is not advertised. The existing brief remains unchanged. Additional future tools require explicit policy mapping before release.

## Required owner/App Store Connect setup — release blocked

Populate `Sources/PaperNestUI/Resources/Subscriptions.plist` with the two real product IDs and published HTTPS PrivacyURL/TermsURL/SupportURL. No dummy legal URLs are shipped. Checkout stays disabled until products and legal links exist. Missing support/legal publication remains a release blocker.

In App Store Connect: create monthly and annual auto-renewable products in one Pro subscription group; set localized names, descriptions, territories and prices; configure a **free, one-week introductory offer** on each intended product; complete agreements/tax/banking and review metadata. Decide whether to enable billing grace. The app cannot configure these account settings. Use the intended production bundle identity rather than assuming the local development identifier is the release identity.

Validate with sandbox accounts and TestFlight: eligible/ineligible purchase, canceled purchase, pending/Ask to Buy, restore on another device, renewals, auto-renew cancellation, trial expiration, billing retry/grace, refunds/revocation and account changes. Local StoreKit fixtures are test-only and do not register products or create a real offer.

## Tests

- `./scripts/test.sh`: regular unit/store/export suite, localization and subscription policy tests.
- `PaperNest-Subscriptions` Xcode scheme: app-hosted StoreKit tests using `Tests/Fixtures/PaperNest.storekit`. The host uses a disposable `/tmp/papernest-subscriptions-host` library. Use the installed iOS 27 runtime with Debug Executable enabled: iOS 26.5 returned SKInternalErrorDomain Code=3, and a non-debug session did not route product loading to the local store. Test fixture prices/IDs/URLs are synthetic and never bundled as production subscription configuration.
- `SubscriptionUITests` in the existing iOS UI target: Home/Profile/paywall dismissal in en/fr/es and Spanish accessibility XXXL. Missing configuration must expose no purchase action.

Final automated verification: 657 unit tests, 2 iPhone and 2 iPad interaction tests, and 3 app-hosted StoreKit tests (billing test covers retry both with and without grace) passed. Mac and iOS builds passed. Actual command outcomes, earlier failures and remaining limitations are recorded in TEST_MATRIX.md. Builds alone do not establish real purchase or restoration success.

## Files in this slice

- New service/views/config: `Sources/PaperNestUI/SubscriptionStore.swift`, `SubscriptionViews.swift`, `Resources/Subscriptions.plist`.
- Navigation/welcome: `LibraryHome.swift`, `RootView.swift`; quota/tool/OCR checks: `LibraryModel.swift`, `NotebookCreationSheet.swift`, `DocumentModel.swift`, `DocumentToolsSheet.swift`, `ExportSheet.swift`, `AppEnvironment.swift`.
- Localization: `Localization.swift` and en/fr/es `Localizable.strings` (distinct Pro/Profile block).
- Tests: `Tests/PaperNestUITests/SubscriptionStateTests.swift`, `Apps/iOS/SubscriptionTests/SubscriptionStoreKitTests.swift`, `Apps/iOS/UITests/SubscriptionUITests.swift`, `Tests/Fixtures/PaperNest.storekit`; hosted target/scheme in `project.yml`.
- Plan, handoff, test matrix and selected screenshots. Earlier dirty files belong to prior work and were preserved.
