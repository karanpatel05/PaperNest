# Brief for Codex

Written by Claude on 2026-10-26 at the owner's request, after the owner set the division of labour:
**Claude is responsible for core logic and the backend; Codex is responsible for design and for testing the whole
app.** This brief says what that means in practice, what is waiting for you, and what I will not touch.

Read `docs/SESSION_HANDOFF.md` first — "Who takes what", then "Current claims", then "Traps found the hard way".
Then `docs/TEST_MATRIX.md`, newest entries at the top. This file does not replace those; it points at what matters
now.

## Your lane

`PaperNestUI`, `Apps/iOS/UITests`, `docs/CLEAN_NATIVE_DESIGN.md`, and the app-level rows of `docs/TEST_MATRIX.md`.

**"Testing the whole app" means the things I cannot do.** Whether a feature works for a person using it: on
iPhone, iPad and native Mac, in English, French and Spanish, with VoiceOver and large Dynamic Type, in dark mode,
on a real device. I write unit and store tests for backend logic because test-first is how that logic gets built;
I do not and cannot verify any of the above.

## 1. The verification backlog — please start here

A large amount of backend now works and has **never been exercised in the running app**. This is the biggest gap
in the project, bigger than any unbuilt feature. Every line below is taken from a "not run / not claimed" note in
TEST_MATRIX, not invented:

- **Real camera capture.** Still blocks the **M1 gate**. Needs a device and a development team; Simulator imports
  do not count. This is the oldest outstanding check in the project.
- **Native Mac interaction for every annotation surface built since 2026-10-23**: text markup, the markup
  manager, notebook creation and page insertion, page comments, outlined shapes, symbol stamps. All of it builds
  and is unit-tested; none of it has been clicked on a Mac.
- **VoiceOver, large Dynamic Type and dark mode.** Unrun across every recent slice.
- **The system custom colour picker** and the shape endpoint sliders — unit-tested values, never driven by hand.
- **Injected I/O-failure UI**: what the user sees when a save fails. Implemented, never observed.
- **A native two-window conflict pass.** Conflict-safe undo/redo is model-tested; no one has watched two windows
  fight over the same page.
- **iPad layout** where the installed runtime previously had no iPad simulator.

When you run these, record the real outcome in TEST_MATRIX even when it is bad — especially when it is bad. The
project rule stands: never mark an unrun check as passed.

## 2. Engine work that is finished and reachable nowhere

Three capabilities work, are unit-tested, and have no screen. Under the new division these are yours to surface.
By the project's own rule, **none should appear in a screen until it really works** — no disabled tiles.

### Compress

```swift
// A document, from its pages:
let before = try await store.originalByteCount(of: item.id)          // Int64
let result = try await exporter.compress(itemName: item.name, pages: pages,
                                         originalByteCount: before, preset: .strong)
// A stored image file, from its bytes:
let result = try await exporter.compress(fileNamed: payload.originalFilename, data: bytes, preset: .strong)
```

`CompressionPreset` is `.light` / `.strong` / `.smallest`. `CompressionResult` gives `originalByteCount`,
`compressedByteCount`, `isSmaller`, `savedByteCount`, `savedFraction` and `output` (an `ExportOutput` whose
`removeTemporaryFiles()` you must call).

**The screen must be built around one fact: a saving is not guaranteed.** `isSmaller` is false and
`savedByteCount` is zero when a source cannot be reduced, and that is a normal outcome, not an error:

- A **page that carries text** cannot be shrunk at all. Rasterizing its text to save bytes would destroy the
  quality and the selectable text, so it is deliberately passed through untouched. This is most of what people
  call a "PDF": every digital one, and every scan an app like Notes or Adobe Scan has put an invisible OCR layer
  on. Expect "no saving possible" to be the usual answer for PDFs, not the exception.
- An **already-compact photo** gets *bigger* when re-encoded, which is the common case since most photos arrive
  compressed.
- A **scanned PDF** — pages that are photographs, with no text of their own — now *does* compress, as a document
  and as a file item (2026-10-27): 193,043 bytes → 111,920 at Strong, 55,115 at Smallest. **Light usually does
  nothing**, because 300 dpi upsamples most scans, so the re-encode is thrown away and the page kept as it was.
  Do not present Light as the gentle saving: on a scan it is normally no saving at all.
- A **password-protected or restricted PDF** is refused with `CompressionError.unsupportedFormat`. Reducing one
  would either return a blank page or strip the author's restrictions. If a Compress action can reach such a file,
  it needs wording that says the file is protected rather than that it is an unsupported type.
- A file that is **neither a re-encodable image nor a readable PDF** throws `CompressionError.unsupportedFormat`,
  having written nothing. That is different from a PDF that simply cannot be made smaller, which comes back with
  real byte counts and `isSmaller == false`.

### Set Password, when a screen for it arrives (engine done 2026-10-27)

`Exporter.export(itemName:pages:options:password:)` writes a PDF that needs the password to open. Three things
about the wording are not negotiable, because they are claims about security:

- It is **AES-128** (standard security handler, revision 4), measured from the written bytes and pinned by a test.
  Say "encrypted with AES-128" or simply "needs this password to open". **Never** "secure", "military-grade",
  "bank-level", or anything implying a weak password is safe — revision 4's key derivation is fast, so a short
  password falls to an offline attack. It is **not** AES-256; Apple's APIs do not expose that.
- The password controls **opening only**. Print and copy permissions are not settable. Do not draw checkboxes for
  them.
- A password is refused for JPEG, PNG, TXT and DOCX with `ExportError.passwordNotSupported`, rather than quietly
  writing an unprotected file. Surface that as "this format cannot be password-protected", not as a generic error.
- **The password must be ASCII**, and this one matters for the French and Spanish builds. Measured, not inferred:
  an export with `"été-Ñandú-2026"` fails to write, even though every character is Latin-1, and PDFKit refuses
  `"contraseña-密码-1"` outright. Anything non-ASCII is refused up front with
  `ExportError.passwordNotRepresentable`. The field needs to say what is allowed *before* someone types a
  password with an accent in it, and the error must explain the restriction rather than reading as a rejection of
  their password.
- **Only the first 32 bytes count.** A 32-character prefix opens a file written with a 44-character password.
  The long password still works, so this is not a failure — but do not imply a longer passphrase is stronger.
- `ExportError.emptyPassword` covers the empty field, which would otherwise be written as a password that opens
  the file with nothing.

The password is a parameter, never part of `ExportOptions`. **Do not put it in anything that gets persisted**, and
do not keep it after the export. There is no password recovery: a lost password means a lost file, and the screen
should say so before writing, not after. Note also that PaperNest cannot *compress* a protected PDF — it refuses
one — so if both actions are offered, the combination needs an explanation rather than a silent failure.

### Compressing to HEIC (engine done 2026-10-27)

`compress(fileNamed:data:preset:format:)` takes a format. **It defaults to JPEG and should stay that way in any
screen.** The same warning as the HEIC export tile applies and matters more here, because compressing is usually
the step right before sending something: offering "smallest" without saying it may not open on the other end
turns a helpful feature into a failed delivery. If both are offered, label them by what they cost, not by size
alone.

A PDF file item ignores the format — HEIC is not a PDF image filter — so do not show the choice for one.

### HEIC export, if a tile for it arrives (engine done 2026-10-27)

`ExportFormat.heic` writes a real HEIC. It is worth offering: on a 1600×2000 page it measured **94,742 bytes
against 284,377 as JPEG** and 209,699 as PNG, at the same quality, keeping the dpi asked for.

The caveat is the whole of the design problem, and it is not a footnote. **Exporting exists to send a file
somewhere**, and HEIC is the format most likely to arrive somewhere that cannot open it — older systems, many
Windows installs, plenty of web upload forms. So:

- **JPEG stays the default.** Do not reorder the tiles to put HEIC first because it is smaller.
- If HEIC is offered, the tile needs a plain line about where it may not open — not a size boast. "Smallest, but
  not every device can open it" is the honest shape.
- Nothing in the app has opened one of these files anywhere but this machine. Until someone has, treat the tile
  as unproven even though the engine is tested.

Everything else is unchanged: it reuses the existing quality slider, `contentType(for:)` resolves `.heic` from
the file extension on its own, and several pages still package as a ZIP.

### Redaction, when a screen for it arrives (engine done 2026-10-27)

Redaction is the one place in this app where a convincing lie is worse than no feature. A black rectangle drawn
over a word, in a PDF, leaves the word underneath — selectable, searchable, recoverable. `PageRedaction` does not
do that: it flattens the page to pixels and paints the region, so the word is not in the bytes.

What a screen has to say, before the user commits:

- **It cannot be undone.** That is the whole point — the engine exists so the original can be deleted. Confirm
  before, not after.
- **The page becomes a picture.** A digital PDF loses its selectable text across the *whole page*, not only the
  redacted part. Searching inside that page stops working. Say so; do not let someone redact a phone number from
  a 40-page contract and quietly lose the text of a page.
- **A shared original may survive.** Two pages of identical paper share one stored file. If another page still
  shows it, the content stays reachable through that page. `isAssetReferenced` answers this *before* you promise
  anything — ask it, and if it says the original is shared, say the content is still in the library and where.
- **Ink, comments and stamps under the rectangle are not touched.** They are separate records. If a note contains
  the thing being redacted, redaction will not remove it.
- **Deleting a file does not scrub the disk.** Never say "securely erased", "wiped" or "unrecoverable". The honest
  claim is that the content is no longer in the document, in the library's text, or in search.

Rectangles are given in upright uncropped source space, like ink and recognised text — not view coordinates.

So: show the measured before and after from the result, never a promised percentage before the work is done, and
say plainly when nothing can be saved. Offering "Compress" and then silently producing a larger file, or claiming
a saving that did not happen, is the one outcome worse than not shipping it.

Two decisions are yours, and neither is made: whether the reduced copy replaces the original, becomes a new
library item, or is only shared; and whether the user picks a preset or a target size. Originals are immutable, so
"replace" means writing a new asset and repointing the item — tell me if you want that and I will build it.

### Export as text

`ExportFormat.txt` already works through the existing `export(itemName:pages:options:)` call. The sheet's format
tiles are written one per format, so TXT needs a tile of its own. `ExportOptions`' paper, resolution and quality
do not apply to it.

`ExportError.noTextToExport` needs a message: a document with no text on any page is **refused** rather than
exported as an empty file. Text comes from recognition first, then from the text a digital PDF already carries;
pages are separated by a form feed. Known limitation to word carefully if you surface it: embedded PDF text is
stored normalized for the search index, so such a page exports as one paragraph rather than its original lines.

### Export as a Word file

`ExportFormat.docx` works through the same `export(itemName:pages:options:)` call as TXT, and needs a tile of its
own for the same reason. Same text sources, same `noTextToExport` refusal.

**The check only you can do: open one.** I verified the package is well-formed — `unzip` lists and extracts
`[Content_Types].xml`, `_rels/.rels` and `word/document.xml`, and `XMLParser` parses each one — but that proves it
is valid OOXML, **not** that a word processor renders it. Export a document and open the result in Pages, Word and
Google Docs, including one with accents and one whose recognized text contains an ampersand. Until that passes,
please do not add the tile: an export that produces a file the user cannot open is worse than no export. It is
"basic" by design — the words in paragraphs with page breaks, no tables, columns, styles or images — so judge it
against that, not against a laid-out document.

### Recognition status, and a language override

The remaining F4 items, both UI-led. Recognition now happens automatically in the background, so the status
surface has real state to show rather than a spinner over nothing.

**One real bug in your file, worth fixing while you are there:** `DocumentModel.recognizeText(on:)` calls the
blocking `TextRecognizer.recognize(_:)` on the MainActor, so manual recognition stalls the UI for as long as
Vision takes. Use `recognizeOnADedicatedThread(_:)` instead. It cannot deadlock the way my first version did, but
it is a visible hitch. Read the Vision trap in SESSION_HANDOFF before touching anything that recognizes.

## 2b. First run, free tier and the paywall — handed to you by the owner

The owner asked for the first-run and subscription screens on 2026-10-26 and has handed the design to you.
I mocked four screens so there is something concrete to argue with, and the owner has the canvas. **Treat the
mockup as a proposal; the constraints below are not mine, they are the project's, and they are the part that
matters.**

The four screens: first launch (empty library), reaching a Pro feature, the paywall, and Settings → Subscription.

**Two structural arguments, which you are free to overturn:**

- **Do not open with a paywall.** A scanner that asks for money before anything has been scanned gets deleted,
  and the reference app's own paywall is dismissible. The first screen's only job is to get one document in.
- **Let the paywall be reached, not pushed.** It appears when someone taps a Pro feature on a page they already
  scanned, so they know what they are buying. The second mockup shows that moment.

**Non-negotiable, from `CLAUDE.md` and the capability inventory — not stylistic preferences:**

- **Prices come from StoreKit. Never hard-code one.** The reference app's $9.99 is its price and explicitly not a
  decision for PaperNest. Every price in the mockup is a placeholder for that reason.
- **A trial reminder on the screen is a promise to schedule one.** The inventory is blunt: it needs a real local
  notification, or the screen must not claim it. The timeline mockup shows a Day-N reminder step — if nobody
  builds the notification, that step comes off.
- **Restore must really restore**, and PaperNest has no account, so restore is the *only* way a subscription
  follows someone to a new device. It belongs on the paywall **and** in Settings.
- **Documents stay readable and exportable after a subscription lapses.** Already a stated rule. Say it on the
  paywall rather than burying it; it is the most trust-building sentence available.
- **No fake purchase flow and no mock entitlement state, ever.** No `isPro` flag is authoritative; entitlement
  comes from `Transaction.currentEntitlements`.
- The reference screenshots are a competitor's copyrighted material: take the *pattern* if it is good, never the
  copy, the claims or the look. Its "50+ premium actions" and audio editing are not things this app does.

**Three decisions are the owner's and nothing can be built until they are made:** the price and billing period,
the trial length and whether there is a reminder, and the free/paid split. My proposal for the split — free keeps
the core promise whole (scan, keep, organise, export a PDF, three notebooks), Pro is the work you do on documents
(recognition and search inside pages, markup, merge/split/extract, unlimited notebooks) — is a starting point, not
an answer.

**And the hard blocker: M5 is unstarted and needs an Apple Developer team before any StoreKit product exists.**
These are screens to decide against, not screens anyone can wire up yet. A paywall shipped today would also be
selling compression and text export, which work but have no UI.

## 3. Your own queue continues

Unchanged, from "Next for Codex": word-level selection, text and custom-image stamps, exported and positioned
comment annotations, notebook planners and navigation, visual fill & sign, then app lock. Private comments,
outlined shapes, symbol stamps, whole-line marks, preset and custom colours and saved-ink management are done.

## 4. Rules I will hold you to, because they are the project's

- **Never `git add -A`.** Stage by explicit path, only paths you wrote. A plain `git commit` will also commit
  whatever I have staged. Commit only when the owner asks.
- **Claim files in "Current claims" before editing, and release them when done.** I check that list and the index
  before every slice. On 2026-10-26 one of your commits swept part of my handoff text in; no harm done, but it is
  how `5abebea` happened.
- **Record real outcomes in TEST_MATRIX.** Never mark an unrun check as passed. Say what you did not run.
- **A tool appears in a screen only when it works.** No greyed-out marketing tiles.
- **Every user-visible string through `L10n`** with en/fr/es keys, added in the same change as the code using it.
  Never a string literal to `Text`. French and Spanish truncate in pop-up menus — iOS forms use inline rows.
- Warning-free builds, Swift 6 strict concurrency.

## 5. What I will not touch

`PaperNestUI` views, `Apps/iOS/UITests`, `Localization.swift`, the three `Localizable.strings`, and
`docs/CLEAN_NATIVE_DESIGN.md`. If a backend slice needs a thin layer on your side, I will say so in Current claims
and describe it rather than build it.

I will keep writing backend logic with its unit and store tests, and I will keep naming in TEST_MATRIX exactly
what I could not verify — that list is your work queue, and I will try to make it precise rather than vague.

## 6. What neither of us can fix

The repository has **no git remote**. Twenty-plus commits, including everything both of us did today, exist only
on this machine, in a `.git` that iCloud syncs while two agents write to it. That needs the owner's account. It is
worth raising with them again.
