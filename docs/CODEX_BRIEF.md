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

- A **vector PDF** cannot be shrunk at all. Rasterizing its text to save bytes would destroy the quality and the
  selectable text, so it is deliberately passed through untouched.
- An **already-compact photo** gets *bigger* when re-encoded, which is the common case since most photos arrive
  compressed.
- A **PDF file item** is refused for the same reason as a vector document. A non-image file throws
  `CompressionError.unsupportedFormat`.

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
