# Claude Code implementation prompt: Apple scanner and notebook app

Copy the prompt below into Claude Code, or place this file in your project root and ask Claude Code to read it and start implementing. The working product name is a placeholder, not a cleared brand name. Prices are proposed launch settings, not established market facts. No production app has been built by this document.

---

You are my senior Apple-platform engineer and product implementation partner. Build a native document scanner and notebook application for iPhone, iPad and Mac. Take the work from repository inspection through working, tested implementation. Do not stop at a plan or generate a collection of disconnected screens.

## 1. Product brief and fixed requirements

Working name: PaperNest. Keep branding centralized so it can be renamed before release. Use original branding, assets and interface design. Adobe Scan, CamScanner and Goodnotes are feature references, not code, branding or interface templates to copy.

Initial markets: United States and Canada. Worldwide distribution is a later business decision. All three platforms and all three interface languages are part of the intended first public release:

- iOS on iPhone.
- iPadOS with Apple Pencil support on compatible devices.
- A genuine macOS application with desktop interactions.
- English, French and Spanish throughout the user experience.
- Optional iCloud sync across the user's devices, with local/offline operation.
- One Pro subscription covering all three platform versions.
- Document scanning, PDF tools, basic editable notebooks and multi-format export.

Primary workflow: scan paper on iPhone, organize and annotate it on iPad, then edit typed content, organize and export on Mac. Users can mix scanned pages, imported PDFs, handwriting, typed notes and images in a notebook. Preserve an editable original; export only creates a separate representation.

Optimize for scan quality, reliable storage, responsive writing, simple navigation and honest behavior. Full feature parity with Adobe, CamScanner or Goodnotes is not the launch requirement.

## 2. Working rules

1. Inspect the repository, README, CLAUDE.md, applicable project instructions and git status before editing. Preserve unrelated changes. Never reset or overwrite user work to simplify implementation.
2. Determine whether this is an existing app or an empty repository. Extend an existing architecture where reasonable. If empty, create a reproducible Xcode project and shared Swift modules.
3. Check the host OS, installed Xcode/Swift versions, available SDKs and simulators. Use a stable toolchain. Choose minimum deployment versions based on required APIs and document the tradeoff; do not assume the latest OS is required everywhere.
4. Consult current official Apple documentation for API availability, CloudKit, subscriptions and platform-specific behavior. Do not invent APIs. Verify availability separately on iOS, iPadOS, native macOS and Mac Catalyst as relevant.
5. Make reasonable reversible engineering decisions without repeatedly asking me. Ask only when credentials, ownership, irreversible actions or a material product ambiguity genuinely block progress.
6. Do not buy services, upload private documents, deploy a backend, submit an app or publish a release without explicit authorization. Do not bypass permissions or access controls.
7. Work in buildable milestones. Fix compilation failures introduced by your changes before adding unrelated features. Run appropriate tests and retain the actual commands and outcomes.
8. If the environment cannot run Xcode or lacks signing/cloud configuration, continue with work that can be done honestly. Distinguish implemented code, simulator-verified behavior, device-verified behavior and blocked integrations. Never report unrun tests as passed.
9. Use mocks only in previews and tests, clearly isolated from production. No fake sync indicators, simulated payment success, fabricated OCR output or decorative controls that do nothing.
10. Keep a living implementation checklist and handoff notes so later Claude Code sessions can resume accurately. Do not promise a fixed completion date before inspecting the work.

## 3. Repository deliverables

Create or update these documents, using the repository's existing conventions where appropriate:

- README.md: setup, dependencies, project generation if any, build/test commands, signing placeholders and supported platforms.
- CLAUDE.md: concise project-specific conventions and verification commands; preserve existing instructions.
- docs/PRODUCT_SPEC.md: behavior and free/Pro boundaries.
- docs/ARCHITECTURE.md: modules, data model, rendering, sync and decisions.
- docs/IMPLEMENTATION_PLAN.md: milestones with acceptance gates and current status.
- docs/TEST_MATRIX.md: automated and manual verification results.
- docs/APPLE_SETUP.md: exact manual developer-account, entitlements, CloudKit and StoreKit setup still required.
- docs/RELEASE_CHECKLIST.md: remaining release work, known limitations and review preparation.
- docs/SESSION_HANDOFF.md: completed work, blockers, next commands and next milestone.

Provide an Xcode project or a documented, reproducible generation workflow, shared schemes, localized resources, meaningful tests and synthetic sample documents. Keep generated caches and credentials out of source control. Do not create pretend privacy-policy URLs or production product IDs.

## 4. Architecture

Prefer Swift and SwiftUI with shared business logic and separate platform adapters. Use UIKit or AppKit bridges where required. Keep modules focused rather than creating excessive abstraction.

Suggested boundaries:

- Domain: document, page, notebook, folder, annotation and revision models.
- Persistence: metadata database, asset storage, migrations and recovery.
- Capture: mobile camera capture and Mac document import/Continuity Camera.
- Imaging/OCR: image adjustments, recognition and text indexing.
- Notebook: canvas, text objects, page templates and editing commands.
- Export: PDF, image, TXT and basic DOCX writers.
- Sync: CloudKit integration, queueing, conflicts and account changes.
- Billing: StoreKit products, verified entitlements and purchase UI.
- App UI: shared views plus native phone, tablet and desktop behavior.

Use Apple frameworks where suitable: VisionKit, Vision, Core Image, PDFKit, PencilKit and StoreKit. Verify each framework's capabilities rather than assuming that choosing it implements a complete feature. In particular, PDFKit is not a general PDF-to-Word converter, and a drawing canvas is not handwriting recognition.

Choose one coherent persistence/sync design and document why. Evaluate local Core Data or another suitable metadata store plus managed asset files, with a CloudKit private database for synchronization. If using CKSyncEngine, verify deployment support and implement its state persistence and error handling. If using automatic Core Data/SwiftData cloud mirroring, explicitly demonstrate how assets, edit history and conflicts remain consistent. Do not casually mix multiple owners of sync state.

Use background tasks and cancellable operations for OCR, image work, exports and sync. Avoid loading an entire large notebook into memory. Bound concurrency and use caches with eviction.

## 5. Document model and editable originals

Design a versioned model before building many screens. At minimum represent:

- Library item: stable ID, document/notebook type, name, parent folder, tags, favorite state, dates, schema version and deletion state.
- Page: stable ID, stable ordering information, dimensions, background type and content references.
- Original asset: imported image or PDF content, immutable identifier, checksum and local availability state.
- Page transformations: crop, orientation, filters and revision history, without repeatedly destroying the original.
- Ink: editable stroke data with color, width and coordinate system.
- Text and image objects: editable contents, style, position and bounds.
- Recognition: text, detected language, bounding regions, source revision and recognition version/status.
- Sync metadata: server identity, revisions, queued operations, errors and deletion tombstones.

Persist semantic edits and originals. Generate thumbnails and export PDFs as derived assets. Invalidate OCR/indexes when source content changes. Define page coordinates and transforms consistently so ink, text and OCR remain aligned after zooming, rotation and export.

Save atomically. Recover safely from interrupted writes. A user edit must not appear saved until it is durably stored locally. If a document has only a thumbnail downloaded, do not present it as fully available offline.

## 6. Scanning and import

On iPhone and iPad:

- Use a supported document-capture API for automatic/manual capture, edge detection, perspective correction and multi-page sessions.
- Provide clear camera permission handling, retry/cancel flows and import alternatives.
- Let users crop, rotate, reorder, remove and rescan pages.
- Provide original/color, grayscale and black-and-white output, plus appropriate brightness/contrast adjustments.
- Keep originals so users can revise processing later.
- Detect unsupported devices and present an honest fallback.

On Mac:

- Support Finder drag-and-drop, file picker import, paste where appropriate, and Continuity Camera document import when supported.
- Do not assume the iPhone document camera controller works on native macOS.
- A webcam is not required for version one. The Mac app must remain useful without an iPhone nearby.

Import PDFs, JPEGs and PNGs initially. Preserve PDF content rather than needlessly rasterizing every page. Handle corrupt files, password-protected PDFs, canceled imports, unsupported files and duplicate filenames. Ask for a password only where the selected API supports opening the protected document; do not attempt to bypass protection.

Support US Letter, A4 and original-size export. Never silently crop page content to fit a paper size.

## 7. Basic notebooks

Implement:

- Blank, lined and grid pages.
- Mixed notebooks containing note pages, scans and imported PDF pages.
- Pen, highlighter, eraser, supported ink selection/move operations, undo and redo.
- Typed text boxes and inserted images.
- Add, duplicate, delete and reorder pages.
- Smooth zoom/pan and correct distinction between drawing and navigation gestures.
- Apple Pencil drawing on compatible iPads; appropriate touch alternatives.
- Mac viewing, typed-note editing and document organization; supported mouse/trackpad annotation controls without promising an identical Pencil experience.
- Autosave with visible recovery errors.

Retain editable ink and objects through save, reopen and sync. Export appearance must match the editor. Where a PencilKit feature is unavailable on a target, use a supported adapter or clearly scope the limitation; do not pretend a raster image is editable ink.

Deferred features, unless explicitly requested later: real-time co-editing, audio recording synchronized to ink, advanced handwriting conversion, math recognition, infinite whiteboards, AI chat, transcription, flashcards and a template marketplace. Plan extensibility without implementing placeholders in the shipping navigation.

## 8. OCR, search and language support

Provide printed-text OCR for English, French and Spanish using verified supported recognition languages. Support automatic language detection where available and a user override. Test accents, punctuation, numbers and mixed-language documents. Preserve Unicode and provide a preview/correction path for exported text.

Search document titles, folder/tag metadata, typed notes and recognized printed text. Show page-level results and helpful snippets. Clearly distinguish recognition pending, completed and failed states. Do not call handwriting searchable unless a real recognition path has been implemented and tested.

Keep OCR local by default. Any future cloud recognition service requires explicit product approval, cost review and user consent before transmitting document contents.

Use String Catalogs or the current supported localization mechanism. No hardcoded user-visible English in production screens. Localize onboarding, errors, paywalls, accessibility labels, permission descriptions where supported, export options and help. Use locale-aware dates, numbers and StoreKit-supplied price formatting. Test long French strings and Spanish accents. Avoid truncation and concatenated translated fragments. Document any translation that needs human review.

## 9. Export requirements

Export is non-destructive. Users choose format, page range, relevant options and destination. Provide progress/cancel, sensible filenames, output-size information when feasible and clear errors. Use system sharing/save panels with platform-appropriate behavior.

### PDF

- Render selected pages in correct order with scans, PDF content, ink, typed text and images.
- Offer appearance-preserving export and a searchable option with aligned recognized text where supported.
- Ensure searchable text is not visibly drawn twice and remains aligned with rotated/cropped pages.
- Preserve existing selectable PDF text where possible; do not unnecessarily re-OCR it.
- Offer reasonable compression/quality choices. Never promise a target size that cannot be achieved without unacceptable quality loss.
- Distinguish app-editable originals from exported annotation behavior; do not advertise all PDF annotations as editable in every external reader.

### JPEG and PNG

- Export each selected page as an image.
- For multiple pages, allow separate files or a ZIP with deterministic numbered filenames.
- Provide JPEG quality and output-size/resolution controls where practical.
- Flatten to an appropriate background for JPEG; do not accidentally lose black ink on transparent pages.

### TXT

- Export typed text and recognized printed text as UTF-8.
- Provide page separators and document-order output.
- Explain that images, layout and unrecognized handwriting are excluded.
- If the selected pages contain only unrecognized ink or images, warn clearly rather than silently producing an empty or fabricated text file.

### Word (.docx), basic scope

- Create a valid Office Open XML package, using a vetted compatible library or a small well-tested writer.
- Export recognized/typed text as editable paragraphs, with basic headings/formatting where justified by source data, and insert selected images with appropriate page breaks.
- Provide two clearly named options: editable-text export with approximate layout, and appearance-preserving page images embedded in DOCX. Do not label the image option as editable OCR conversion.
- Keep handwriting as an image unless genuine handwriting recognition is implemented. Never fabricate transcription.
- Preserve French/Spanish characters, escape XML correctly, handle empty pages and mixed text/image content.
- Never rename HTML, RTF, TXT or PDF to .docx. Validate package relationships and open representative exports in Word or another compatible editor when available; record if that visual check is blocked.
- Defer faithful reconstruction of arbitrary tables, columns, equations and complex layouts. State the limitation in the export UI and docs.

## 10. iCloud synchronization

Include sync in the first-public-release architecture, not as a last-minute retrofit. Use the user's private iCloud database/account context; do not create a separate username/password system just to sync.

Sync originals and editable content needed to reconstruct documents, along with folders, ordering, names, favorites, text objects and ink. Derived caches may be regenerated. Ensure assets and metadata references become usable consistently even when they arrive in different orders.

Required behavior:

- Local edits work offline and queue for retry.
- Sync is eventual; never promise instantaneous cross-device delivery.
- Show accurate local/sync/download/error states driven by real state.
- Persist the operation queue and sync engine state across restarts.
- Respect service retry/backoff instructions, quota limits and connectivity constraints.
- Use stable IDs and idempotent operations to avoid duplicates after retries.
- Resolve independent changes where safe. Preserve a conflict copy when concurrent edits cannot safely merge, especially same-page ink or text changes. Do not silently choose the latest entire document and discard another device's edits.
- Implement Recently Deleted with a documented retention policy, tombstones and recovery; prevent an offline device from resurrecting intentionally deleted content unintentionally.
- Handle iCloud sign-out, account switching, disabled iCloud, unavailable assets and full storage without deleting the only local copy or uploading the previous account's documents to a new account automatically.
- Before account changes or disabling sync affect files, present clear choices and preserve access to existing local documents.
- Explain that private CloudKit storage uses the user's iCloud allowance. Do not advertise unlimited included cloud storage.
- Treat sync and backup as different capabilities. Support export/recovery and do not call synchronization a complete backup strategy.

Test with at least two devices or supported test environments using the same iCloud account before calling sync verified. Document development/production container setup and schema deployment; never deploy production schema changes without authorization.

## 11. Subscription and feature access

Use StoreKit with one Pro entitlement and monthly/annual products in one subscription group. Configure a universal purchase arrangement across platform versions where supported. Verify signed transactions and handle transaction updates, pending purchases, user cancellation, restoration, renewal, expiration, refunds, revocation and billing grace states correctly.

Do not store a user-editable isPro flag as the authority. StoreKit purchase identity is distinct from the iCloud document account; account mismatch must not leak documents or incorrectly transfer a purchase.

Proposed launch pricing, configurable in App Store Connect rather than hardcoded checkout strings:

- US monthly: $3.99; annual: $24.99.
- Canada monthly: CA$5.49; annual: CA$34.99.
- Optional introductory first annual term: US$19.99 / CA$26.99, then regular annual renewal.

These are configuration proposals. Verify available offer mechanisms and eligibility, and display only offers actually returned/configured for the customer. Do not invent discounts, fake crossed-out prices, trial eligibility or availability. No lifetime or weekly plan at launch.

Free: unlimited basic local scans, crop/rotate/basic filters, ordinary PDF/JPEG/PNG sharing without watermarks, all interface languages, and a small notebook allowance (use three as a configurable initial product assumption).

Pro: batch OCR, searchable PDFs, text extraction/TXT export, basic DOCX export, advanced PDF tools, unlimited notebooks, additional annotation tools and iCloud sync. Define the exact tool boundary consistently across platforms. A limited feature preview may use synthetic samples or an explicitly configured entitlement, never unverified payment simulation.

On expiration, preserve documents and permit viewing and ordinary export of existing content. Stop new premium operations as appropriate, but do not delete work or trap files. Provide a recovery/download route for existing remote documents even when premium sync is no longer active.

Provide Restore Purchases and Manage Subscription. Localize the paywall and show renewal price, term, offer conditions and links to genuine support/privacy/terms pages before release. If URLs are not supplied, mark release as blocked rather than shipping dummy links.

Use local StoreKit tests and sandbox/TestFlight verification before release. A billing service/backend is not required solely to show a paywall; introduce a server or third-party billing service only with a documented need. Any later paid server-side AI must verify entitlement on the server as well.

## 12. UX and platform polish

Phone: recent documents, search, folders and a prominent capture action; readable page-editing and export flows.

iPad: adaptive sidebar, large editor, page thumbnails, keyboard shortcuts, drag/drop and Pencil-appropriate controls.

Mac: native menus, keyboard shortcuts, file imports, resizable/multiple windows where practical, sidebar navigation and save dialogs. Verify Mac editing behavior rather than just stretching the mobile layout.

All: dark/light appearance, VoiceOver, accessible contrast, scalable text where appropriate, keyboard focus, empty/loading/error states and undo for destructive editing. Onboarding should explain scanning, notes and optional sync without requiring account creation or payment before a basic scan.

Do not expose architecture jargon in customer-facing screens. Do not show unfinished features as working buttons. Keep all user documents exportable. Provide a private feedback channel separately from public reviews. Never offer free usage, discounts or functionality in exchange for an App Store rating/review, and never gate public review prompts by sentiment.

## 13. Privacy and diagnostics

Default to local document processing. No advertising SDK or behavioral tracking in the first implementation. Never log document text, page images, handwriting, payment information or account identifiers in analytics/crash breadcrumbs. Use synthetic documents for tests and screenshots.

Assess platform file protection, sandbox permissions, temporary export cleanup and secret handling. Do not claim end-to-end encryption unless the actual implementation and account requirements have been verified. Do not assume Face ID UI alone encrypts files.

Prepare accurate privacy declarations, required API reasons/manifests where applicable, permission descriptions and a list of third-party dependencies/licenses. Draft documentation can be prepared locally, but do not claim legal compliance or publish policies on my behalf.

## 14. Milestones and acceptance gates

### M0 — Inspect, decide and create the foundation

Inspect the environment/repo, record architecture decisions, create project targets/modules and a localized adaptive shell. Build every supported target that the environment can build. Establish a persistence round-trip test and reproducible build instructions.

### M1 — Local scan/import to export

Implement capture/import, persistent document library, page editing and PDF/image exports. Gate: a real scan can be saved, the app restarted, and the document reopened/exported without losing pages or orientation. Test Mac file import separately from mobile camera capture. Do not call simulator image imports a real-camera test.

### M2 — Cross-device proof

Implement enough real CloudKit sync to prove document creation, rename, download, offline edits and conflict preservation across devices. Gate: a scan created on iPhone appears correctly on another device, survives relaunch, and conflicting edits are preserved. Credentials can block live validation but not justify fake success.

### M3 — Editable notebooks

Add ink, text, templates, mixed pages and PDF annotation. Extend sync to the editable model. Gate: save/reopen/sync/export retains stroke appearance, positioning, page order and text edits across supported platforms.

### M4 — OCR and remaining exports

Add recognition/search and UTF-8 TXT plus valid basic DOCX. Gate: representative English, French and Spanish fixtures produce correct readable output with documented limitations; PDF selectable text alignment and DOCX structure are verified.

### M5 — Subscriptions and access rules

Implement configured products, purchase/restore, transaction verification and expiration/revocation flows. Gate: sandbox or local StoreKit scenarios show correct entitlement behavior and existing documents remain readable/exportable after expiry. Explicitly separate local test results from live App Store verification.

### M6 — Release hardening

Finish localization/accessibility, large-document performance work, storage pressure and recovery tests, privacy configuration and release docs. Prepare an archive/TestFlight checklist; actual upload/publication requires authorization.

Keep the repository usable between milestones. Continue to the next authorized milestone when the current gate is met; do not seek approval for every routine step. If a session ends, leave exact next actions and a truthful status table.

## 15. Verification matrix

Write meaningful tests around data integrity and business behavior, not tests that merely mirror constants. Include:

- Persistence and migrations; interrupted save recovery.
- Page order and coordinates after crop/rotate/zoom, rendering and export.
- OCR fixtures with accents, mixed languages, low contrast and blank pages.
- PDF pages, text selection/alignment, image quality and export cancellation.
- DOCX ZIP/XML structure, media relationships, Unicode and external-reader opening.
- Sync retries, duplicate events, missing assets, conflicting edits, deletion/restore, account changes and storage-quota failures.
- Subscription verification, pending/canceled transactions, renewal/expiry, refund/revocation, restore and appropriate offline access behavior.
- English/French/Spanish layouts, VoiceOver and relevant keyboard/Pencil interactions.
- Representative 1-, 20- and 100-page documents: record device, elapsed time, responsiveness and peak memory where measurable. Do not invent benchmarks or universal performance guarantees.

Maintain a manual checklist for physical camera capture, Apple Pencil feel, two-device iCloud behavior, native Mac UI and export opening in external apps. Automated unit tests do not substitute for these checks.

## 16. Required reporting

After each substantial milestone, report:

1. What changed and the user workflow now supported.
2. Files/modules affected.
3. Actual build/test commands and outcomes.
4. What is implemented but not verified, plus why.
5. Remaining risks, manual Apple setup and the next milestone.

Use status labels such as Implemented, Automated tests passed, Simulator verified, Device verified, and Blocked. Do not call the app production-ready while signing, real sync, subscription restoration or export integrity remain untested.

## 17. Start now

Inspect this repository and toolchain. Summarize the key findings briefly, choose and document the storage/sync and platform strategy, and start implementing M0 and the first working slice of M1. Use placeholder bundle identifiers only in clearly marked configuration if my Apple Developer team is unavailable. Do not ask me to choose colors, folder names or routine architecture details before making progress. Do not stop after generating the plan.

If there is already implementation, determine the actual milestone status from code and tests rather than restarting. Continue from the first incomplete acceptance gate.

### Official references to verify during implementation

- Apple VisionKit: https://developer.apple.com/documentation/visionkit
- Apple Vision: https://developer.apple.com/documentation/vision
- Apple PencilKit: https://developer.apple.com/documentation/pencilkit
- Apple PDFKit: https://developer.apple.com/documentation/pdfkit
- Apple CloudKit: https://developer.apple.com/documentation/cloudkit
- Apple StoreKit: https://developer.apple.com/documentation/storekit
- Universal purchase: https://developer.apple.com/help/glossary/universal-purchase
- App Review Guidelines: https://developer.apple.com/app-store/review/guidelines/
- Xcode command-line tools: https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference

---

## Optional continuation instruction for a later Claude Code session

Read CLAUDE.md, docs/SESSION_HANDOFF.md, docs/IMPLEMENTATION_PLAN.md and this specification. Inspect git status and recent changes. Verify the current build before editing. Continue from the first incomplete milestone without overwriting unrelated work. Update the checklist with actual test evidence and leave a precise handoff at the end.
