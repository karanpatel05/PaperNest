# Word-level text boxes — Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** Row 20 lists *word-level selection* as remaining. Markup works on whole recognised lines, so highlighting one word highlights the sentence it sits in. Recognition is the reason: a `RecognizedLine` carries one box for the whole line and nothing smaller.

## Verified before designing
Vision was asked directly, on a synthetic page reading `Invoice total 1234 EUR`:

```
line                      x=0.080 w=0.412
  word "Invoice"          x=0.080 w=0.129
  word "total"            x=0.213 w=0.087
  word "1234"             x=0.305 w=0.096
  word "EUR"              x=0.405 w=0.087
```

`VNRecognizedText.boundingBox(for:)` gives real per-word boxes: ordered left to right, not overlapping, and the last word ends exactly at the line's right edge (0.405 + 0.087 = 0.492 = 0.080 + 0.412). That is what makes this worth building rather than approximating by splitting the line box on character counts, which would drift on any proportional font.

## Constraints and review focus
- **Existing recognition results have no words, and that must not look like "no text".** Results already stored were written before this field existed. `RecognizedLine` decodes a missing `words` as empty, a test pins it with real old-shape JSON, and anything consuming them falls back to the line. Nothing is recomputed behind the user's back and no migration is needed — recognition is JSON in `page_recognition`.
- **The existing initialiser keeps working.** `RecognizedLine(text:box:confidence:)` is used across the suite and in production; `words` is added with a default rather than forcing every call site to change.
- **A word Vision cannot box is dropped, not faked.** `boundingBox(for:)` can return nothing for a range; inventing a box from the line would put a highlight over the wrong ink. So `words` may hold fewer entries than the line has words, and that is stated rather than smoothed over.
- **Same coordinate rule as everything else.** Vision's origin is bottom-left and ours is top-left; word boxes get the same flip the line box already gets, in upright uncropped source space.
- Recognition still runs through `recognizeOnADedicatedThread`. The Vision deadlock trap in SESSION_HANDOFF is not re-litigated here.
- No UI. Selecting a word is the screen owner's work; this gives it something to select.

## Task 1 — carry the words
- [x] Failing tests: a recognised line reports its words in reading order; each word's box sits inside the line's box and the words do not overlap; the words' text matches the line's.
- [x] `RecognizedWord`, `RecognizedLine.words`, and the recogniser filling them.

## Task 2 — do not break what is stored
- [x] Failing tests: recognition JSON written before this change decodes with no words rather than failing; a result round-trips through the store keeping its words.
- [x] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, the `PaperNestUI` iOS Simulator build.
- [x] Record in TEST_MATRIX, update row 20, release the claim, commit.

## Execution ledger
- Baseline: 433 tests passing, 0 warnings, Mac and iOS builds clean, committed as `61d51dd`.

## Outcome
438 tests, 0 warnings, Mac and iOS builds clean. Two things decided the shape: the probe, which showed Vision's boxes are exact enough to be worth using, and the stored-results question, which ruled out changing the model in a way that would have made every existing recognition fail to decode.
