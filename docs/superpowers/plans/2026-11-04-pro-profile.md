# PaperNest Pro and Profile implementation plan

Goal: Implement the owner’s specified calm paywall/Profile in the existing app.
Architecture: One process-wide observable StoreKit service verifies transactions and renewal status, with no persisted access flag. Configured product IDs and genuine legal/support URLs are release inputs. Profile presents status, dates, restore/manage and existing Settings. Native paper illustration and semantic lavender cards reuse Theme.

- [x] Implement verified entitlement/status reduction, product loading, exact seven-day eligibility, purchase/restore/update handling and expiry refresh.
- [x] Build localized adaptive paywall/Profile and Home navigation. Welcome completion presents the offer once; dismissal never starts a trial.
- [x] Add StoreKit configuration and purchase-state tests plus separate UI navigation tests.
- [x] Build Mac/iOS, run tests, record outcomes and external setup.

No account creation, fake sync benefits, simulated production purchases, or user-content deletion. Existing basic functionality must remain available when subscriptions cannot be configured. Missing legal URLs block checkout. The full premium tool boundary must be audited before commercial release; no blanket lockout of existing content.

Verification: 657 unit tests; 2 iPhone and 2 iPad interaction tests; 3 hosted StoreKit tests including both retry/grace cases; Mac and iOS builds passed. Release remains blocked on genuine product/legal configuration and sandbox/TestFlight, configured-paywall interaction, Mac interaction and VoiceOver checks. See TEST_MATRIX.md for failed early attempts and exact outcomes.
