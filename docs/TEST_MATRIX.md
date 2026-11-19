## 2026-11-19 — Presentation mode's pen pointer: draw on the page shown, never saved (Claude)

Owner: "Extend presentation". Of the extensions — Mac, presenter controls on an external display, the sample's pen pointer — the pen is the one that can be verified here (Mac interaction is blocked; the Simulator's external displays cannot be driven from the tests). The ⋯ menu now chooses the pointer: **No Pointer, Laser Pointer or Pen**. With the pen, a drag draws red strokes on the page shown (`PenSketch`, shares of the page; a tap that never moved leaves nothing); they stay until the page turns or **Clear Drawing**; swipes draw instead of turning pages, and ‹ › and the keys still turn them. Nothing drawn reaches the document.

| Check | Result |
|---|---|
| New `PenSketchTests` (3, Core) | **Pass.** A drag is a stroke and a tap is nothing; points held to the page; clearing empties it; the three pointers. |
| New `PresentationUITests.testThePenDrawsOnThePageAndNothingIsSaved` | **iPhone 17 pass (35.1 s), iPad Air 13 pass (39.3 s)**: two drags are two strokes and the page stays; Clear Drawing appears with a drawing, empties it and goes; a new stroke, then › to page 2, and the drawing is gone; after Exit **no page of the document has any ink** (read back from the library). |
| `testPresentingInFrenchAndSpanish` (now also: with a pen drawing, Exit, Clear Drawing and ⋯ all reachable and on screen; fr and es, at default and AX XXXL) | **iPhone pass (122.6 s), iPad pass (134.2 s).** **First run: passed but the screenshot showed French XXXL broken** — "Effacer le dessin" wrapped a few letters a line into a tall pill over the page and Exit and ⋯ were pushed out of sight. Clear Drawing is now an eraser icon like ⋯ (its VoiceOver label is the words) and Exit stays on one line. Screenshot looked at after: eraser, "Quitter", ⋯ along the top, the stroke on the page. |
| `testPresentingTurnsPagesPointsAndEndsWhereItStopped` (laser now chosen in the menu), `testAKeyboardTurnsPages` | **iPhone and iPad pass.** |
| `./scripts/test.sh`, git-free copy | **1,596 tests, 0 failures, 0 warnings.** `build-mac-app.sh`: built, no warnings. |
| Environment | The first iPad run never started: `simctl bootstatus` hung 69 minutes on a simulator already reporting Booted, then the app would not launch ("Host is down"); after restarting the simulator the run above passed. |

**Not verified:** VoiceOver itself; a real device. **Not started:** Mac; presenter controls on an external display; speaker notes. Escape still does not end a presentation in the Simulator (unchanged).

## 2026-11-19 — Presentation mode: a document full screen, a page at a time, with a laser pointer (Claude, roadmap P2 #15)

Owner: "Go ahead with the next feature". The owner's queue (watermark, scanner feedback and book mode, forms/signatures/passwords, the scanner's UI verification) is done; in the roadmap's next tiers the rest is built, blocked (XLSX needs table detection; review links need the real sync gate) or deferred until approved (handwriting conversion, audio, assistant), which leaves presentation mode. On **iPhone and iPad**: Present, in the document's title menu, shows the page being read full screen on black, as in sample §13. A tap shows the controls (Exit, ⋯ with the laser pointer, ‹ ›, the page dots or "n / N"); pages turn by swiping, ‹ ›, the arrow keys, space and Page Up/Down, and VoiceOver's adjustable action; closing leaves the reader on the page last shown. The laser pointer draws a fading red dot only on screen (never ink, never saved), and while on, swipes point instead of turning. The screen does not sleep while presenting; status bar and home indicator hidden. Pages drawn as Print draws them (comments never render); only the page shown and the next.

| Check | Result |
|---|---|
| New `PresentationTests` (5, Core: `PresentationDeck`, `LaserTrail`) | **Pass.** Starts on the page being read (held to the document); steps and stops at both ends; a one-page document goes nowhere; the trail fades (half-faded at half its life, gone after 0.6 s; times passed in); old points dropped, at most 64 kept. The first run failed at an exact floating-point boundary (10.9 − 10.3 just under 0.6); the check moved off the edge. |
| New `PresentationUITests.testPresentingTurnsPagesPointsAndEndsWhereItStopped` | **iPhone 17 pass (54.1 s), iPad Air 13 pass (59.9 s)**: Present from the title menu on page 1; controls hidden until a tap; the document's bars not reachable; ‹ off on the first page; › to 2, a swipe to 3, › off and a swipe kept on the last; **laser on: a swipe stays on page 3; laser off: a swipe turns to 2**; Exit, and the reader is on page 2; **then a finger stroke on the page is saved** (the presentation took the keyboard from the canvas behind). |
| New `PresentationUITests.testAKeyboardTurnsPages` | **iPhone pass (31.0 s), iPad pass (31.5 s)**: → to 2, space to 3, ← to 2. |
| New `PresentationUITests.testPresentingInFrenchAndSpanish` (fr, es, and es at AX XXXL) | **iPhone pass (64.8 s), iPad pass (70.4 s)**: "Présenter" / "Presentar" in the title menu; Exit reads "Quitter" / "Salir", Exit and › reachable and on screen. Screenshots looked at: the page full screen, no bars; controls in English; Spanish XXXL — "Salir", ⋯, ‹ › and the dots fit. |
| **Failures found and fixed on the way** | (1) No `presentation.page` at all: an identifier on the whole presentation replaced its children's. (2) The ⋯ menu never opened: a tap gesture over the controls caught its tap; taps and swipes now belong to the backdrop and the page. (3) **iPad keyboard**: with SwiftUI focus and key presses, keys turned pages in 4 of 7 iPad runs — in the failures none did (the document's drawing canvas kept the first responder); a resign-first-responder and a later refocus did not settle it. Now a UIKit view that becomes the first responder reads the presses: **3 of 3 iPad runs, then the final run**. (4) The first drawing check failed on the test's own steps: a finger draws only once finger drawing is on (Display settings), as `NightModeUITests` does. |
| **Escape** | **Not working in the Simulator tests**: `typeKey(.escape)` never ended the presentation, with SwiftUI key handling, a keyboard shortcut, or the UIKit view (cause not established; the press may never reach the app). Exit and VoiceOver's escape are the ways out; Escape is not claimed. |
| `./scripts/test.sh`, git-free copy | **1,593 tests, 0 failures, 0 warnings.** An earlier full run had `InlineTextSessionTests.concurrentFlushWaitersPersistLatestDraftAsOneObject` fail once under load; alone, 12 of 12 pass. `build-mac-app.sh`: built, no warnings (presentation is iOS-only, compiled out). `build-for-testing` (iOS): no warnings. |

**Not verified:** VoiceOver itself (labels and the adjustable action asserted by XCUITest only); a real device or an external display. **Not started:** Mac; presenter controls on an external display; the pen pointer and speaker notes of the sample. **Note:** the laser pointer is seen by an audience only through screen mirroring.

## 2026-11-19 — The after-capture note no longer covers the page at the largest text sizes on a phone (Claude)

Owner: "Yes, fix it". The gap found in the entry below: on iPhone at AX XXXL the note covered nearly all of the ~120 pt page preview. Now, at the accessibility text sizes in compact width, `ScanQualityNote` is a mark of a fixed size (44 pt) under the page that opens the note in a dark sheet (each issue on its own line, Done); VoiceOver reads the whole note from the mark's label. The ordinary sizes and iPad keep the note under the page. `ScannerWorkspaceView.swift` untouched.

| Check | Result |
|---|---|
| `ScannerLargeTextUITests` (now: on a phone the mark is at most 60 × 60 pt, says the whole note, opens it in full, and closes) | **iPhone 17 pass (83.0 s), iPad Air 13 pass (54.1 s)**, en/fr/es. **A popover was tried first: the test passed but the screenshot showed the note clipped top and bottom and drawn light on light** — replaced by the sheet. Screenshots looked at (iPhone es and fr): the page visible with the mark on it; the sheet dark, "Demasiado oscuro" / "Reflejo en la página" and "Identique à la page 1" whole, "Listo" / "Terminé". |
| `ScanQualityUITests`, `ScanRepeatUITests` (ordinary size), iPhone 17 | **Pass** (69.6 s, 49.6 s, 16.8 s). |
| `./scripts/test.sh`, git-free copy | **1,588 tests, 0 failures, 0 warnings.** `build-for-testing` (iOS): no warnings. |

**Not verified:** VoiceOver itself (the mark's label is asserted by XCUITest only).

## 2026-11-19 — UI verification: this session's scanner surfaces at the largest text size, and Book's one-page fallbacks (Claude, owner's queue item 4)

Owner: "Move on" (to the remaining UI verification). Scoped to what no one else is checking — the after-capture notes, the repeat note and Book mode, added this session — at Accessibility XXXL in en/fr/es, and Book's failure states. Codex's active claim (the export sheet) left alone. Mac interaction stays blocked (screen access declined); VoiceOver is not claimed (labels are asserted by XCUITest only); dark mode does not apply (the scanner's chrome is fixed dark).

| Check | Result |
|---|---|
| New `ScannerLargeTextUITests.testTheAdviceNotesAtTheLargestTextSize` (AX XXXL; a retake and a dark page with a reflection) | **iPhone 17 pass (46.6 s), iPad Air 13 pass (47.6 s)**, en/fr/es: the filmstrip labels name the repeat and both issues; the notes say all of "Same as page 1" and "Too dark · Glare on the page" (fr "Trop sombre · Reflet sur la page", es "Demasiado oscuro · Reflejo en la página") and sit within the screen side to side. Screenshots looked at: **iPad fr** — the note on one line under the page, the page visible. **iPhone es and fr — layout gap:** the text is complete (Spanish wraps to three lines), but at this size the review screen leaves the page preview about 120 pt tall, and **the note covers nearly all of it, zoom controls included**. Not fixed here: the review layout is the design lane's; options are a row of its own for the note outside the preview, or a capped type size for it. |
| New `BookCaptureUITests.testAnUprightPageInBookModeStaysOnePage` | **iPhone pass (17.6 s), iPad pass (18.0 s)**: one upright page captured in Book mode is not offered as two and is kept as one. |
| New `BookCaptureUITests.testABookPhotoWithNoOutlineStaysOnePage` | **iPhone pass (17.8 s), iPad pass (18.4 s)**: a photo with no outline in it keeps the whole frame, one page. |
| New `BookCaptureUITests.testABookCaptureAtTheLargestTextSize` (fr, es) | **iPhone pass (51.9 s), iPad pass (47.3 s)**: Book reached in the strip, the capture shown as "Deux pages" / "Dos páginas", kept as two. The first iPhone run failed on the test's own swipe — the chip it swiped on moved off with the one-mode-per-swipe strip; it now drags along the strip. Screenshots looked at: iPhone fr, Livre chosen at the strip's end; iPhone es, three pages in review, the preview small. |
| `BookCaptureUITests` (existing two), iPhone rerun | **Pass** (26.0 s, 26.1 s). |

**Not verified:** VoiceOver itself, Mac, a real camera. **Open:** the iPhone XXXL note covering the page preview (above).

## 2026-11-18 — Book mode follow-up: its "Move closer" can be said; repeats rechecked in the app (Claude)

A review of `d244a1b`: Book's ready size (25% of the frame) had not been measured against what the detector finds, as every other mode's has (`ScanDetection.readyArea`). Two cases added to `ScanFeedbackDetectionTests`, on drawn spreads through the real detector and the guide: **a spread covering 18% of the frame is found and told "Move closer"**; one filling the frame is told "Hold steady". **Pass** (8 in the suite). And since the copy rule changed (same bytes **and** crop), the app-level repeat checks were rerun on **iPhone 17: `ScanRepeatUITests` both pass** (49.8 s, 15.5 s; the byte copy still shows no note), **`ScanQualityUITests` pass** (65.3 s). Test-only; no product change.

## 2026-11-18 — Book mode: an open book captured once becomes its two pages (Claude, roadmap order item 2)

Owner: "Go ahead with book mode". Book is a fifth capture mode ("Book" / "Livre" / "Libro", last in the pill). It finds the whole two-page spread and, when the outline is plainly wider than tall, shows the capture with its fold marked ("Two pages" to VoiceOver); Keep makes it two ordinary pages, left then right, each the same photo cropped to its half. **No curvature flattening** (the paper's curve near the fold stays), no curvature guides; pages from Photos or Files are not split.

| Check | Result |
|---|---|
| Probe first, through the real rectangle detector (drawn spreads on a dark table) | Whole spread found in 16 of 18 cases — fold shadow, dark fold line, a curl toward the fold of 2% and (landscape) 4%, corners within 2.3%. A 4% curl in a portrait photo found either the spread with corners about 9% off, or (dark fold line) only one page. So **a capture is split only when the found outline is plainly wider than tall** (`ScanSpread.isSpread`, ≥ 1.1 in the photo's pixels): a shorter-over-longer ratio cannot tell an A5 page from an A5 spread (both 0.707). |
| New `ScanSpreadTests` (5, Core) | **Pass.** The straightened outline's corners map to the outline's; a rectangle splits halfway; **on a spread seen at an angle the fold falls where the outline's diagonals cross** (checked independently), not halfway along the edges; wide outline a spread, upright page and square outline not; a fold near an edge is held in to 10–90%. |
| New `ScanBookTests` (8 tests, 10 cases, Render; real detector) | **Pass.** Fold shadow at 0.45 and 0.55 found within 0.01; a dark fold line at 0.52 found; no fold → exactly halfway; a dark picture beside the fold (a quarter of the height) does not pull the split, with or without a fold. The whole spread found for no fold, shadow and line, flat and curled, landscape and portrait photos; an upright page in Book mode found and not a spread; the strongly curled case that finds one page is not split; **photo to two pages**: a spread at an angle, found, straightened with Core Image as a crop is, its fold found and the split line landing within 2% of the fold as drawn. |
| Mutations (each restored) | The column mean instead of its 70th percentile → the fold-line, picture and no-fold tests fail. No dip required → the picture and no-fold tests fail. |
| **Repeats: a book's two pages share one photo** — new `ScanQualityMemoTests.aRetakenSpreadsRightPageNamesTheFirstRightPage`, **written first** | **Failed before the fix** (a retaken spread's right page was silenced as a "copy" of its own left page, same bytes), **pass after**: a copy made on purpose is now the same bytes **and** the same crop. All 28 canvas tests pass. |
| Codex's scanner tests with a fifth chip | **First run: `testSpanishLargestTextScanSettingsRemainDismissible` failed** ("es mode whiteboard must be reachable"). Reproduced in a probe: at XXXL the first drag flung the strip to its far end, Whiteboard at x = −234, and the test only drags one way. **Fix:** the strip moves one mode per swipe (`scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))`, iOS 18+; snapping to edges on 17). After: **iPhone 17 pass** — whiteboard (37.2 s), card (44.2 s), scan settings (97.0 s), French XXXL (36.3 s), Spanish XXXL (33.3 s); **iPad Air 13 pass** — French XXXL (34.4 s), Spanish XXXL (32.3 s). |
| Settings tests | `ScanSettingsTests` and `ScanSettingsStoreTests` used `"book"` as the example of a mode from another version; it now is one (they use `"hologram"`, and `"book"` is checked to read as Book). |
| New `BookCaptureUITests` (real capture path: debug camera photo, shutter, Keep) | **iPhone 17 pass (32.9 s), iPad Air 13 pass (33.1 s)**: Book chosen, the capture's preview value "Two pages…", Keep → three pages (one seeded + two), the two cropped to 10–50% and 50–90% across, 18–84% down (±3). The first run failed only on its own check (the preview's value also carries its zoom). `testBookIsOfferedInFrenchAndSpanish`: **iPhone pass (26.9 s)**. Screenshots looked at: the spread with its fold marked before Keep; page 2 the left page with the fold's shadow at its edge; the Spanish pill with all five chips, Libro chosen. |
| `./scripts/test.sh`, git-free copy | **1,586 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 281 + 269 + 302). `build-mac-app.sh`: built, no warnings. `build-for-testing` (iOS): no warnings. |

**Not verified:** a real camera or real book; VoiceOver itself; the pill at XXXL in the screenshot (asserted by Codex's tests only). **Design mismatches:** the sample puts Book first in the pill (it is last, so the existing chips stay put); no curvature correction or guides yet.

## 2026-11-18 — Of two photographs of one page, the one worth deleting is marked (Claude)

Owner: "Yes, fix the mark". The first version always marked the **later** page "Same as page N" — so after the natural fix for a blurred capture, taking it again, the good retake carried the mark, inviting its deletion. Now `ScanQualityMemo.repeated` marks the page worth deleting: the one with something wrong with it (any issue its mode lets be said) when only one of the two has; otherwise the later, the extra copy. A byte-for-byte copy still says nothing.

| Check | Result |
|---|---|
| New `ScanQualityMemoTests` cases (3, iOS, `PaperNest-Canvas`) — **written first** | `theBlurredPageOfARepeatIsMarkedNotItsSharpRetake` **failed before the fix** (the blur was found and the pages matched, but the mark was on the retake) and **passes after**; `aBlurredRetakeOfAGoodPageIsMarked` and `ofTwoGoodPhotographsTheLaterIsMarked` (with a third, different page named by no one) pass before and after. All 27 canvas tests pass. |
| New `ScanRepeatUITests.testTheBlurredPageIsMarkedNotItsSharpRetake` (en) | **iPhone 17 pass (28.4 s), iPad Air 13 pass (17.3 s)**: a blurred page and its sharp retake; page 1 reads "Looks blurry · Same as page 2" in its label and note, page 2 has nothing. |
| `ScanRepeatUITests.testASecondPhotographOfAPageIsNamedAsItsRepeat`, `ScanQualityUITests` (unchanged) | **iPad Air 13:** repeat test **pass (60.0 s)**. **iPhone 17:** the first run never started (the test runner failed to launch: Mach error -308, "server died", right after the previous session was cut off mid-run); after rebooting the simulator, `ScanQualityUITests` **passed (47.4 s)**, and the repeat test passed its English checks, then the runner exited unexpectedly while tapping page 4 and was restarted, counted as a failure (cause not established); **rerun alone, it passed (66.4 s)**, at a machine load of about 90. |
| `xcodebuild build-for-testing` (iOS), git-free copy | **Succeeded, no compiler warnings.** |
| `./scripts/test.sh`, git-free copy | **1,573 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 273 + 269 + 297). |

**Not verified:** a real camera; VoiceOver itself. **Known limit:** when both photographs have something wrong (or neither), the later is marked whichever is worse.

## 2026-11-18 — Glare follow-up: white printed on tinted paper is not glare (Claude)

A review of `d7da368` asked what tells a reflection from white print. Probed: a pure-white box printed on 0.85 paper (0.8–3.8% of the page, sharp or softened by 2 px) **was called glare** — so would a form's white box on tinted stock or a white panel on a card. Now a blown-out patch must also have a **halo**: a tenth or more of the pixels within two cells of it lie between the paper and white. A reflection is light added and falls off gradually; white print has a sharp edge.

| Check | Result |
|---|---|
| Probe (Render, drawn) | Halo of reflections 0.19 (the UI test's straight-line fall-off) to 0.94 (a flash on dark paper); of white boxes 0.008–0.021, sharp or softened. Line at 0.1. |
| New `ScanQualityAnalyzerTests.whitePrintedOnTintedPaperIsNotGlare` (2 cases, sharp and softened) | **Pass**; the reflection, glint, specks, bright-page, resolution and dark-flash tests still pass (17 in the suite). **Mutation:** without the halo rule, both box cases fail. |
| `./scripts/test.sh`, git-free copy | **1,573 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 273 + 269 + 297). |
| `xcodebuild build-for-testing` (iOS) | **Succeeded, no compiler warnings.** |
| `ScanQualityUITests` (now also shows the glare note and screenshots it) | **iPhone 17 pass (59.3 s)**; **iPad Air 13 failed once** — after tapping the blurred page, its note did not appear within 10 s, though its label already named the blur (cause not established; the 1-minute load had been 64 shortly before) — **and passed on rerun (70.5 s)**. Screenshot looked at (iPhone, es): "Reflejo en la página" whole under the page, the reflection visible. |
| `ScanRepeatUITests`, `ScannerWorkspaceUITests.testCardModeAsksForTheBackAndNamesBothSides` on iPhone 17 | **Pass** (48.8 s, 43.5 s). The card test's fixture is a 0.9 grey card on 0.25: nothing blows out. |

**Not looked at:** the combined note ("Too dark · Glare on the page") at iPhone width in French and Spanish — no UI test draws a dark page with a reflection. **Known limit (unchanged):** glare is said only when the page's typical paper is at most 0.9, so on white paper a phone exposes brightly, glare may go unsaid.

## 2026-11-18 — Glare on a captured page is named in the scanner (Claude, roadmap order item 2)

Owner: "Yes, glare next". A page with a reflection on it gets the corner mark, "Glare on the page" / "Reflet sur la page" / "Reflejo en la página" in its filmstrip label (for VoiceOver) and in the note under it. Advice only. Said for documents, boards and cards (a laminated card is where glare is likeliest), not for photos. **Measured on drawn reflections, not a camera.**

How (`ScanQualityAnalyzer.glare`): cells of 16 pixels at the measuring size (about 5 mm on A4); a cell is blown out when half its pixels are at 250 of 255 or more; glare is the share of the page in the **largest** patch of blown-out cells, counted only when the page's typical paper is at most 0.9 (so it stands out). 0.5% of the page or more is said, after darkness and before focus.

| Check | Result |
|---|---|
| `ScanQualityReportTests` (+1 test, +4 checks, Core) | **Pass.** Glare at 2% is said and at 0.4% is not; it comes after darkness and before focus and angle; a card keeps it, a photo does not. |
| `ScanQualityAnalyzerTests` (+6, Render, drawn reflections: light added as a Gaussian, washing paper and ink alike) | **Pass.** A reflection: 1.6% of the page, glare and nothing else. A glint: 0.1%, nothing. Paper exposed to white all over: 0, with or without a reflection on it. Hundreds of white specks: largest patch 0.03%, no glare. 1,500 vs 3,000 pixels: 1.58% both. A flash on dark paper: too dark and glare (1.2%) — a weaker reflection first drawn blew out only 0.13% of dark paper, which has further to go to white; the test now draws a flash-like one. |
| Mutations (each restored) | Without the stand-out rule → the page exposed to white all over is called glare. All blown-out cells instead of the largest patch → the specks are called glare. |
| `./scripts/test.sh`, git-free copy | **1,572 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 272 + 269 + 297). `./scripts/build-mac-app.sh`: built, no warnings. |
| `xcodebuild build-for-testing` (iOS), git-free copy | **Succeeded, no compiler warnings.** |
| `ScanQualityUITests.testBlurredDarkAndReflectedPagesAreNamedForWhatIsWrong` (renamed; a fourth page with a reflection added in UIKit with `plusLighter`) | **iPhone 17 pass (53.2 s), iPad Air 13 pass (74.5 s)**, en/fr/es: the reflected page's label names glare and not blur; the sharp page names nothing. Capture-screen screenshot looked at: the reflected page, latest, shows its white patch with the mark at the top-left and the count at the top-right. |
| `ScanRepeatUITests` (unchanged) | **iPhone 17 pass (48.4 s), iPad Air 13 pass (75.5 s).** |

**Not verified:** a real camera, real glossy paper or laminate; VoiceOver itself; Mac (the scanner is iOS-only). **Known limits:** a reflection on paper already nearly white all over (typical paper above 0.9) is not found; by the same rule, a page lit so unevenly that one side blows out would be called glare (not tested). Low contrast and book mode are still not started.

## 2026-11-18 — Repeats follow-up: the scanner's memo keeps only the scan in progress (Claude)

A review of `f67252f` found that `ScanQualityMemo.shared` lives as long as the app and never forgot: every capture was compared (about 80 ms a pair in a debug build) with every page measured since launch, and memory grew with each. Now `measure(_:among:)` takes the scan's pages, compares with those only, and forgets every other page and pair (an earlier scan's, a deleted page, an old crop). `ScannerThumbnail`'s `pages` is required, so no caller can empty the memo by leaving it out. The pending capture is drawn from its own preview, not through the memo.

| Check | Result |
|---|---|
| New `ScanQualityMemoTests` (2, iOS, `PaperNest-Canvas` scheme) — **written first** | **Failed before the fix** (an earlier scan's two pages and their pair still kept; a deleted page still kept), **pass after**. All 24 canvas tests pass. |
| `./scripts/test.sh`, git-free copy | **1,565 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 266 + 269 + 296); the Import target takes about 35 s. The repeat tests now make fingerprints only, without the quality measures they do not need. |
| **Correction to the entry below** | Its "1,566 tests" and "about 160 s" counted a calibration probe left behind in the verification copy (never in the repository). The slice itself was 1,565 tests, with the Import target at about 35 s. |
| `xcodebuild build-for-testing` (iOS) | **Succeeded, no compiler warnings.** |
| `ScanRepeatUITests`, `ScanQualityUITests` on iPhone 17 | **Pass** (48.9 s, 50.1 s). Not rerun on iPad after this change. |

## 2026-11-18 — A page photographed twice is named "Same as page N" in the scanner (Claude, roadmap order item 2)

Owner: "Yes, duplicates next". After each capture, a page that is a second photograph of an earlier page in the same scan gets the corner mark, "Same as page N" in its filmstrip label (for VoiceOver) and in the note under the page, in en/fr/es. Advice only: nothing is deleted or held back. **Measured on drawn pages, not a camera.**

How: each page's `ScanFingerprint` (Core) is its grey picture at 160 × 208 with each row's own level taken away — where words begin and end along each line — and `ScanLikeness` compares two at one shared shift, lets 16 tiles slide 2 more pixels each, and takes the lower quartile of the tiles' matches; 0.6 or more either way round is the same page. A page byte-for-byte equal to an earlier one (Duplicate, one file brought in twice) is a copy on purpose and says nothing — which also keeps `ScannerWorkspaceUITests`' card labels unchanged. Comparisons run off the main thread in `ScanQualityMemo`.

| Check | Result |
|---|---|
| New `ScanLikenessTests` (4, Core, pictures built pixel by pixel) | **Pass.** A page is its own repeat slid 3 × 2 pixels; other words on the same rows are not (< 0.4); a slide beyond the reach is not found (a missed repeat); blank pages are never repeats; another shape gives 0. |
| New `ScanRepeatTests` (7 tests, 14 cases, Render, drawn print) — calibrated by probing first | **Pass.** Second photographs: mild (1% across, 0.8% down, 1% larger, 0.4°, dimmer, softer, grainier) 0.91 either way; harsh (3%, 2%, 3% larger, 1.2°, dim, soft, grainy) **0.67** — nearer the 0.6 line. Different print set exactly the same way, as drawn or photographed differently: **< 0.3 either way** (0.16 measured on full pages, 0.18 on short ones); the same words in other type or spacing: not the same; a page printed in only a few tiles is not judged; a blank page repeats nothing; another shape is not the same page. |
| **Design changes the probes forced** | (1) Every tile sliding freely with a fixed floor for which tiles count: different pages read up to **0.64**, and a dim retake had too few tiles left to judge. Now one shared shift, ±2 per tile, and tiles count by a share of the richest tile. (2) **Short pages**: with print only near the top, different print read up to 0.53 (median, 4 tiles). Now the lower quartile and at least 6 tiles; a page printed down only about a third of its height is not judged (its own retake is then missed too: the price). (3) A comparison took 1.7 s in a debug build; with Accelerate for row sums and a running-sum table, about 80 ms. |
| Mutations (each restored) | Median instead of lower quartile → short-page test fails (0.41). Tiles sliding freely → short-page test fails (0.36). Four tiles enough → short-page test fails. Fixed tile floor → retake and different-print tests fail. Level from a square instead of the row → different-print, short-page and reach tests fail. |
| `./scripts/test.sh`, git-free copy | **1,566 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 267 + 269 + 296) — one of them a calibration probe left in the verification copy, never in the repository, which also made the Import target take about 160 s (see the follow-up above: 1,565 tests, about 35 s). `./scripts/build-mac-app.sh`: built, no warnings. |
| `xcodebuild build-for-testing` (iOS), git-free copy | **Succeeded, no compiler warnings.** |
| New `ScanRepeatUITests.testASecondPhotographOfAPageIsNamedAsItsRepeat` | **iPhone 17 pass (49.1 s), iPad Air 13 pass (60.1 s)**, en/fr/es: of a page, its second photograph (shifted 12 × 9 points, 1% larger, 0.4°, dimmer), another page set the same way and a byte copy of the first, only the second photograph's label says "Same as page 1" / "Identique à la page 1" / "Igual que la página 1", with the note over it; the copy has none. Screenshots looked at (iPhone fr, iPad es): mark on page 2 only, note under the page. |
| `ScanQualityUITests` (changed) | **iPhone 17 pass (50.7 s), iPad Air 13 pass (76.6 s)**. **The first run with repeats failed, rightly**: its blurred page was the sharp page drawn again and blurred, and was named "Same as page 1"; it now has its own words. |
| `ScannerWorkspaceUITests.testCardModeAsksForTheBackAndNamesBothSides` (Codex's, unchanged) | **iPhone 17 pass (43.0 s)** — its exact labels ("Review scan 2, Front") still hold: its captures are byte copies of one fixture. |

**Not verified:** a real camera (the likeness is from drawn pages); VoiceOver itself; Mac (the scanner is iOS-only). **Known limits:** a page whose outline was not found keeps the whole frame, so if it sits elsewhere in the second photograph it is not found; a page printed in fewer than six tiles is not judged; retakes turned or scaled more than the harsh case may be missed. Glare, low contrast and book mode are still not started.

## 2026-11-18 — Scan quality follow-up: what is said depends on the capture mode; the capture screen's mark looked at (Claude)

A review of `e9cf4ce` found that the checks were tuned on paper but ran in every capture mode. A drawn black card with one line of white print, cropped to the card, measures **too dark**: its own colour, not the light. Now `ScanQualityReport.issues(in:)` decides what may be said for the page's `ScannerPage.mode` (set from the mode at the shutter in `appendCapture`): **Photo says nothing** (kept as taken, perhaps dark or soft on purpose), **Card never says too dark**, Document and Whiteboard say everything; pages from Photos or Files count as documents.

| Check | Result |
|---|---|
| New `ScanQualityReportTests.whatIsSaidDependsOnWhatWasPhotographed`, `ScanQualityAnalyzerTests.aBlackCardIsNotCalledTooDarkAsACard` | **Pass.** The first card drawn, dense with white print, was not "too dark" at all (the paper level fell on the print); redrawn as a card is, one line of print on black: too dark by the measure, nothing said as a card or a photo. |
| `./scripts/test.sh`, git-free copy | **1,554 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 259 + 269 + 292). |
| `xcodebuild build-for-testing` (iOS), git-free copy | **Succeeded, no compiler warnings.** |
| `ScanQualityUITests` on iPhone 17 | **Pass (51.3 s)**, en/fr/es as before, and now (en) back to the capture screen with a screenshot of the review stack, looked at: the mark at the top-left of the latest (dark) page, the count at its top-right, neither covering the other. That button's VoiceOver label stays "Review scan" and the count — the issue is not spoken there; the filmstrip page's label carries it. Not rerun on iPad after this change. |

**Not verified:** the mode reaching a page through a real camera capture (`appendCapture` passes it; compiled, not exercised — the Simulator has no camera, and seeded pages are documents).

## 2026-11-18 — Scan quality after capture: blurry, steep angle, too dark (Claude, roadmap order item 2)

Owner: "Go ahead with the next feature". Item 2 is scanner feedback and book mode; the live labels (Move closer, Hold steady, Improve lighting, Ready, Move back) already existed (2026-11-16). This slice adds what can be measured honestly **after** a capture. Advice only: a page is never refused or held back. **Thresholds come from drawn pages, not a camera.**

What it does: `ScanQualityAnalyzer` (Render) measures each captured page as cropped and before any look; `ScanQualityReport` (Core) decides. A page that looks blurry, was taken at a steep angle or is too dark gets a corner mark on its scanner thumbnail (the filmstrip and the capture screen's review stack), its filmstrip label names the issues for VoiceOver ("Review scan 2, Looks blurry"), and a note under the page being reviewed says them in words. Strings in en/fr/es.

| Check | Result |
|---|---|
| New `ScanQualityReportTests` (8, Core) | **Pass.** Issues and their order; a dark page is not also called blurry; nothing measured says nothing; stretch 1 square-on, 0.65/0.4 for a steep outline; **sides measured in the photo's pixels, not in shares** (an outline giving 1.83 in pixels and 1.94 in shares); outlines that are not outlines give none. |
| New `ScanQualityAnalyzerTests` (9 tests, 15 cases, Render) — calibrated by probing first | **Pass.** Sharp or 1-px-soft print at three sizes with grain is not blurry (≥ 0.34); 3.5-px blur is blurry at every size (0.10–0.17); **print blurred in linear light until faint is still blurry**; the same page at 1,500 and 3,000 pixels reads the same (0.482 vs 0.489; 0.096 vs 0.096); a blank sheet unevenly lit is not judged; a dark page is too dark and nothing else; a page 80% covered in black print is not dark; a steep outline is steep, the whole frame is not, no photo size no verdict; the photo's size is read with its EXIF orientation. |
| **Two real flaws found by the UI test and fixed** | The first iPhone run **failed**: the dark page was flagged, the blurred one was not. Probing on the Mac: (1) Core Image blurs in linear light, so thin print went faint, and the blank-page rule (paper minus darkest 1% of the *whole page* under 0.15) took it for a blank sheet; now marks are measured against **their own surroundings** (under 0.025: blank). (2) Past a point, heavier blur read *sharper* (0.36 → 0.65): the one-shade steps of a grey picture were all the edges left. Sharpness now compares the page blurred by 1 px with a further pixel of spread (variances add), instead of the raw picture. Tried and dropped: a 1→2 px comparison (small print blurred into stripes read 0.39) and ignoring one-shade steps (two-shade rounding steps then read 1.0). |
| Mutations (each restored) | Blank-page rule removed → blank-sheet test fails. Whole-page rule back → faint-print test fails. Pre-blur removed → blurred-page test fails (2 sizes). No downsampling → the sharp and soft tests fail (all 3 sizes). Mean instead of paper level → dense-page test fails. |
| `./scripts/test.sh`, git-free copy | **1,552 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 258 + 269 + 291). `./scripts/build-mac-app.sh`: built, no warnings. |
| `xcodebuild build-for-testing` (iOS, PaperNest-iOS, which builds `PaperNestUI` for the Simulator), git-free copy | **Succeeded, no compiler warnings**, after each change. |
| New `ScanQualityUITests.testABlurredAndADarkPageAreNamedForWhatIsWrong` | **iPhone 17 pass (55.7 s)**, **iPad Air 13 pass (154.6 s)**, en/fr/es: of a sharp, a blurred (Core Image, 8 px) and a dark page seeded with `-PaperNestDebugScannerImages`, the blurred page's label says "Looks blurry" / "Semble flou" / "Parece borroso", the dark one's "Too dark" / "Trop sombre" / "Demasiado oscuro" and not blurry, the sharp one's neither; the note appears over the blurred page and goes for the sharp one. Screenshots looked at (`/tmp/pn-scan-quality-shots`, iPhone fr/es, iPad fr): marks on pages 2 and 3; the note first collided with the zoom controls at the top of the preview and was moved under the page; on iPad it sits under the page above the presets. |

**Not verified:** a real camera (Simulator only; the thresholds are from drawn pages), VoiceOver itself (labels asserted by XCUITest only), Dynamic Type at the largest sizes, Mac (the scanner is iOS-only). **Steep angle is unit-tested only**: seeded pages have no detected corners. **Not started, with reasons:** glare (needs a highlight measure that tells glare from white paper; not built), low contrast (indistinguishable from a blank page by these measures), duplicate captures (possible with `GrayPicture.fingerprint`, a slice of its own), book mode (page-curvature correction is a separate geometry problem; nothing built). `docs/CLAUDE_CODE_STATUS.md` (untracked, not mine) still says scan-quality feedback remains.

## 2026-11-18 — Forms, signatures and passwords verified end to end: a password keeps an unchanged form fillable, and the export sheet says when fields survive (Claude, roadmap order item 3)

Owner: "Go ahead with forms, signatures and password verification". Mostly verification, reading the written files back; two real gaps found and fixed.

**Fixed: a password cost a form its fields.** An unchanged fillable PDF exported with a password came out encrypted but no longer fillable — pinned by `askingForAPasswordStillCostsTheForm` as "you cannot have both today". A probe showed why: the rebuild copies pages into a new PDF, which keeps the widget boxes and loses the `AcroForm`; writing **the source document itself** with the password keeps every field and a filled answer. `Exporter.writeProtectedCopy` now does that when the export is the unchanged original (every page untouched, all in order, original paper, no mark), the source has no author limits and is not already encrypted. Everything else is as before (byte-for-byte copy without a password; rebuild otherwise).

**Fixed: nothing said when a form would be flattened** (roadmap item 2, "clearly explain when an edited page must be flattened"). `Exporter.formFieldFate(of:options:password:)` answers, by the writer's own rules (`isUntouched`, `wholeSourceAsset`, author limits, encrypted source, password), whether the chosen pages' fields will be kept; the export sheet shows "This form's fillable fields are kept…" or "…won't be kept: its pages are redrawn…" under the PDF settings, recomputed as the paper, watermark, PaperNest mark, pages or password change.

| Check | Result |
|---|---|
| New `ProtectedFormExportTests` (7) — **written first: the two form tests failed** ("fields lost") | After: **pass**. Unchanged form + password: AES, locked, refused with "", a near miss and a wrong password, opened by the password, **both fields still fields**, two widgets; a filled answer survives and stays editable; links survive; **an owner-password source that allows everything is rebuilt, still AES under the asked-for password**; some pages (rebuild, untouched pages put back): AES, password, the link; every page redrawn (the drawing context's own encryption): AES, password; without a password the unchanged form is the same bytes. The three password paths each keep an AES/unlock/wrong-password check. |
| Mutations | New path removed → both form tests fail; the caller's already-encrypted guard removed → the owner-password test fails (the writer's own guard then refuses). Restored, all pass. |
| New `FormFieldFateTests` (5) — what the sheet says vs. the real export | **Pass.** For unchanged, unchanged + password, A4, a watermark, the PaperNest mark, JPEG, ink drawn on, the same page twice, a restricted form without and with a password, and a PDF with no form: the predicate's answer matches the field count read back from the exported file every time. |
| New `SignedExportTests` (3) | **Pass.** A filled, signed form exports flat (no fields), "Ana Ruiz" in the page text, the signature where it was placed and nowhere else, and **the original's bytes unchanged and still hashing to its name**; a signed copy under a password is AES, refused with a wrong password, and shows the signature once unlocked; **on a cropped, quarter-turned page the signature lands in the corner it was placed in, not the opposite one** (mutation: placement without `pageToSource` → that test fails). |
| Existing tests changed | `askingForAPasswordStillCostsTheForm` and `WholeSourceCopyTests.aPasswordRulesOutACopy` removed (their claim is no longer true; the password is now the caller's decision, and the fields' survival is tested above); `wholeSourceAsset` lost its password argument. `BulkExportTests.cancellingKeepsTheLibraryIdle…` failed once in a full run: it counted **every** export folder in the shared temporary folder, and export tests in other targets write there at the same time; it now counts only folders that appeared during its own export and hold its archive. |
| `./scripts/test.sh`, git-free copy (`8268e25` + this slice) | **1,535 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 249 + 269 + 283). An earlier full run in the worktree had the bulk-export failure above. |
| `./scripts/build-mac-app.sh`; `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`; `build-for-testing` (iOS) | All succeeded, no compiler warnings. |
| New `ExportPasswordUITests.testAPasswordTheWriterCannotStoreIsRefusedAndAGoodOneExports` | **iPhone 17 pass (72.5 s), iPad Air 13 pass (126.9 s)**, en/fr/es: "été2026" refused with Copy off, "correct-horse" accepted, the protected Copy completes. XCUITest cannot read the copied file; what it asks for is proved by the engine and `ExportPasswordWorkflowTests`. |
| New `ExportPasswordUITests.testAFormSaysWhetherItsFieldsStayFillable` | **iPhone 17 pass (329.3 s, load ~38–57)**, **iPad Air 13 pass (157.1 s)**. The note reads "kept" for the unchanged form, still "kept" with a password typed, "lost" on A4. Earlier runs failed on the test's own scrolling (one direction only; the page list instead of the form on iPad; the keyboard over the form), fixed in the test. Screenshot looked at: the note under the PDF settings, nothing cut. |
| Existing flows, iPhone 17 | **Pass**: `testPDFFormFilledCopyReopensWithFields` (106.4 s), `testSavedSignaturePlacesAndSurvivesReopen` (105.3 s), `RestrictedPDFUITests` 2/2, `ExportSizeUITests` 4/4, `WordExportUITests` 3/3, `testExportTilesSelectOneAtATimeAndCopyConfirms`; `testFrenchSignatureAtLargestTextSize` and `testExportSaveOpens…` **failed in a run at load 60–77 and passed on rerun** (27.5 s, 29.5 s). |
| Existing flows, iPad Air 13 | **Pass**: the form fill/reopen (119.6 s), saved signature (73.7 s), French XXXL signature (28.2 s), `RestrictedPDFUITests` 2/2. A first iPad run stopped in runner setup ("Timed out while loading Accessibility", freshly booted); rerun after a warm-up. |
| Environment, not this slice | The iCloud-evicted `.git` hung `xcodebuild`'s package resolution in a git worktree for ~2 hours (UI tests were then run from a git-free copy of the same tree); the host reached load 211 and **ran out of disk** (one run lost its logs: "no space left on device"); 21 GB of this session's own orphaned build caches were deleted. |

**Not done / limits:** radio buttons, dropdowns (choice fields), date fields and initials are **Not started** — the Fill Form sheet lists such fields as "Read-only or unsupported field. Its current value is preserved." (engine refusal tests; the UI test asserts the row); a restricted form exported with a password still loses its fields (rebuilt to keep the author's limits), and so does a source already encrypted; PDF permissions the person exporting could choose (no printing, no copying) are not offered — only the author's are kept; the "kept" note is the writer's rule, not a promise about every reader; VoiceOver, native Mac interaction and a physical device not checked.

## 2026-11-18 — The PaperNest watermark finished: a sharp logo at print resolution, the free mark read back from the file, French, Spanish and dark (Claude, roadmap order item 1)

Owner's queue ("Finish the PaperNest-branded watermark preset using the existing watermark architecture"). The preset itself was built on 2026-11-16 (entry below, not restarted); this closes what that entry left open. **The large preset's logo was soft at print resolution**: it came from the icon rendition of the mark (144 pixels at most on iOS, **96 in the Mac build**), drawn about 85 points across. `scripts/make-app-icon.py` now also writes `BrandMarkLarge` — the mark at its own size in the approved art (`docs/brand/papernest-instagram-profile.png`), **558 pixels, never scaled up**, one universal template image — and `BrandMark.watermarkLogo` takes it (falling back to the icon rendition). No substitute logo: the same art and the same keying as the icon. Rerunning the script left every existing icon file byte-identical.

| Check | Result |
|---|---|
| New `WatermarkLogoTests` (2) — **written first, failed first** | Before: **failed**, "the watermark logo is 96 × 96 pixels" (Mac). After: **pass** — at least 354 pixels each way (85 pt at 300 dpi) and square; the mask is the mark (clear corner, solid ring). |
| `WatermarkLogoTests` **in the iOS app** (`PaperNest-Canvas` scheme, `PaperNest-CanvasTests`, iPhone 17 / iOS 26.5) | **2/2 pass**: the large rendition loads from the compiled, thinned asset catalogue on iOS — the 2026-11-16 entry's "on iOS … not asserted" is now asserted. (A first attempt named the `PaperNest-iOS` scheme, which does not hold that target: refused, not a failure.) |
| New `BrandWatermarkExportTests` (2) — the sheet's own options to the written PDF | **Pass** (both already true; they guard it now). With `ExportSheet.optionsToExport` / `brandMarkToExport` as an export builds them: a **free user's export carries the PaperNest mark in the bottom-left even with the switch off**, read back from the exported PDF; Pro with the switch off carries none; the branded preset draws the mark across the page and carries the logo. Closes "no end-to-end check reads a free user's exported file". |
| Before/after at 300 dpi (temporary probe, deleted) | The branded preset exported and drawn at 300 dpi: the old logo's ring and leaf edges are visibly stepped and soft; the new one's are clean. |
| `./scripts/test.sh`, clean worktree (`1f679a6` + this slice) | First run: **1,521 passed, 1 failed** — `InlineTextSessionTests.deleteDuringPendingSaveCoalescesConcurrentTerminalRequests` (inline text timing; untouched here), which then **passed 3/3 alone**. Second full run: **1,522 tests, 0 failures, 0 warnings** (422 + 49 + 263 + 249 + 256 + 283). Recorded as a load-dependent flake, not fixed here. |
| `./scripts/build-mac-app.sh` | Succeeded, 0 warnings. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | Succeeded. |
| `xcodebuild build-for-testing -scheme PaperNest-iOS` (iOS Simulator) | Succeeded. |
| `WatermarkExportUITests` (13, one new), iPhone 17 / iOS 26.5, light | **13/13 pass**, including new **`testThePaperNestPresetInFrenchAndSpanish`** (68.3 s: the tile chosen, the preview says PaperNest, no text field to retype the brand, centre placement in reach, in fr and es). |
| Same new test, iPhone 17 in **dark** (`simctl ui … appearance dark`, restored to light after) | **1/1 pass** (85.3 s). |
| `WatermarkExportUITests` (13), iPad Air 13-inch (M4) / iOS 26.5 | **13/13 pass**. |
| Screenshots (`/tmp/pn-watermark-shots/`) | Looked at: French dark — "Marque PaperNest" switch and note, the white page with the mark and "PaperNest" diagonal in the preview, "Au centre" chosen, "Opacité 14 %"; Spanish light — the four other presets, "Marca de PaperNest", the preview, "Centro" chosen, "Tamaño: 39 KB". Nothing cut. |
| **Mac interaction** | **Blocked**: the dev Mac app was opened on a throwaway seeded library (`/tmp/pn-dev-brand`, export sheet open) and access was requested; the owner declined (`user_denied`). Not retried. The Mac app is built; the Mac logo size is asserted by `scripts/test.sh`. |
| Not run | The whole `./scripts/ui-test-ios.sh` suite (hours, and it would hold the shared iPhone simulator Codex is verifying on); VoiceOver; Dynamic Type beyond the existing French XXXL watermark test; a physical device. |

**Not done / limits:** the logo is still a raster (558 px is ample to about 470 dpi at the preset's size; a vector mark would need the brand art as vectors, which the repository does not have); the free mark remains removable by any PDF editor (attribution, not protection); the library backup and printing stay unmarked by the owner's earlier decision.

## 2026-11-17 — Image stamps: an image kept to place again, its original kept alive by every check (Claude, roadmap item 11, last part; item 11 done)

Owner in session ("Yes"). The stamp sheet (button renamed **Text or Image Stamp** / Tampon ou image / Sello o imagen, identifier unchanged) gains **Your Images**: images added from Photos or Files are kept in the library (schema v15, `saved_picture_stamps`) and placed like the other stamps, in a chosen size and corner of the page as shown, in their own proportions, as ordinary placed images (moved, resized, undone, exported). The date toggle is hidden for an image. **A picture stamp keeps its original alive, as a saved template does**: the four checks of whether an asset is still used now ask one helper (`isAssetKeptAside`) covering both.

| Check | Result |
|---|---|
| New `PictureStampStoreTests` (9) | **Pass.** Kept, listed newest first, the same image again brought forward rather than duplicated, deleted; a PDF or a sizeless image is refused; placing writes an ordinary placed image on top, and an unknown stamp is refused; **the launch housekeeping, in the app's order (`purgeDeletedPages`, `purgeReplacedPageContent`, `purgeExpiredDeletions`, `sweepOrphanAssets`), keeps an image only a picture stamp uses** — row, file, `isAssetReferenced`, `deleteAssetIfUnreferenced` refused, and placing afterwards; deleting the page it was placed on for good keeps it, and deleting the stamp lets the next sweep take row and file; a placed copy keeps it after the stamp is deleted; **redacting a page whose paper is that image cannot remove it**; **sync never offers it for eviction**; a v14 library migrates to v15 keeping its text stamps. |
| Mutation check, one per site | Switched back to templates only, each site fails its own test: `isAssetReferenced` → the housekeeping test (2 issues); `deleteUnreferencedAssetRows` → housekeeping and keep-until-deleted (2); `isAssetUsedElsewhere` → the redaction test; `syncEvictableAssets` → the sync test. Restored, all pass. |
| `StampModelTests` (+3) | **Pass (10).** An image added (a 400 × 200 PNG) is kept, chosen and thumbnailed; placed top right at a fifth of the page's shorter side, twice as wide as tall; Undo removes and Redo restores it; text and a PDF are refused and nothing is kept; deleting the image leaves its placed copy. |
| `StampStoreTests` | Version checks now follow `Schema.latestVersion`. **Pass (10).** |
| `./scripts/test.sh`, clean worktree (`613e3a1` + this slice) | **1,518 tests, 0 failures, 0 warnings** (418 + 49 + 263 + 249 + 256 + 283). |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| iPhone 17 / iOS 26.5, same build | **14/14 pass**: `StampUITests` 7/7, including the new `testASavedImageIsPlacedUndoneRedoneAndKept` (53.0 s: an image saved through the store before launch is chosen, the date switch is gone, Place puts it on the right in its own proportions, read from disk; Undo, Redo, relaunch; the saved image still there), `testImagesInFrenchAndSpanish` (79.6 s) and `testAFreeUserPlacingAnImageIsAskedToUpgrade` (45.1 s: paywall naming markup, nothing placed); `DocumentUtilitiesUITests` 6/6 and `NotesToolbarUITests.testTranslatedPanelsFit` (the button's label changed). |
| Screenshots (`/tmp/pn-stamp-shots/`) | Looked at: the image placed top right on the invoice; the French sheet. **The French title first read "Tampon texte ou im…", cut off**; French and Spanish became "Tampon ou image" / "Sello o imagen", the two localized stamp UI tests were rerun (**2/2 pass**, 81.4 s, 81.8 s) and the French title now fits. |

**Not done / limits:** the system Photos and Files pickers were not driven by a UI test (an image is put in the library before launch; adding from bytes is covered by `StampModelTests`); an image keeps its own background (a JPEG from Photos is opaque); the full-size original is kept; picture stamps are not synced and not in the library backup; on a turned page an image turns with the page, as every placed image does; images have no names, only "Image 1, 2…"; not checked on iPad, native Mac, VoiceOver or Dynamic Type.

## 2026-11-17 — The export sheet previews the first page as it will be exported (Claude, roadmap item 7, previews; item 7 done)

Owner in session ("Yes go ahead"). At the end of the export form a **Preview** section shows the first chosen page **read back from a real one-page export** with the sheet's options: a PDF's first page drawn (so Letter and A4 differ, and a watermark or the PaperNest mark is there), the exported JPEG/PNG/HEIC itself, the start of a text file's words, or a Word file's page picture or paragraphs. That one-page export is the size estimate's first sample (`Exporter.sample`), so the preview costs no extra export except when two to four pages are chosen; the file is removed once read. Captioned "Page 1 as it will be exported." With progress, cancellation, both Word layouts and the size estimate, roadmap item 7's list is done (XLSX waits on real table detection, as the roadmap says).

| Check | Result |
|---|---|
| New `ExportPreviewTests` (7, through the real exporter) | **Pass.** A PDF preview is the exported paper (Letter 612:792, A4 595:842, 720 pixels on the long side); **a Confidential watermark is in the preview** (red pixels the unmarked preview lacks); JPEG and PNG previews are the exported image at the page's shape; TXT and editable-Word previews are the page's words; a Word file of page pictures previews as its picture; of six pages only the first is previewed, and the export folder is empty afterwards; Word paragraphs read one per line with `&amp;` unescaped and page breaks skipped. |
| `ExportSizeEstimateTests` (9) after `estimateSize` became a wrapper of `sample` | **Pass.** |
| `./scripts/test.sh`, clean worktree (`62deaeb` + this slice) | **1,506 tests, 0 failures, 0 warnings** (415 + 49 + 254 + 249 + 256 + 283). |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| iPhone 17 / iOS 26.5, export UI tests, same build | **22/23 on the first run.** `ExportSizeUITests` 4/4, including the new **`testThePreviewIsThePageAsExported`** (en/fr/es: the PDF preview is a picture, and after choosing TXT it reads "Page 1 of the quarterly report…", 96.0 s); `WordExportUITests` 3/3; `WatermarkExportUITests` 12/12; `RestrictedPDFUITests` 2/2; `AppUITests.testExportSaveOpensTheSaveDialogAndClosingItKeepsTheExport` passed. **`AppUITests.testExportTilesSelectOneAtATimeAndCopyConfirms` failed**: the size line added in `62deaeb` makes the footer one caption line taller, so on a phone the Pages tiles start below the visible list and were never created, and after scrolling to them the format tiles were. The test now scrolls to the tiles and back to check the format (one shared-test edit, noted in the handoff); rerun: **passed** (34.1 s). |
| Flaky, not this slice | In that rerun `testExportSaveOpensTheSaveDialogAndClosingItKeepsTheExport` failed once on "the save dialog did not close" (the system document picker); it passed in the first run and in two reruns alone (29.0 s, 29.7 s): 3 of 4. |
| Screenshots (`/tmp/pn-export-size-shots/`) | Looked at: Spanish with TXT chosen — "Vista previa" with the page's words in monospaced type, "La página 1 tal como se exportará.", "Tamaño: 70 bytes" above the actions. |

**Not done / limits:** the preview is the first chosen page only; when that page cannot be exported on its own in the chosen format (a text format and a first page with no words), neither preview nor size is shown; it sits at the end of the form, under the options; on a phone the export form now shows one caption line less before scrolling; not checked on iPad, native Mac, VoiceOver or Dynamic Type; bulk export has neither preview nor estimate.

## 2026-11-17 — The export sheet says how large the export will be (Claude, roadmap item 7, output-size estimates)

Owner in session ("Do one by one don't ask me"). Above Save, Copy and Share the export sheet now says **"Size: 2.4 MB"** when every chosen page was measured, or **"Size: about 2.4 MB, worked out from a few pages"**, and "Working out the size…" meanwhile. `Exporter.estimateSize` really exports — the same writer, marks and quality — into temporary folders removed at once: all chosen pages when there are four or fewer, otherwise one sample page and four evenly spread ones, fitted as **a cost paid once per file plus a cost per page** (`ExportSizeModel`). The sheet re-estimates 400 ms after any change to the format, options, watermark, PaperNest mark or pages, and stops while an export runs. Progress, cancellation and both Word layouts already existed; this was item 7's missing piece.

| Check | Result |
|---|---|
| New `ExportSizeEstimateTests` (9, Export) | **Pass.** Sample pages spread evenly, first and last included; the once-per-file cost is not multiplied (1,100 / 1,400 bytes → 4,000 for 30 pages, not 10,500); two pages measured exactly (within 64 bytes of the real export: a PDF carries its own date and identifier); 20 scanned pages as PDF and as JPEG within 15%; 30 text pages as an A4 PDF within 20%; **30 pages of words as a Word file within 20%**; nothing left in the temporary folder and nothing stored (revisions unchanged, no recognition made); cancelling stops it with `CancellationError` and leaves nothing; a text export of wordless pages is refused with `noTextToExport`, as the export would be. |
| Accuracy (temporary probe, deleted after) | Real vs estimate vs scaling the sample up: 20 scans PDF 1,077,546 / 1,082,607 (+0%) / +1%; 20 scans JPEG ZIP 2,442,662 / 2,463,820 (+1%) / −1%; 30 text pages PDF A4 284,575 / 279,682 (−2%) / +2%; **30 pages Word 6,019 / 6,027 (+0%) / 13,807 (+129%)**. |
| Mutation check | With straight scaling in place of the fitted model, the arithmetic test and the Word-file test fail; restored, they pass. The text-PDF test alone did not catch it (the synthetic PDF's fonts are small), which is why the Word test was added. |
| First runs | The no-leftovers and cancelling tests first failed on other tests' exports running alongside in the shared temporary folder; they now use an exporter with a folder of its own. |
| `./scripts/test.sh`, clean worktree (`d1519da` + this slice) | **1,499 tests, 0 failures, 0 warnings** (408 + 49 + 254 + 249 + 256 + 283). |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| New `ExportSizeUITests` (3), iPhone 17 / iOS 26.5 | **3/3 pass** (11.3 s, 16.7 s, 22.7 s): two pages say an exact size; ten pages say "about", and choosing JPEG changes it; French and Spanish lines appear in sight. |
| `WordExportUITests` (3), same run | **3/3 pass** (the sheet's footer changed under them). |
| Screenshot (`/tmp/pn-export-size-shots/`) | Looked at: French, "Taille : environ 12 ko, d’après quelques pages" above the three actions, nothing cut. |

**Not done / limits:** an estimate from a few pages, so a document whose pages differ a lot (mostly text with a few photographs) can be off; bulk export does not estimate; the password is left out (protection barely changes the size); a refusal shows no size and the export explains it; not checked on iPad, native Mac, VoiceOver or Dynamic Type. Export previews beyond the watermark's remain.

## 2026-11-17 — Text stamps: Approved, Paid, Received, Reviewed, Rejected, Draft, Confidential and one's own words, kept to use again (Claude, roadmap item 11, stamps)

Owner in session ("Do one by one don't ask me"). Document Tools → **Text Stamp** (after the symbol Stamp button, which is unchanged) places a stamp on the page as shown: a preset word in the reader's language, a stamp kept in **Your Stamps**, or one's own words (outlined or filled, five colours, optionally kept), with today's date or not, small/medium/large, top right/bottom right/centre. A live preview drawn by the page renderer shows exactly what is placed. A stamp is **an ordinary text box with a stamp style**, so it moves, resizes, edits, undoes, redacts, exports, prints and is found by search like typed text; the sheet says it becomes part of the page, unlike an export watermark. Placing is Pro markup. **Schema v14** (`saved_stamps`).

| Check | Result |
|---|---|
| New `TextStampTests` (13, Core) | **Pass.** A box without a stamp encodes with exactly its old eight keys; a stamp round-trips and an old box reads as plain; **an unknown style reads as plain text rather than failing the page**; wording is one tidy line of at most 40 characters; the date is the second line and the box is bold, centred, sans; a saved design reads back tidied; Draft is the one filled preset; content sits inside border and padding (more padding at a filled stamp's round ends); sizes follow the page; placement in the corner of an upright page, of what a cropped page shows, and **of what a turned page shows** (through `PageGeometry`); a stamp wider than the room starts at the edge. |
| New `StampRenderTests` (6, through the renderer) | **Pass.** An outlined stamp's border is opaque green inside its frame with clear rounded corners; a filled stamp's tint is 14% of its colour; the same words as an ordinary box draw nothing at the edge; **22 words (every preset in en/fr/es and a custom one), both styles: every letter present, on one line, inside the padding, centred across and down**; the date line is smaller than and under the words; a larger stamp is the same shape scaled. |
| Mutation check (render) | With a stamp's inset left out of the selection rectangles, the one-line/centred test fails (6 issues); restored, it passes. |
| New `StampStoreTests` (10) | **Pass.** A placed stamp is a stamped text box and its word is findable; **changing its words keeps it a stamp** (neither editor passes the style back); undo of an edit restores it as it was and undo of placing removes it; moving keeps it a stamp; saved stamps kept, listed newest first, deleted; the same stamp kept again is brought forward, not duplicated (a different date setting is a different stamp); a stamp with no words is refused; saved stamps survive reopening; a v13 library migrates to v14 keeping its pages; a library a newer build moved on is refused. |
| Mutation check (store) | With `updateText` writing no style, the words-changed test fails (2 issues); restored, it passes. |
| New `StampExportTests` (1) | **Pass.** A stamp exported to PDF is selectable text ("APPROVED") with its green border drawn in the export, paper just outside. |
| New `StampModelTests` (7, through the sheet's model) | **Pass.** Approved goes top right exactly where the preview showed, bold, in the preset green; Undo removes it and Redo brings it back; one's own words kept are saved and chosen again bring their date setting; deleting a saved stamp leaves the placed one; words not kept are not saved; nothing to place without words; the date in the reader's way (fr_FR "17 nov. 2026", en_US "Nov 17, 2026"); **40 wide letters at the large size get smaller type and stay on the page on one line**; editing a stamp's words through the text box editor measures it again and keeps its corner. |
| First runs | The long-stamp test failed: one shrink of the type left the stamp 2–3 points too wide (the slack and rounding do not shrink with the type); the type now shrinks until it fits. The iOS UI-test build first failed on `await` inside `XCTAssert…` in the new file; fixed by reading the values first. |
| `./scripts/test.sh`, clean worktree (`5bf4079` + this slice) | **1,490 tests, 0 failures, 0 warnings** (408 + 49 + 254 + 249 + 247 + 283). |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| New `StampUITests` (4), iPhone 17 / iOS 26.5 | **4/4 pass** (53.7 s, 78.9 s, 81.8 s, 45.8 s): Approved placed bottom right, read from disk as an outlined "APPROVED" in the lower right; Undo removes it, Redo restores it, still there after relaunch; one's own words typed, kept, placed, saved in the library and offered again as Your Stamps 1 with its preview; French and Spanish preview "APPROUVÉ"/"APROBADO", rows, sizes and Place in reach, placed word read from disk; **a free user tapping Place gets the paywall naming markup, and nothing is placed**. |
| `StampUITests` (4), iPad Air 13-inch (M4) | **4/4 pass** (180.1 s, 46.6 s, 61.4 s, 37.1 s). |
| Regression, iPhone 17, same build | **10/10 pass**: Codex's `testSymbolStamps{English,French,Spanish}Lifecycle` (the symbol Stamp flow is unchanged), all 6 `DocumentUtilitiesUITests` (the Insert section gained a button), `NotesToolbarUITests.testTranslatedPanelsFit`. |
| Follow-up in the same commit series | The custom row read the same as its section header ("Your Own Words" twice); the row is now **Type Your Own** / Saisir vos mots / Escribir tus palabras. `LocalizationTests` + `StampModelTests` pass (12); `StampUITests.testOwnWordsAreKeptAndOfferedAgain` and `testTheStampSheetInFrenchAndSpanish` rerun on iPhone 17: **2/2 pass** (78.7 s, 80.4 s). |
| Screenshots (`/tmp/pn-stamp-shots/`) | Looked at: the French sheet (a green outlined "APPROUVÉ" preview on white paper, seven presets with colour dots, nothing truncated); the Spanish options (date toggle, Tamaño and Posición as inline rows, the footer note); the placed English stamp bottom right on the invoice. |

**Not done / limits:** saved stamps are words only — a reusable **image** stamp is not here (Insert Image and stickers place pictures, unsaved); stamps are not rotated; the words and date are written in when placed and stay in that language if the app's language changes; while a stamp is being edited inline the editor shows its words without the border; an older build reads a synced stamp as plain coloured words and, if it edits one, drops the style (sync is not production); saved stamps are not synced and not in the library backup; **on a turned page a stamp is placed in the corner shown but turns with the page, as every text box does** (the renderer draws page objects in source space, then turns them with the page); a stamp's words and date are page text, so search finds them and **Compare shows a placed stamp as added words**; native Mac interaction, VoiceOver and Dynamic Type were not checked.

## 2026-11-17 — Clean up a document: pages deleted by identity, long documents fast, signed copies and corrected text kept (Claude, follow-up to the entry below)

A review of the slice below found five faults, fixed here. **(1) The wrong pages could be deleted:** suggestions name pages by position, and the confirmation deleted by position, so a page added, removed or changed elsewhere between the look and the confirm moved the deletion onto other pages. The look now records each page's identity and revision; Delete goes ahead only if the document still has the same pages and every chosen one is at the revision it was found at, otherwise nothing goes, the document is looked through again, and the screen says so ("The document changed after it was looked through…"). Review is off while it looks again. **(2) Long documents stalled:** similar pages compared every page's words with every other's (`WordDiff`, quadratic); they are now grouped by their normalized words. **(3) A signed copy was offered as similar to the unsigned one:** similar pages must now have the same marks, by words and by look. **(4) A PDF page without text counted as read**, so a blank picture-only PDF (what scanner apps save) was chosen as blank; it is now unread until a recognition completes, like a scan. **(5) Hand-corrected recognized text** was not counted as something that goes with a page; it now is (kept copy, never chosen, named in the confirmation).

| Check | Result |
|---|---|
| Timing, `similarCandidates` on 100 pages × 500 words (temporary probe test, deleted after) | **113,172 ms before, 20 ms after**, 0 pairs both times. |
| `PageCleanupTests` (+4, Core) | **Pass (18).** The same words or the same look with different marks are not similar; words compare in one Unicode normal form (composed and decomposed "Café"); several pages with the same words all point at the first; the copy with corrected text is kept, and a blank page with corrected text is offered, not chosen. |
| `PageCleanupScannerTests` (+2) | **Pass (7).** A picture-only PDF page (a white bitmap drawn into a PDF) is only offered while unread, and blank and chosen once a recognition reads it and finds nothing; of two copies of a statement, the one whose recognition was corrected by hand is kept. |
| `CleanupModelTests` (+2) | **Pass (5).** A chosen page turned elsewhere after the look: Delete refused, nothing deleted, looked at again, Review off meanwhile; the new look offers the turned page only as looking blank (its reading was of the page before it turned) and deleting then takes only the duplicate. The original a duplicate was offered against is removed elsewhere: deleting the duplicate is refused, so the last copy stays. |
| Mutation check | With the identity-and-revision condition removed from `CleanupModel.deleteSelected`, both new model tests fail (12 issues); restored, they pass. A first version of the removed-page test passed with the condition gone (the keep-one-page rule refused it first); it was rewritten around the real hazard. |
| `./scripts/test.sh`, clean worktree (`2510776` + this follow-up) | **1,453 tests, 0 failures, 0 warnings** (401 + 49 + 244 + 243 + 246 + 270). |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| `CleanupUITests` (3), iPhone 17 / iOS 26.5, same worktree | **3/3 pass** (43.1 s, 47.4 s, 82.2 s). Not rerun on iPad for this follow-up. |

**Not done / limits:** the copies-of-this-document rows show names without folders; the confirmation lists every chosen page and is not shortened past about eight lines; a page changed elsewhere is caught at Delete, not the moment it changes.

## 2026-11-17 — Clean up a document: blank, repeated and similar pages offered, chosen only on strong evidence, deleted as one undoable step (Claude, roadmap item 12)

Owner in session ("Do one by one don't ask me"). Document Tools → **Clean Up Pages** looks through the document on the device and lists what could go: **blank** pages (read, no words, no marks, no ink at the large size), pages that **look blank** (unread, or a faint mark), **duplicates** of another page (the same original, crop, rotation and marks) and pages **similar** to another (the same words from another file, or the same picture at the large size). Only blank pages and duplicates are chosen to start with, and never a page carrying a private comment, a bookmark or kept details (the copy with them is the one kept); each row says what would go with it. **Review** asks before anything goes, says Undo brings the pages back until PaperNest quits, and deletes them as one step. A document keeps at least one page. Other documents identical to this one are listed, each to move to Recently Deleted (kept 30 days) after a confirmation. No schema change. Design: `docs/ARCHITECTURE.md` → Rendering.

| Check | Result |
|---|---|
| New `PageCleanupTests` (14, Core) | **Pass.** A read page with no words, marks or ink is blank and chosen; **faint ink at the large size is not blank and not chosen**; **an unread scan is never chosen as blank**; an empty notebook page is offered, not chosen; a page with marks or something attached is not chosen; the same original and marks again is a duplicate of the first; **the copy with a bookmark is kept**; different marks or crop are not duplicates; five empty notebook pages are not four duplicates; the same words from another original are similar; **different words with the same look are not**; without words, the same look only goes to the pictures to confirm; one suggestion per page; ink is what is clearly darker than paper (pencil yes, scanner grey no). |
| New `PageCleanupScannerTests` (5, through the renderer) | **Pass.** A read blank scan is blank and chosen while a page of words is not offered, and **a read scan with only a faint pencilled note in its margin is offered as looking blank, not chosen**; an unread blank scan is only offered; the same page again is a chosen duplicate, and once the later copy has a bookmark, the earlier one is offered instead; two separately made files with the same words are similar (offered, not chosen) and a different text with the same layout is not; an identical document is found, a marked one is not, and one in Recently Deleted is not offered. |
| New `CleanupModelTests` (3, through the screen's model) | **Pass.** The duplicate and the blank page are offered and chosen; **deleted as one step, Undo brings back every page in order, Redo takes them again**; choosing every page is refused and deletes nothing; an identical document is offered and moved to Recently Deleted, not gone. |
| First runs | The scanner's faint-mark test first passed for the wrong reason: the marked scan was unread, so it could never be chosen anyway. It now has a completed recognition like the blank one, so only its ink stands between it and being chosen, and the mark is a realistic size. |
| `./scripts/test.sh`, clean worktree (`d9dc1cd` + this slice) | **1,445 tests, 0 failures, 0 warnings** (399 + 49 + 244 + 241 + 246 + 266). |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| New `CleanupUITests` (3), iPhone 17 / iOS 26.5 | **3/3 pass** (47.7 s, 44.6 s, 82.8 s): a document of a statement, the same statement again and a read blank scan opens Clean Up with page 2 (duplicate) and page 3 (blank) chosen and page 1 not offered; Review asks first, and after Delete Pages one page is left, read back from disk; unchoosing page 3 leaves it; French and Spanish rows and Review in reach. |
| `CleanupUITests`, iPad Air 13-inch (M4) | **3/3 pass** (52.5 s, 43.5 s, 74.2 s); the confirmation is a popover there. |
| Screenshots (`/tmp/pn-cleanup-shots/`) | Looked at: the French suggestions on iPhone ("Page 2 : doublon de la page 1", "Page 3 : vierge", both ticked, "Sélectionnées : 2" and the on-device note, nothing truncated); the English confirmation ("Delete the selected pages?", each page and why, "Undo brings them back until PaperNest quits.", a red Delete Pages). |

**Not done / limits:** two separate scans of the same paper nobody has read are not found (their pixels differ everywhere and they have no words); near-copies of whole documents are not found, only identical ones; the review is a list with what goes with each page, not before-and-after thumbnails; undo lasts until the app quits (pages are purged at the next launch); nothing is looked for across documents except identical copies. Cleanup is not on the owner's Free/Pro list, so it is free. **Not verified:** the Mac, dark mode, large text, VoiceOver, long documents' speed (every page is drawn once, and blank candidates and look-alikes again at the large size).

## 2026-11-17 — Structured capture: signs kept, CSV formulas defused, replacing and stale details said, and extraction made fast (Claude, follow-up to the entry below)

Found in review after the structured capture commit. **Negative amounts lost their sign**: "TOTAL -12.00", "−12,00 €" and "(12.00)" were read as 12.00, so a credit note's amount due came out positive; a minus before the currency or the digits, or accounting parentheses, now keep it (a hyphen between numbers, as in "10-12.00", is still not a minus). **CSV cells could become formulas**: text read off a page anyone can send, starting with `=`, `+`, `@`, a tab or a carriage return, or with `-` when not plainly an amount, is a formula to Excel and Numbers; such a cell now starts with `'`. **Saving on page 2 silently replaced the details kept from page 1** (one set per document): the review now says "Saving replaces the details kept from page 1." **Saving details read from an earlier version marked them current** without a new reading: they now keep their old revision until the page is read again. **Extraction was slow**: every call compiled its patterns and data detector afresh; on an 80-line page a receipt took 546 ms and an invoice 1,188 ms on the main thread. Patterns are now compiled once (and each keyword list is one pattern): 9 ms and 18 ms, a business card 65 ms (debug build). The entry below says `DetailExtractorTests` has 32 cases; it had 30.

| Check | Result |
|---|---|
| `DetailExtractorTests` (now 17 tests, 34 cases) | **Pass.** Four more ways of writing an amount, each read with its sign and kept as read (-12.00, −12,00 €, (12.00), -$5.50); a hyphen between numbers is not a minus and a refund in parentheses is negative; **a CSV cell cannot be a formula** (`=HYPERLINK(…)`, +1-555, @SUM(A1), -1+2 and a leading tab start with `'`; -12.00, -12.00 EUR and plain words do not). |
| `DetailsModelTests` (now 6) | **Pass.** Opened on page 2 of a document whose page 1 details are kept, the review says Save replaces page 1's and reads page 2 afresh; details read before a rescan, edited and saved without reading again, are still stale, and reading the page again makes them current with the new total. |
| Timing, 80 synthetic lines, debug build (a probe, not kept) | Before: receipt 546 ms, business card 84 ms, invoice 1,188 ms. After: 9 ms, 65 ms, 18 ms. |
| `./scripts/test.sh`, clean worktree (`7338677` + this change) | **1,423 tests, 0 failures, 0 warnings** (396 + 49 + 244 + 236 + 246 + 252). The first run had four warnings: the data detector, already `Sendable`, did not need `nonisolated(unsafe)`; removed, and run again. |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings, after that change. |
| `DetailsUITests` (3), iPhone 17 / iOS 26.5 | **3/3 pass** (46.5 s, 45.2 s, 78.7 s), on the build before the annotation was removed (the code is otherwise the same). |

## 2026-11-17 — Structured capture: a receipt's, a business card's or an invoice's details, reviewed before saving (Claude, roadmap item 10)

Owner in session ("Do one by one don't ask me"). Document Tools → Process → **Extract Details** reads the page on screen and shows a review: the kind it guessed (receipt, business card or invoice; changeable), each field as editable text, **Check this** beside a value read with little certainty, and for an invoice its rows, to be checked one by one. **Save** keeps the reviewed details with the document; a business card can be shared as a contact card (vCard), a receipt or invoice as CSV; **Read the Page Again** reads the page's current text afresh. Everything is read on the device from the page's own text or its current recognized text; a scan nobody has read says to recognize its text first. **Schema v13** adds `document_details` (new table, nothing rebuilt, not synced, not indexed); an older build refuses a v13 library. **A redaction deletes details kept from its page.** Design: `docs/ARCHITECTURE.md` → Schema and Rendering.

| Check | Result |
|---|---|
| New `DetailExtractorTests` (15 tests, 32 cases, Core) | **Pass.** **A label and its amount side by side are one row**; nine ways of writing an amount read exactly (42.18, 42,18 €, 1,234.56, 1.234,56, 1 234,56 with a no-break space, 1 234,56 €, EUR 42.18, 42.18 USD, $42.18) with the currency only as written and the text kept as read; rates, dates and whole numbers are not amounts; eight dates read one way (ISO, 16 Nov 2026, Nov 16, 2026, 16 novembre 2026, 3 de abril de 2026, 16/11/2026, 11/16/2026, 05/05/26) and **03/04/2026 kept as written, unresolved**; a receipt's merchant (flagged), date, labelled total (never the subtotal), tax and currency; an unlabelled total is the largest amount, flagged, with no currency invented; a field not there stays empty; a badly read line is flagged; an invoice's supplier, number, dates, total, tax and two rows; French and Spanish invoice labels (Facture n°, Date d'échéance, Net à payer; Factura nº, Fecha de vencimiento, Total a pagar); a business card's name (flagged), company, phone, email and website; the kind guessed from the page; a vCard escaped, CRLF-ended and folded at 75 octets with accents whole; CSV quoting and line items. |
| New `DocumentDetailsTests` (6, Store) | **Pass.** Kept, replaced (one set per document) and deleted; **an ink stroke leaves them current, a rescan makes them stale**; gone with their document and with the page read from; a page of another document refused; **a schema v12 library migrates to v13** with its template, and can keep details. |
| New `DetailCaptureTests` (3, through the renderer; Vision) | **Pass.** A synthetic receipt scan has no lines until recognition runs; once read by Vision, it is a receipt with CORNER BAKERY, 2026-11-16 and 6.00; a digital invoice is read from its own text at full confidence, a typed box left out; **redacting a page deletes the details kept from it**. |
| New `DetailsModelTests` (4, through the review's model) | **Pass.** A digital invoice is guessed as one and read; an edit counts as certain; saved, and shown again as saved; choosing another kind reads that kind's fields; an unread scan says it has no text, and nothing was recognized to read it; a guess is flagged until edited. |
| `SavedTemplatesTests` | Its check that the schema is exactly v12 now accepts the latest. |
| `./scripts/test.sh`, clean worktree (`ebe49fe` + this slice) | **1,419 tests, 0 failures, 0 warnings** (394 + 49 + 244 + 236 + 246 + 250). After the French and Spanish titles were shortened (two strings), `LocalizationTests` again: 5/5. |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings (the Mac build before the two title strings changed). |
| New `DetailsUITests` (3), iPhone 17 / iOS 26.5 | **3/3 pass**, and **3/3 again** after the titles were shortened (46.5 s, 46.1 s, 78.4 s): Extract Details on a digital invoice opens the review with An Invoice selected, A-17 and 99.50 EUR; adding to the invoice number and saving keeps "A-17B" at confidence 1 and the total as read, read back from disk; choosing A Business Card shows its email field and a contact card to share; French and Spanish: the three kinds and Save in reach. |
| `RedactUITests` (redaction changed), iPhone 17 | **3/3 pass** (a redaction now also deletes kept details). |
| `DetailsUITests`, iPad Air 13-inch (M4) | **3/3 pass** (53.0 s, 47.2 s, 72.4 s), on the build before the titles changed. |
| Screenshots (`/tmp/pn-details-shots/`) | Looked at: the French review on iPhone, first with its title cut off ("Vérifier les dét…") between Annuler and Enregistrer, so the French and Spanish titles became "Vérification" and "Revisión"; after, "Vérification" whole, the kinds as rows with Une facture ticked, N° de facture A-17, Total 99.50 EUR and Devise EUR, empty fields showing their names. |

**Not done / limits:** only the page on screen is read; rules, not a model, so unusual layouts read poorly, and an invoice's rows always need checking; amounts need two decimals (a yen total without decimals is not found); a value read wrongly but confidently is not flagged; details are not synced, not searched and not in the backup; business cards are shared as a vCard file rather than added to Contacts directly (that would link the Contacts framework and need its usage description); no XLSX. Structured capture is not on the owner's Free/Pro list, so it is free (reading a scan first needs Recognize Text, which is Pro once products are configured). **Not verified:** the Mac, dark mode, large text, VoiceOver, real receipts.

## 2026-11-17 — User-made templates: save any page as a template, make notebook pages from it (Claude, roadmap item 8, last part)

Owner in session ("Go ahead"). From the Insert tool, **Save as Template** keeps the page on screen, with its paper or its own background (a letterhead, a form page) and its crop and rotation, and what is drawn and typed on it, under a name asked for in a prompt (it starts as the document's name). In a notebook, **My Templates** in the Insert tool makes a new page from one: a copy under new identities, undone and redone like any added page. Rename and Delete are in each template's menu, and Delete asks first. Private comments and recognized text are never part of a template, and a template's words are not findable until a page is made from it. **This is the first schema change of the session: v12 adds `saved_templates`**, a new table with nothing rebuilt; **an older build refuses a v12 library**. Templates are kept on this device and **not synced**, like bookmarks, and the library backup (a ZIP of documents as PDFs) does not include them, as it does not include saved signatures. With this, roadmap item 8 is done. Design: `docs/ARCHITECTURE.md` → Schema.

| Check | Result |
|---|---|
| New `SavedTemplatesTests` (8, Store) | **Pass.** A template keeps the page's paper, size, transform and marks in paint order, never the private comment, and is on disk when the call returns; **a page made from one is a copy** (same paper and size, the same marks under new identities), **its text findable only once the page exists** (the source deleted, "quarterly" answers nothing until then), and undo then redo bring it back once; a PDF page with a rotation is saved and comes back at its own size, not A4, and only a notebook takes a page from a template; **a template keeps its originals alive** — after its scan's document is deleted for good, both its background and its placed picture survive the permanent delete and the launch sweep, `isAssetReferenced` says so and `deleteAssetIfUnreferenced` refuses, and once the template is deleted the sweep takes them; Redact's check counts a template; **sync never offers for eviction an original a template keeps**; names are kept apart, renamed and deleted; **a schema v11 library migrates to v12 with its notebook, page and bookmark intact** and can save templates. |
| The sweep's template check, taken out to see the test fail | **It fails**: the permanent delete throws `FOREIGN KEY constraint failed` (787) — the risk the check exists for. Put back, it passes. |
| New `SavedTemplateWorkflowTests` (1, through `DocumentModel`) | **Pass.** Saved from a meeting notebook, the template is offered in another notebook, where a page made from it carries the five headings, is selected and can be undone; rename and delete through the model, and the page made from it stays. |
| `BookmarkTests` | Its check that the schema is exactly v11 now accepts v11 or later. |
| `./scripts/test.sh`, clean worktree (`bfa7dca` + this slice) | **1,391 tests, 0 failures, 0 warnings** (390 + 49 + 238 + 233 + 246 + 235). `LocalizationTests` pass with the nine new keys and the two reworded Redact messages. |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| New `SavedTemplatesUITests` (2), iPhone 17 / iOS 26.5 | **2/2 pass on the final code**, in one run (52.9 s, 48.9 s): Insert → Save as Template opens a prompt that starts with the document's name; renamed "Agenda page" and saved, the library holds one template with the page's one text box; My Templates offers it, and a tap makes a second page on lined paper carrying "Weekly agenda"; Delete in its menu asks first, in an action sheet, and afterwards the template is gone and the page stays. French and Spanish: the prompt, its field and Enregistrer / Guardar in reach, and saving keeps the document's name. On the way: my first queries looked for SwiftUI identifiers on the prompt's field and buttons, which a system alert does not carry (they are now found through `app.alerts`, and the identifiers are gone from the code); and with a template saved, the panel's other tools sit below My Templates, so the test now knows the panel is open by its row of papers. |
| `SavedTemplatesUITests`, iPad Air 13-inch (M4) | The main test **passes** (81.6 s; the confirmation is a popover there), and the French/Spanish prompt test **passed** (71.5 s) on the build before the test's panel check changed. **Seen:** the delete confirmation's popover sits at the left edge of the document, not by the template's card, since nothing anchors it there. |
| Existing UI tests the Insert panel touches, iPhone 17 | `NotesToolbarUITests.testEveryToolChangesWhatIsSaved` and `testTranslatedPanelsFit` **pass**; `StationeryUITests` **3/3**. |
| Screenshots (`/tmp/pn-templates-shots/`) | Looked at: the French save prompt on iPhone (title, explanation, "Planning" already in the field, Annuler and Enregistrer, nothing truncated); the iPhone Insert panel with My Templates and its "Agenda page" card between the papers and On This Page; the iPad confirmation, "Delete “Agenda page”?" over "Pages already made from it are kept." and a red Delete, beside the page made from the template showing "Weekly agenda". |

**Also changed:** Redact's two shared-original messages now name a saved template alongside another page, in en, fr and es, since a template can hold the original a redaction cannot remove. **Not done / limits:** templates are not synced and not in the backup; a template's card shows a generic sign, not a picture of it (that needs a renderer that takes marks not stored on a page); templates can be made into notebook pages only, not inserted into documents, and New Note does not offer them; deleting a template cannot be undone (it asks first). Templates are not on the owner's Free/Pro list, so they are free. **Not verified:** the Mac, dark mode, large text, VoiceOver, sync.

## 2026-11-17 — UI design-implementation review (Claude, owner's review prompt; review only, no product edits)

The owner pasted `docs/UI_DESIGN_REVIEW_PROMPT.md`. Compared the running app against `docs/CLEAN_NATIVE_DESIGN.md` (dated owner approvals win), `docs/WATERMARK_DESIGN_CLAUDE.md`, `docs/FEATURE_UI_SAMPLES.md`, and then the feature atlas. The atlas is concept art: its logo, sample names, "Accept All" and Tables/Images tabs are not a spec. **Tree tested:** a detached worktree at `a69cc18` (`~/Library/Caches/PaperNest/claude-ui-review`). It does **not** contain Codex's uncommitted `RedactEditor.swift` / `ScannerWorkspaceView.swift` fixes, so findings those fixes address are marked "known". **Simulators:** iPhone 17 Pro `63992C10` and iPad Air 13-inch (M4) `62328381`, iOS 26.5. Private seeded libraries were used; `scripts/ui-test-ios.sh` was not run. A temporary worktree-only XCUITest (`ZReviewScreensUITests`, never in the shared tree, never committed) opened each screen from its real entry point. It wrote screenshots and `performAccessibilityAudit` reports to `/tmp/claude-ui-review-shots/<config>/`. **The evidence kept in the repo is `docs/design/review-2026-11-17/`** (uncommitted): 35 screenshots (numbered 01–37; 30 and 31 are the two original-fingerprint files) and every audit report. Logs and `.xcresult` bundles are in `~/Library/Caches/PaperNest/claude-ui-review-results/`.

**Host conditions, which affect every timing below.** Five simulators were booted at the peak (three belonged to other sessions), swap reached 36.7 of 37.9 GB, and the load average reached about 670. UI tests ran 5–30× slower and failed on infrastructure: "Timed out while fetching snapshot from testmanagerd", `kAXErrorServerNotFound`/`IPCTimeout`, and one runner crash "signal abrt while preparing to run tests". No failure was judged until it was rerun alone at normal load.

| Check | Result |
|---|---|
| `./scripts/test.sh` (worktree) | **1,318 passed, 0 failed, 0 warnings** (379+49+226+223+246+195), 1 min 54 s |
| `./scripts/build-mac-app.sh` | **passed, 0 warnings** |
| `xcodebuild build-for-testing -scheme PaperNest-iOS` (iOS Simulator) | **TEST BUILD SUCCEEDED**, no compiler warnings (built three times as the review test changed) |
| Mac interaction | **Not run.** computer-use `request_access` for the dev app (`com.example.papernest.dev`) → `user_denied`. The Mac app was launched with a throwaway library and quit without being seen. |
| Screen pass, iPad, en, light, default size (13 screens) | 12/13 on the first run. The Export failure was the review test's own scroll helper. The rerun with fixed IDs **passed**, including the PaperNest preset. |
| Screen pass, iPhone, en, light, default | 11/13. Export failed on the test's wrong preset ID. Compress hit a 20 s open timeout at load ~300, but the screen opened and returned its result (screenshot). |
| Screen pass, iPhone, fr, light, **XXXL** | 10/13. Export: same test-ID bug. OCR panel: "Correct Text" not reached in 8 swipes. Paywall: the helper could not open Document Tools at XXXL; not judged. |
| Original unchanged (`test13`, iPad and iPhone) | **Passed.** A watermarked Copy (Confidential) followed by Redact mark → Cancel left the page rows and every asset's SHA-256 identical (`*-original-fingerprint.txt`). |
| Existing suites, iPad, en (36 tests, 96 min under load) | 22 passed, 11 failed, 3 with no verdict (`RedactUITests.testTheScreenInFrenchAndSpanish`, `ScannerFeedbackUITests.testTheAdviceFollowsWhatTheCameraSees`, `.testNothingFoundSaysNothing`: started, then "Restarting after unexpected exit, crash, or test timeout"). **Solo reruns at normal load: 9 of the 11 now pass**: Export Save dialog, notebook create/relaunch, OCR panel en/fr/es, comments en/fr/es, Redact apply, scan→export→Home, and three watermark tests. **Still failing:** `OCRCorrectionUITests.testACorrectedWordIsSavedAndFindAnswersIt` twice ("the OCR panel did not open"; Document Tools still showing, though the same entry opened in 4 other iPad runs, so inconclusive), and `WatermarkExportUITests.testWithoutProductsTheMarkStartsOff` twice. The latter is a **test defect on iPad**: it centre-taps the Toggle row, which `PanelControls.flipSwitch` documents does nothing on iPad. |
| Screen pass, iPhone, es, light, **XXXL** (6 screens) | **6/6 passed** (Home, Export incl. PaperNest preset, Redact, Signature, Form, paywall). |
| Existing suites, iPhone, en (subset, warm simulator, normal load) | **5/5 passed**: form filled copy reopens, saved signature places/undo/reopens, Redact Cancel writes nothing, watermark Copy, closing Export forgets the watermark. (The first full iPhone run crashed in runner setup, "signal abrt while preparing to run tests", with no verdict.) |
| Screen pass, iPhone, en, **dark**, default (7 screens, 14:10 CST, load ~4, after other work paused) | **7/7 passed** (Home, Export incl. PaperNest preset, Redact, OCR panel + correction, Signature, Form, scanner review). The first two dark attempts failed in runner setup on a freshly booted simulator ("Timed out waiting for AX loaded notification"); the third ran after a 60 s warm-up. Paper stays white; surfaces follow the dark palette. |

**Verified interactions (iPad unless marked; iPhone repeats noted):**
- Export with watermark:
  - Preset selection, placement, opacity and rotation change the preview.
  - Custom requires text; a text format says it can't carry a watermark.
  - Copy, Share and Save each export with the watermark; closing the sheet forgets it (Copy and closing also on iPhone).
  - French at XXXL keeps controls reachable.
  - Free-user mark until Pro, and Pro gates for Redact/Compress (paywall names the feature).
  - The unavailable state "Subscriptions are unavailable right now" + Try Again / Continue with Free was shown (iPad).
- Redact: mark → review → apply removes the line from page and library; Cancel writes nothing (iPad and iPhone).
- OCR: panel language/range validation and recognition in en/fr/es; correction Cancel asks and saves nothing; editor in fr/es.
- Forms: filled copy reopens with fields (iPad and iPhone).
- Signature: saved signature places, undo/redo, survives reopen (iPad and iPhone); French XXXL reachable (iPad).
- Process tools do real work; scanner review edits save and reopen; scan → export → Home.
- Scanner advice in fr/es.
- Approved Home with recents/folders; notebook creation survives relaunch; comments edit/cancel/delete/undo in all three languages.

**Mismatches found (evidence file numbers refer to `docs/design/review-2026-11-17/`).** HEAD moved during the review (to `613e3a1` at commit time). Of the reviewed screens, only two changed after `a69cc18`. **Export** (`62deaeb`, `613e3a1`) gained a size line in the footer and a preview at the end of the sheet. **Notebook creation** (`ae9d080`, `ebe49fe`) gained more papers and saved templates. So the Export and template findings need a recheck at HEAD. `RedactEditor`, `SignatureSheet`, `PDFFormSheet`, `OCRPanel`, `RecognizedTextEditor`, `ScannerWorkspaceView`, `Theme`, `LibraryHome` and `SubscriptionViews` are **unchanged at HEAD**, so those findings stand.
- **Major:**
  1. Redact review offers the irreversible Redact Page while warnings sit below the visible area. iPad Air 13" at default size: the second warning is cut mid-line and the third is hidden (01). iPhone fr XXXL: no warning is visible at all (04). iPhone default size: the hidden one was the conditional "another page uses the same original" warning (02), which appeared only because the seed gave both pages one asset; on an ordinary document both warnings probably fit. **Expected:** the prompt's "no inaccessible off-screen content" and Claude's R7 note ("keep every warning the review shows on screen before Redact Page"). Codex's 08:24 entry read below-viewport warnings as "not a new truncation finding", so this is the owner's call.
  2. Export action bar at XXXL (iPhone) truncates: fr "En-re…", "Co-pier", "Par-ta…"; es "Gua rd…", "Co-piar", "Co m…".
  3. The Signature panel's pinned footer and header leave about a quarter of the screen for content at fr XXXL (iPhone).
  4. The Form sheet at fr and es XXXL moves Save Filled Copy into a "…" overflow and drops its title; in English at default size the title already truncates to "Fill PDF Fo…".
  5. Scanner review at fr XXXL: Save "Enr…", presets cut to one or two letters, zoom pill over the page, tool row clipped.
  6. Dark mode: filled primary actions draw white text on the pale dark accent (#C5AEFF, 1.93:1 by Codex's 10:23 calculation). Seen on OCR "Recognize 1 page" and Redact "Review"; the audit flags both. Codex's uncommitted fix changes only Redact's Review tint, but the problem is the shared filled-action colour.
  7. Known, fix uncommitted (Codex): Redact action labels truncate at fr XXXL ("Cav…"). Codex's 13:30 entry reports its uncommitted fix showing full labels on the phone.
- **Minor:**
  - OCR panel chrome at XXXL.
  - Form panel chrome differs from the approved compact header + pinned footer; raw PDF field names used as labels.
  - Watermark preview sits below the presets (not in view on iPhone after choosing one).
  - Single password field with no Confirm, and its warning text fails the contrast audit in light and dark.
  - Home See All hit area too small.
  - Template rows have no paper preview. **Possibly superseded:** `ae9d080` added six papers to the same sheet; not re-checked.
  - Scanner advice sits under the top bar (already noted by Claude, 2026-11-16).
- **Polish:**
  - Save to Files wraps alone on iPad.
  - Compress "Save…/Share…" vs Export's direct buttons.
  - Paywall reuses the Redact glyph for the mark row.
  - Dark stage in the light Redact sheet.
  - Scrolled Redact title goes white over the blurred preview.
  - "Nouveau ca…" large title at XXXL.
  - Signature's Name field is pure black inside the dark purple card.

**Not a mismatch:** the free-export PaperNest mark contradicts the watermark doc's "never forced" line, but the owner changed that policy on 2026-11-13 (`docs/PRO_SUBSCRIPTIONS.md`). **Landed after the tested commit, not reviewed:** Compare (`5e73951`, `7c5ad32`); stationery papers (`ae9d080`, `bfa7dca`); saved templates (`ebe49fe`); receipt, business-card and invoice details (`7338677`, `d9dc1cd`); clean-up suggestions (`2510776`, `04b6ebe`); text stamps (`2e6aa94`); export size estimate and preview (`62deaeb`, `613e3a1`). **Correctly absent at `a69cc18`** (the samples say not to expose them yet): review links, structured capture and clean-up assistant (both landed later), handwriting-to-text, presentation, audio notes, assistant, Book scan mode, extra templates, PDF restrictions.

**Not covered:**
- Mac (access denied).
- Physical devices, a real camera, real StoreKit purchase, iCloud.
- VoiceOver navigation; the audit is not VoiceOver verification.
- iPad dark (dropped for time; Codex checked iPad dark Redact today).
- iPad and phone dark for Compress, Comments, paywall, notebook creation and scanner capture.
- iPad XXXL screenshots. Reachability tests did pass on iPad for French XXXL watermark controls and French XXXL signature.
- iPad Spanish screenshots. Interaction tests covered the OCR panel, comments, OCR correction and scanner advice in Spanish on iPad.
- Spanish at default size on iPhone.
- Exported files opened in an external reader.

## 2026-11-17 — Stationery: a planner's days in the headings' language, with the reader's week (Claude, follow-up to the entry below)

Found in review after the stationery commit: the planner's day names came from the calendar's locale while every other heading comes from `L10n`, which resolves through the app's own localizations. The usual way someone sets a language is to change it and keep their region, so the two can disagree: French with a US region, or a German phone whose headings fall back to English while the days would have been German. Now the day names are in the language the headings resolved to, and the week starts on the reader's region's first day (`TemplateHeadings.readersWeek`).

| Check | Result |
|---|---|
| New `TemplateHeadingsTests.theDaysAreInTheHeadingsLanguageAndTheRegionsWeek` | **Pass.** French in the US: Dimanche, then Lundi; English in France: Monday first. |
| `NotebookHeadingsTests`: search after redo (one more expectation) | **Pass.** Redone headings answer a search again: the undo path re-indexes typed text. |
| `./scripts/test.sh`, clean worktree (`ae9d080` + this change) | **1,382 tests, 0 failures, 0 warnings** (389 + 49 + 230 + 233 + 246 + 235). |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| `StationeryUITests` (3, with the new `testAPlannerPageForAFrenchReaderInTheUS`), iPhone 17 / iOS 26.5 | **3/3 pass** (33.0 s, 24.2 s, 59.1 s). Launched with the language French and the region en_US, a planner page's headings read "Semaine du", "Dimanche", "Lundi" … (nine in all). Whether the earlier code would have failed this test was not checked. Screenshot looked at: "Semaine du" over its rule, then Dimanche to Samedi and Notes in eight ruled boxes, two by four. |

**Not checked:** Night Mode, where grey (45%) headings on dark paper may be faint; dark mode; large text; the Mac.

## 2026-11-17 — Stationery: nine papers, and meeting and planner pages that arrive with their headings (Claude, roadmap item 8)

Owner in session ("Start the next slice, templates and stationery"). Notebook pages can now be **dotted**, **Cornell**, **checklist**, **meeting**, **weekly planner** or **form** as well as blank, lined and grid, from New Note, the add-page sheet and the Insert tool. A **meeting** page arrives with Meeting, Date, Attendees, Notes and Action Items; a **planner** page with Week of, the seven days from the reader's calendar (Sunday first in the US, Monday in France) and Notes. The headings are ordinary grey text boxes in the reader's language, written in the same transaction as the page, so they can be edited, moved or deleted and undo takes them away with the page. Each paper's lines come from one place (`PageTemplateLayout`), for the screen and every export. Design: `docs/ARCHITECTURE.md` → Rendering, "Template pages".

**Item 8 is not finished:** user-made templates need a table of their own and a sync design, and are the next slice of it.

| Check | Result |
|---|---|
| New `PageTemplateLayoutTests` (10 tests, Core) | **Pass.** **Lined paper is unchanged** (33 rules, 72 to 840 points, edge to edge) and **grid paper is unchanged** (46 rows from 18 to 828, 33 columns from 18 to 594); blank has nothing; dotted is a dot at each of 33 × 46 crossings; every paper's lines, dots, boxes and heading places are on the page, and every paper but blank prints something; a meeting's headings are in order (title, date, attendees, notes, action items), the title largest and bold, none overlapping; a planner has Week of, seven days and notes in eight boxes, none overlapping, each day's heading in its box; papers without words have no headings; a checklist row is a box and a rule; a page too small gets nothing rather than lines off it. |
| New `NotebookHeadingsTests` (4, Store) and the existing `NotebookPageTests` | **Pass.** A new page's headings are written with it in order, and findable ("attendees"); **undo takes the page and its headings away, and redo brings back exactly those headings, once**; a new notebook's first page has its headings; pages without headings have no objects; every paper is stored and read back as itself. The existing add-page and continuation tests run over all nine papers. |
| New `TemplateHeadingsTests` (6 tests, 8 cases) | **Pass.** The week starts where the reader's does (en_US Sunday, Monday; fr_FR Lundi … Dimanche, capitalized; es_ES Lunes); a meeting's and a planner's headings in order, other papers none; small grey labels, the title bold; **every heading of every paper fits its box in en, fr and es**, measured with CoreText the way the renderer lays a text box out (a text box clips what does not fit, without saying so); a new planner notebook's first page has its nine headings, and a meeting page added to a lined notebook its five, the lined page none. |
| New `StationeryRenderTests` (3 tests, 11 cases, through the renderer) | **Pass.** Blank paper is white; every other paper prints; dotted paper has a dot at 18, 18 points and paper between dots; lined paper's first rule is still at 72 points. |
| `./scripts/test.sh`, clean worktree (`4f49c0e` + this slice) | **1,381 tests, 0 failures, 0 warnings** (388 + 49 + 230 + 233 + 246 + 235), on the final layout and before it. `LocalizationTests` pass with the 12 new keys. |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings (the iOS log's one `warning:` is App Intents' metadata tool). |
| New `StationeryUITests` (2), iPhone 17 / iOS 26.5 | **2/2 pass on the final layout** (32.9 s, 60.8 s): from the Insert tool, every one of the nine papers can be brought into view in its sideways row, the panel's date and time is still beside it, and Meeting adds a second page on the meeting paper with five headings, the first "Meeting", "Réunion" or "Reunión", and none on the lined page. First run on that layout: the page and its headings passed, but the check that every paper can be reached failed at Cornell, because a swipe flung the row past it; the check now drags the row a little at a time. |
| Existing UI tests the panel and pickers touch, iPhone 17 | `NotesToolbarUITests` **3/3** (every tool, adding a grid page from Insert, read back from disk; translated panels; straightening a stroke) and `AppUITests.testNotebookPagesAddCancelUndoRedoAndReopenInAllLanguages` **pass**. `testTranslatedPanelsFit` **failed on the first layout**: nine papers in a three-row grid pushed the Insert panel's date-and-time, text box and divider below the fold, where its lazy grid had not made them; **the papers are now one row that scrolls sideways**, and it passes. `AppUITests.testNotebookCreationOpensAndSurvivesRelaunch` **fails, and fails the same way on a clean checkout of `4f49c0e` without this slice**: after the test taps Home from an empty All Documents, Home's New Note never appears (the screenshot shows All Documents still on screen). Not this slice's; left for whoever owns Home's tests. |
| `StationeryUITests` + `testTranslatedPanelsFit`, iPad Air 13-inch (M4) | **2/2 pass** (47.4 s, 87.4 s), and `testTranslatedPanelsFit` **passes** (100.2 s). |
| Screenshots (`/tmp/pn-stationery-shots/`) | Looked at: the French meeting page on iPhone, "Réunion" in grey bold, Date and Participants over their rules, Notes over ruled lines, "Actions à mener" over rows of checkboxes. The French Insert panel on iPhone: Vierge, Ligné, Quadrillé and the edge of the next paper in a row that scrolls sideways, with Zone de texte, Image, Date et heure and Séparateur still in view below. |

**Side effects, stated rather than engineered around:** headings are typed text, so they are indexed: every meeting page answers a search for "date" or "notes", and shows as typed text in search hits; they stay in the language they were written in; a page added by scrolling to the end of a notebook gets the paper's rules and no headings; an older build reads a new paper as blank, and sync refuses a page whose paper it does not understand. **Not done:** user-made templates (item 8's third part), page sizes other than A4, coloured or dark papers, a planner for a month or a day, papers on the Mac's own picker checked by eye (built, not opened). Templates are not on the owner's Free/Pro list, so they are free.

## 2026-11-17 — Compare on iPad: 2/2 (Claude, completes the two entries below)

The iPad run the entries below could not make, done on the committed code (`7c5ad32`) in a clean worktree once the host was quiet (load 35 at the start, against 180–700 during the earlier attempts).

| Check | Result |
|---|---|
| `CompareUITests` (2), iPad Air 13-inch (M4) / iOS 26.5 | **2/2 pass** (113.7 s and 106.1 s): summary `text:1 picture:0 added:1 removed:0 moved:0`, opens on 2/3 Changed by its words with one mark on each page, the overlay, the text change naming March and April, Next to 3/3 Added with the original missing, Done; French and Spanish with the three views and Done hittable. |
| Screenshot looked at (`/tmp/pn-compare-shots/ipad-side-by-side-fr.png`) | The sheet over Document Tools: "Modifications du texte : 1", the three views, "2 sur 3 · Modifiée", "March" boxed in red on the original and "April" in green on the new page, nothing truncated. **Seen:** in the iPad form sheet the two pages fill its lower half, so the legend, Précédente / Suivante and the limits line are reached by scrolling; a larger sheet would show them at once. |

**Still not verified:** the Mac screen (built, not opened), dark mode, large text, VoiceOver, a long document's speed.

## 2026-11-17 — Compare: matched pages compared larger, so a small change on a scan is found (Claude, follow-up to the entry below)

Found in review after the comparison was committed: pages compared only by picture were drawn 400 pixels long, where body-size print is about five pixels tall. **A probe confirmed it**: two scans nobody had read, in 18-pixel type on a 1000 × 1400 page, differing by one character — "42.10"/"42.70", "3 March"/"8 March", "1234567"/"1234561" — **came back "Same"**; "4.20"/"42.0" and every pair at 24 pixels were caught. Now pages are still matched at 400 pixels, and each matched pair is compared again at 1,600 pixels in 8-pixel cells (cells within two of each other are one region); word boxes are widened by 30% of their height before picture differences under them are left to the words. Also: the identical message no longer says "the same words" when some pages were compared only by how they look (it says those pages were compared by look and a very small or faint mark can be missed), and closing the sheet cancels a comparison still running.

| Check | Result |
|---|---|
| The probe again, after the change | All eight pairs (four pairs at 18 and 24 pixels) **changed**, one region each. |
| New `DocumentComparerTests.aOneCharacterChangeInBodySizePrintIsFoundByThePicture` (3 cases, the three pairs the old code called Same) | **Pass**: each is compared by picture (no text on either page), changed, one picture difference. |
| Existing comparison tests | **Pass**, including a changed word in a digital PDF with **no** picture difference (the widened word boxes cover its ink) and a stroke over identical text found where it is. |
| `./scripts/test.sh`, clean worktree (`5e73951` + this change) | **1,358 tests, 0 failures, 0 warnings** (382 + 49 + 226 + 230 + 246 + 225). |
| `./scripts/build-mac-app.sh`; `xcodebuild build-for-testing` (iOS Simulator) | Both succeeded, no compiler warnings. |
| `CompareUITests` (2), iPhone 17 / iOS 26.5 | **2/2 pass in one run** (66.5 s and 58.9 s): still `picture:0` for one changed word, the overlay, the text change, the added page, French and Spanish. |
| `CompareUITests`, iPad | **Not run, no verdict**, for the second time: on an idle iPad Air 11-inch (M4) the runner timed out waiting for the AX loaded notification as the host's load rose to 177. The iPad layout is still unverified. |

**Cost:** each matched pair is drawn twice more, at 1,600 pixels; a long document's speed is still not measured. **Still a limit:** a very small or faint mark can be missed by a picture comparison, and two separate scans of the same paper still differ everywhere.

## 2026-11-17 — Compare two documents: side by side, overlay and text changes; added, removed and moved pages (Claude, roadmap item 5)

Owner in session ("Start the next slice, PDF comparison"). Document Tools → Process → **Compare** opens a screen with this document as the Original and a New one chosen from the library (Swap turns them round). It counts text changes, picture differences and pages added, removed and moved, opens on the first page that differs, and shows each page **side by side** (removed words in red on the original, added words in green on the new page, picture differences in amber), **overlaid** (what only the original has in red, what only the new one has in green) or as **text** ("Removed: March", "Added: April"). Every page says how it was compared: by its words; by words read from a scan, where a misread word shows as a change; or by how it looks only, and why (which page has no text). Design: `docs/ARCHITECTURE.md` → Rendering, "Comparing two documents".

| Check | Result |
|---|---|
| New `WordDiffTests` (7), `PageAlignmentTests` (10), `DocumentComparisonTests` (13 tests, 16 cases), Core | **Pass.** Word diff: a replaced word is one change with both sides; removals and additions apart; exact comparison (Total/total, 10/100) after Unicode normalization (é composed or not); every unshared word in exactly one change; a huge difference is one coarse change between the shared ends. Alignment: the same document page for page; **a page inserted at the front is one added page, not every page moved**; a deleted page is removed and shown where it was; **two swapped pages are one move**; identical blank pages pair by position; a page with 75% of its words is the same page changed, one with 20% is removed and added; wordless pages match by look. Pages: a PDF's characters become words with one box each; **typed text boxes are left out** and recognized lines split; identical pictures have no difference, a mark is one region where it is, ignored areas and one-pixel fringes are not differences; a changed word is a change with both words and boxes and no picture difference; **matching words over a changed picture are a change, not Same**; a page without words is compared by picture and says which side has none; recognized words on either side are said; **picture regions on a rotated, cropped page come back in its source space and land where they were seen**, for all four rotations; counts are kept apart. |
| First run of the Core tests | One failure, in a test: 0.7 + 0.1 is 0.7999… in floating point; the expectation now allows for rounding. |
| New `DocumentComparerTests` (6, through the real renderer; Vision for the scans) | **Pass.** One changed word in a digital PDF is one change ("March" → "April") with its box where the line is (about 0.15 down) and no picture difference; a page inserted in the middle is one added page, none moved; **a stroke drawn over identical text is a change, found by the picture where the stroke is**; two scans nobody has read are compared by picture and say so, and once automatic recognition has read them, by their words ("42" → "43", recognized); a document compared with itself is identical; the overlay is red, dark, white and green where it should be. |
| New `CompareModelTests` (3) | **Pass.** The original is not offered against itself; choosing another document compares it and opens on the first page that differs; stepping stops at the ends; both pages and the overlay are drawn; Swap compares the other way round ("April" removed, "March" added); a page only the new document has has no original page and no overlay. |
| `./scripts/test.sh`, clean worktree (`a69cc18` + this slice; other sessions' uncommitted work left out) | **1,357 tests, 0 failures, 0 warnings** (382 + 49 + 226 + 229 + 246 + 225), on the final state (after the two fixes below) and before them. `LocalizationTests` pass with the 41 new keys, including French typography. |
| `xcodebuild build-for-testing`, `PaperNest-iOS`, iOS Simulator (XcodeGen for the new test file) | Succeeded, no compiler warnings. |
| `./scripts/build-mac-app.sh` | Succeeded, 0 warnings, on the final state. The Mac sheet was **built, not opened**. |
| New `CompareUITests` (2), iPhone 17 / iOS 26.5 | **Both pass on the final build**, in separate runs: the main flow (128.9 s: summary `text:1 picture:0 added:1 removed:0 moved:0`, opens on 2/3 Changed by its words with one mark on each page, the overlay, the text change naming March and April, Next to 3/3 Added with the original missing, Done) and French/Spanish (62.3 s: the three views and Done hittable, a text change shown). On the way: two runs never started (the runner timed out waiting for the AX loaded notification, host load about 180: infrastructure); one found that **tapping the middle of the New row did nothing**, only the name at its end was a link (fixed: the whole row is the link); one found that **the overlay picture was hidden from accessibility**, so VoiceOver skipped it (fixed: it is an element labelled Overlay); French/Spanish once stalled on a testmanagerd snapshot timeout (infrastructure) and passed when run again. |
| `CompareUITests`, iPad Air 13-inch (M4) / iOS 26.5 | **Not run, no verdict.** The iPad Air 13-inch was taken by another session's long run, and one attempt collided with it. On an idle iPad Air 11-inch (M4) / iOS 26.5, booted for this, the runner timed out twice waiting for the AX loaded notification while the host's load average was 200–700 (iCloud Drive syncing): infrastructure, not a test result. **The iPad layout is unverified.** |
| Screenshots (`/tmp/pn-compare-shots/`) | Looked at, iPhone: English overlay ("March" red and "April" green laid over each other, the rest dark); French side by side ("March" boxed in red on the original, "April" in green on the new page, the legend, Précédente / Suivante and the limits line, nothing truncated); Spanish text view ("Eliminado: March" in red, "Añadido: April" in green). The New row's label is drawn in the tint colour, as the link it is. Not looked at: iPad, dark mode, large text. |

**What it says about itself:** under each page, how it was compared; at the bottom, that pages are compared by their words and by how they look, that two separate scans of the same paper look different everywhere, and that a file storing its words in another order shows changes where none can be seen. A pair whose shapes differ says one was stretched onto the other.

**Not done / limits:** two revisions of one document (the page content history) are not offered, only two documents; two separate scans of the same paper differ everywhere, since nothing lines them up; on pages compared by words, a picture difference under a word is left to the words; typed text boxes are compared only as pictures; only pages are compared, not outlines, links or form fields; no export or print of the comparison; the comparison is not stored and runs again each time; **not gated as Pro**: comparison is not on the owner's Free/Pro list, which leaves anything unnamed free — the owner's call. **Not verified:** the iPad (see above), the Mac screen, dark mode, large text, VoiceOver, a long document's speed (each page is read and drawn once, one after another).

## 2026-11-17 — Free users' printouts carry the PaperNest mark too (Claude, owner in session)

Owner asked for a recommendation on the two routes `0f1848a` left unmarked; the recommendation was to mark printing
(its panel can "Save as PDF" on the Mac, and share a PDF from the iPhone and iPad print options, which made it a
two-tap way round the mark) and keep the library backup unmarked (the user's safety net and a faithful copy of
their own documents; an awkward way to share one file). Owner: "Yes go ahead".

**What changed.** `DocumentPrinter` (`Reader/DocumentPrint.swift`) asks an injectable `freeMark` step before making
the PDF; the default, `entitlementFreeMark`, waits for entitlements to load and asks `Watermark.freeExportMark`, and a
print cancelled during that wait makes nothing. The mark rides on `DocumentPrinter.options(attribution:)`, the plain
print options plus `attribution`. Nothing is marked while no App Store products are configured. The backup and the
form workspace's saved copy stay unmarked.

**Verification**, in a clean detached worktree outside iCloud: `0f1848a` plus exactly the committed files.
- New `DocumentPrintTests` (3): a free user's printout carries the mark in every page's corner and never in its
  text; a Pro user's is unmarked; the print options are the plain document's plus the mark. **Shown to fail first:**
  against the old printer they do not compile (no `freeMark`, no `options(attribution:)`).
- `./scripts/test.sh`: **1,318 passed, 0 failed, 0 warnings** (1,315 plus the 3). No export folder left in the temp folder.
- `./scripts/build-mac-app.sh`: **passed, 0 warnings.**
- `xcodebuild build-for-testing -scheme PaperNest-iOS`: **TEST BUILD SUCCEEDED**, no warnings from the changed files.
- `DocumentPrintUITests` (2, run by a subagent): **iPhone 17 Pro 2/2, iPad Pro 13-inch (M5) 2/2** (iOS 26.5). The
  print panel appeared 2.8–4.7 s after the tap against the test's 20 s. One iPad launch in French took 195 s at a
  load above 100 (spindump: the app rendering pages, nothing from printing or StoreKit; that test never prints).
- **What the UI runs do not cover:** the scheme has no App Store products, so the entitlement wait returned at once
  and the printouts were unmarked; the wait against real StoreKit, and a marked printout through the real panel,
  were not exercised. The store sets `hasLoaded` after its first refresh whether it succeeded or not, so a print
  waits for StoreKit at most once per launch.

**Not done.** No physical printer and no device; the print panel itself is the system's and was not driven to a
printout or a saved PDF. A printout says nothing about the mark (the panel is the system's, with no room for a note).

## 2026-11-17 — Redact and Compress are Pro (Claude)

Owner in session ("Yes go ahead"), carrying out the Free/Pro list approved on 2026-11-13, which says "Compress and Redact once their screens exist". `ProFeature` gains `compress` and `redact`, with names in the paywall's list ("Compress documents", "Redact pages"; French and Spanish too). For a free user, once products are configured, the **Compress** and **Redact** buttons in Document Tools open the paywall naming the tool instead of its screen, and `DocumentModel.redact` refuses as well (`SubscriptionStore.require(.redact)`), so no other way in can write a redaction. **Nothing changes today:** with no App Store products in `Subscriptions.plist`, every check allows everything.

| Check | Result |
|---|---|
| `./scripts/test.sh`, clean worktree (`0f1848a` + this change) | **1,315 tests, 0 failures, 0 warnings** (376 + 49 + 226 + 223 + 246 + 195). `SubscriptionStateTests` loops over every `ProFeature`: the two new ones are allowed before products are configured, refused by name for a free user after, and each has its own translated name and a symbol. `LocalizationTests` pass with the new keys. |
| `xcodebuild build-for-testing`, `PaperNest-iOS`, iOS Simulator (project regenerated with XcodeGen for the new test file) | Succeeded, no compiler warnings. |
| `./scripts/build-mac-app.sh` | Succeeded, 0 warnings. |
| New `ProToolGateUITests` (2 tests), iPhone 17 / iOS 26.5, launched with `-PaperNestDebugProProducts` and nothing bought | **2/2 pass.** Redact in Document Tools opens the paywall with `pro-locked-feature` = `redact` and no Redact screen behind it or after closing it; Compress the same with `compress` and no Compress screen. Screenshot looked at: "Included in PaperNest Pro: Redact pages" above the list. |
| `ProToolGateUITests`, iPad Air 13-inch (M4) / iOS 26.5 (Compress opens in the side panel there, not a sheet) | **2/2 pass**, the paywall naming each tool, from the side panel as well. |
| `RedactUITests` (3 tests), iPhone 17, without products: the control | **3/3 pass**: with the boundary off, Redact opens and redacts as before. |
| `SubscriptionUITests` (3 tests), iPhone 17 | Profile paywall in en/fr/es (the list is now eleven rows; Spanish at XXXL still reaches Continue with Free) and the welcome test **pass**. `testAFreeUserGetsThePaywallNamingTheRefusedFeature` **failed** on the first run, "export sheet did not open": it opens "Crop target" from `/tmp/papernest-uitest-library`, which only `scripts/ui-test-ios.sh` seeds, and this run used `xcodebuild` directly. With a private library seeded the way the script does (`PAPERNEST_UITEST_LIBRARY`), it **passed** (39.8 s). |

**Not done:** the Compress screen itself does not check again (its only way in is the gated button and a DEBUG launch argument), unlike Redact's model; the Mac's Document Tools were built, not opened; nothing was bought in a StoreKit test store to see the tools open for a subscriber (the paywall's own tests cover access).

## 2026-11-16 — The PaperNest watermark: a branded preset, and a small mark on free exports that Pro removes (Claude, owner in session)

Owner: "Yes, build it" (the PaperNest branded watermark), then, asked whether free exports should carry it
automatically, chose **"Automatic on free exports"** — the Nov 15 decision "free version will have papernest
watermark and paid will have option to remove". How it works: `docs/ARCHITECTURE.md` → Rendering, "The PaperNest mark".

**What works.**
- A **PaperNest** tile among the watermark presets: the app's real mark (`BrandMark`) beside its name, centred,
  −32°, 14%, in the deep accent. The name is the brand's and cannot be retyped.
- **Free exports carry a small PaperNest mark** in the bottom-left corner of every page, beside any chosen
  watermark: the export sheet (a "PaperNest mark" switch, on for a free user, whose switching off opens the paywall
  for the new Pro feature "Exports without the PaperNest mark"), bulk export and Compress. Pro starts with it off and
  may turn it on. Nothing is marked until App Store products are configured, like the rest of Pro.
- Never marked: the library backup, printing and the form workspace's saved copy.

**Calls made here, for the owner to check.** The free mark is a separate small badge (brand mark and name,
bottom-left, 55%), not the large diagonal preset, so the chosen Confidential/Draft/Approved/Custom stay free and the
two never collide; "choosing None opens the paywall" became "switching the PaperNest mark off opens the paywall".
**Two exemptions the owner should decide on:** the free library backup gives every document as an unmarked PDF in a
ZIP, and printing (whose panel can save a PDF) is unmarked; both make "remove the mark" easy to get round.

**Verification**, in clean detached worktrees outside iCloud. Final: `20b01bd` plus exactly the committed files.
- `./scripts/test.sh` on the final tree: **1,315 passed, 0 failed, 0 warnings.** 20 are new: `WatermarkTests` 22 → 29,
  `WatermarkExportTests` 10 → 17, `WatermarkDraftTests` 11 → 17. `LocalizationTests` passes with the 9 new keys in
  en/fr/es; `SubscriptionStateTests` covers `removeWatermark` with every Pro feature.
- **Shown to fail:** with the logo's fill and the attribution both stubbed out, 7 of the new tests failed (the logo
  colour test and every free-mark export test).
- `./scripts/build-mac-app.sh`: **passed, 0 warnings.** Mac interaction not exercised.
- `xcodebuild build-for-testing -scheme PaperNest-iOS`: **TEST BUILD SUCCEEDED**, no warnings from the slice's files.
- `WatermarkExportUITests`, 12 tests (3 new), run by a subagent on iPhone 17 Pro and iPad Pro 13-inch (M5), iOS 26.5,
  with `xcodebuild test-without-building -only-testing`, in four rounds on the slice as it changed:
  - Round 1 (before the review fixes): iPad 12/12; iPhone 11/12, the opacity drag lost its touch in a load spike
    (recording: released after 15 of 178 points), 1/1 alone.
  - Round 2 (review fixes, tiles two to a row): iPhone 12/12; iPad 11/12, `testWithoutProductsTheMarkStartsOff`
    looked for the switch after the new preview had pushed it under the bar (a test scroll; fixed), then **12/12**.
  - Round 3 (switch moved above the preview, reveal helper stops when the form will not move): iPhone 11/12 and iPad
    10/12. Two were accessibility stalls at a load of about 160 that passed alone; the third, on the iPad in both runs,
    was the rotation slider not taking XCUITest's `adjust` gesture when it was the last row, 30 points above the bar.
  - Round 4: with the sliders scrolled 80 points clear of the bar, the slider test **passed on both devices**. A
    diagnostic at the low position showed a plain press-and-drag moves the slider (0° → 74°): XCUITest's adjust
    gesture, not the layout. The diagnostic was removed; the test file was compared with `cmp` afterwards.
  - The other 11 tests' last results are round 3's on the same helper: all passed on both devices, two of them on a
    rerun after a load stall. The scanner and Redact commits since (`ff24675`…`20b01bd`) touch none of the export files.
- Screenshots seen: the PaperNest tile carries the brand mark; the switch is on with the free note; the preview shows
  the small bottom-left mark; the paywall says "Included in PaperNest Pro: Exports without the PaperNest mark". No
  hyphenation at two tiles to a row on iPad. A runtime log line predates this slice ("content type com.adobe.pdf not
  included in its writableContentTypes", from the export sheet's save dialog).

**Independent review** (a fresh subagent, read-only) found no route a free user can take to an unmarked PDF or
picture besides the deliberate ones, and five faults, fixed before the final runs:
- A paying user could be marked: entitlements load after launch, and buying Pro from the sheet left the switch on.
  The switch now follows the entitlement (`onChange`), the export checks it again as it starts
  (`ExportSheet.brandMarkToExport`), and bulk export and Compress wait for entitlements to load (and stop if cancelled
  while waiting).
- Compress said "The copy is the original size" for a marked copy, and neither it nor bulk export warned that the
  mark redraws every page; both now say so, and Compress names the mark as the reason a copy is no smaller.
- A picture with two marks was copied twice in memory; now one pass.
- The Mac picked an upsampled logo; it now takes the asset's largest picture as it is.
- Tests that proved less than they claimed: the corner check passed on the letters alone and the test logo was a
  symmetric disc. New: a lopsided logo must come out upright on a picture and through a real PDF's soft mask;
  `optionsToExport` no longer defaults to unmarked; the export-time recheck is tested.

**Found on the way:** my own deliberate red run (attribution stubbed out) left a `PaperNestExport-…/Doc.txt` in the
shared temp folder, because a refusal test discards output it did not expect; `BulkExportTests` then failed every
time on that leftover. Removed it; the three refusal tests now clean up even when they fail.

**Not done / limitations.**
- No physical device, no VoiceOver pass, no Mac interaction (built, not used), no French or Spanish screenshot of
  the new switch or tile.
- The large branded preset's logo comes from a 144-pixel picture (96 on a thinned 2x iPad) and is soft at print
  resolution; a vector logo would fix it.
- The logo-loading code is tested on the Mac (`scripts/test.sh`); on iOS it is exercised only by the UI tests' tile
  and preview, not asserted.
- No end-to-end check reads a free user's exported file; the engine tests prove the mark is drawn when asked, the
  sheet tests prove it is asked for.
- The mark is vector and mask objects at the end of each PDF page: any PDF editor can remove it. It is attribution
  and an upgrade nudge, not protection.

## 2026-11-17 — The Redact screen: mark areas, see the page as it will be written, apply; marks over the areas go with it (Claude, roadmap item 4)

Owner in session ("Start doing it"): roadmap item 4's "manual redaction tool with a review-before-apply step", on the engine from 2026-10-27. Document Tools → Process → **Redact** opens a screen where areas are dragged across the page. **Review** shows the page drawn by the redaction engine itself, as it will be written, and says what goes with it. **Redact Page** applies it. The engine now also removes the ink, text boxes and placed pictures drawn over the areas, in the same operation: they are drawn over the page in every export, and a text box's words answer searches, so leaving them would show what was redacted. Private comments are never drawn and stay. Applying clears the document's Undo, because an Undo could put a removed mark back. Design: `docs/ARCHITECTURE.md` → Rendering, "Redaction".

| Check | Result |
|---|---|
| New `PageRedactionReviewTests` (7 tests, 10 cases, Core) | **Pass.** A box drawn on the page goes back to the same place after a round trip through source space, for all four rotations with a crop; a box drawn backwards is the same box; a tiny box grows to the minimum side and never shrinks; a box drawn hard against the right and bottom edges still reaches them; ink bounds include the stroke's width, and a comment has no bounds; only marks over an area are named (a text box and a placed picture over it, not the box beside it, never the comment); a mark only grazing an area counts. |
| New `PageRedactionMarksTests` (4 tests, through the real renderer and store) | **Pass.** A text box over the area is removed and one beside it stays; the removed box's words no longer answer a search, and neither they nor the page's own words are in a PDF exported afterwards; marks from another page are never removed, even when passed; `paperHasWords` is true for a digital page and for a picture with recognized lines, false for a picture nobody has read; a redaction refused before it draws anything (no areas) removes no marks. |
| New `RedactionChecksTests` (3 tests, Store) | **Pass.** An original only this page uses is not used elsewhere; a second page of identical paper is found from either side; a page in the trash still counts. |
| New `RedactionWorkflowTests` (2 tests, through `DocumentModel`) | **Pass.** The review returns the engine's picture, the overlapping box (only it), one comment and that the page has words, and writes nothing (the page's content and its three marks unchanged); applying makes the page a picture, removes the box over the area and keeps the box beside it and the comment, "9921" and "55512345" stop answering a search and "March" still does, and the undo manager has nothing to undo or redo afterwards; a document whose paper was imported twice is flagged in the review before anything is written. |
| New `PageRedactionTests.readingTheRedactedPageAgainFindsOnlyWhatIsLeftShowing` (real Vision, Import target), added after review | **Pass** (the suite 8/8). A scan reading "ACCOUNT 55512345" and, lower, "Filed in March" is read by automatic recognition; the account line's recognized box, with a margin, is redacted; "march" stops answering; **the next automatic pass reads the redacted page again** and "march" answers once more, while "55512345" and "account" never do. This is why the review's selectable-text warning was reworded: it said the page's words could no longer be searched, and with recognition allowed (today everyone, since no App Store products are configured) the words still showing come back. |
| First runs | Four failures, all in the new tests or their setup: the marks tests were in the Import test target, which cannot import Export (moved to Export's tests); `"m110"`/`"m600"` are not valid sort keys and failed in `setComment`; the duplicated-document test generated its PDF twice, so the bytes, and the stored files, differed (one constant now); and `hasSelectableText` was first read from the background search index, which a just-imported page may not have reached yet (now read from the page itself, `paperHasWords`). |
| `./scripts/test.sh`, clean worktree (`2bed07e` + this slice; other sessions' uncommitted work left out) | **1,295 tests, 0 failures, 0 warnings** (370 + 49 + 226 + 223 + 232 + 195), on the final state including the reworded warning and the re-reading test. Earlier, on the final screen before those: 1,294, 0 failures, 0 warnings. No `PaperNestExport-*` folder was in the temporary directory. |
| `./scripts/build-mac-app.sh` | Succeeded, 0 warnings (final screen, before the reworded warning; the rewording changes only strings). |
| `xcodebuild build-for-testing`, `PaperNest-iOS`, iOS Simulator | Succeeded, no compiler warnings, on the final state (the log's one `warning:` is App Intents' metadata tool noting there is no AppIntents dependency). |
| New `RedactUITests` (3 tests), iPad Air 13-inch (M4) / iOS 26.5 | **3/3 pass**, and **3/3 again** after each layout fix below (not re-run after the warning's rewording, a string change). From the document: reveal Redact in Document Tools, drag across the statement's line (the page's value goes to "1"), Review, the flatten, selectable-text and cannot-be-undone warnings are there, Redact Page; the screen closes, the page is stored as a picture and "SECRET" no longer answers a search. Cancel after marking leaves the page the PDF's page. French and Spanish: Review and Redact Page are hittable. |
| `RedactUITests`, iPhone 17 / iOS 26.5 | **3/3 pass** before the layout fixes, **3/3** after the first two, **3/3 on the final screen** (160.7 s; the simulator booted under a host load of about 260), and **3/3 on the final state** with the reworded warning (114.4 s). English review screenshot looked at: the engine's picture with the band in black, the flatten and selectable-text warnings, and "This can't be undone." beside Edit Areas and Redact Page in the fixed bar. |
| Screenshots (`/tmp/pn-redact-shots/`) and the layout fixes they led to | Looked at on iPhone: the marking screen's title was dark on dark under the navigation bar (the page's dark background ran under it; fixed); the review's white backing filled the full width instead of sitting behind the page picture (fixed); the cannot-be-undone line could scroll out of sight below the other warnings (moved into the fixed bar beside Redact Page). French marking screen after the fix: "Caviarder" readable. iPad French review after the last fix: the preview with the band in black, the warnings scrolling above a fixed bar holding "Cette action est irréversible.", Modifier les zones and Caviarder la page. Not looked at: dark mode, large text, the Mac sheet, VoiceOver. |

**What the screen says before writing:** the whole page becomes a picture of itself; its selectable text goes, across the whole page, when it has any, until text recognition reads the page again and finds only the words still showing; which marks go (a switch, on by default) and how many comments stay; that another page still shows the same original, so the words stay in the library; that with sync on, copies already in iCloud are not reached; that it cannot be undone. A restricted PDF page cannot be reviewed. If the original is shared, the screen stays open after applying and says the words are still in the library.

**Not done / limits:** **not gated as Pro**, although the owner's Free/Pro split of 2026-11-13 puts Redact (and Compress, also ungated) in Pro: `ProFeature.swift` is in the watermark session's claim, so the gate is left for when it is free; no Undo, by design; the marks are removed in a commit of their own just before the paper is replaced, so a failure in between leaves them removed and the page unchanged; **iCloud copies of the original are not deleted** (deleting an asset only cancels an upload not yet made), and the screen says so only when sync is on; content outside a crop stays in the flattened picture; a form's typed answers are flattened with everything else; areas cannot be drawn with VoiceOver; one page at a time, no redacting search results or a pattern across pages; deleting a file does not scrub the disk, and nothing says it does. **Not verified:** the Mac screen (built, not opened), a real device, sync on.

## 2026-11-16 — The scanner says what the camera sees: Move closer, Move back, Improve lighting, Hold steady, Ready (Claude, roadmap item 2/6)

Owner in session ("Yes, start it"): the roadmap's capture-quality feedback and the scan design's §3. While the camera is pointed, a short label under the scanner's top bar says **Improve lighting**, **Move back** (the page nearly touches the frame's edge), **Move closer** (it covers too little of the frame), **Hold steady**, or **Ready** (in the accent). The label and the automatic shutter are decided in one step from the same look (`ScanCaptureGuide`), so with Auto on, Ready is shown only when the shutter fires, and a kept sheet still in view, or a look within three seconds of the last capture, says nothing; with Auto off, Ready means good to take by hand. Photo mode, which looks for no edges, only ever says Improve lighting. **A change of behaviour: the automatic shutter no longer takes a steady page that is too small, too dark or nearly cut off** — it used to take any rectangle that held still. Design: `docs/ARCHITECTURE.md` → Rendering.

**No real camera was used.** On a simulator the camera is unavailable; the labels were seen only through recorded looks played through the camera's own processing (`-PaperNestDebugScannerFrames`, DEBUG only). The brightness reading was tested on buffers built in each format, not on camera frames. **The darkness threshold (12%, clearing at 18%) is a guess and the size thresholds come from drawn scenes; neither is tuned on a device.** The camera's video output keeps its default pixel format, which is not set anywhere: if a device hands over a format the reader does not know (it reads biplanar YUV in either range and BGRA), brightness is always unknown and **Improve lighting never appears** — it would not hold anything back, but it would never be said. Pinning the output's format would settle it; that is a camera change nobody could try here.

| Check | Result |
|---|---|
| Probe before designing: drawn scenes through the real detector | A sheet is found down to about 5% of the frame, a board to about 11%, a card to about 1%, so Move closer at 20%, 20% and 3% can fire in every mode. A sheet drawn 0–1.5% from the edge is found with corners reported about 1.6–1.8% from it; touching the edge or running off the frame, it is not found at all. So Move back (2.5% margin) can fire, but only for a page about to be cut off; a page already cut off gets no outline and no advice. |
| New `ScanCaptureGuideTests` (17 tests, Core) | **Pass.** The automatic shutter's three old tests, ported from `ScannerAutomaticCaptureTests` (a steady sheet taken once until removed; after Keep it waits for the next sheet; movement and interruption restart the count); Hold steady for eight looks, then Ready, which stays with Auto off; Move closer with hysteresis (16% → closer, 21% still closer, 25% fine, 21% then fine); Move back with hysteresis; Improve lighting first, even with nothing found, clearing only above 18%; unknown brightness holds nothing back; nothing found in good light says nothing; with Auto on, Ready only on the look that fires; a kept sheet still in view is never called Ready; within three seconds of a capture it says nothing rather than Ready; **Auto does not take a steady page that is too small, too dark or nearly cut off**; a card is close enough sooner than a page; a photo is told only about the light and never taken; every mode's ready size is above what its detector can find; area and edge distance in shares of the frame. |
| New `ScanFeedbackDetectionTests` (6 tests) | **Pass.** Through the real detector and then the guide: a small sheet, board and card are each found and told to come closer; a sheet filling the frame well only has to hold still; a sheet drawn 0.8% from the edge is found and told to move back; one running off the frame is not found and gets no advice. |
| New `ScanFrameLuminanceTests` (6 tests) | **Pass.** Video-range YUV runs from 16 to 235, full range from 0 to 255, BGRA weighs green most (Rec. 709); row padding filled with white is never read (97-pixel rows, padded); half black, half white is half bright; a format it does not read (ARGB) is unknown. |
| First run of the new tests | Two failures, both in the tests: BGRA white came to 0.99999… (the weights sum to 1 only up to rounding), and the ported movement test shifted the sheet to the frame's edge, where the guide rightly said Move back. Fixed in the tests. |
| `./scripts/test.sh`, clean worktree (`9cd6171` + this slice) | **1,277 of 1,278 pass, 0 warnings.** The one failure is `BulkExportTests.cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind`, which fails on any `PaperNestExport-*` folder in the shared temporary directory: one was there, holding `Doc.txt`, created at 22:28 by another process (no export test of this slice's ran then; this slice touches no export code). **The same test fails the same way on a clean checkout of `9cd6171`, without this slice, while that folder is there.** |
| `xcodebuild build-for-testing`, `PaperNest-iOS` (compiles the iOS-only camera code) | Succeeded, no compiler warnings. |
| `./scripts/build-mac-app.sh` | Succeeded, 0 warnings. |
| New `ScannerFeedbackUITests` (3 tests), iPhone 17 and iPad Air 13-inch (M4), iOS 26.5 | **3/3 pass on each.** One recording steps the label through Move closer ("Move closer"), Move back, Improve lighting, Hold steady and Ready ("Ready"), with the shutter still on screen; empty frames say nothing until a page arrives; French ("Rapprochez-vous", "Prêt") and Spanish ("Acércate", "Listo"). Scanner defaults pinned, Auto off. |
| Follow-up, same day: the capture window | Found in review: while a picture was being taken, the guide was run as if Auto were off, so the label could fall back to Hold steady, or say Ready over a look nothing was taken of. Now, while capturing, the camera moves only the outline, keeps the advice it last sent, and does not feed the guide (as the shutter's old rule was not fed then either). iOS Simulator build succeeded, no warnings; `ScannerFeedbackUITests` 3/3 again on iPad. **The path itself is unexercised**: nothing is captured without a camera. |
| Screenshots (`/tmp/pn-scanner-feedback-shots/`) | Looked at: iPhone French Move closer and Spanish Ready — the label under the top bar, clear of the mode strip and the shutter. The simulator's camera permission alert covers the middle of the screen in every one: the scanner asks for the camera, and there is none to grant. Not looked at: the label over a live camera picture (its dark capsule is drawn for one), large text, VoiceOver. |

**Not done:** blur, glare, skew, low contrast, duplicate and blank page detection, and book mode. **Not verified:** any of it on a device with a camera; whether the thresholds suit real paper, rooms and hands; clipping judged against the preview (it is judged against the camera's frame, which is the photo; the preview fills the screen and trims the frame's sides).

## 2026-11-16 — Search says which page matched and shows the words around it; a deleted page's words stop answering (Claude, roadmap item 1)

Owner in session ("Yes, start it"): roadmap item 1's last open piece, "search snippets that show the matching page and recognized text context". While searching, the library now lists under the matching documents an **In Pages** section: each matching page as "Document · Page N", the words around the match with the matching words in bold, and where the words came from (recognized text, text in the PDF, typed text). A tap opens the document at that page, also when the document is already open in an iPad tab. **Also fixed:** a deleted page's words went on answering searches until the next launch's purge (thirty days with sync on), so a document stayed in the results for words only on a page in the trash; `search(_:)` and the new hits now count a page's words only while the page is live. Design: `docs/ARCHITECTURE.md` → "Revisions and derived data".

| Check | Result |
|---|---|
| New `SearchHitTests` (17 tests) with `RecognitionSearchTests`, `LibraryStoreTests`, `RecognitionCorrectionTests` | **67/67 pass, no warnings.** A hit names the page (2 of 3), the source (recognized), and marks "Invoice" as the page writes it, with "total 42 for October" around it; a prefix marks the whole word ("invo" → "invoices"); an accent-blind query shows the accented word ("deja" → "déjà", "aout" → "août"); every word of a two-word query is marked; line breaks and runs of space become single spaces; **a deleted page's words stop answering `search(_:)` and the hits at once, and come back with the page on undo**; a document in Recently Deleted has no hits; page numbers follow a reorder and skip a deleted page; a digital page that was also recognized is one hit, from its own text; typed text is found and says so; a title match has no page and comes first; three hits per document, and the overall limit; documents in `search(_:)`'s order; words read off paper that has since been replaced are not hits, corrected words are; FTS syntax in the query is words (`OR`, `NEAR(`, `AND NOT` must be on the page; quotes, `*`, `-`, `^`, `:` and brackets are dropped); unpaired marks give plain text; space is tidied across runs. FTS5 `snippet()` worked with the table aliased and joined. |
| First run of `SearchHitTests` | Two expectations failed, both mine: the test expected `invoice OR` and `NEAR(invoice` to find the page, but the query treats every word as a word to find, which is the point. The test now asserts that. |
| New `SearchPageHitsModelTests` (4 tests) | **4/4 pass.** The library's hits follow the search and only the documents shown (a notebook's hit goes when the kind leaves notebooks out; no hits when not searching); hits are in the list's order (by name: Alpha's two pages, then Zebra's); a document opened from a hit shows that page on its first load, and a request made before the load is kept for it; a document already open goes to the requested page and another document's window leaves the request alone. The sort preference the test changes is put back. |
| `./scripts/test.sh`, clean worktree (`ae3a9c7` + this slice; the watermark session's uncommitted lines left out) | **1,207 tests, 0 failures, 0 warnings** (359 + 49 + 222 + 210 + 196 + 171). |
| `xcodebuild build-for-testing`, `PaperNest-iOS`, iOS Simulator | Succeeded, no compiler warnings. |
| `./scripts/build-mac-app.sh` | Succeeded, 0 warnings. The Mac library's search was **built, not seen**. |
| New `SearchHitsUITests` + `DocumentFindUITests` (the document view gained a task), iPhone 17 / iOS 26.5 | **5/5 pass.** Searching "invoice" from Home lists Statements and under it one hit, for page 2 (value "2"), labelled with the document, "Page 2", "Invoice total 42 …" and "Recognized text"; no hit for pages 1 or 3; tapping it opens the document at "Page 2 of 3". French ("Page 2") and Spanish ("Página 2") hits are labelled and reachable. The three Find tests pass. |
| Screenshots (`/tmp/pn-search-hits-shots/`) | Looked at: English and Spanish iPhone results — "In Pages" / "En las páginas" under the document row, "Statements · Page 2", "Invoice" in bold in its context, the source under it. **Seen, not mine, already in the handoff for Codex:** the library's large title is drawn over its search field on iPhone until the list scrolls. |
| `SearchHitsUITests` + `DocumentFindUITests`, iPad Air 13-inch (M4) / iOS 26.5 | First attempt never ran: `simctl bootstatus` waited 30 minutes on a simulator already booted, and once stopped, the simulator could not launch the test runner ("Host is down", its system shell had crashed) — infrastructure, no test verdict. Simulator shut down and booted again: **5/5 pass**, the hit opening the document at "Page 2 of 3" in the iPad layout. Screenshot looked at: French — "Dans les pages", "Statements · Page 2", "Texte reconnu". |
| Watermarks landed underneath (`8024da8`, another session) before this commit: `./scripts/test.sh` and the iOS build again, on `8024da8` + this slice | **1,250 tests, 0 failures, 0 warnings** (370 + 49 + 222 + 210 + 228 + 171); `build-for-testing` succeeded. The UI tests above ran on `ae3a9c7` + this slice; the watermark commit touches export and none of this slice's files. |
| **Follow-up, same day: hits were capped before they were narrowed to the documents shown** | Found in review. `searchHits` kept sixty page hits library-wide, newest documents first, and only then did the library keep the ones on screen — so searching in a folder (or with Notes / Documents chosen) could list a matching document with no page under it, its hits crowded out by newer documents elsewhere. `searchHits(_:among:)` now narrows to the documents shown inside the query (`json_each` over one JSON parameter), before any cap, and `LibraryModel` passes them. New store test `hitsAreNarrowedToTheGivenDocumentsBeforeAnyCap`, and model test `aFoldersHitsAreNotCrowdedOutByDocumentsElsewhere` (one old document in a folder, twenty-five newer ones elsewhere with three hits each). **Checked that it bites:** with the committed `LibraryModel.swift` put back, the model test fails; with the fix, it passes. |
| Follow-up: new UI test `testAHitTakesAnAlreadyOpenDocumentToThePage` | Opens the document (page 1), goes back — its tab is kept with its loaded model — searches from Home and taps the hit: page 2. This is the already-open path end to end, which the earlier model test only called directly. |
| Follow-up: `./scripts/test.sh` and the iOS build, clean worktree (`4f7ffb1` + the follow-up) | **1,252 tests, 0 failures, 0 warnings** (371 + 49 + 223 + 210 + 228 + 171); `build-for-testing` succeeded. |
| Follow-up: `SearchHitsUITests` (3 tests), iPad Air 13-inch (M4) and iPhone 17, iOS 26.5 | **3/3 pass on each**, the already-open test included. |

**Not verified:** the Mac library's search on screen (built only); dark mode, accessibility text sizes and VoiceOver reading of the hit rows; a library of thousands of documents (the query reads at most 2,000 matching rows of the documents on screen, then keeps three hits per document and sixty in all — not timed). **Limitations:** hits are in the document list's order and page order, not ranked by relevance; at most three pages per document are listed; Find is not opened with the query when a hit is opened; a title match is not listed as a page hit (the document row already shows it).

## 2026-11-16 — Export watermarks: Confidential, Draft, Approved and Custom (Claude, owner in session)

Owner: "Read docs/WATERMARK_DESIGN_CLAUDE.md and implement the PaperNest watermark feature … one real slice with
Confidential, Draft, Approved, and Custom watermark presets". How it works: `docs/ARCHITECTURE.md` → Rendering,
"Export watermarks". Built on `1900a73` (Word page images) once that claim was released; verified on `ae3a9c7`.

**What works.** The export sheet has a Watermark section for PDF, JPEG, PNG and HEIC: None (the default),
Confidential, Draft, Approved and Custom. A preset fills in its own word in the reader's language (CONFIDENTIEL,
BORRADOR, APPROUVÉ…), placement (Center, Top right, Bottom right, Tiled), opacity, rotation and an optional
date line, all editable. A preview draws the first exported page on its paper with the mark, through the export's
own drawing function. Save, Copy and Share all export through `ExportSheet.optionsToExport`, so all three carry the
same mark; closing the sheet forgets it. TXT and Word refuse a watermark (`ExportError.watermarkNotSupported`), and
the sheet says so where the section was if one had been chosen. Nothing is stored; the library is never changed.

**Engine** (`PaperNestExport`): `Watermark`, `WatermarkPreset`, `WatermarkPlacement` (`Watermark.swift`);
`WatermarkDrawing` (layout, glyph-outline drawing, `applying(_:to:pageSize:)` for pictures). `ExportOptions.watermark`
(nil by default); `Exporter` draws it after each PDF page's content and OCR layer, on the paper, and over each
picture; `isUntouched` stands pass-through down when a visible watermark is set.

**Verification**, in a clean detached worktree outside iCloud: `ae3a9c7` plus exactly the committed watermark files
(each compared with `cmp` before committing).
- `./scripts/test.sh`: **1,229 passed, 0 failed, 0 warnings.** 43 are new: `WatermarkModelTests`,
  `WatermarkLayoutTests`, `WatermarkDrawingTests` (22, `Tests/PaperNestExportTests/WatermarkTests.swift`),
  `WatermarkExportTests` (10, through the real exporter: the mark is in every PDF page and picture, the page's own
  text and a scan's OCR layer stay selectable and the watermark's words are not in the text, an untouched PDF is no
  longer handed back byte for byte, an empty or emoji-only watermark changes nothing, Letter paper puts a corner mark
  in the paper's corner, a copy-restricted PDF keeps its limit, TXT and both Word layouts refuse, one export draws
  the mark once, the library is unchanged) and `WatermarkDraftTests` (11: what the sheet hands the export).
  `LocalizationTests` passes with the 26 new keys in en/fr/es. The first full run had **1 failure**,
  `oneExportDrawsTheMarkOnce`: it read the fixture's black orientation square in the page's corner as the mark's
  darkest pixel (green 0). A test bug: it now reads only the middle of the page, and the rerun above is clean.
- Engine tests were first shown to fail: with `draw` stubbed to return early, the Confidential, Draft, Approved and
  tiled drawing tests failed, and the opacity test crashed on an arithmetic overflow in the test itself (fixed).
  The same run exposed a real fault: `sizesFollowThePageNotThePoint` failed because the system font's optical sizes
  changed the letters with size; letters are now shaped at one reference size and scaled.
- `./scripts/build-mac-app.sh`: **passed, 0 warnings.** Mac interaction was not exercised.
- `xcodebuild build-for-testing -scheme PaperNest-iOS` (fresh derived data): **TEST BUILD SUCCEEDED**, no warnings
  from the watermark or export-sheet files (the one warning is the unrelated appintents metadata note).
- `WatermarkExportUITests` (9 tests, `xcodebuild test-without-building -only-testing`, not `ui-test-ios.sh`), run by a
  subagent on simulators no other session was using:
  - **iPhone 17 Pro, iOS 26.5: 9 passed, 0 failures** (962 s; load 40–88 during the run).
  - **iPad Pro 13-inch (M5), iOS 26.5: first run 8 passed, 1 failed** — `testCopyExportsWithTheWatermark`,
    "confidential did not become the selected watermark" at the preset tap. The recording shows the tap on the
    Confidential tile and no change on screen; XCTest spent 1.7 s and 3.4 s in its pre-tap idle checks for that one
    tap against 0.1–0.2 s for every other. Judged a dropped tap during a stall, not proven. **Rerun: 9 passed,
    0 failures** (268 s, load 2).
  - Before the review fixes, the first eight tests had passed 8/8 on the same two devices after test-only fixes
    (scrolling past the sheet's top bar, and the tearDown below).
  - Screenshots: `/tmp/pn-watermark-shots/{iphone,ipad}-{confidential-en,draft-moved-en,draft-share-en,approved-fr-xxxl}.png`,
    viewed: presets, placement tiles, sliders, date switch and the two notes fit at iPhone and iPad width in English;
    French at accessibility XXXL keeps every control reachable.

**Independent review** (a fresh subagent, read-only, with a throwaway compile harness) found seven issues, all
fixed before the final runs: emoji-only text counted as a watermark but drew nothing (now judged from the glyph
outlines, and the sheet names it); the preview could compose one page's picture at another's size; a corner radius
beyond half the width for one narrow letter; an unbounded transparency layer (now bounded to the marks); a format
switch silently dropping a chosen mark (now a note); re-tapping the selected preset wiping edits; long tiled text
making three marks (tiles now at most half the page). Its test critiques led to `oneExportDrawsTheMarkOnce` (a
darkness check rather than byte equality), `aRestrictedPDFKeepsItsLimitsUnderTheMark`, the Word page-images
refusal and `everyExportCarriesTheDraftWhereItCanBeDrawn`.

**UI test infrastructure found on the way:** an `async` `@MainActor` `tearDown` deadlocks the XCTest runner when a
test is interrupted (reading `isSelected` on a missing element interrupts regardless of `continueAfterFailure`):
the runner waits on the main thread for a tearDown that needs it, until XCTest times out — 8–12 minutes. The new
class cleans up with `addTeardownBlock` instead. `WordExportUITests.swift` still has the async tearDown.

**Not done / limitations.**
- No physical device, no VoiceOver pass (accessibility values and labels are set and asserted, not listened to), no
  Mac interaction (built, not used), no Spanish UI run (strings present; French XXXL run only).
- The PaperNest branded preset in the design doc is not built (the request named four presets); nor a logo image,
  colour choice for Custom, or the free-version forced watermark the owner decided on 2026-11-15.
- A watermark on Word page images is refused, not drawn.
- Pages with a watermark are redrawn, so an imported PDF's links and fillable fields are not kept on them (said
  under a PDF in the sheet). Tiled marks repeat their outlines on every page: about 80 KB per Letter page for
  "Acme Holdings Ltd" tiled.
- Mixed text such as "TOP 🔒 SECRET" keeps the emoji's width as a gap.
- A picture export still holds the rendered page and the watermarked copy at once (two full-size bitmaps).
- Seen, not fixed (outside this slice): the export sheet's bottom bar truncates its French labels at accessibility
  XXXL, and the review saw a tile report Selected when it was not; the watermark tiles now also say Selected / Not
  selected as an accessibility value.
- Design acceptance test 9 (a failed export keeps the sheet usable for a retry) is not met by the sheet as it is:
  after a failure it offers only Done.

## 2026-11-16 — OCR text correction: a page's recognized lines can be corrected, and every reader gets the corrections (Claude, roadmap item 1)

Owner in session ("Yes, start it"), the slice recommended after Word page images: roadmap item 1's "OCR correction/editor view with page-level previews". In the OCR panel, under a new **Recognized Text** section, the page on screen now says whether it has been read (not yet / could not be read / has its own text / recognized / corrected), and a recognized page offers **Correct Text…**: a sheet with the page above its lines, the line being edited outlined on the page (mapped through `PageGeometry`), one field per line, lines recognition was unsure of marked, a count of changed lines, Cancel (asks before discarding) and Save. Saving goes through a new guarded store call and is one step of the document's undo history. The corrected words are what search, find, selection, read aloud, TXT and Word export and the searchable PDF use. Automatic recognition after an engine update leaves corrected pages alone; Recognize Text chosen by hand still replaces them, and the panel says so first when the chosen pages include corrected ones. Design: `docs/ARCHITECTURE.md` → "Revisions and derived data".

| Check | Result |
|---|---|
| New `RecognitionCorrectionTests` (14 tests) with `AutomaticRecognitionTests`, `RecognitionSearchTests`, `TextMarkupStoreTests`, `NotebookPageTests` | **40/40 pass, no warnings.** Search finds the corrected word and no longer the misread one; the page's revision moves and the corrected result is current for it; accented corrections are kept and found; an emptied line is removed, ends and line breaks are tidied, an unchanged line stays exactly as read, a changed one keeps its box and becomes certain; nothing changed writes nothing and moves nothing; a one-word typo fix keeps the word boxes, a changed word count falls back to the line; entries that do not match the lines are refused; an editor opened before the page was recognized again cannot overwrite the newer reading; failed and stale results cannot be corrected; undo works after ink was drawn (and redo after it); undo is refused after the page was recognized again; a newer engine reads the untouched page and not the corrected one; a corrected page with new paper is read again; a result stored before `correctedAt` existed decodes untouched and an untouched result writes no marker. The query's `json_extract` ran in these tests through the library the app links (macOS). |
| First run of the new store tests | One failure, a real one: a failed result corrected with no lines came back as "nothing changed" instead of being refused, because the no-change shortcut ran before the check that the result is current. The check now runs first. Also six unused-result warnings in the tests; `correctRecognition` is `@discardableResult`. |
| `./scripts/test.sh`, clean worktree (`30c3d40` + this slice; the watermark session's uncommitted lines left out) | **1,183 tests, 0 failures, 0 warnings** (352 + 49 + 205 + 210 + 196 + 171). |
| `xcodebuild build-for-testing`, `PaperNest-iOS`, iOS Simulator | Succeeded, no compiler warnings. |
| `./scripts/build-mac-app.sh` | Succeeded, 0 warnings. The Mac editor was **built, not seen**. |
| New `OCRCorrectionUITests`, iPhone 17 / iOS 26.5, first run | `testACorrectedWordIsSavedAndFindAnswersIt` **passed**: the OCR panel says "recognized", Correct Text opens with "Invocie total 42" marked unsure, the line is corrected, the preview outlines line 1, the count says 1, Save closes the editor, the panel says "corrected", the library holds the corrected lines with `correctedAt`, and **Find answers "Invoice" (1 of 1) and "Invocie" with No Results**. Find was first opened after the correction here, so it read the page fresh: this alone does not show that the revision move matters — `OCRCorrectionModelTests` below does. `testCancellingAfterAChangeAsksAndSavesNothing` **failed**: the confirmation's Discard button matched twice on iPhone (test fixed with `firstMatch`) — and the runner then sat idle in tear-down until my 580-second limit stopped it, as on iPad last slice even though `continueAfterFailure = false` was gone. The one thing both stalled files had that the other UI tests do not was an `async` `tearDown` override; both new UI test files now clean up with `addTeardownBlock`. |
| iPhone 17 / iOS 26.5, second run (`OCRCorrectionUITests` + `WordExportUITests`) | **6/6 pass**: the three OCR correction tests (Cancel asks, Discard saves nothing, the panel stays "recognized"; French and Spanish editors with Save in reach) and the three Word export tests with the new teardown. |
| Screenshots (`/tmp/pn-ocr-correction-shots/`) | Looked at: English editor as opened (the outline appears once a line is chosen; the unsure line marked; Save disabled) and French after a correction (the outline on line 1 of the page, the pencil on the changed line, "Lignes modifiées : 1" and Enregistrer above the keyboard). The lines' header read "1 / 1" (the page stepper's format); changed to "Page 1 of 1" — the runs below are of that build. |
| iPad Air 13-inch (M4) / iOS 26.5, final build (`OCRCorrectionUITests` + `WordExportUITests`) | **6/6 pass.** The editor opens as a sheet over the OCR panel in the trailing inspector; Find answers the corrected word and not the misread one. Screenshot looked at: Spanish editor — "Página 1 de 1", the outline on the page, the pencil on the changed line, Guardar beside the count. |
| iPhone 17 / iOS 26.5, final build (`OCRCorrectionUITests`) | `testACorrectedWordIsSavedAndFindAnswersIt` and `testCancellingAfterAChangeAsksAndSavesNothing` **pass** — the first in 508 s, 403 of them launching the app while this Mac's load average was over 100 from several sessions' runs. `testTheEditorInFrenchAndSpanish` was stopped by my own time limit before it finished (no verdict) and re-run alone: **passed** (150 s). Every test in both suites has now passed on the final build on iPhone and iPad. |
| **Follow-up, same day** — new `OCRCorrectionModelTests` (3 tests, `Tests/PaperNestUITests`) | **3/3 pass.** (1) One `DocumentFind` indexes the page, finds "Invocie", the page is corrected, the same instance indexes again: "Invocie" is gone and "Invoice" found. **Checked that it bites:** with `bumpRevision` taken out of `applyRecognitionCorrection` (temporarily, then restored from `HEAD`), it fails on both expectations — find's cache would keep answering the misread word for as long as the document stays open. (2) The panel's account of a page — none, failed, recognized, corrected, own text — and `correctedPageCount`, which drives the "recognizing again replaces it" note. (3) Undo and redo of a correction through `DocumentModel` and a real `UndoManager`, and `historyRevision` moving when it is registered. |
| Follow-up fix: `registerRecognitionUndo` now calls `historyDidChange()` | The correction's undo is registered from a Task, which the undo manager's notifications do not cover; without it the Undo buttons kept showing the state from before the correction (the same fault `historyRevision` exists for with ink). Found in review, not seen in the app; test (3) pins it. |
| Follow-up: `./scripts/test.sh`, clean worktree (`733fbc7` + the follow-up) | **1,186 tests, 0 failures, 0 warnings** (355 + 49 + 205 + 210 + 196 + 171). |
| Follow-up: `testACorrectedWordIsSavedAndFindAnswersIt`, iPhone 17 / iOS 26.5 | **Pass** (100 s), now also asserting that after Save the panel shows the warning that recognizing the page again replaces the correction (`ocr-replaces-corrections`). Run on iPhone only; the iPad run above is of the build before this assertion. |

**Not verified:** the Undo and Redo buttons pressed in the running app (undo and redo through the document model and a real `UndoManager` are tested, and the buttons are now told — see the follow-up rows); the Mac editor on screen (built only); dark mode, accessibility text sizes and VoiceOver in the editor; a real Vision result being corrected (the UI tests seed a result so the words are known). **Limitations:** corrections stay on the device where they were made — recognition is not synced; Recognize Text chosen by hand replaces them (said in the panel); the editor works on one page at a time and cannot add a line that recognition missed; correction is not a Pro feature (`ProFeature`, the owner-approved list, was not changed).

## 2026-11-16 — Word export's second layout: page images in a .docx (Claude, roadmap item 1 / 7)

Owner in session: implement the next unblocked slice of `docs/FEATURE_ROADMAP_CLAUDE_CODE.md`. The brief asks for two clearly named Word options, editable text and appearance-preserving page images; only editable text existed. Word now has **Editable Text** (unchanged, still the default, so Convert opens on it) and **Page Images**: each page drawn as a JPEG export draws it (ink, marks, the source's paper annotations) and placed alone on a Word page of its own size, or fitted on Letter/A4. It needs no text, so a blank or handwritten notebook exports; it writes no words and never says it does. **Also fixed:** Copy was disabled for every multi-page TXT or Word export, because the sheet took any non-PDF of several pages for a ZIP; the sheet now asks the engine (`ExportOptions.writesArchive`). Design: `docs/ARCHITECTURE.md` → Rendering.

| Check | Result |
|---|---|
| New `DocxPageImagesTests` (16 tests, 21 cases) and `RestrictedPDFExportTests.itsPagesCannotLeaveAsPicturesInAWordFile` | **Pass.** A blank notebook is refused as editable text and exported as page images; the picture layout holds no `<w:t>`; with `unzip` as the reader, every `r:embed` resolves through `word/_rels`, every target is in the archive, every part has a content type, `docPr` ids are unique and every part is well-formed; one section per page and no page-break paragraph; a portrait page is 12240 × 15840 twips and a turned one 15840 × 12240 landscape, each picture exactly its page; a cropped page is the size of what is left; a 300 × 1200 receipt on Letter fills the height, is centred, not stretched; margins plus picture make up the page for six sizes, none over 22 inches; a 3000 × 2000 page is shrunk to 31680 × 21120; the picture is JPEG, 1275 × 1650 at 150 dpi, orientation marker top-left; a drawn ink stroke is in it; a password is refused; cancelling at page 2 leaves nothing; `keepsOnlyWords` and `writesArchive` for each format and layout; three pages with ZIP chosen are one `.docx`. |
| First runs of the new suite | Failed on my test code, not the writer: a regex helper force-unwrapped an optional group (crash), then the content-type check read `.rels` as having no extension (NSString's view; the packaging spec reads "rels"). **The crash left eight empty `PaperNestExport-*` folders in the system temporary directory**, which made `BulkExportTests.cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind` fail three runs in a row on its own. Removed them (all created at 18:16 by that run); the suite now exports into its fixture's own folder so a stopped run cannot do that again. |
| `./scripts/test.sh`, clean worktree (`f913696` + this slice only) | **1,169 tests, 0 failures, 0 warnings** (352 + 49 + 191 + 210 + 196 + 171). |
| `LocalizationTests` | Pass, after one fix: French wants U+202F before a colon; the first draft had a plain space. |
| `xcodebuild build-for-testing`, `PaperNest-iOS`, iOS Simulator | Succeeded, no compiler warnings. |
| `./scripts/build-mac-app.sh` | Succeeded, 0 warnings. The Mac sheet was **built, not seen**. |
| New `WordExportUITests`, iPhone 17 / iOS 26.5 | **3/3 pass** with the final test: page images exports the two-page blank notebook (Copy enabled, "Copied"), editable text says "None of these pages carry any text" (Copy enabled), French and Spanish tiles both reachable. `DocumentUtilitiesUITests.testProcessToolsDoRealWork` (Convert opens Word on editable text) passed with the first version. |
| New `WordExportUITests`, iPad Air 13-inch (M4) / iOS 26.5 | First run: `testProcessToolsDoRealWork` and the editable-text test passed; the page-images test failed looking for "200 dpi" — it swiped the app, which on iPad scrolls the page beside the export panel — and with `continueAfterFailure = false` in an async test the runner then sat idle in tear-down for eight minutes until I stopped it. Test fixed (it scrolls the export form; no `continueAfterFailure = false`). **Final run 3/3 pass**; iPhone re-run 3/3 with the same final test. |
| Screenshots (`/tmp/pn-word-export-shots/`) | Looked at: iPhone 393-pt French page images and Spanish editable text — tiles side by side, note wraps, the three ways out visible; iPad English options — paper size, resolution and JPEG quality under the note. Dark mode, accessibility text sizes and VoiceOver not looked at. |
| Quick Look (`qlmanage -t`, `qlmanage -p`) on engine exports: a portrait text page, the same document's turned page and a lined notebook page with ink, at original size and on Letter | Three pictures in page order at 612 × 792, 792 × 612 and 300 × 500 (475 × 792 on Letter); the first page's thumbnail shows the marker upright and the text; the note's picture shows its lines and ink. A prototype with the pictures floating (anchored to the page) was rendered out of order and stacked by Quick Look, which is why the writer uses inline pictures. |
| Microsoft Word | **Not run**: not installed on this Mac. |
| Pages | **Blocked**: driven by AppleScript, opening the file hung both times (120 s) once automation access was allowed — probably a dialog in Pages that could not be seen from here. Not seen in Pages. |
| `textutil -convert html` | Not a check: it dropped a prototype's pictures entirely. |

**Not verified:** Word and Pages; that Word shows no blank page between pages (the structure is built for it — one section per page, no page-break paragraph, a 1-point paragraph mark — but only Quick Look has read it); the new tiles in dark mode and at accessibility sizes; the Mac sheet on screen. **Deviation:** the two layout tiles have identifiers and the selected trait but no `accessibilityValue`, like every `ChoiceTile` in the sheet; changing `ChoiceTile` would change what VoiceOver reads on every tile, so it is left for Codex's accessibility pass. **Limitations:** pictures are JPEG at the chosen dpi; they carry no alt text (each has its file name only) and the layout has no text layer; Word export in either layout stays Pro, as before.

## 2026-11-16 16:29 CST — Whole-commit check of `6a09a67` after Codex committed its UI work (Claude)

Owner: "codex has committed everything". Checked `6a09a67` (Codex's OCR, document tools and Home commit on top of
`bb2a3d0`) in a clean detached worktree outside iCloud. The working tree was clean, so this is everything committed
and nothing else.

- `./scripts/test.sh`: **1,152 passed, 0 failed, 0 warnings** (1,148 at `bb2a3d0`, plus Codex's four
  `OCRPanelTests`). `PrivacyManifestTests` passes, so nothing in the new UI code calls an undeclared required-reason API.
- `xcodebuild` `PaperNest-iOS` (generic iOS Simulator) and `PaperNest-macOS`, `CODE_SIGNING_ALLOWED=NO`: **both
  succeeded, 0 warnings.**

**Not run:** no iOS UI tests (XCUITest), no simulator or device interaction, no Mac interaction, no signed or archived
build. Still open from Codex's own records: the native color picker does not open on iPad iOS 27, and the iPhone
French XXXL scanner-settings run was blocked by the simulator. Not addressed by this commit: on a 393-point iPhone the
scanner's page-tool row runs past the screen, and `testReviewEditsSaveAndReopen` fails on the iPhone Duo.

The commit also adds three screenshots from the owner's Desktop that are not referenced anywhere: one in the
repository root and two in a folder named `changes ` (with a trailing space). `origin` is public, and the branch is
not pushed.

## 2026-11-16 — Privacy manifest declares system boot time; a test keeps it complete (Claude, owner in session)
Found while answering the owner's "is PaperNest ready to deploy?": `ProcessInfo.systemUptime` is called in
`ScannerCamera.swift` (how long the outline has held still before the automatic shutter fires) and in
`NotebookScrollAppend.swift` (whether a Mac scroll followed a wheel event within 0.25 s), and
`Apps/Shared/PrivacyInfo.xcprivacy` did not declare `NSPrivacyAccessedAPICategorySystemBootTime`. App Store Connect
rejects such an upload (ITMS-91053); nothing fails before that. Added the category with reason **35F9.1** (time
elapsed between events within the app). The other categories the source uses were already declared: file timestamps
only in `AssetFileStore`'s own container (C617.1), `UserDefaults` only the app's own defaults with no shared suite
(CA92.1). No disk-space or active-keyboard API is called.

New `Tests/PaperNestUITests/PrivacyManifestTests.swift` (2 tests) reads every Swift file under `Sources`,
`Apps/iOS/Sources` and `Apps/Mac/Sources` for Apple's required-reason symbols and fails, naming the files, for any
category the manifest gives no reason for; a second test fails if the scan reads nothing. **Shown to fail first:**
on `HEAD` with the old manifest it failed naming exactly those two files; it passed after the manifest change.

Clean worktree at `b17eb70` outside iCloud, plus these three files:
- `./scripts/test.sh`: **1,148 passed, 0 failed, 0 warnings** (1,146 before, plus the two new tests).
- `plutil -lint Apps/Shared/PrivacyInfo.xcprivacy`: OK.
- `xcodebuild` `PaperNest-iOS` (generic iOS Simulator) and `PaperNest-macOS`, `CODE_SIGNING_ALLOWED=NO`: **both
  succeeded, 0 warnings**. `plutil -p` on the `PrivacyInfo.xcprivacy` inside each built `PaperNest.app` shows the
  SystemBootTime entry with 35F9.1.

**Not done:** no archive and no App Store Connect upload, so Apple's own check of the manifest has not run. The test
covers Apple's list as of today and cannot pick reasons; additions to the list need adding to the test. Frameworks
from Apple are not scanned (they carry their own manifests); there are no third-party dependencies.

## 2026-11-16 16:17 CST — French XXXL phone verification blocked by test infrastructure (Codex heartbeat)

Usage56% allowed; brief/claims/latest matrix/staging checked, no concurrent build. Existing French XXXL Scan settings test targeted iPhone17 Pro/iOS26.5 (`63992C10-33B4-4CE3-91C3-EE23ECC595A5`), focused rebuild/test, parallel testing off, signing disabled,240s process-group bound. **Timed out exit124**. Runner reported XCTDaemonErrorDomain Code18, “Timed out waiting for AX loaded notification”, before test initialization. No app-flow verdict. `/private/tmp/pn-fr-scanner-phone.log`; result `Test-PaperNest-iOS-2026.11.16_16-12-50--0600.xcresult` in default DerivedData. Initial wrapper invocation exited2 because `/private/tmp/papernest-bounded.py` had been removed; recreated wrapper then ran the one bounded attempt above.

No source edits or new tests. Phone check remains pending; next check should restore healthy simulator accessibility/test startup before retrying, without treating this as a scanner failure. French iPad pass remains prior evidence only. No staging/commits, other work preserved, Vault/VPN deferred.

## 2026-11-16 14:50 CST — French XXXL Scan settings remains reachable and dismissible (Codex heartbeat)

Usage55% allowed. Read Phase3 release and current claims; no staged paths or competing builds. Added `testFrenchLargestTextScanSettingsRemainDismissible` to ScannerWorkspaceUITests.swift, pinning all scanner defaults and using a synthetic pending capture and disposable UUID library. No product edits.

**1 passed23.606s,exit0**, iPad Pro13 M5/iOS26.5 (`046CA563-2BFA-4051-9804-3D17C8E41FF6`), focused rebuild/test bounded240s, signing disabled and parallel testing off. `/private/tmp/pn-fr-scanner-settings.log`. French + accessibilityXXXL: Keep capture, More, French Scan settings, scroll Auto capture fully above Done, tap Done, return to capture screen. Test changes no stored preferences.

Viewed retained screenshot `french-XXXL-scan-settings`, exported `/private/tmp/pn-fr-settings-evidence/24F2292A-63B3-409D-9C45-63E5EFE27FC2.png`: long French toggle label wraps without ellipsis, switch is visible, Terminé remains fully visible at bottom. This checks reachability/dismissal only; not a full contrast/VoiceOver audit, not settings persistence, not camera capture (simulator shows unavailable-camera message behind sheet). Scrolling text is visible beneath translucent navigation title; visual refinement remains possible. Spanish/phone/other scanner surfaces remain pending.

Claims released; no staging/commits, other work preserved. Vault/VPN deferred.

## 2026-11-16 — Scan Studio Phase 3: Whiteboard and ID / Card are modes that do something, and the scanner has defaults (Claude, owner in session)

Owner: "Start Phase 3", after Phases 1 and 2 landed as `c42ce81`. Design: `docs/design/SCAN_FEATURES_DESIGN.md`, sections
1, 2 and 8. How it works: `docs/ARCHITECTURE.md` → Rendering, "What the scanner looks for depends on its mode".

**What works now.** The capture screen offers four modes in one pill: Document, Whiteboard, Photo, ID / Card. The two
chips that said Coming soon are gone, with their string.

- **Whiteboard** looks for the largest rectangle in view, allows corners further from square, and accepts a board much
  wider than it is tall. The capture starts as High Contrast with its lighting evened out (Cleanup 100/60/20); Reset
  still gives back the capture as taken.
- **ID / Card** looks for a small rectangle of a card's proportions. A kept capture is a front, and its back is offered:
  "Scan back" makes the next capture that front's back, placed straight after it; "Continue", or simply taking another
  picture, leaves the front on its own. The capture screen says which side comes next, and in review each page says
  Front or Back. The sides are two pages, edited and deleted separately.
- **Scan settings**, in More: the mode the scanner opens in, the filter a new Document or Card capture starts with,
  and whether the automatic shutter is on when it opens. They are three preferences, never the library, and change
  nothing about the mode in use or the pages already scanned.
- The live outline and the crop of the still now come from one rule (`ScanEdgeDetector`). Document mode asks the
  detector exactly what it asked before.

**Unit tests (Mac, `./scripts/test.sh`).** Shared tree: **1,150 passed, 0 failed, 0 warnings**, 32 of them new here.
This commit alone, in a clean worktree outside iCloud, on the final source: **1,146 passed, 0 failed, 0 warnings**
(four fewer: Codex's uncommitted OCR panel tests are not in it).

- `ScanCaptureModeTests` 10, `ScanCardPairingTests` 9, `ScanSettingsTests` 4 (`PaperNestCoreTests`): a quad's area and
  its proportions in a picture that is not square; which of several quads each mode takes; a shape outside a mode's
  range is not taken; each mode's starting look; the front, the offer, Scan back, Continue, a second capture without
  answering, a back deleted before it is kept, either side deleted, the mode left with a question up; stored values
  that are missing or unknown.
- `ScanEdgeDetectorTests` 5 (`PaperNestImportTests`), each mode's request put to the real rectangle detector on
  scenes drawn here: a sheet on a desk is found to within 3% of the picture at every corner; Whiteboard takes the
  whole board and not the sheet pinned to it; a board seen from the side is found; Card takes the card and not the
  sheet of paper beside it; an empty frame gives nothing in any mode.
- `ScanSettingsStoreTests` 4 (`PaperNestUITests`), on preferences of their own. Written after the eight lines they
  test, so they were then shown to fail: with the stored filter ignored, two of the four fail.

**What the modes change, measured.** A throwaway probe put each mode's request to each scene. A board whose short
side is 0.47 of its long side with a sheet pinned to it: Document finds only the sheet (the board is outside the
detector's own range of shapes), Whiteboard finds both and takes the board, Card finds nothing. A card beside a
sheet of paper: Document and Whiteboard take the sheet, Card finds both and takes the card. A board seen from the
side: Document finds nothing, Whiteboard finds it. The Whiteboard look was chosen by eye on a drawn board with a
glare, a shadow and four marker colours: High Contrast alone keeps the glare and the shadow; with the lighting
evened out the board comes out white and the colours stay.

**iOS unit tests (`xcodebuild test -scheme PaperNest-Canvas`, iPhone 17, iOS 26.5).** `ScannerPageTests` **13 passed,
0 failed**: the eleven from Phase 1, a still with nothing to crop to keeps its whole frame in every mode, and a card
in a still is cropped to in Card mode by the simulator's own detector.

**iOS UI tests (`ScannerWorkspaceUITests`, ten tests, the script's `xcodebuild test` line run directly), on the final
source, from the clean worktree: this commit alone.**

| Simulator | Result |
|---|---|
| **iPad Air 13-inch (M4), iOS 27.0** | **10 passed, 0 failed**, 398 s. The settings test passed again alone with its last change, 84 s. |
| **iPhone 17, iOS 26.5** | **All 10 passed, over two runs.** The full run: 9 passed, 358 s, and the settings test failed in its own tap, because the Auto capture switch lay under the Done bar; the test now scrolls it clear. That test alone, afterwards: passed, 82 s. No product source changed between the two. |
| **PaperNest iPhone Duo, iOS 27.1** | **9 passed, 1 failed**, 431 s. The failure is `testReviewEditsSaveAndReopen` at its first layout check (Save's top at 12 points against the 44 the test assumes), which fails the same way at `55f163e`, before any of this work. A screenshot from this run shows why: that device's status area is down its right-hand side, not across its top. The settings test passed again alone with its last change, 103 s. |

The three new tests: `testWhiteboardModeFindsTheBoardAndStartsWithItsLook` (four modes offered and nothing says Coming
soon; the same wide board is kept whole by Document and cropped to by Whiteboard, corners read from the crop tool;
the capture starts as highContrast with Cleanup 100/60/20; Reset removes it), `testCardModeAsksForTheBackAndNamesBothSides`
(Front, the offer, Scan back, Back, the next card, Continue, the question withdrawn on leaving the mode, five pages
named in review with the back after its front, the crop on the card, the front deleted and the back still named) and
`testScanSettingsDecideHowTheScannerOpensNextTime` (set, relaunched, the scanner opens in Card with Auto on and a new
capture starts Grayscale while the page already there keeps its look; then put back and relaunched again).
**Every other scanner test now pins the three defaults with launch arguments**, so a default left stored on a
simulator cannot change how they open; the settings test is the one that does not, and it restores them.

**Two faults the UI tests found in the settings sheet, both about a short sheet.** (1) On iPad the Auto capture switch
could not be found: the list makes its rows as they come into view and the sheet is shorter than the list, so the
last row does not exist until it is scrolled to. The test scrolls now; **on iPad the third setting is below the
fold**, which is Codex's to judge. (2) On the Duo, once the list had scrolled, Done could not be found: a screenshot
shows the sheet's top bar gone, title and Done with it. **Under iOS 27.1 on that short screen an inline navigation
bar and everything in it disappears when the list under it scrolls.** Done is in a fixed bar at the bottom of the
sheet now, and the test passes on all three. The Cleanup sheet keeps Cancel and Recommended in its top bar; its
scrolling part is not the bar's own scroll view and its tests pass on the Duo, but it was not scrolled there.

**Runs that failed on the way.** The settings test on iPad (1 of 10) and on the Duo (the same, with the older
failure: 2 of 10) before fix (1); on the Duo again before fix (2); and on iPhone 17 after fix (2), where the
switch was in the list but under the new Done bar and the test's tap landed on the bar. One `xcodebuild test` in the shared tree sat for
twenty minutes at 0% CPU with `Config/Signing.local.xcconfig` open and was stopped: see iCloud, below.

**Builds.** `./scripts/build-ios-sim-app.sh` and `./scripts/build-mac-app.sh` in the shared tree before the last change to
the settings sheet: both built, no warnings. After it, the app was built for the Simulator from the worktree by the
UI runs above; the shared tree was not built again, because it could not be read reliably.

**What the worktree is.** `c42ce81` plus this slice, with `Localization.swift` and the three strings files as `c42ce81`
less the Coming soon key plus this slice's block. The commit was made from it, so what was tested is what was committed.

**iCloud evicted this checkout twice during the work, and that is why the last runs are from the worktree.** The disk
was 97% full (12 to 15 GB free of 460). When work resumed after the app was quit, 571 files of the checkout were
evicted, 159 of them inside `.git` and eight of them this slice's uncommitted files; `git status` sat for minutes in
`read()` on an evicted test file. They were read back (92 s for code, tests and `.git`) and forty minutes later 575
were evicted again, git's pack files among them; this time one read of an evicted source file did not return in ten
minutes and a build froze. Nothing was lost: every file of the slice was compared byte for byte with the worktree's
copy, which is in `~/Library/Caches` and never evicted. `brctl download` on the evicted files brought `.git` back in
under a minute when plain reads had stalled. **Until this checkout is out of an iCloud-synced folder, kept
downloaded, or the disk has room, any session can meet the same stall.** `ls -lO` shows `dataless` on an evicted
file; `git -c core.trustctime=false status` avoids reading files that were only evicted.

**Not run, and not verified.**

- **No camera, no board, no card.** Every scene was drawn. Whether the live outline settles on a real whiteboard or a
  real card, how the automatic shutter behaves in those modes, and what the board look does to a real board under
  real light are all unknown. The live path (`ScannerCamera.captureOutput`) was compiled and never run: the
  Simulator has no camera, and the UI tests deliver a still through the same code a camera still takes.
- **No device.** Nothing was installed on the iPad or an iPhone.
- **French and Spanish were not looked at**, nor accessibility text sizes. The mode pill is built to scroll when four
  names do not fit, and that was not seen happening. Both are Codex's to see.
- VoiceOver was not used. The rest of the iOS UI suites, `scripts/ui-test-ios.sh` whole and
  `./scripts/test.sh --sanitize=thread` were not run.

**Not built** (design sections in brackets): the Move closer / Hold steady / Ready labels [3]; the camera orientation
hint [2]; the destination row before Save [9]; Cleanup as an inline inspector on iPad [6]. A card's two sides are
two pages named Front and Back; they are not put on one sheet and they do not move or delete as one.

**Known limits.** The default filter applies to Document and Card captures made with this camera, not to pictures
imported from Photos or pages from the system scanner. In Card mode a sheet of paper alone in view is close enough
to a card's shape to be taken. A board whose short side is under 0.3 of its long side is outside Whiteboard's range.

## 2026-11-16 09:08 CST — Shape save failure preserves draft and retries successfully (Codex heartbeat)

Usage55% allowed; brief/latest claims/staging checked. Claude ACTIVE scanner Phase3 respected; no Scanner files edited. Updated only stale setup in `testShapeSaveFailureKeepsDraftAndCanRetry` to create through Notes instead of removed Home Tools and obsolete toolbar assertion. Test change retained; no product changes.

**1 passed34.462s,exit0**, focused rebuilt iPad Pro13 M5/iOS26.5 test (`046CA563-2BFA-4051-9804-3D17C8E41FF6`), UUID disposable library,240s bound, parallel testing off, signing disabled. `/private/tmp/pn-save-retry26.log`. Real second SQLite connection holds BEGIN IMMEDIATE, save shows the expected failure message, dismissing alert keeps the selected ellipse draft, releasing lock allows retry, sheet closes and exactly one markup row appears. Retained screenshot shape-save-failure. This covers database-write contention UI, not every disk/I/O failure or device/runtime.

No commits/staging. iOS27 native color activation remains separately unresolved. Other app-verification backlog and native Mac/device checks remain; Vault/VPN deferred. No new UI feature selected.

## 2026-11-16 08:11 CST — Full XXXL Shape slider/custom-color/save flow passes on iPad26.5 (Codex heartbeat)

Usage55% allowed; brief/current claims/latest results and staging checked. Retained a focused test correction in AppUITests.swift: activate the native well below its wrapped XXXL label and wait for the actual color grid instead of requiring an absent Close accessibility button. No product changes.

**1 passed104.647s,exit0** on iPad Pro13 M5/iOS26.5 (`046CA563-2BFA-4051-9804-3D17C8E41FF6`), focused rebuild/test,240s bound, parallel testing off, signing disabled. `/private/tmp/pn-full-shape26.log`; default DerivedData result `Test-PaperNest-iOS-2026.11.16_08-08-13--0600.xcresult`. Real Notes creation at accessibilityXXXL, Shape position slider value change, width4 selection, native azure77 choice, popover dismissal, changed color label, Add, and saved markup-row appearance all pass. Retained screenshots cover position, width and native picker.

After app termination, read-only SQLite inspection of this run's disposable library `/private/tmp/papernest-accessibility-ui-C672EB49-3045-4231-9767-87221A5E9023` confirms one ink shape: width4 and color(red0.6548919677734375,green0.776458740234375,blue1,alpha1), with edited endpoints. This is stored-state evidence, not merely a changed swatch. Not a relaunch/persistence UI test.

iOS27 native activation remains separately unresolved and reproduces with a minimal native picker outside Shape; do not mark27 passed or rewrite product sheets speculatively. No staging/commits, other work preserved, Vault/VPN deferred. Minimal diagnostic routes are absent; current build is the actual app. Next verification can target another outstanding app flow while retaining the separate27 investigation.

## 2026-11-16 07:09 CST — Bound color changes on iOS26.5; minimal activation still fails on iOS27 (Codex heartbeat)

Usage54% allowed; brief/current claims/latest matrix and empty staging checked. Temporary isolated native picker exposed its bound SwiftUI Color description via a separate Text, instead of relying on the native well's coarse color-name value. No Shape, document or Form in diagnostic route. Disposable UUID libraries; focused rebuilt tests bounded240s each, parallel testing off, signing disabled.

- iPad Pro13 M5/iOS26.5 (`046CA563-2BFA-4051-9804-3D17C8E41FF6`): **1 passed10.418s,exit0**. Native picker opened, azure77 selected, popover dismissed and actual bound Color description changed. Screenshot retained as bound-state-after-selection. `/private/tmp/pn-bound-color26.log`; result `Test-PaperNest-iOS-2026.11.16_07-05-57--0600.xcresult`. Confirms earlier azure==azure AX-name assertion was too coarse for state verification.
- Same diagnostic on iPad Pro13 M5/iOS27 (`6528AE8B-27E3-44B5-9348-B654556BE3F9`): **1 failed18.204s,exit65**, waiting azure77; no color selection reached. `/private/tmp/pn-bound-color27.log`.

Both temporary RootView wrapper and test restored exactly; no retained source edits/staging/commits. Last compiled bundle is diagnostic; rebuild before normal verification. Comparison supports an iOS27 simulator/native-activation issue outside Shape, not a proven PaperNest sheet bug. Next complete real Shape slider/color/save verification on iOS26.5 with picker-presence and persisted state assertions; track iOS27 activation as a separate runtime-specific investigation instead of speculative product rewrites. Largest-text flow and persistence are not covered by this minimal pass. Vault/VPN deferred, other work preserved.

## 2026-11-16 06:03 CST — Minimal native picker comparison isolates failure beyond Shape (Codex heartbeat)

Usage54% allowed; brief/claims/latest matrix and staging checked. Claimed temporary RootView body wrapper and existing shape-test substitution; both restored exactly, preserving all prior edits. Diagnostic launch rendered only a labelsHidden SwiftUI ColorPicker bound to local Color.blue; no Shape sheet, document, Form, or notebook UI. UUID disposable library. No competing build at comparison start.

- iPad Pro13 M5/iOS27 (`6528AE8B-27E3-44B5-9348-B654556BE3F9`): **1 failed17.442s,exit65**. Center tap on visible36x36 native control; azure77 never appears. Failure hierarchy shows only native Diagnostic color button, value azure. `/private/tmp/pn-minimal-color.log`.
- iPad Pro13 M5/iOS26.5 (`046CA563-2BFA-4051-9804-3D17C8E41FF6`): **1 failed11.886s,exit65**, but **picker opened, azure77 existed and was tapped, popover dismissed successfully**. Only final AX-value inequality failed: native color label stayed azure (initial blue and chosen shade share this coarse label). `/private/tmp/pn-minimal-color26.log`. This is not proof the bound color failed to change; diagnostic must expose actual bound RGB/state to test it.

Both focused rebuilt tests bounded240s, parallel testing off, signing disabled. This comparison shows the observed iOS27 activation failure reproduces without Shape integration; avoid speculative product-sheet rewrites. It does not establish an OS bug (simulator/test delivery still possible). Next expose bound color state in isolated diagnostic and compare native activation on runtimes; native AX color-name inequality alone is insufficient. Prior missing-Close assertion also remains invalid on some iPad popovers.

No diagnostic route/test remains in source. Last built app/test contain temporary route, so rebuild before normal testing. No staging/commits; scanner/other work preserved, Vault/VPN deferred. Original large-text/save flow remains unverified.

## 2026-11-16 05:01 CST — Retained app diagnostics do not identify picker presentation failure (Codex heartbeat)

Usage54% allowed; brief/current claims/latest matrix and empty staging reviewed. Exported diagnostics from `Test-PaperNest-iOS-2026.11.16_03-58-36--0600.xcresult` to `/private/tmp/pn-presentation-diagnostics` with xcresulttool (exit0). Read the captured application stdout/stderr (98,177 lines); searched for UIColorPicker, already-presenting, attempt-to-present, not-in-window, and presentation failure/error messages: **zero matches**. AX replies remain responsive and the azure77 query returns no matches. Absence of these diagnostics does not rule out a presentation or event-delivery issue.

No new UI test or source change this turn; retained previous failure remains unresolved. Next actionable experiment remains minimal native ColorPicker outside Shape, with a disposable launch route and actual native-picker existence assertions; retain no diagnostic route in product. No more unchanged coordinate/duration retries. No staging/commits; other sessions' work preserved; Vault/VPN deferred.

## 2026-11-16 04:01 CST — Longer native-well press does not resolve activation (Codex heartbeat)

Usage53% allowed; brief/claims/latest results and empty staging checked. Temporary standard-text picker-only diagnostic used a retained before-tap screenshot and a 0.15-second press at the trailing well, with actual azure77 presence instead of Close. Focused rebuild/test on iPad Pro13 M5/iOS27, disposable library,240s bound, parallel testing off and signing disabled: **1 failed50.448s,exit65** waiting for azure77. `/private/tmp/pn-well-duration.log`. Longer contact did not resolve this failing activation; no successful color selection/save claimed. Failure includes full hierarchy for subsequent inspection. This single test does not isolate timing from screenshot overhead.

Restored entire test exactly to pre-turn contents; no retained source/product edits, staging or commits. Avoid more coordinate/duration retries. Next useful isolation is a minimal native ColorPicker presentation comparison outside the current Shape sheet, or presentation diagnostics from this run, to distinguish native control/test infrastructure from sheet integration. No new UI feature selected while this verification remains open. Other sessions' work and scanner preserved; Vault/VPN deferred. Last compiled bundle is temporary diagnostic; rebuild for normal tests.

## 2026-11-16 03:05 CST — Failed picker activation confirmed in recording and event (Codex heartbeat)

Usage53% allowed; brief/current claims/latest evidence read, staging empty. Read-only inspection of retained `Test-PaperNest-iOS-2026.11.16_02-06-21--0600.xcresult`, attachments exported to `/private/tmp/pn-grid-evidence`. No new test run or source changes.

Viewed recording frame36s (`/private/tmp/pn-grid36.png`, recording duration37.65s): Shape is still open with visible native color well at roughly(760,934.5) points; no native picker. Failure hierarchy `AC358126-F09F-450C-99CC-0A38E2F6A5E6.txt` likewise contains Custom Color at(258,920.5,516,28) but no Grid/Spectrum/Sliders picker. Parsed synthesized tap attachment `575627E4-99FE-4545-92A5-35C8416AF517` (binary plist): down/up both at(761.1,934.5). Therefore this failed run really did target the visible well, not the label center; missing azure77 was not merely a wrong query for an open picker. This does not prove delivery to the control or a product bug. Earlier run still proves the picker can open without Close.

Next isolate the control's activation/presentation timing or inspect app presentation logs, with explicit before/after snapshots and actual picker-presence assertions; do not repeat the same geometry-only diagnostic. Color selection/save remains unverified. No commits/staging; scanner and other sessions' work preserved; Vault/VPN deferred.

## 2026-11-16 02:09 CST — Native picker can open without a Close accessibility button (Codex heartbeat)

Usage allowed53%; brief/claims/latest matrix reviewed; staging empty and no competing build at start. Claimed only existing shape-test diagnostics and these notes; no product/scanner changes.

Standard-text picker-only diagnostic on iPad Pro13 M5/iOS27 (`6528AE8B-27E3-44B5-9348-B654556BE3F9`), tapping trailing native well at normalized(0.975,0.5): **1 failed48.050s,exit65** at expected Close. Crucially, failure AX **does contain native picker**: popover(345,643.5,401,582.5), Grid/Spectrum/Sliders, Color Spectrum and `azure 77`. No Close button is exposed. `/private/tmp/pn-standard-well.log`. Thus the previous Close assertion alone is not a reliable presentation check; native picker can open in this app on this simulator. Does not establish successful color selection/save.

Follow-up diagnostic removed only Close assertion and waited for `azure 77`: **1 failed43.207s,exit65**, color query did not appear within5s. `/private/tmp/pn-standard-well-grid.log`. Both runs bounded240s, rebuilt, disposable libraries, parallel testing off, signing disabled. No root cause inferred for second failed activation; targeted well interaction is not yet repeatable. Next inspect second-run video/popover hierarchy before retaining any test change; use actual picker presence rather than Close as success criterion.

Restored entire diagnostic test to its exact pre-turn contents (XXXL launch, slider/width checks, original tap and assertions). No retained source edits, staging or commits. Last built bundle is diagnostic; rebuild before normal testing. Largest-text native picker, color selection/persistence and remaining platform checks still open; Vault/VPN deferred.

## 2026-11-16 01:02 CST — Standard-text native color picker diagnostic (Codex heartbeat)

Usage allowed (52% used); current claims and empty staging checked. Temporary diagnostics only in the existing shape test, all restored afterward; no product edits or commits. iPad Pro 13-inch M5, iOS27, 6528AE8B-27E3-44B5-9348-B654556BE3F9, disposable library.

- Warm build/test with standard text: **1 failed,95.233s,exit65**, bounded240s. Notebook creation and position slider reached, but the large-text-specific `Line width` StaticText query had no match at standard size. `/private/tmp/pn-standard-color-warm.log`. This was a test-query failure before the picker, not a product verdict.
- Removed only position/width actions temporarily to isolate picker: **1 failed,43.436s,exit65**, bounded180s. Custom Color exists, passes viewport/hittability, is tapped at35.01s; native Close never appears. AX still shows Custom Color (258,920.5,516,28), value dark blue. `/private/tmp/pn-standard-picker-only.log`; result `Test-PaperNest-iOS-2026.11.16_00-59-33--0600.xcresult` in default DerivedData. Second build began while first run was finishing result cleanup; first had already reported its assertion failure, so avoid attributing any timing to product behavior.

The same Close assertion fails at standard text, but a label-center tap may still miss the native well; this does not establish a product defect or explain the previous XXXL well-targeted failure. Next isolate native well activation at standard size and inspect presentation evidence. No additional unchanged retries. Original XXXL launch and slider/width assertions restored exactly; last built test bundle remains the temporary standard-text picker-only diagnostic, so rebuild before normal verification. Scanner work untouched; Vault/VPN remain deferred.

## 2026-11-16 00:05 CST — Standard-text color-picker isolation interrupted during app launch (Codex heartbeat)

Usage allowed (52% used); reviewed brief, latest claims and staged paths (none). Claude released Scan Studio functionality; preserved it and all unrelated edits.

Temporarily changed only the existing shape-slider/color-picker test launch to standard text on iPad Pro 13-inch M5 / iOS 27 (`6528AE8B-27E3-44B5-9348-B654556BE3F9`). Rebuilt with focused `xcodebuild test`, parallel testing disabled, code signing disabled, 240-second process-group bound. **Timed out, exit124**. `/private/tmp/pn-standard-color.log` initially stalled at build settings, then built and started the test. At the timeout boundary app launch reported NSMachErrorDomain -308, “server died”; this may be a consequence of process-group termination. No picker verdict. Do not treat that launch error as a separately proven product fault.

Restored original accessibilityXXXL launch arguments exactly. No retained source changes, staging or commits this turn. Standard-text isolation remains pending; next check should account for the cold build/startup time before another bounded UI run. Previous well-tap failure remains unresolved, not a confirmed product defect.

## 2026-11-15 — Scan Studio: presets and Cleanup change the page, and several pages can be edited together (Claude, owner in session)

Owner: "Codex is designing and implementing additional scanning features, you have to implement functionality", then
Codex's written brief: make the preset strip, the Cleanup sheet and the batch toolbar it had laid out as a shell do
what they say (Phase 1), then the batch page actions (Phase 2); Whiteboard and ID/Card stay marked Coming soon.
Design: `docs/design/SCAN_FEATURES_DESIGN.md`. What was built and how it works: `docs/ARCHITECTURE.md` → Rendering.

**What works now.** Each page of a scan being reviewed has one preset (Original, Auto, Enhanced, Grayscale,
Black & White, High Contrast) and three Cleanup amounts (Remove shadows, Whiten background, Sharpen text). They are
drawn each time the page is shown or saved and never into the capture, so Reset and Original still give back what
the camera took. The strip, the Filter menu and Enhance all show and set the page's one preset. Cleanup opens on the
page's own amounts, shows Before and After on a picture of the page, and changes only what the button pressed says:
this page, all pages, or the picked pages. Select pages picks pages in the filmstrip; the bar then filters, cleans
up, duplicates, moves as one block, or deletes them, asking first only when more than one page would go.

**Unit tests (Mac, `./scripts/test.sh`, shared tree).** **1,118 passed, 0 failed, 0 warnings**, 37 of them new here.

- `ScanAppearanceTests` 6 and `ScanPageBatchTests` 14 (`PaperNestCoreTests`): amounts clamp, on assignment too, and
  NaN means none; delete, duplicate, group move and edit on a queue, with the page being shown followed through each.
- `ScanImageProcessorTests` 17 (`PaperNestImportTests`), on pages made pixel by pixel: a shadow over a quarter of
  the page is lifted to within 12 levels of the lit paper at full amount and about half way at half; tinted paper
  goes to white on every channel while ink stays dark; a soft edge gets at least 15% steeper and flat areas do not
  move; Grayscale, High Contrast and Enhanced do what their names say; Black & White gives white paper and black ink
  under the shadow too; a heading bar and a picture keep their colour through Remove shadows and stay black through
  Black & White; every preset with and without Cleanup keeps the page's size and covers it; a preview a third the
  size shows the same as the full page; 48 pages given Auto at once finish.

**Two faults found by looking, not by the first tests.** (1) The first Remove shadows passed its numbers and
bleached every filled block: a contact sheet of a made-up page with a heading bar, a highlight and a picture showed
the bar with a pale hole and the picture washed out, and Black & White turned the picture into an empty frame. The
lighting is now read from paper alone; two tests pin it. (2) A test run hung with eight threads in
`CIVNFaceDetector` under `autoAdjustmentFilters`: Core Image's automatic adjustment looks for faces through Vision,
which parks the calling thread. A probe outside the project: 48 calls at once on Swift concurrency's threads never
returned; with an empty `features` list they took 26 ms together and gave the same two filters. **The scanner's
Enhance had this before today**, one page at a time; it could have hung the review screen once several enhanced
pages redrew together. Fixed in the engine and pinned by a test that stops the run with the reason.

**iOS unit tests (`xcodebuild test -scheme PaperNest-Canvas`, PaperNest iPhone Duo, iOS 27.1).**
`ScannerPageTests` **11 passed, 0 failed**: presets and Cleanup change the saved picture and not the capture; Reset
undoes look, turn and crop; a copy carries every edit; the redraw key changes with each of them; a preview is no
larger than asked and keeps the look; the Cleanup sheet's picture is the page without its look, turned by the preview.

**iOS UI tests (`ScannerWorkspaceUITests`, the script's `xcodebuild test` line run directly; these suites make
their own libraries).** On the final source:

| Simulator | Result |
|---|---|
| **iPhone 17, iOS 26.5** | **7 passed, 0 failed**, 256 s |
| **iPad Air 13-inch (M4), iOS 27.0** | **7 passed, 0 failed**, 252 s |
| **PaperNest iPhone Duo, iOS 27.1** | **6 passed, 1 failed**, 280 s. The failure is `testReviewEditsSaveAndReopen` at its first check, before it touches anything: Save's top edge is at 12 points and the test expects at least the 44 it assumes for a phone on which it finds no status bar. **It fails the same way, with the same two numbers, at the last commit `55f163e` with none of this work in it** (one run, from a clean worktree, same simulator), so it is older than this change. Whether the test's 44 points or the screen is wrong on that device was not looked into. |

The three new tests, all passing on all three: `testCleanupAppliesToThisPageOrToAllPages` (opens Cleanup from the tool
and from the strip's tile, moves a slider, Recommended, Before and After, Apply to this page changes that page only,
Cancel changes nothing, Apply to all pages reaches all three, Reset undoes one page, and the scan still saves),
`testPresetsBelongToEachPageAndEveryControlShowsThem` (the strip, Enhance and the Filter menu on two pages, then Reset)
and `testPickedPagesAreChangedMovedDuplicatedAndDeletedTogether` (pick and unpick, batch filter, batch Cleanup, move a
page to the front, duplicate two, delete three after the question and its Cancel, delete one without a question).
The four older tests pass with them.

**Runs that failed on the way, and why.** (1) The Cleanup test's first three runs on the Duo: the layout fault below.
(2) On iPhone 17, three tests, the older `testReviewEditsSaveAndReopen` among them, could not tap Reset: **on a
393-point iPhone the tool row is now eight tools wide** (the shell added Cleanup and Select pages to six), so Select
pages is cut by the screen's edge and Reset and Delete start beyond it. The row scrolls and has no indicator.
XCUITest does not scroll it by itself, so the tests now drag the row to a tool before using it (`tool(_:_:)`); a
first version of that helper asked `isHittable` of the hidden tool, which is itself a failure, and failed the same
three. **The row's width is a design matter left for Codex; nothing was removed from it.**

**One layout fault found by a UI test.** On the 678-point-tall PaperNest iPhone Duo the Cleanup sheet's Recommended
button lay underneath "Apply to this page" (frames read from the accessibility tree: Recommended at y 548, Apply at
y 536 to 580), so a tap meant for Recommended applied and closed the sheet. It is in the sheet's top bar now.

**Builds.** `./scripts/build-ios-sim-app.sh` and `./scripts/build-mac-app.sh` on the final source: both built, no warnings.

**The commit, alone, in a clean worktree** (`HEAD` plus this slice; `Localization.swift` and the three strings
files as `HEAD` plus the scanner keys only). `./scripts/test.sh` **1,114 passed, 0 failed, 0 warnings**
(four fewer than the shared tree, which also has Codex's uncommitted OCR panel tests);
`xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` succeeded with no warnings. The UI
tests were run from the shared tree, not from that worktree.

**Not run, and not verified.**

- **No camera and no photographed page.** Every look was judged on synthetic pages, by numbers and by eye on a
  contact sheet. How Remove shadows, Whiten and Black & White do on real paper under real light is unknown.
- **No device.** Nothing was installed on the iPad or an iPhone. Cost was measured only on this Mac in a debug
  build: about 0.2 s for a 3-megapixel page with Cleanup, 0.02 s for a preset alone.
- **French and Spanish were not looked at.** The strings exist and `LocalizationTests` passes; the layouts were
  only ever opened in English. Accessibility text sizes were not opened either. Both are Codex's to see.
- VoiceOver was not used. The Mac has no scanner, so nothing there changed.
- The rest of the iOS UI suites were not run, and `scripts/ui-test-ios.sh` was not run whole: only
  `ScannerWorkspaceUITests`, through the script's own `xcodebuild test` line. `./scripts/test.sh --sanitize=thread`
  was not run.
- After the last UI runs nothing in `Sources` changed. Screenshots from the runs were looked at on iPad and on
  iPhone 17 (Cleanup sheet, strip, picked pages); they are in the runs' result bundles, not in the repository.

**Not built** (design sections in brackets): Whiteboard and ID/Card capture and front/back pairing [1, 8], which
stay marked Coming soon; the Scan settings sheet [2]; the Move closer / Hold steady / Ready labels [3]; Cleanup as
an inline inspector on iPad [6], where it is the same sheet as on the phone; thumbnail pictures in the preset tiles
[5], which show symbols; the destination row before Save [9]. Group move is two buttons, not a drag.

**Known limit.** A filled area in a gray close to the paper's own colour reads as paper in shadow, and Remove
shadows lightens it. A page with almost no paper in it, a photograph, is left alone by Remove shadows and Whiten.
With Black & White the page is always evened out and taken to white, so those two sliders change nothing there;
Sharpen text still does.

## 2026-11-15 23:03 CST — Color-well geometry compared against recording (Codex heartbeat)

- Exported the failed warm diagnostic result to `/private/tmp/pn-well-evidence`. Extracted retained recording frame at142.388s to `/private/tmp/pn-well-end.png`; inspected original2064x2752 image. Shape remains onscreen with Custom Color label and leading well visible.
- Failure AX custom-color bounds are x258,y835,w309.5,h95.5 points. Temporary tap (0.05,0.85) computes approximately (273.5,916.2) points, matching the visible well center near (272,916) after accounting for2x screenshot scale. Thus the prior simple label-center miss is insufficient to explain the well-targeted failure. The recording alone does not establish delivered events or the underlying presentation cause.
- No new test run/product change. Next isolate native picker in a simpler, standard-text interaction before further XXXL changes; inspect presentation logs if that also fails. Preserve the failing route's evidence rather than assume a renamed Close button. No commits/staging; Claude's active scanner work untouched. Scoped docs claim released.

## 2026-11-15 22:08 CST — Color-well targeted tap remains inconclusive (Codex heartbeat)

- Temporarily changed only the XXXL custom-color tap to element-relative (0.05,0.85), matching the prior retained screenshot's leading/bottom well. No scanner or product changes; Claude's active Scan Studio work preserved.
- Initial build+test `/private/tmp/pn-color-well-tap.log` hit **240-second total bound,exit124**, before diagnostic verdict. Warm `test-without-building` `/private/tmp/pn-color-well-tap-warm.log` **1 failed,155.794s,exit65**, within240sec bound: still waiting native color-picker Close (temporary line1407). Slow/retried AX queries occurred; no successful color change or saved shape claimed.
- The simple well-offset hypothesis did not produce a passing interaction. Reverted temporary test tap exactly; supported Notes setup remains. Next inspect this run's retained AX/screenshot geometry or isolate native color-picker activation in a smaller test, rather than repeat unchanged runs. No product defect/root cause inferred.
- Owned iPad27 ended shut down. No staging/commits; scoped claims released. Source is restored, while the last built diagnostic test bundle contains the temporary tap: rebuild before running the restored test.

## 2026-11-15 21:39 CST — The iPad UI run on the committed editor fix: 27 passed, none failed (Claude)

Closes the row left open in the entry below ("Still running when this was committed"). The same 28 tests on the same
simulator (iPad Air 13-inch (M4), iOS 27.0), the shared tree with `812434d`'s `DocumentView.body` (seven functions,
one body) and the device-sized stack: **27 passed, 1 skipped as phone-only, 0 failed**, `TEST SUCCEEDED`, exit 0,
1,933 s. `NightModeUITests` **3/3**, including `testInkDrawnAtNightShowsLightAndIsSavedInTheColourChosen`, the test
the `ViewModifier` attempt failed twice. Also `AppUITests` 5 (notebook create and reopen, tool panels, OCR panel,
export tiles, export panel close and reopen), `BookmarksUITests` 3, `DocumentFindUITests` 3, `DocumentPrintUITests` 2,
`DocumentTabsUITests` 1, `DocumentUtilitiesUITests` 5, `FolderNoteUITests` 1, `ReadAloudUITests` 4. The Mac was
swapping under an unrelated video render for the first part of the run (load average over 400, later about 35);
nothing needed a rerun. `main` was fast-forwarded to `812434d` and pushed at the owner's request ("merge it to main").
Still not run: what the entry below lists.

## 2026-11-15 — A document opens on a real iPad again: the editor's body no longer needs most of a megabyte of stack (Claude, owner in session)

Owner: "APP crashes on Ipad and home srcreen of ipad comes in". Seventeen PaperNest crash reports on the owner's
iPad Pro 12.9-inch (6th generation), iPadOS 27.0.1, between 18:18 and 19:56, read off the device with `devicectl`
(PaperNest's reports only; the real library was not read). Sixteen are crashes; six of them were copied and read,
from each batch, and are one signature:
`EXC_BAD_ACCESS / KERN_PROTECTION_FAILURE` in the main thread's stack guard, in `swift_getTypeByMangledName` called
from `DocumentView.body.getter`. The app reopens the last document at launch, so it died one to four seconds after
each launch and could not be used at all.

**Cause, measured.** `DocumentView.body` was one chain of some seventy-five modifiers. Each modifier's result holds
everything chained before it, and a debug build keeps every one of them on the stack until the function returns:
under lldb the frame of `body.getter` alone was **885,408 bytes**. A device's main thread has **1008 KB** (the crash
report's own region list); the Simulator and the Mac gave 8 MB, so it never failed anywhere but on the device. Ten
modifiers were added between 2026-11-13 and 2026-11-15 and four more in the uncommitted panel work; the first device
run after that was the first crash. The type-decoding recursion at the top of the crash stack is the last straw and
not the cause (74 frames, 79 KB).

**Fix.** The chain is split into seven functions that `body` applies in order (`bars`, `toolsPanel`, `lifecycle`,
`exportAndPictures`, `toolSheets`, `pageSources`, `readerServices`), each `@inline(never)`. The view built is the
same value of the same type, evaluated in the one `body`; only the stack changes. `project.yml` now links Simulator
builds with a device's stack (`-stack_size 0xFC000`, and no debug dylib there, since the linker only takes a stack
size for a main executable), so a UI test that opens a screen needing more stack than a device has now crashes in
the Simulator too. `CLAUDE.md` has the convention. No schema, store or model change.

**A first attempt was wrong, and is not what is committed.** Moving the seven runs into `ViewModifier`s cut the
stack further (the editor opened with 384 KB) and passed 26 of 27 iPad UI tests, but
`NightModeUITests.testInkDrawnAtNightShowsLightAndIsSavedInTheColourChosen` failed twice on it and passed on the
pre-fix code on the same simulator. The screen recording shows why: the stroke is light under the finger, gone the
moment the finger lifts, and back only when drawing is switched off. Each modifier re-evaluated on its own, where
the editor had always re-evaluated whole, and the live ink relies on that. **That build was on the owner's iPad from
20:12 to 21:06**; the owner reported "it opens now on ipad" on it. The committed version replaced it at 21:06.

| Check | Result |
|---|---|
| Crash reports from the iPad | 17 today, 18:18–19:56. Six of the sixteen crashes read, one signature (above); the other ten were not opened. None after the 20:12 install. The seventeenth (19:36) and two older ones (11 and 12 November) are scene-update watchdog kills with an idle main thread: a different matter, not looked into. |
| The crash, off the device: the tree as it was, Simulator build, main-thread stack set to the iPad's 1008 KB (`LC_MAIN`), launched into a seeded throwaway library with `-PaperNestDebugOpenItem` — iPad Air 13-inch (M4), iOS 27.0 | **Crashed** inside 4 s, SIGSEGV. Under lldb: `EXC_BAD_ACCESS` code 2 on the main thread, `DocumentView.body.getter` → `__swift_instantiateConcreteTypeFromMangledNameV2`, 188 frames (the iPad's reports: 180–185). The same build with the Simulator's default stack stayed up (control). |
| The same launch with the fix, at 1008 KB | Stayed up; the editor and Document Tools on screen (screenshot looked at). |
| How much stack the editor needs now: the same launch at smaller stacks | Opens at **448 KB**, dies at 384 KB. Before the fix it died at 1008 KB. |
| `./scripts/test.sh`, clean worktree at `9a32c7d` plus this change only | **1,077 passed**, exit 0, no warnings. |
| `./scripts/test.sh`, shared tree (also carrying Codex's uncommitted panel work) | 1,083 passed, exit 0, with the first attempt in place; not run again after the change of approach. |
| The committed tree's own Simulator build opening a document at device stack — clean worktree, iPad Pro 11-inch (M5), iOS 27.0 | Built, exit 0, stack size 0xFC000. Launched into a seeded throwaway library with `-PaperNestDebugOpenItem`: stayed up for the 20 s watched, the editor on screen (screenshot looked at). |
| The built Simulator app's stack size (`otool -l`, `LC_MAIN`) | 1032192 (0xFC000); one executable, no `PaperNest.debug.dylib`. |
| iPad UI tests on the **first attempt** (the `ViewModifier`s), device-sized stack, shared tree — iPad Air 13-inch (M4), iOS 27.0, load average 20–35 from an unrelated video render | 29 run: **26 passed, 1 failed, 2 skipped** as phone-only. Passed: `AppUITests` notebook create and reopen, export panel close and reopen, tool panels, OCR panel, export tiles; `DocumentUtilitiesUITests` 5, `DocumentTabsUITests` 1, `FolderNoteUITests` 1, `DocumentFindUITests` 3, `DocumentPrintUITests` 2, `BookmarksUITests` 3, `ReadAloudUITests` 4, `NightModeUITests` 2 of 3. Failed: the night ink test, again when run alone; it **passed on the pre-fix code** on the same simulator (default stack, since that code cannot open a document at a device's). |
| The same set on **the committed fix** | **Still running when this was committed.** Three passed, none failed: tool panels, export tiles, notebook create and reopen. The Mac is swapping under the same render (load average over 400), and the run is crawling. **`NightModeUITests` has not run on this version yet**; what is known is that it builds the same view in the same single `body` as the code that passed. The outcome goes in a later entry. |
| `./scripts/build-mac-app.sh`, shared tree | Passed, no warnings (run on the first attempt; the Mac compiles the same file). |
| On the iPad itself | Signed Debug build of the shared tree installed with `devicectl` at 21:06. Not launched by me: the iPad refused a remote launch. **The owner opened it: "opened it again, works fine".** |

**Not run.** XCUITest on the iPad: there is no provisioning profile for the UI-test runner and I did not pass
`-allowProvisioningUpdates`, which would create one in the owner's developer account. A release build on a device
(the 885 KB is a debug build's; release was not measured). iPhone UI tests, the rest of the UI suite, Mac
interaction. The seven functions leave the editor needing about 450 KB of a device's 1008; it will creep up as
modifiers are added, and the Simulator's device stack is what catches it.

**Left on the iPad:** a 600 KB synthetic library in the app's `tmp` (`PaperNestUITest-F364B5C5-…`), copied there for a
launch that the lock then refused. iOS clears `tmp`.

## 2026-11-15 20:05 CST — Color-picker failure evidence reviewed (Codex heartbeat)

- Exported prior xcresult attachments to `/private/tmp/pn-large-shape-evidence`; inspected width screenshot and extracted screen-recording frame114s at `/private/tmp/pn-large-shape-at114.png`. Shape remains presented after the custom-color tap; no native color-picker panel is visible. Thus a renamed Close button alone does not explain the failure.
- At accessibilityXXXL, Custom Color label occupies a broad row while its small native color well wraps underneath at the leading edge. AX reports one button covering x258,y847.5,w309.5,h95.5; default center tap can target the label area rather than the well. This is a hypothesis for the next focused test: tap the observed well within the element bounds and verify native picker appears before changing product code. Do not infer a confirmed framework or save defect.
- Background Document Tools heading and tiles visibly fragment/truncate at XXXL; retained screenshot documents an additional layout follow-up once current crash work is released. No new tests, source edits, staging or commits. Claude actively owns DocumentView.body physical-device crash fix; no build or edits to that work.

## 2026-11-15 19:05 CST — Large-text shapes reach color-picker boundary (Codex heartbeat)

- Updated only `testLargeTextShapeSlidersAndSystemColorPicker` setup to use existing supported Notes creation helper. Removed obsolete debug Home Tools route and its old notebook-toolbar/sidebar-width assumptions; shape slider, width, color and saving assertions preserved.
- iPad6528AE8B/iOS27/accessibilityXXXL: **1 failed,120.906s,exit65**, `/private/tmp/pn-nov15-large-shapes.log`,240-second bound. Creation and editor/shape navigation succeed; position slider value changes and width4 Selected assertion pass. Failure at AppUITests.swift:1406 waits for native color picker button labelled Close after custom-color tap. No color change or saved-shape pass claimed.
- Next inspect retained failure hierarchy/screenshots for custom-color presentation and current native picker semantics; this alone does not establish a product defect. No speculative product change. Retained supported-route test update, no staging/commits. Owned simulator ended shut down; own claims released.

## 2026-11-15 — Folders offer New Note beside Import File, on iPhone, iPad and Mac (Claude, owner in session)

Owner: "When created new folder, along with import file, it should have option to create new Note", then "also on
mac". The empty-folder screen shows **New Note** next to Import… (`folder-new-note`), and a folder's toolbar has
**New Note** next to Import (`library-new-note`) so it is still there once the folder has something in it — that
second place is Claude's call. The note is made in the folder (`createNotebook` already used the folder showing).

**Found by the first run, and fixed.** `LibraryModel.open` switched to All Documents before opening anything from a
library scope. A note made in a folder therefore opened over All Documents on iPhone (Back did not return to the
folder) and did not open at all on iPad (changing the selection lost the push). It now opens over the folder when
opened from one; Favorites and the other scopes behave as before. A file imported while inside a folder now also opens
over that folder.

| Check | Result |
|---|---|
| New `FolderNoteUITests`, iPhone 17 / iOS 26.5, clean worktree | Failed before the `open` fix (Back went to All Documents), **passed** after: Home → New Folder → the empty folder offers New Note and Import → New Note → "Cells" opens → Back is the folder, the note is in it, New Note is in the toolbar. |
| The same, iPad Air 11-inch (M4) / iOS 26.5 | Failed before the fix (the note did not open), **passed** after. |
| Around it, both devices | Passed: `testPremiumFolderActionCreatesARealFolder`, `testImportDestinationCreatesFolderAndOpensDocument`, `testNotebookCreationOpensAndSurvivesRelaunch`; iPhone `testAFolderMadeInTheSidebarHoldsAMovedDocument`; iPad `testIPadSidebarKeepsTheBrandAndFoldersIsOneDestination`; `ApprovedLibraryUITests` 2/2 on each in the first run. |
| `./scripts/test.sh`, clean worktree | **Passed: 1077 tests**, 0 failures, 0 warnings. |
| Mac, offscreen render of `LibraryView` on an empty folder | "This Folder Is Empty" with **Import…** and **New Note** side by side. The Mac toolbar's New Note was not seen: the offscreen render draws no window toolbar. Nothing was clicked on the Mac. |

## 2026-11-15 — Word and Excel import as pages: iPhone and iPad through WebKit, Word on the Mac (Claude, owner in session)

Owner: "Yes, build both" (Word and Excel), after the throwaway test in the entry below. **iPhone and iPad:**
`OfficeDocumentRenderer` copies the file somewhere WebKit's process can read it, loads it into a web view that sits
behind the window's content, waits for `didFinish` and then for the print page count to read the same twice, and
prints A4 pages with `UIPrintPageRenderer`. It gives up after 20 seconds, resumes its wait exactly once, and keeps
the result only if at least one page carries words; otherwise the file is kept as a file. `.docx`, `.doc` and `.xlsx`
only. `LibraryModel` calls it where an import would otherwise become a file item, and for files unpacked from a ZIP.
**Mac:** `TextDocumentConverter` reads `.docx` and `.doc` with `NSAttributedString` and lays them out like RTF.

| Check | Result |
|---|---|
| New Mac test, written first | `aWordFileBecomesPagesOnTheMac` (`.docx` and `.doc` generated in the test by `NSAttributedString`, 82 lines) failed with `unsupportedType`, then passed: two or more pages, first and last line read back from the stored PDF. |
| `./scripts/test.sh`, clean worktree of `HEAD` plus only this change | **Passed: 1077 tests** (342 + 49 + 191 + 188 + 179 + 128), 0 failures, 0 warnings. |
| New `OfficeImportUITests`, iPhone 17 / iOS 26.5, clean worktree | **5/5:** `.docx` opens in the editor with ≥ 2 pages and find matches "Line 120 of the proposal"; `.doc` opens and finds "Project proposal"; `.xlsx` opens and finds "1234.5"; a 2,400-paragraph `.docx` opens as ≥ 30 pages and finds its last paragraph (test 25 s); a fake `PK…` `.xlsx` opens as a file preview, not the editor. |
| The same, iPad Air 11-inch (M4) / iOS 26.5 | **5/5.** |
| Through the real file picker, iPhone 17, by hand | A `.docx` placed in On My iPhone, picked from Home → Import File → Open → Save and Open: opened in the editor as pages. This is the security-scoped path the automated tests skip. |
| Looked at | The iPhone screenshots: both open with the full editor tool bar. **The Word text prints smaller than in Word** — the file's own margins plus the print inset leave it in the middle of the page; readable, and it zooms. The spreadsheet shows its two columns and values. |

**Fixtures.** `scripts/ui-test-ios.sh` writes them to `/tmp/papernest-office-fixtures` before each run: `textutil`
makes the `.docx`, `.doc` and the long `.docx` from generated RTF, Python writes a minimal `.xlsx`, and `printf` the
broken one. All synthetic.

**Not built, not run.** Excel on the Mac stays a file: the Mac has no reader for it. `.xls` (no way to make one here),
PowerPoint, Pages, Numbers and Keynote stay files, not tried. Adding an Office file into an existing document as
pages (`insertPages`) still says unsupported. The Mac was not looked at on screen. `--sanitize=thread` was not run on
the Mac Word reading; the Mac test reads Word off the main thread and passed.

## 2026-11-15 — Approved OCR and Signature panels (Codex)

- Shared compact panel header, scrolling cards and pinned footer; trailing inspector on wide Mac/iPad, native sheet on iPhone. OCR exposes actual Vision-supported languages with preserved priority, All/Current/Range selection, validated ranges, real thumbnails, progress and committed completion counts. Signature keeps existing draft/store/gating/placement logic and adds the approved visual treatment. No schema, subscription or product-brief changes.
- `GIT_DIR=/dev/null ./scripts/test.sh`: **passed, exit 0; 1,080 tests** across six reported target runs (346 + 49 + 191 + 187 + 179 + 128). Log `/tmp/pn-panels-all-tests.log`. After final presentation adjustments, focused OCR selection/workflow, recognition, signature/name-field and localization: **19 tests in 6 suites passed**, `/tmp/pn-panels-focused-last.log`.
- Final `./scripts/build-mac-app.sh`: **passed**, `/tmp/pn-panels-mac-header.log`; app under `~/Library/Caches/PaperNest/build-17de0868e51d/dist/PaperNest.app`. Generic iOS Simulator `xcodebuild build-for-testing`: **passed**, `/tmp/pn-panels-ios-release-check.log`. No Swift compiler errors/warnings observed; Xcode emits optional AppIntents metadata diagnostics.
- Native Mac, isolated ad-hoc signed app and `/tmp/pn-panel-design-mac-library`: selected pages 1 and 3, real OCR completed 2/2; drew signature, verified unnamed Save disabled, named/saved/placed it, undo/redo changed the page 1→0→1 stroke, reopened saved selection. Test app quit. No real user library used.
- iPad Pro 13-inch (M5), iOS 26.5: `testOCRPanelSelectionAndRecognition` **passed 142.942 s**, exercising en/fr/es, empty-language disabled action, invalid/valid ranges, recognition result and close; `testSavedSignaturePlacesAndSurvivesReopen` **passed 60.438 s**, drawing/naming/saving/placement/undo/redo/reopen. Result `/tmp/pn-ocr-signature-ipad-final.xcresult`.
- iPhone 17 Pro, iOS 26.5: OCR test **passed 182.919 s**, all three languages; `/tmp/pn-ocr-signature-phone-final.xcresult`. Signature final current-source build/run **passed 89.012 s**, `/tmp/pn-signature-phone-header.xcresult` (exit 0), including the compact-header regression, drawing, unnamed/named Save states, saved selection, placement, undo/redo and relaunch. Final screenshot verifies readable saved name and white primary-action label.
- Initial checks retained: first focused run failed three French colon-spacing assertions and two incorrect new-test assumptions that background import OCR left page 1 empty; corrected localized spacing and asserted page 1 stays equal to its pre-operation recognition. Initial iPad OCR timed out at 45 s in French; failure hierarchy confirms completed 1/1 result appeared afterward. Rerun passed, timeout now 120 s. Initial iPhone Signature test failed before panel entry with a long notebook title. Opening UIKit’s `OverflowBarButtonItem` still exposed only Export: the custom Document Tools toggle was omitted entirely. The compact header now groups its 44-point Find/Export/Tools controls as one fixed-size toolbar item, preventing that automatic overflow loss; wide header behavior stays intact. iPad history helper now scrolls the actual horizontal toolbar instead of searching the PDF tools list.
- Screenshot review caught dark primary-action text and cramped saved-signature names; final source uses white action labels and gives signature names a separate line below previews. Actual OCR en/fr/es and signature screenshots are in xcresult attachments. Physical devices, screen-reader operation, dark-mode and accessibility-size runtime checks were not performed in this slice. Semantic adaptive tokens, Dynamic Type, existing VoiceOver labels and en/fr/es localization remain in use. Full-tree diff-check still reports unrelated pre-existing trailing whitespace in `DocumentUtilitiesSidebar.swift:264`; untouched.

## 2026-11-15 — Text files import as pages that open ready to mark up (Claude, owner in session)

Owner: "on iphone when i import any dicuments it does not open notes and pdf section rrady for edit", then, asked
which kind, "Word or text file", "Mark up its pages" and "all files show be editable". Reproduced first, on `HEAD` in
a clean worktree, on iPhone 17 / iOS 26.5: a PDF imported from Home through the real file picker, a PDF imported from
All Documents, and a photo all opened in the editor; a `.txt` opened in a read-only Quick Look preview, as designed.
The owner's 2026-10-28 decision to drop file conversion is reopened in FEATURE_EXPANSION and the inventory.

**What changed.** `DocumentImporter.prepare` lays out a text file as PDF before deciding the path
(`TextDocumentConverter` in `TextToPDF.swift`): any type that conforms to `public.text` except HTML, decoded as UTF-8
(or UTF-16 with a byte-order mark, and no NUL bytes), and RTF through `NSAttributedString`. Chosen by the file's type,
not by whether its bytes decode, so a binary is never turned into pages. HTML stays a file: reading it needs WebKit on
the main thread and imports run off it. What is stored is the PDF; its words are real text in it. **The original text
file is not kept beside the pages** — the store sweeps an original no page refers to — so the content survives as the
PDF's text and the source file stays wherever it was imported from.

| Check | Result |
|---|---|
| New `TextDocumentImportTests`, written first | Failed 8 ways before the change (every text type was `unsupportedType`), pass after: `.txt`, `.md`, `.csv`, `.log`, `.swift`, `.json`, UTF-16 `.txt` and `.rtf` become pages whose words read back from the stored PDF; a binary `.bin`, a `.txt` holding NULs, a blank `.txt` and a fake `.xlsx` still throw `unsupportedType` and leave no asset behind. |
| `./scripts/test.sh`, shared tree, 17:02 | **Passed: 1076 tests**, 0 failures, 0 warnings (held Codex's uncommitted panel edits as well). |
| `./scripts/test.sh`, clean worktree of `HEAD` plus only this change, 17:16 | **Passed: 1076 tests** (342 + 49 + 191 + 187 + 179 + 128), 0 failures, 0 warnings. |
| **iPhone 17 / iOS 26.5** and **iPad Air 11-inch (M4) / iOS 26.5**, clean worktree, `scripts/ui-test-ios.sh`, 17:05–17:12 | **4/4 on each:** `testATextFileImportsAsPagesAndOpensInTheEditor` (new: a `.txt` imports, opens in the editor with the pen tool, "Page 1 of 1", no preview), `testImportDestinationCreatesFolderAndOpensDocument`, `testAFileItemPreviewsAndShowsItsTypeSizeAndACopy`, `testMissingFilePreviewCanBeClosedInEveryLanguage`. |

**Tests changed, and why.** Five tests used a text file as the example of something that stays a file:
`ImportTests.damagedEmptyAndUnsupportedFilesAreRejectedWithoutSideEffects`, `LibraryWorkflowTests`, `ArchiveExtractionTests`
and three in `BulkExportTests` now use non-text bytes (`.bin`, `.dat`); the file-preview UI tests' seeded fixture in
`scripts/ui-test-ios.sh` is now `Budget notes.html`, which stays a file and which Quick Look still shows as text.

**Word and Excel on the iPhone: a throwaway test, deleted afterwards.** In a separate worktree a debug hook loaded
files into a `WKWebView` and paginated them with `UIPrintPageRenderer` on iPhone 17 Pro / iOS 26.5. A `.docx` made by
`textutil` (a heading and 120 wrapped lines) came out as **4 Letter pages with all 11,705 characters extractable** and
the heading bold. A hand-built `.xlsx` (a 2×2 table) came out as **1 page with real text, but "Quarterly paper" clipped
to "Quarterly"** at its column edge. The `.doc` written next to the `.docx` shared its output name and was not looked at
separately. PowerPoint, Pages, Numbers and Keynote were not tried: no sample could be made here. The Mac has no WebKit
route for these; its `NSAttributedString` reads Word but not Excel. Nothing of this is in the app.

**Not run.** The Mac was not looked at; the importer is shared, so a text file becomes pages there too, unverified on
screen. No other UI test was run.

## 2026-11-15 16:57 CST — iPad27 XXXL Notes creation passes on current tree (Codex heartbeat)

## 2026-11-15 — Mobile tool-panel screenshot verification

- `xcodebuild test ... -only-testing:PaperNest-iOSUITests/AppUITests/testCaptureUpdatedToolPanels`: iPad Pro 13-inch M5, iOS26.5, PASS (1 test, 41.570s), `/tmp/pn-ipad-panels-20261115.log`, `/tmp/pn-ipad-panels-20261115.xcresult`.
- `xcodebuild test-without-building` with the same test: iPhone17Pro, iOS26.5, PASS (1 test); `/tmp/pn-iphone-panels-20261115.log`, `/tmp/pn-iphone-panels-20261115.xcresult`.
- Opened Signature, canceled, opened Pages, closed, revealed Recognize Text. Exported and visually inspected all six actual screenshots. Disposable Crop target fixture only. OCR has an action in Document Tools, not a separate settings panel. This check does not exercise signature saving, page mutations or OCR execution. No product functionality changed.


- Existing `AppUITests.testLargeTextNotebookCreationFromNotes` **1 passed,35.145s,exit0**, `/private/tmp/pn-nov15-creation-warm.log`,240-second bound. iPad6528AE8B/iOS27. Normal text-field focus/typing and identifier-based toolbar Create verified in log, followed by editor-text-box assertion. Disposable UUID library; no prefilling or diagnostic source changes.
- Prior keyboard-associated failure is no longer reproduced by this route on current source after intervening panel/app changes. This result does not identify which change resolved it or prove every creation route. No speculative fix needed. Remaining shape/color accessibility checks should use supported Notes navigation; Home Tools entry was removed by owner instruction.
- Earlier total-bound run remains incomplete, not a test failure. Owned simulator ended shut down; no other simulator touched. No source edits/staging/commits; scoped documentation claims released. Repaired the previous interrupted-baseline heading separation without changing another session's report.

## 2026-11-15 — Document and utility panel visual redesign (Codex)

Owner scope: approved panel styling on Mac/iPad/iPhone, presentation only. Shared semantic lavender chrome; rounded selection/paper cards; compact headers; scrolling native controls. Export/Compress use the existing wide editor inspector, with explicit close callbacks and separate embedded/sheet chrome. Signature/forms/pages retain inspectors. Other native placement/library sheets retain their routes. No processing/store/schema/subscription changes. Existing strings and accessibility identifiers preserved; added `export-close`.

- `./scripts/build-mac-app.sh`: passed; final `GIT_DIR=/dev/null ./scripts/build-mac-app.sh` after the binding fix passed (31.17s), `/tmp/pn-panel-design-mac-final-pass.log`.
- `./scripts/build-ios-sim-app.sh`: passed, log `/tmp/pn-panel-design-ios.log`; simulator-placeholder OS-version diagnostic from Xcode, no source compiler error.
- `./scripts/test.sh --filter LocalizationTests`: passed, 5 tests / 1 suite, all en/fr/es key and argument checks. `/tmp/pn-panel-design-localization.log`.
- iPhone 17 Pro / iOS26.5: export format/page selection + Copy confirmation passed (16.855s). Existing navigation test initially failed its outdated `panel.exists == isPad` assertion: Option6 now opens a phone drawer. Updated assertion to expect the revealed drawer. Final phone navigation/close-reopen rerun stalled before test launch in Xcode coordinated project-file read and was stopped; no pass claimed for that rerun. Logs `/tmp/pn-panel-design-phone-ui.log`, `/tmp/pn-panel-design-phone-final.log`.
- iPad Pro13 / iOS26.5: initial embedded Export run stalled at app-idle, app ~100% CPU. Stopped the owned run; sampled `/tmp/pn-panel-ipad-sample.txt` shows repeated layout/sheet-presentation resolution. Removing embedded sheet traits and restoring original inspector width did not resolve it. Restoring the original direct inspector binding and using `.constant(false)` for suppressed sheets instead of custom closures capturing the entire editor resolved the loop; dismissal cleanup stays in `onChange`. Close/reopen regression test passed (15.705s), `/tmp/pn-panel-design-ipad-bindings.log`; export format/page selection + Copy passed (14.632s), `/tmp/pn-panel-design-ipad-final.log`. Both **TEST SUCCEEDED**.
- Mac native disposable library `/tmp/pn-panel-design-mac-library`: Export inspector opened, PDF→JPEG selection updated, close restored editor controls; Compress inspector opened, Light selection and existing compression action returned no-gain Save/Share result, close restored editor. French compact-width Export/Compress visually checked. Full-width export actions fit French labels. Isolated verification app closed. No real library used.
- Known limits: final phone navigation rerun blocked before launch; exhaustive panel-by-panel/Dynamic Type/VoiceOver/dark-appearance matrix not run. AppleInterfaceStyle launch argument did not change observed appearance, so no dark-mode visual pass claimed. No hardware camera/purchase testing required for this visual-only slice.
- Filesystem: iCloud intermittently blocked source/Git/doc reads; downloaded requested files. Final retries use `GIT_DIR=/dev/null` to avoid optional root SCM metadata traversal; no Git config/index changes. Separate concurrent `DocumentUtilitiesSidebar.swift` edit left untouched (its whitespace issue is outside this slice).


## 2026-11-15 — iPad27 notebook creation baseline interrupted (Codex heartbeat)

- Usage available (0% used); read current Claude releases, shared claims and staged paths before work. No staged paths or concurrent xcodebuild observed. Rechecked existing AppUITests.testLargeTextNotebookCreationFromNotes on iPad6528AE8B/iOS27 after intervening app changes; no source edits.
- `/private/tmp/pn-nov15-creation-baseline.log`: **240-second total bound,exit124; no completed test verdict**. Substantial dependency/app rebuild preceded runner startup; final UI log is Notes-create tap, before keyboard/Create diagnostic. Cannot count this as a new reproduction or pass of the prior keyboard issue. Next use the warmed build for one bounded baseline rerun before resuming focus-only/typing isolation.
- Runner ended owned simulator shut down. Other booted simulators untouched. No source changes/staging/commits; scoped documentation claims released. Earlier successful prefilled/no-keyboard comparison remains the last conclusive diagnostic.

## 2026-11-15 — Document Tools on the Mac: the rest seen, two more Mac bugs fixed (Claude)

Dev Mac app, throwaway library, sample PDF, forced dark with `-AppleInterfaceStyle Dark`.

- **Seen working:** dark appearance of the editor and Document Tools; clicking a thumbnail goes to its page (2 / 3);
  **Compress** opens, Smallest chosen, Compress run, and it reports honestly that this text PDF cannot get smaller,
  offering Save… and Share…; **Convert to Word** opens Export with Word selected; **Display settings** shows the zoom
  row, Zoom to Fit, Fit to Width, Night Mode and Two Pages.
- **Bug, mine, fixed — Compress never left its spinner on a Mac.** The app logged "AttributeGraph: cycle detected"
  millions of times and stopped answering. Found by drawing the sheet in stages behind a temporary switch (header
  only: 0 cycles; spinner only: 0; the button only: 0; the level row in its card: cycles), with a new debug flag
  `-PaperNestDebugShowCompress YES` opening the sheet by itself. The shared `PanelSegmented` measures whether its
  options fit in a row; inside a Mac sheet, which sizes itself to its content, that looped. The Mac now uses the
  native segmented control there, and the sheet has a fixed size with its content scrolling. 0 cycles after.
  Two wrong guesses first — a fixed width, then the notes — each disproved by the cycle count, not the picture.
- **Bug, mine, fixed — Display settings on a Mac** was as narrow as its content, so the seven zoom choices stacked
  into a column and pushed Fit Page, Night Mode and Two Pages out of the popover. Now 540 points wide on a Mac.
- **Drag to reorder thumbnails on a Mac: still NOT confirmed.** A real-pointer drag (full-screen control, granted
  once) did not reorder, and no drag started: on a Mac a `Button` keeps the mouse press. The thumbnail is now a tap
  target with the drag on it (button trait and action kept; a click still selects, checked). A second real-pointer
  try was not possible: the approval prompt timed out. The background drag tool cannot test it either way.
- **Noticed, not mine, not changed:** Export with Word selected greys out Copy with "A ZIP archive can't be copied",
  though a Word export is one file.
- Unit suite green; iOS Simulator build clean; `testProcessToolsDoRealWork` and `testOneControlShowsAndHidesPagesAndToolsTogether`
  pass on iPhone 17 (iOS 26.5) with the changed sheet.
- Still not checked on a Mac: hover, resizing the column.

## 2026-11-14 — Reader features R5: Two-page view, and Night Mode's switch put back (Claude, owner's queue)

The last item of the reader queue the owner approved ("Yes, go on"). Free: it is not in `ProFeature`.

**What changed in the app.** Display settings' Reading section has **Two Pages** and, under it while it is on,
**Cover Page Alone** — on an iPad and a Mac, and only for documents: a phone has no room for two pages, and a notebook
scrolls its pages in one column, so neither switch is offered there. On, the editor shows the spread that holds the
page being read: two pages side by side, each fitted to its half of the width. A landscape page stands alone, and so
does the page before it rather than being paired across it out of order. With the cover alone the first page stands
alone and page 2 faces page 3, as a printed book does. The page beside the one being read is an ordinary page — its
own find hits, bookmark ribbon and night mode — and a tap on it makes it the page being read; drawing, typing and
selecting happen on the page being read only, as they always have. Going to a page brings its spread, and the
floating bar's previous and next step a spread at a time, from either page of it, as Acrobat does. Like night
mode it is a preference on this device: nothing about the document changes, and every throwaway library (each UI
test and development run) starts one page at a time.

**Night Mode had lost its switch.** `1e7fdda` (the "commit everything" commit, entry below) replaced the editor's
floating bar and did not carry `nightMode: $isNightMode` into the Display settings call; the parameter is optional,
so it compiled. Night mode still worked and nothing could turn it on. Measured on `a7c79e5` before the fix: all three
`NightModeUITests` failed with "Display settings has no Night Mode switch" (`/tmp/pn-two2-head-night.log`). The
argument is back, and the Reading section now holds Night Mode and the two-page switches together
(`ReadingSection`, replacing `NightModeSection`). The session that dropped it confirmed it was not meant.

**How it is built.** `PageSpreads` (`Sources/PaperNestCore/PageSpreads.swift`, new) pairs pages from their upright
sizes. `TwoPageView` (`Sources/PaperNestUI/Reader/TwoPageView.swift`, new) holds the two preferences, the spread for
the page being read, each page's share of the width and the Reading section. In `DocumentView.swift` the viewer draws
a spread as an `HStack` of the existing page surface, which now takes the room it is to fit; with two-page view off,
or in a notebook, the code path is the one there was. `DocumentUtilitiesSidebar.swift`: the popover's two bindings,
the Reading section, the reset. Strings: block `Two-page view`, four keys in en/fr/es.

**Results.** Verified in a clean worktree holding `a4a4281` plus only this change — the branch as committed. (It
was moved twice while being verified, as another session committed `a7c79e5` and then `a4a4281` under it; each time
it was rebuilt on the new commit and the runs started again.)

| Check | Result |
|---|---|
| `./scripts/test.sh` | **Passed: 1,071 tests** (342 + 49 + 191 + 182 + 179 + 128), 0 failures, 0 compiler warnings — `/tmp/pn-two3-unit.log` |
| New: `PageSpreadsTests` 8, `TwoPageViewTests` 5 | **Passed** |
| `./scripts/build-mac-app.sh` | **Built**, 0 warnings |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **BUILD SUCCEEDED**, 0 warnings |
| `TwoPageViewUITests` (new, 2), iPad Pro 13-inch (M5), iOS 26.5 | 1/2, then **2/2**. The French and Spanish test's own check was wrong: it compared the switch's whole accessibility label, which is the row's title and then its description, with the title. It now checks that the label begins with it — `/tmp/pn-two4-ipad-two.log` |
| `TwoPageViewUITests`, PaperNest iPhone Duo, iOS 27.1 | **2/2** — on a phone the switch is not offered, in English, French and Spanish (`/tmp/pn-two3-iphone-new.log`) |
| `NightModeUITests` 3 | **Before**, on `a7c79e5`: **0/3**, each "Display settings has no Night Mode switch" (`/tmp/pn-two2-head-night.log`). **After**: iPad **3/3**, iPhone **3/3** |
| `DocumentUtilitiesUITests` (the Display popover sits in its bar) | iPad **5/5**. iPhone **5/6**: `testOneControlShowsAndHidesPagesAndToolsTogether` failed twice, "utilities-section-annotate cannot be reached in the panel" (`/tmp/pn-two3-iphone-new.log`, `/tmp/pn-two4-iphone-du.log`). **Not mine**: on plain `a4a4281`, without this change, it fails the same way at the same line (`/tmp/pn-baseline-du.log`). Its owner says its scrolling helper was tuned on an iPhone 17 and may overshoot the Duo's drawer, and will fix the test |
| `ReadAloudUITests` and the reader suites (find, selection, links, restricted, annotations, bookmarks, print) | iPad: read aloud **4/4**, the rest **17/17**. iPhone: read aloud **4/4** after one failure under load, the rest **17/17** (read aloud entry below) |

**What the tests prove.** `PageSpreadsTests` (8): pages pair from the first; with the cover alone two faces three; a
wide page stands alone and so does the page before it; a wide cover; a square page is not wide; no pages and one
page; across 23 pages with landscape ones scattered, with and without the cover, every page is in exactly one spread
of one or two, in order; the spread a page is in. `TwoPageViewTests` (5), on pages imported into a real library: the
spread of the page being read, with and without the cover; a landscape page alone; previous and next step a spread
from either page of one and stop at the ends, with and without the cover; each page's share of the width; a
throwaway library starts one page at a time.

`TwoPageViewUITests` (2): on an iPad, Two Pages puts pages 1 and 2 side by side — page 2 to the right, the same
height, wholly on screen; a tap on page 2 makes it the page being read and keeps the spread; next, from page 2,
brings 3 and 4 and is then unavailable, and previous brings 1 and 2 back; going to page 3 brings 3 and 4; Cover Page Alone makes page 3 face page 2 and leaves the cover alone; switched off, one page again and the
cover option gone. On a phone the switch is not offered. In French and Spanish the switch is named, on screen and a
full-width row on an iPad, and absent on a phone.

Screenshots: `docs/screenshots/two-page-2026-11-14/`.

**Not verified, plainly.**

- **The Mac**: built, not used. The switches are offered there; the spread was not seen.
- **On a portrait iPad with the library sidebar and Document Tools both open**, the middle column is narrow and two
  pages in it are small (screenshot `ipad-spread-1-2.png`). Two pages suit landscape, or a closed panel.
- **Zoomed in**, a spread is two pages at that zoom, side by side, scrolled together; that was not looked at, nor a
  spread's pinch.
- Right-to-left documents pair left to right.
- A page turned in PaperNest counts by its turned size: a portrait page turned a quarter turn stands alone.
- Links on the page beside the one being read are not tappable until it is tapped once (the link overlay is only on
  the page being read). Selecting text works only on the page being read.

## 2026-11-14 — Reader features R4: Read aloud (Claude, owner's queue)

Owner: **"Yes, go on"** to read aloud and two-page view, the last two items of the reader queue. This entry is
**read aloud** only. Neither feature is in `ProFeature`, so both are free; nothing was gated.

**What changed in the app.** **Read Aloud** in the title menu (and in the Mac's Page menu, with no shortcut — the
system has its own Edit > Speech, and this project has been bitten by clashing keys). It reads the document from
the page being read to the end, in the system voice for each page's own language, and lights the word being said
with find's colour for the current hit. A bar under the toolbar says which page it is on and has a speed button
(1× → 1.25× → 1.5× → 0.75×, the numbers shown as they are in every language), Pause/Resume and Stop. It turns the
page itself when it reaches the next page with words on it and passes over pages without (a scan nobody has
recognised). If the reader turns the page while it is talking it starts again there; turned while paused, it waits
for Resume and starts there. When the line being read leaves the screen — zoomed in, or on a phone's tall page —
the page scrolls just far enough to keep it in view. A page with no text says so and says how to get some. It
pauses when the app goes to the background and stops when the document closes; only one document talks at a time.

**How it is built.**

- `ReadAloudScript` (`Sources/PaperNestCore/ReadAloudScript.swift`, new) turns a page's `PageTextLayout` into what
  is said, and maps what the synthesizer reports saying back to boxes on the page. **It does not use find's search
  text**: that is folded (case, accents and spacing removed), while a synthesizer reports a range of UTF-16 units of
  the very string it was given, so reusing it would light the wrong word on accented text. A word split across lines
  by a hyphen is said whole ("docu-" / "ment"); a line ending in a full stop and the like is followed by a pause; any
  other line runs on, so a sentence broken across lines is one sentence. Typed text boxes are read after the page's
  own words, on their own.
- `ReadAloud` (`Sources/PaperNestUI/Reader/ReadAloud.swift`, new) is the player; `SystemSpeech` wraps
  `AVSpeechSynthesizer`, made only when something is first said and held for as long as the document is open. Its
  delegate's calls are passed to the main queue, which keeps them in order, and each carries its utterance, so
  anything about an utterance that was stopped or replaced is ignored. On iOS the audio session is spoken audio
  (heard with the ring switch on silent; other audio ducks), held from the first word to Stop — not let go and
  taken back at each page turn or change of speed — and set up and released on a serial queue off the main thread,
  which the system warned about. A call or an alarm pauses reading. A synthesizer that was cut off mid-utterance is
  let go and a fresh one takes the next utterance (see *Found while testing*).
- Shared files: `DocumentView.swift` (one `@State`, the title-menu item, the bar in the top inset after find's, the
  highlight overlay before `nightFilter`, scrolling to the line, pause on background, stop on close),
  `PaperNestCommands.swift` (the Page menu item), `Localization.swift` and the strings (block `Read aloud`, seven
  keys in en/fr/es).

**How it reached the branch.** It did not go in as its own commit. At 15:30 another session committed everything in
the working tree at the owner's word, as `1e7fdda` ("Document Tools in the Option 6 layout, and read aloud in
progress"), and read aloud went in with it as it stood. Checked afterwards: every read-aloud file, and the text-box
fix in the entry below, is byte for byte the version verified here, and every line it added to the shared files
(`DocumentView.swift`, `Localization.swift`, the strings, `PaperNestCommands.swift`) is in that commit. The same
commit dropped Night Mode's switch from Display settings (see the two-page entry above).

**Results.** First in a clean worktree holding `81e5937` plus only this change; then the tree as it now stands on the
branch, `a4a4281` plus the two-page work above.

| Check | `81e5937` + read aloud | `a4a4281` + two-page view (the branch as committed) |
|---|---|---|
| `./scripts/test.sh` | **Passed: 1,054 tests**, 0 failures, 0 warnings — `/tmp/papernest-readaloud-unit4.log` | **1,071 passed**, 0 warnings — `/tmp/pn-two3-unit.log` (`1e7fdda` alone: 1,055 passed, `/tmp/pn-head-unit.log`) |
| New: `ReadAloudScriptTests` 10 (11 cases), `ReadAloudTests` 14 | **Passed** | Passed |
| `./scripts/build-mac-app.sh` | **Built**, 0 warnings | Built, 0 warnings |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **BUILD SUCCEEDED**, 0 warnings | Succeeded, 0 warnings |
| `ReadAloudUITests` (new, 4), iPad Pro 13-inch (M5), iOS 26.5 | **4/4** — `/tmp/pn-final-ipad-ra.log`, no runner restarts | **4/4** — `/tmp/pn-two3-ipad-ra.log` |
| `ReadAloudUITests`, PaperNest iPhone Duo, iOS 27.1 | **4/4** — `/tmp/pn-final2-iphone-ra.log`, no restarts | 3/4, then **4/4**: the main test failed once at its first step ("Timed out while evaluating UI query", one runner restart, the load jumping from 23 to 108–170 — `/tmp/pn-two3-iphone-ra.log`); run again, 4/4 (`/tmp/pn-two4-iphone-ra.log`) |
| `DocumentFindUITests` 3, `TextSelectionUITests` 2, `PageLinksUITests` 2, `RestrictedPDFUITests` 2 | iPhone **9/9** (`/tmp/pn-final-iphone-text.log`); iPad: the run was taken over by another session's tests (below) | iPad **9/9**, iPhone **9/9** — `/tmp/pn-two3-ipad-reader.log`, `…-iphone-reader.log` |
| `PDFAnnotationsUITests` 3, `NightModeUITests` 3, `BookmarksUITests` 3, `DocumentPrintUITests` 2 | iPad **11/11** earlier in the day, before the last two speech changes and the text-box fix (`/tmp/papernest-readaloud-ipad-5.log`, a bookmarks test failing once under a load average of 160 and passing 3/3 run alone); iPhone 14/14 across `/tmp/papernest-readaloud-iphone-2.log` and `-6.log` | `PDFAnnotationsUITests`, `BookmarksUITests`, `DocumentPrintUITests`: iPad **8/8**, iPhone **8/8** (same logs). `NightModeUITests`: iPad **3/3**, iPhone **3/3**, with its switch put back (`/tmp/pn-two3-ipad-new.log`, `…-iphone-new.log`) |

**What the tests prove.** `ReadAloudScriptTests` (10 tests, 11 cases) and `ReadAloudTests` (14, the player driven by
a fake voice):

- Lines run on as one sentence and pause after a full stop; a hyphen-split word is said whole and lights on both
  lines; a hyphenated name is left alone; a word a digital PDF gives as a fragment per character lights as one box;
  an accented word — precomposed and decomposed — lights itself and the word after it lights the right box; a
  ligature fragment lights as one; typed text comes after the page and apart; an empty page says nothing; starting
  part-way through maps the synthesizer's ranges back to the same words.
- It starts at the page being read and lights each word; turns to the next page with words, passing over one
  without, and its own turn does not restart it; the reader turning the page starts it there, or waits for Resume
  when paused; a finish reported after Stop does nothing; a new speed starts from the current word, and the replaced
  utterance finishing late does not turn the page, so no page is skipped; pause, resume, and a speed change while
  paused taking effect on resume; a call pauses; the end of the document stops; a document with no words says so;
  starting another document stops this one; the speed button goes round; a French page is read in French; the
  audio is held across page turns and speed changes and given back on Stop; a word with no box on the page leaves
  the light on the word before rather than putting it out.

**Proved able to fail.** With the hyphen join switched off, `aWordSplitAcrossLinesIsSaidWhole` failed; with the
check that an event belongs to the utterance being said removed, `aNewSpeedStartsFromTheCurrentWordAndSkipsNoPage`
failed (the replaced utterance turned the page). Both put back. A third guard — remembering a page turn it made
itself — never failed when removed, because the player already records the new page before turning to it; it was
taken out rather than kept as code nothing needs.

**Found while testing, in the running app, and fixed.**

1. **Changing speed sometimes silenced it on iOS 27.1.** A new speed stops the utterance and starts the rest of
   the page at once. On the iPhone Simulator (iOS 27.1) the new utterance was sometimes never said:
   `testTheSpeedButtonChangesSpeedAndReadingCarriesOn` failed **two runs in three** ("no word was lit after the
   speed changed"), and never on iPadOS 26.5. Two changes: the audio session stays held between utterances (it
   had been released and re-taken in between), and a synthesizer cut off mid-utterance is replaced by a fresh one
   for the next. After both, the test passed **three runs in three** on the iPhone. That is evidence for the cause,
   not proof of it.
2. **Audio session work on the main thread**: the system logged that `setActive` there "can lead to UI
   unresponsiveness". It now runs on a serial queue.
3. **The Simulator's voice runs several times faster than real speech**: two short lines, page turn included,
   were read in about a second and a half, before the UI test looked. The test's pages are long for that reason,
   and it lets a pause settle for half a second, because a pause lands at the end of the word being said and the
   next word's notice can already be on its way.

**Runs that do not count.** This machine was shared all afternoon with other sessions running their own Simulator
tests, with load averages from 30 up to 570. Three kinds of run were thrown out, and are listed so nobody mistakes
them for results:

- Two iPhone runs of the whole set overlapped another session's `xcodebuild test` on the same iPhone Duo Simulator:
  the runner restarted again and again ("Restarting after unexpected exit, crash, or test timeout") and whole
  suites, Read Aloud among them, were silently skipped.
- One iPad run of the text suites was taken over outright: the other session installed its own test runner on the
  same Simulator, and the failures in my log pointed into its worktree (`/tmp/pn-verify3/…`).
- One iPhone run of the French and Spanish test failed at launch ("editor not shown after 30 s") as the load climbed
  back towards 90. It had passed in three earlier runs and passed in the next.

Since then every run waits for the load to fall below 25–30 and for no other `xcodebuild test` on that Simulator,
and its log is checked for restarts and for paths from another worktree. One bookmarks test failed in an iPad run
of the whole set with the load near 160 and passed 3/3 run alone.

**Not verified, plainly.**

- **Nobody listened to it.** Every UI run spoke at volume 0 (`-PaperNestDebugSpeechVolume 0`, development builds
  only) so as not to talk through the Mac's speakers. Whether the voice reports its words at volume 0 was checked on
  the Mac (eight of eight words at 0 and at 0.01), and on both Simulators the words went by. How it sounds — the
  pauses between lines, the voice chosen for each language — was not judged by ear.
- **The Mac**: built, not used. The Page menu item was not seen.
- **No background audio**: the app does not declare it (an Info.plist and App Review matter for the owner), so
  reading pauses when the app goes to the background and the lock screen has no controls.
- Form answers drawn on a page (the annotation work above) are not in its text and are not read. Words a crop hides
  are skipped. Right-to-left text, vertical text and tables were not tried; text is read in the order the page's
  text layout gives it.
- Voices: a language whose voice is not installed is read in the system's default voice; nothing offers to
  download one. Speed changes restart from the start of the current word.
- VoiceOver users have the system's own speech; how Read Aloud and VoiceOver behave together was not tried.

## 2026-11-14 — Find, selection and read aloud lit the wrong letters on every line after the first (Claude)

Found while building read aloud (entry above). On a digital PDF of several lines the reader lit no word at all for
"2" of "Line 2". Measured on the fixture: **every line's character boxes sat one character further along than the
line before's.** Line 2's "L" came back with the box of the "i", and by line 4 everything was three characters off,
with blank boxes where the shift landed on a gap. Find's highlights, the text selection and read aloud's light all
take their boxes from `PageRenderer.textLayout(for:)`, so all three were off on any page with more than one line —
on real documents, nearly every page. Older than today: it came in with the text layout (`b2d52c0`).

**Cause.** `PageTextReader.embeddedLines` asked `PDFPage.characterBounds(at:)` for each character by its position
in `PDFPage.string`. The two do not count the same way: `string` has a line break between lines that
`characterBounds(at:)` does not count. Measured with a scratch program on a three-line page: index 18 is the line
break in `string`, and `characterBounds(at: 18)` is the box of the next line's "L". A one-character
`selection(for:)` is indexed the way `string` is, and its bounds are right.

**Fix.** Each character's box now comes from `selection(for:)`. Cost, measured on real form pages: 3 ms for the
2,680 characters of the N-400's first page, 2 ms for the I-765's. One file: `Sources/PaperNestRender/PageTextReader.swift`.

**Why no test caught it.** Every test of the text layout used a page of one line; so did the find and selection UI
tests' words. New: `everyLineOfADigitalPDFIsBoxedWhereItIsDrawn` — four lines; every character has a box, every
line starts under the first, and the number on the last line has ink under its box and none beside it. It
**failed before the fix** (line 2 started at 0.1347 against line 1's 0.1199, and lines 2 and 3 had characters with
no box) and passes after.

**How it reached the branch.** With read aloud, in `1e7fdda` (entry above), byte for byte the version verified.
**Results** are those of the read aloud entry: the two were verified together. Of what this touches: `PageTextReaderTests` 15/15 (the two new tests among them), `DocumentFindTests`,
`PageTextSelectionModelTests`, `PageTextSelectionTests`, `WordBoxTests` pass; in the running app, on the branch as committed (`a4a4281` plus two-page view), `DocumentFindUITests`,
`TextSelectionUITests`, `PageLinksUITests` and `RestrictedPDFUITests` pass 9/9 on the iPad and 9/9 on the iPhone.

**Not verified.** Scanned pages are unaffected (their words come from recognition, with their own boxes) and were
not re-checked. Right-to-left and vertical text were not tried.

## 2026-11-14 (evening) — Document Tools on the Mac, seen on screen; a crash fixed (Claude)

Owner granted screen access to the dev Mac app. Throwaway library, the sample `multilingual-letter` PDF.

- **Crash, mine, fixed.** Opening any document crashed the Mac editor: `ToolGridLayout.columns(for:)` turned an
  infinite width into an `Int` ("Double value cannot be converted to Int because it is either infinite or NaN").
  A Mac inspector column asks its content for an ideal size at infinite width; iPhone and iPad never do, so every
  simulator run passed. It shipped in `1e7fdda` and `a7c79e5`. Fix: `ToolGridLayout.usableWidth(_:)` answers nil,
  infinite, NaN or zero with the panel's inner width; `anUnboundedWidthIsAnsweredWithoutTrapping` covers it.
  Found from the crash report, then confirmed fixed by reopening the same document.
- **Panel opened scrolled past Pages**, also mine: the thumbnail strip's `ScrollViewReader.scrollTo` scrolled every
  enclosing scroll view. Now bound to the strip's own `scrollPosition`, so only the strip moves.
- **Seen working on the Mac, after both fixes:** Document Tools as the right column with real thumbnails and Pages
  (3); four tools across in each section; pinned Export / Save; the stacked-layers toggle hiding the panel and the
  page widening, then showing it again; ⌥⌘0 hiding it; Next Page twice to 3 / 3 with thumbnail 3 selected; zoom in
  to 200% from the floating bar.
- **Not checked on the Mac:** hover appearance, dragging a thumbnail to reorder, dark mode, the Compress and Convert
  sheets, resizing the column.
- Unit suite green. The commit's tree (HEAD plus only these hunks; the Reader features session's two-page hunks left
  in the working tree) was compiled on its own before committing.

## 2026-11-14 — Document Tools "Option 6" (Claude, owner's request)

Owner supplied the Option 6 mockup and brief. Built by regrouping the Document Utilities panel of 2026-11-12, not a
new container. **Not committed** — the read-aloud session holds an active claim on the same files (handoff).

**What changed.**
- Panel renamed **Document Tools**. Sections: **Pages** (real thumbnails, lazily rendered; Add Page / Organize /
  Rotate / Delete underneath), **Edit PDF** (Crop, Rotate, Filter, Split, Replace Page), **Annotate** (Highlight /
  Underline / Strike Through recognised text, Comments, Draw, Draw with Finger, Signature, Manage Markup),
  **Insert** (Text, Image, Shape, Stamp), **Process** (Recognize Text, Fill Form on PDFs, Compress, Convert to Word).
  Each section folds on its own and remembers it. **Export / Save** is pinned below the list.
- Tiles lay out as many to a row as fit (minimum 96 pt on iOS, 76 on Mac): two in an iPad column, three on a phone.
- **New, real functionality:** *Split* (`DocumentModel.split()`, Pro gate as in the library, confirms how many
  documents were made); *Compress* (`CompressSheet`, new — the exporter's Light/Strong/Smallest presets, which had no
  screen until now; shows the real before/after sizes and says so when nothing could shrink; Save or Share the copy;
  the library is untouched); *Convert* opens the existing export sheet with Word chosen (`initialFormat`), every
  gate still applying; the three text-markup tiles open the existing sheet on their style (`initialStyle`).
- **Bottom bar:** − / 100% / + / fit | ‹ n / N › | drawing mode | display settings. The percentage opens display
  settings. Previous/Next go through the same path as a thumbnail tap.
- **Phone drawer:** two heights (tap or drag the handle) and swipe down to close; accessibility actions for both.
- **Dark palette** (`EditorChrome` only, not `Theme`): the owner's #151222 / #241F37 / #302A46 / #49405F, white and
  #BFB9D1 text; accent text and icons are the lavender #B99AFF on dark panels because #7438F5 there is too faint.

**Results.** Unit suite green after one fix (a French colon). Mac build clean, 0 warnings. **Run on different
simulators from earlier, in a separate build folder,** because the read-aloud session was testing on the iPhone Duo
and iPad Pro 13 at the same time:

| | iPhone 17, iOS 26.5 | iPad Pro 11-inch (M5), iOS 27.0 |
|---|---|---|
| `DocumentUtilitiesUITests` (5: one toggle; page stepper; Process does real work; lower bar; phone drawer) | 5/5 light | 4/4 (drawer test skips on iPad) |
| same, dark appearance | one-toggle passed; drawer test failed at its first wait (see below) | one-toggle and Process passed |
| `NotesToolbarUITests/testEveryToolChangesWhatIsSaved` | passed | **failed** — Pen settings scroll view "visible frame is empty" |
| `EditorFirstTouchUITests` (3) | 3/3 | not run |

`testProcessToolsDoRealWork` checks on disk: Convert opens export with Word selected; Compress produces a measured
result with Save and Share; Split makes exactly one new document per page and keeps the original.

**Failures, honestly.**
- The toolbar test on the **11-inch** iPad fails opening the Pen panel. It passed on the 13-inch on 2026-11-12 and
  today's work did not touch the toolbar or its panels — but **it was not baselined on this device**, so I cannot
  say it predates today.
- The dark-mode phone drawer test failed waiting for the panel right after the previous test relaunched the app; the
  same test passed in light mode minutes earlier. This looks like the empty-accessibility-tree-after-relaunch flake
  recorded on 2026-11-12, but that is a resemblance, not a finding.
- My test helper first used full swipes, which in the phone's short drawer carried section headers straight past;
  short drags fixed it. That was a test defect only.

**Not verified.** The Mac (still never seen). VoiceOver. Fit to Width. Replace Page, Organize, the thumbnail menu,
Insert Image and Stamp from the panel (present, not driven). The paywall path of Split and Convert (this build has
no product IDs, so Pro is open). The 13-inch iPad and iPhone Duo (busy with the other session's tests).

**Not built from the brief.** Merge from inside the editor (needs another document; the library's Tools has it).
Resize page. Drag-and-drop thumbnail reordering (Organize does reordering). Page viewing modes. Signature/Comments on
the top toolbar (left as is, per "maintain the existing toolbar"). The top toolbar's More (…) menu still repeats the
panel's tools — the earlier brief's "no duplicate controls" is not yet met there; that is the owner's call. Sync
status in the editor: the app sidebar already shows the real iCloud state ("Not set up in this build").

## 2026-11-14 (afternoon) — The reader features seen on a Mac at last, and two more night-mode bars fixed (Claude, owner in session)

Owner: **"yes i give sreen access for mac"**, then **"Ask again"** when the first request came back declined. The Mac
was the one platform none of night mode, bookmarks, find, text selection or links had been seen on. Done with the
dev app (`./scripts/build-mac-app.sh`) built from a clean worktree of `f02e424`, on a throwaway library seeded with
`Samples/multilingual-letter.pdf` (three pages of text) plus two hand-written PDFs: one with an internal and a web
link, one with a filled form field. Background control only: the app was driven through accessibility and the
menu bar, and what it saved was read back from the library on disk.

**Seen working on the Mac** (screenshots in `docs/screenshots/reader-mac-2026-11-14/`):

- **Night mode.** The switch in Display settings (the popover scrolls on a short window) turns the page dark with
  light print; the toolbars, the sidebar and Document Utilities stay as they are. A pen stroke drawn at night shows
  light and was **saved black**; a highlight shows as a dim amber band and was **saved amber**; a text box typed at
  night shows light words, its formatting bar keeps **day colours with a black swatch** (the `f02e424` fix, now seen
  on the Mac), and the note was **saved black**. A filled form's answer ("Jane Sample") shows light on the dark page.
- **Bookmarks.** Page > Add Bookmark shows the red ribbon (red at night too) and saves one row. Page > Go to Page… took
  "3". Page > Bookmarks… lists Page 1; its Add Bookmark button marked page 3 and **the list updated in place** (Page 1,
  Page 3, the button turning into Remove Bookmark); clicking the Page 1 row went to page 1 and closed the list.
- **Find.** Page > Find… opens the bar; "statement" gave **1 of 1**, lit orange on the dark page.
- **Selecting text.** A pointer drag selected "Synthetic sample —"; **Copy put exactly that on the clipboard**, dash
  included (read back with `pbpaste`). Highlight from a selection saved highlighter strokes (see the defect below
  for how many).
- **Links.** Both links are on the page to accessibility ("Go to page 3" and the web one). The web link raised
  "Open this link?" **showing its full address**, with Open, Copy Link and Cancel; **Copy Link copied
  `https://example.com/`**. The internal link turned to page 3. Open was not pressed, to keep a browser off the
  owner's screen.
- Everything drawn and typed was still there after quitting and reopening the app.

**Two defects found on the Mac and fixed — the same kind as `f02e424`.** Night mode darkens everything drawn over
the page, and two more bars of controls are drawn there:

1. **The bar over selected text** (Copy, Highlight, Underline, Strikethrough) went dark at night
   (`mac-night-selection-bar-before-fix.jpg`).
2. **The lasso's selection bar** ("1 selected", edit, more, deselect) went dark too.

Fix: one `.nightFilter(isNight)` on each, in `TextSelectionOverlay.swift` and `PageSelectionOverlay.swift`; the
filter is its own opposite, so the bar gets its day colours back while the page and what is selected on it still
turn. `DocumentView.swift` untouched. Seen fixed on the Mac (`mac-night-selection-bar-after-fix.jpg`,
`mac-night-lasso-bar-after-fix.jpg`). Two new tests in `ReaderNightAndBookmarksUITests` read each bar off the screen
at night. **Proved able to fail:** without the fix both fail on the iPhone 17 simulator — selection bar averaging
rgb(32,31,41), lasso bar rgb(8,8,9) (`/tmp/pn-bars-before4.log`). With it:

| Suites (night mode, the reader-gaps suite, text selection) | Result |
|---|---|
| iPhone 17, iOS 27.0 | **10/10 + ⌘D skipped** by design, no restarts (`/tmp/pn-bars-after-B6966C5F-*.log`) |
| iPad Pro 13-inch (M5), iOS 27.0 | **11/11**, no restarts (`/tmp/pn-bars-after-6528AE8B-*.log`) |

Unit suite on that tree **1,029 tests, 0 failures, 0 warnings**; Mac build clean.

**A third defect found on the Mac, and left to the session that already has it.** On a page with several lines,
the character boxes behind find, selection and highlight-from-selection **drift one character per line**:
`PDFPage.characterBounds(at:)` does not count the line breaks that `PDFPage.string` puts between lines, while the
reader indexed it with positions in `string`. Seen on the Mac as: highlighting "Total: $1,234.56" (line 3) saved
**two** strokes, because the selection began at line 2's final "." whose box sat at line 3's start. Measured with
PDFKit on that page: `characterBounds(at: 26)` ("Q") returns the "u"'s box; `characterIndex(at:)` on line 3's "T"
returns 62, which is "." in the string; `page.selection(for:)` over a string range gives the right box. The
read-aloud session found the same thing independently and **has an uncommitted fix in
`Sources/PaperNestRender/PageTextReader.swift`** (boxes from `selection(for:)`); that file was not touched here,
and the Mac reproduction was sent to it. The unit tests that pixel-check boxes only ever used one-line pages, which
is why they did not catch it — a multi-line case belongs with that fix.

**Not verified on the Mac, plainly.**

- **Settled later the same day, with full-screen control (owner: "Approve and check").** With the Page menu really
  open, a bookmarked page reads **Remove Bookmark ⌘D** and an unmarked one **Add Bookmark ⌘D**; the "Add Bookmark"
  read through accessibility earlier was stale, not a bug. **⌘D pressed on the Mac keyboard** removed page 1's
  bookmark (ribbon gone, row gone from the library) and a second ⌘D put it back (a new row). In the Bookmarks list,
  a row's ⋯ menu opens with **Rename… and Remove Bookmark**; **Remove worked** — the row left the library and the
  ribbon went — though its effect landed only on the next input event, which looks like how simulated clicks end a
  Mac menu rather than the app. **Rename is not settled:** in three tries (a click, the keyboard, and an explicit
  press-and-release followed by bringing the app forward) no rename prompt appeared, and nothing was logged. Whether
  the prompt is broken on the Mac or the simulated clicks never delivered the choice is unknown; a person choosing
  Rename… on a Mac would settle it. Rename itself is covered on iOS by `BookmarksUITests`.
- **⌘F and ⌘G pressed on a Mac keyboard** (⌘D was, see above).
- Pressing Open on a web link; VoiceOver; a second window on the same document.
- **Settled the same afternoon: the iPad Air 13-inch (iOS 26.5) failure was the tests, not the app.** There,
  the selection-bar test — and the original `NightModeUITests` test too (`/tmp/pn-ipadair-night2.log`) — could not
  find the Night Mode switch. A throwaway probe on that simulator waited three seconds after opening the document
  and tapped Display: the popover opened with Night Mode in it, seen and present to accessibility
  (`display-night-mode`). `EditorFirstTouchUITests` passes 3/3 there (`/tmp/pn-ipadair-firsttouch.log`), so the first
  touch is not being swallowed. The tests' tap came the moment the document had opened, and on that model it came to
  nothing. `ReaderNightAndBookmarksUITests` now taps Display again if the switch has not appeared after 3 s, and
  passes **6/6** there (`/tmp/pn-ipadair-gaps.log`). `NightModeUITests` belongs to another session and still taps
  once; it will fail the same way on that model until it does the same. **What a person sees on that iPad is fine;
  why a very early tap does nothing there is not known.**

## 2026-11-14 — Night mode and bookmarks re-checked on today's code, and four of their gaps closed (Claude, owner in session)

Owner: **"finish night mode and bookmarks"**, then **"Try again"**. Both were already built and committed on
2026-11-13 (`dd405ea`, `35b9a93`); an earlier report of mine in another session called them uncommitted drafts,
which was out of date. So "finish" meant two things: prove they still work after the ten commits that landed on
top of them — two of which change the very picture night mode recolours (`78d7e77` draws form answers and other
annotations into the page; `e61ebf2` makes pictures follow the print flags) — and close the gaps in their
"Not verified" lists most likely to hide a real defect.

**Where it was run.** A clean worktree of `HEAD` (`81e5937`), not the main checkout: the main checkout carries a
stopped session's unfinished read-aloud edits in `DocumentView.swift`, `PaperNestCommands.swift`, `Localization.swift`
and the strings, and testing there would have tested a state nobody committed.

**Results on `81e5937`.** Unit suite **1,029 tests, 0 failures, 0 warnings**; `./scripts/build-mac-app.sh` clean.

| Suite | iPad Pro 13-inch (M5), iOS 26.5 | iPhone: PaperNest iPhone Duo (iOS 27.1) or iPhone 17 (iOS 27.0) |
|---|---|---|
| `NightModeUITests` (3) | 3/3 | 3/3 (Duo) |
| `BookmarksUITests` (3) | 3/3 | 3/3 (iPhone 17) — see below |
| `ReaderNightAndBookmarksUITests` (new, 4) | 4/4, final code | 3/3 + ⌘D skipped by design (iPhone 17), final code |
| `DocumentFindUITests` (3) | 3/3 | 3/3 (Duo) |
| `TextSelectionUITests` (2) | 2/2 | 2/2 (Duo) |
| `PageLinksUITests` (2) | 2/2 | 2/2 (Duo) |

Logs: iPad `/tmp/pn-verify-ipad-1.log` (all six suites) and `/tmp/pn-verify-ipad-2.log` (the new suite on its
final code); iPhone Duo `/tmp/pn-verify-iphone-1.log` and `-2.log`; iPhone 17 `/tmp/pn-verify-iphone17-1.log`.
**The iPhone column took three devices' worth of runs, and the reason matters.** On the Duo, the first run's
Bookmarks, Find and Night Mode tests never got going — XCTest restarted its runner nine times — and the second run
lost `testABookmarkIsStillThereAfterRelaunch` at launch; a third run had both its tests "crashed with signal kill".
**The app did not crash once** (no crash report). Another session had started its own UI tests on the same Duo
simulator, and two test runs on one simulator kill each other's runner. The Bookmarks suite and the new suite were
then run on an idle iPhone 17 simulator (iOS 27.0), where every test passed with no restart. So the bookmark
suite's iPhone result is on iOS 27.0, not 27.1.

**What the new suite proves** (`Apps/iOS/UITests/ReaderNightAndBookmarksUITests.swift`):

- **Typing at night.** With Night Mode on, a text box placed on a PDF page takes every letter ("Night note"), shows
  light print inside the box while it is typed, and is **saved in the colour chosen, not its night shade** — read
  back from the library on disk. The page reads light on dark again once the box is placed.
- **A filled form at night.** A field whose answer PDFKit draws (`acroFormPDF`, "MMMMMMMM") shows the answer dark on
  light by day and **light on dark at night**, read off the screen in the field's own box. This is the first check
  of `78d7e77`'s annotation drawing together with night mode. (`PDFAnnotationsUITests`, from that commit, already
  covers the drawing itself on iOS by day.)
- **⌘D from a hardware keyboard (iPad).** It shows the ribbon and saves one bookmark; ⌘D again removes both.
  Skipped on the phone by design: a phone has no menu bar for the shortcut to live in. **While it ran, the app's
  whole log was streamed at debug level** (about 41,000 lines from the app, 210 of them UIKit's): **no**
  `MenuBuilder` message and nothing about a conflicting shortcut. The 2026-11-13 entry could only say that of the
  iPhone; now it is true of the iPad too, for this launch.
- **A notebook's continuous pages, at night.** Go to page 2 and Add Bookmark: exactly one ribbon, on page 2, saved
  against page 2's id. At night the ribbon reads as **red** on the dark page (sampled off the screen). From page 3,
  the Bookmarks list's row leads back to page 2.

Screenshots: `docs/screenshots/reader-gaps-2026-11-14/`.

**Three things learned, for whoever tests the editor next.**

1. **On a phone the bottom bar floats over the lower part of the page.** A patch of "plain paper" sampled at y 600
   of 792 was the bar, which is light at night, and two of the new tests failed for it on the first iPhone run. They
   sample at y 430 now (`plainPaper`).
2. **Going to a page in a phone notebook centres it, so its top edge — and the ribbon — are out of sight above.**
   Zooming out to bring it back made it worse (the ribbon went to y −91). Dragging in the margin beside the paper
   scrolls it back into view. A reader who goes to a bookmark on a phone does not see its ribbon until they scroll
   up; that is how notebook navigation behaves today, recorded here rather than changed.
3. **Two test runs on one simulator kill each other.** Another session started its own UI tests on the same iPhone
   simulator while mine ran; XCTest reported my two tests as "crashed with signal kill" and the app never crashed.
   The Mac was also nearly out of memory at the time (15.4 of 16 GB of swap). Check `pgrep -fl "xcodebuild test"`
   for a run on your simulator before starting one.

**One night-mode defect found by these runs, and fixed.** While a text box was being typed in at night, **its
formatting bar was turned too**: the bar went dark and the colour swatch for black text showed **white**
(`docs/screenshots/reader-gaps-2026-11-14/iphone-typing-at-night-before-fix.png`). Nothing wrong was stored — the
text was saved black — but the swatch told the reader the opposite of the colour they had chosen, and night mode's
own rule is that controls stay as they are. The bar is drawn in the page's overlay, under the page's night filter.
**Fix:** `InlineTextOverlay.swift` gives the bar the same filter again; the filter is its own opposite (invert,
then turn the hue half way round — for SwiftUI's hue matrix that is exact), so the bar is back in its day colours
while the words being typed still turn. Two lines; `DocumentView.swift` untouched.
`testTextTypedAtNightIsSavedInItsOwnColour` now reads the swatch off the screen. **Proved able to fail:** on `HEAD`
without the fix it failed on iPad with the swatch at rgb(255,255,255) (`/tmp/pn-swatch-before.log`). With the fix:
iPad **7/7** and iPhone 17 **6/6 + ⌘D skipped** across `NightModeUITests` and the new suite
(`/tmp/pn-swatch-after-*.log`); unit suite **1,029 tests, 0 failures, 0 warnings**; Mac build clean. Not looked at:
the bar at night on a Mac, and the colour picker popover (it opens in its own window, outside the filter either way).

**Still not verified, plainly.** **The Mac** — screen access has been declined before and was not asked for again;
night mode and bookmarks there have only been built. A physical iPad or iPhone, Apple Pencil, VoiceOver and the
largest text sizes. Switching Night Mode *while* a text box is being typed in is not reachable in the app today:
the bottom bar that holds Display settings stands down while a text box is being edited, on both phone and iPad.
Rotated and cropped pages at night, swipe-to-remove a bookmark, and the rename alert in French and Spanish.

## 2026-11-14 — Print allowed in the Mac's iCloud signing file (Claude, owner in session)

Owner: **"Yes, add it"**, asked whether to add the print entitlement to `Apps/Mac/PaperNest.iCloud.entitlements`
myself. A sandboxed Mac app may not open the print panel without `com.apple.security.print`. The development file
`Apps/Mac/PaperNest.entitlements` has had it since Print (`2ce8567`), but a build with iCloud switched on is signed
with the iCloud file, which did not have it: Print would have failed there and nowhere a test could see.

That file also holds someone else's uncommitted edits (the iCloud keys taken out). They are left in the working tree
as they were, with the print key added beside them; **the commit holds only the two print lines**, on top of the
file as it is in `HEAD`.

| Check | Result |
|---|---|
| `plutil -lint`, the committed file and the working copy | **OK** both |
| Each compared with what it was | Only `com.apple.security.print` → `true` added |
| A copy of the development Mac app signed ad hoc with the committed file, entitlements read back with `codesign -d --entitlements` | **`com.apple.security.print` = true** is in the signature |

**Not verified:** a build with iCloud switched on was not made — it needs a provisioning profile for a container
that does not exist yet (see the iCloud rows further down) — and nothing was printed from a Mac.

## 2026-11-14 — Annotations, follow-up: pictures follow the print flags; the exporter's PDFKit work checked under load (Claude)

Two things the entry below claimed or left open, checked after it was committed (`78d7e77`).

- **A JPEG, PNG or HEIC picture of a page drew the screen's marks, not paper's.** The docs said every page that
  leaves the app follows the author's print flags; picture exports went through `renderImage`, which draws for the
  screen, so a mark the author kept off paper was in the picture and not in a PDF export of the same page. Now
  `renderImage(… annotations:)` takes the rule and picture exports ask for `.paper`. New test
  `anImageExportKeepsTheMarksMeantForPaper` **failed first** (20,636 blue pixels where none belong), then passed.
- **Does printing a form while its pages are drawn hang?** Page drawing builds a form's fields under
  `PDFKitAnnotationLock`; the exporter's copy of an untouched page and its PDFKit write do not take the lock. New
  test `printingAFormWhileItsPicturesAreDrawnFinishes`: sixteen pictures of a filled, restricted form drawn while
  four print exports of it, each with a password so the page is copied and written through PDFKit, run at once.
  **Passed 7 of 7 runs, in about 0.1 s each.** So the exporter was left outside the lock, and `ARCHITECTURE.md` now
  says which code takes it and which does not, and that this was measured, not explained. Nothing proves the
  exporter can never meet the deadlock; seven runs found no sign of it.
- **Saved page pictures**: none. `ThumbnailCache` keeps page pictures in memory only, so forms already in a
  library show their answers the next time their pages are drawn; nothing needs clearing.

| Check | Result |
|---|---|
| `./scripts/test.sh`, clean worktree of `78d7e77` + this change | **Passed: 1,029 tests** (320 + 49 + 191 + 180 + 179 + 110), 0 failures, 0 compiler warnings — `/tmp/papernest-annots2-unit.log` |
| `anImageExportKeepsTheMarksMeantForPaper` (new) | Failed before the change, passed after |
| `printingAFormWhileItsPicturesAreDrawnFinishes` (new) | **7/7** runs passed |
| `./scripts/build-mac-app.sh` | **Built**, 0 warnings |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **BUILD SUCCEEDED**, 0 warnings |

No UI test was run for this follow-up: it changes what is in an exported JPEG, PNG or HEIC of a PDF page that has
annotations, which the unit test reads, and nothing on screen.

## 2026-11-14 — Form answers and other PDF annotations are drawn on the page (Claude, owner in session)

Owner, after the USCIS entry below named what was left: **"Fix everything as per your understanding"**. This
entry is the part of "everything" that could be fixed and checked here; the end of it lists what was not.

**What was wrong.** PaperNest draws a PDF page with Core Graphics' `drawPDFPage`, which draws the page's
**content** and nothing else. A PDF keeps several things a reader sees in **annotations** instead: the answer typed
into a form field, a checkbox's tick, a box, stamp or highlight another app drew. None of them was on the page in
PaperNest, in its thumbnail, or on any page PaperNest had to redraw for an export or a print. So a form filled in
Fill PDF Form opened again with empty boxes, and drawing one line on a filled-in form lost its answers from the
export and from the print. It was true of every PDF, long before the USCIS forms made it easy to meet.

**What changed.**

- **`PageAnnotations`** (`Sources/PaperNestRender/PageAnnotations.swift`, new) draws a PDF page's annotations
  over its content, through PDFKit — which is what Preview draws with — in the same space and under the same clip.
  It is used everywhere a PDF page is drawn: the page, thumbnails, a page drawn as pixels because of a filter, the
  picture text recognition reads, the picture redaction paints over, and pages an export or a print redraws.
- **What is drawn.** Links and pop-ups never (a link is somewhere to tap; the reader finds links itself), nor
  anything its author hid. On screen, everything else. On paper — Print, or a page an export had to redraw — only
  what the author also marked for printing, as Acrobat prints. A redrawn page carries a field's answer as part of
  the page: there it is no longer a field anyone can change, but it is no longer lost.
- **A page with no annotations costs nothing new**: whether it lists any is read from the page dictionary through
  Core Graphics, and PDFKit is never opened for it.
- **One lock for PDFKit's annotation work across the app** (`PDFKitAnnotationLock`), shared by page drawing,
  `PDFForm` (which had a lock of its own) and the link reader (which had none). See *Proved able to fail*.
- **PDFKit turns an annotation by the page's `/Rotate` as it draws it**, and PaperNest has already turned the
  page, so on a turned page every mark came out turned twice. Its transform is undone first.
- **Redaction refuses a page from a restricted PDF** (`RedactionError.restrictedByAuthor`), before anything is
  drawn or written: a redacted page is a new picture with no limits on it, which would have handed out what the
  author held back. Compressing was checked and needed nothing: a library document is compressed through
  `Exporter.export`, which keeps the limits, and a loose PDF file that is encrypted is refused.
- **Compressing a scanned page** draws its annotations meant for paper into the new picture, which carries none of
  its own.

No schema change, no new strings, no screen changed. Files: `PageAnnotations.swift` (new), `PageRenderer.swift`,
`PageLinkReader.swift`, `PageRedaction.swift`, `PageRedactor.swift`, `Exporter.swift`, `Compression.swift`,
`PDFForm.swift` (its lock is now the shared one).

**Results.** Verified alone, in a clean worktree holding `HEAD` (`6dd5da5`) plus only this change.

| Check | Result |
|---|---|
| `./scripts/test.sh` | **Passed: 1,027 tests** (320 + 49 + 191 + 180 + 177 + 110), 0 failures, 0 compiler warnings — `/tmp/papernest-annots-unit.log` |
| New: `PDFAnnotationRenderTests` 11, `AnnotationExportTests` 4 | **Passed** (red first: all 15 failed before the fix) |
| `./scripts/build-mac-app.sh` | **Built**, 0 warnings |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **BUILD SUCCEEDED**, 0 warnings |
| `PDFAnnotationsUITests` (new, 3) — read the simulator's screen | iPad Pro 13-inch (M5), iOS 26.5: **3/3** (`/tmp/papernest-annots-ipad-2.log`; the first two also in the run below). PaperNest iPhone Duo, iOS 27.1: **3/3** |
| The reader set, because every page picture goes through this: `RestrictedPDFUITests` 2, `DocumentFindUITests` 3, `TextSelectionUITests` 2, `PageLinksUITests` 2, `NightModeUITests` 3, `BookmarksUITests` 3, `DocumentPrintUITests` 2 | iPad **17/17** (`/tmp/papernest-annots-ipad.log`, 19/19 with the two annotation tests). iPhone **17/17** (`/tmp/papernest-annots-iphone.log`, 20/20 with the three), the load average about 35 from other work while it ran |

**What the tests prove.** `PDFAnnotationRenderTests` (11, on the renderer) and `AnnotationExportTests` (4), on
synthetic fixtures — `markedUpPDF` (new: a blank page whose only marks are annotations — a red box shown and
printed, a blue one shown but not printed, a green one hidden, a link) and the existing `acroFormPDF`:

- Marks kept in annotations are on the page, and in its thumbnail; the hidden one and the link are not.
- On a page turned 90°, 180° and 270° by its file, and on one whose crop box does not start at the media box's
  corner, each mark is where PDFKit itself puts it (compared with PDFKit's own drawing of the same file, within 2%).
- A crop made in PaperNest carries the marks with the page and cuts off the ones outside it; a page with a filter,
  drawn as pixels, keeps them.
- A filled-in field shows its answer; an empty one shows nothing. The picture text recognition reads shows the
  answer too (a choice: otherwise recognised words would disagree with the page on screen).
- Sixteen pictures of a form drawn at once all come back, each with the answer.
- Redacting one answer paints it out and keeps the answer beside it. A page from a PDF whose author forbade copying
  is not redacted and is left unchanged.
- A page drawn on and exported has the answer **in its content** — read back with Core Graphics alone, which draws
  no annotations — and no field left on top to draw it twice. A restricted form drawn on and made ready for the
  print panel has its answer in the page and is still closed to copying. A form filled with `PDFForm.filled` and
  imported shows the answer. A redrawn page has the mark meant for paper, not the one meant only for the screen,
  and not the hidden one.

`PDFAnnotationsUITests` (3), on the simulator's screen pixels — the proof that PDFKit's drawing lands the right
way up in an iOS context, which the Mac unit tests cannot give:

- A form with two answers shows both in their boxes and nothing in the empty third.
- The annotation-only page shows the red box top left and the blue one top right, nothing for the hidden box or
  the link; the page thumbnail shows both boxes.
- **End to end, the case people met:** a form whose author switched copying off, filled in PaperNest's own Fill
  PDF Form sheet, saved as a copy, the app quit and the copy opened again: the typed answer is in its box on the
  page. Before this change that copy opened with an empty box.

Screenshots: `docs/screenshots/pdf-annotations-2026-11-14/` (the filled copy reopened, and the annotation-only
page, on iPad and iPhone).

**Proved able to fail.** Before the fix all fifteen new unit tests failed (`/tmp/papernest-annots-red.log`), each
on its own assertion, the redaction refusal included. Then, with the fix in:

- **The lock taken out**: the run that draws sixteen pictures at once **never finished**. A sample of the stuck
  process showed nine threads waiting in `xpc_connection_send_message_with_reply_sync`, under CoreText's font
  lookup, under `-[PDFAnnotation getFontFromAppearanceString:]`, under `PageAnnotations.load` — the deadlock
  `PDFForm` had recorded for eight concurrent fills, reached now by drawing pages. Swift Testing's one-minute time
  limit did not end it; the run was killed after ten minutes. Lock put back.
- **Redrawn pages given the screen's marks instead of paper's**: `aRebuiltPageKeepsTheMarksMeantForPaper` failed
  ("a mark not meant for paper was printed"). Put back.
- PDFKit's transform not undone: the three turned-page cases failed, the marks turned twice. That is how the
  defect was found.

**The three real USCIS forms** (I-130, N-400, I-765; the blank files the owner let us download, in a scratch folder
outside the repository), through the app's own code by a throwaway test in the worktree, deleted, never committed:

| | I-130 | N-400 | I-765 |
|---|---|---|---|
| Dark pixels in the first fillable field, page 1 at 2×: blank form / filled in PaperNest (`PDFForm.filled`) / PDFKit's own drawing of the filled file | 36 / 872 / 854 | 36 / 882 / 864 | 0 / 920 / 900 |
| Filled copy with a line drawn on page 1, made ready for print, page 1 read back with Core Graphics alone | 872 — the answer is in the page | 882 | 920 |
| That print file | copying off, printing on, 12 pages | copying off, printing on, 14 pages | copying off, printing on, 7 pages |
| Page 1 at 2×, `renderImage`, warm, mean of 5 | 16.6 ms | 15.6 ms | 14.5 ms |
| Of which, roughly: the content alone through Core Graphics / building the annotations | 3.9 / 3.7 ms | 3.5 / 3.9 ms | 3.5 / 3.3 ms |

Looked at, not only counted: the I-765's page 1 with its family-name box filled shows the answer in the box, as
PDFKit draws it. **The barcode at the foot of each page now shows too** — it is a form field with an appearance —
but it is the barcode the blank form was made with. Acrobat redraws it from the answers with the form's scripts;
neither PDFKit nor PaperNest runs them, so the barcode does not encode what was typed.

**Not verified, plainly.**

- **Whether USCIS accepts a form filled in PaperNest is still not known**, and a filled form was still not opened in
  Adobe Reader (none on this Mac). The barcode above is one concrete reason it might not be.
- **The Mac**: built, not used. The renderer the Mac shows pages with is the one the unit tests run on macOS.
- A redrawn page flattens: a field's answer is drawn into it and the field is gone from that page, and a link on it
  stops working. That was already so for links, and fields were gone before too, without their answers.
- An annotation set to print but hidden from view (a print-only watermark) is left off paper as well.
- Fill PDF Form was driven in the running app on a synthetic restricted form, not on a USCIS form. Import through
  the file picker was not driven. Only copying and printing are tracked as an author's limits; a
  file whose author forbade form filling or commenting is still treated as allowing them.
- Cost was measured on three forms on this Mac, not on an iPhone.

## 2026-11-13 — USCIS forms would not open: PDFs with copying switched off are imported and keep their limits (Claude, owner in session)

Owner: **"i cannot open forms from USCIS website"**, in PaperNest; what happened was "It refuses to import". Asked
how such PDFs should be treated instead, the owner chose **"Open them, keep the limits"**.

**Cause, measured on the real files.** With the owner's leave three blank forms were downloaded from uscis.gov —
I-130, N-400 and I-765 — into a scratch folder outside the repository (they are not in it and no test uses them).
Each one is a PDF 1.7 file encrypted under an **owner password only**: it opens for anyone, with **copying
switched off and printing and form filling left on**. `PDFInspector.open` declined any PDF whose author had
restricted copying or printing, by a rule in `PRODUCT_SPEC.md`, so every USCIS form was turned away. Nothing was
broken; the rule was wrong for the files people actually have. (The three are also XFA forms with an ordinary
form inside. Apple's PDF code draws the ordinary form, so they show as forms and not as a "Please wait…" page.)

**What changed.**

- **Import.** A PDF that opens without a password is stored exactly as it arrived, whatever its author switched
  off. Still declined: a file that needs a password *and* is restricted, because the unlocked copy the library
  keeps would not carry the limits.
- **The limits are read, never stored.** `DocumentPermissions` (copying, printing) comes from the stored originals
  through `PageRenderer.permissions(for:)` every time it is needed. No schema change. A page carries its author's
  limits into any document it is merged, split or duplicated into, because it carries its original.
- **They are kept in one place: `Exporter.export`**, which the export sheet, Print, bulk export, the library
  backup and the form workspace all go through.
  - Copying off: TXT, Word, JPEG, PNG and HEIC are refused before anything is written. A PDF is allowed.
  - That PDF is the original file itself when nothing was changed. When it has to be rebuilt — something drawn on
    a page, some pages left out, other paper, a password — it is written **with the same limits under an owner
    password made up for the occasion and never kept** (`AuthorProtection`), by both writers.
  - Printing off: the document is not made ready for the print panel.
  - The finished file is **opened and checked** before it is handed over. An export that came out freer than its
    sources fails rather than ships.
  - A password the person exporting asks for opens the file as a reader, not as its owner.
- **Screens.** Copy in the text-selection bar is disabled for such a document (Highlight, Underline and
  Strikethrough are not: marking is not copying). The export sheet offers only PDF and says why underneath. Print
  says "The author of this PDF doesn't allow printing it" instead of a generic failure. Filling a form fails
  closed if the filled copy would come out freer than the form.

**Why the rebuild needed its own work.** Measured on the I-765 with a scratch program before any code was
written: its pages copied into a fresh `PDFDocument` and written plainly came out **unencrypted, copying
allowed**. That is exactly what PaperNest's export does to pages nobody has touched whenever it also has to draw
one, so accepting these files without changing the exporter would have made PaperNest a tool for removing the
restriction — which is what the old rule was trying to prevent, by the bluntest means available. With
`PDFDocumentWriteOption.accessPermissionsOption` and an owner password the same write comes out encrypted,
opening freely, copying off.

**Results.** Verified alone, in a clean worktree holding `HEAD` plus only this change — twice, because another
session committed its rework of the export sheet (`ddbe1e2`) under these hunks while the first round was running.
**The first column is the tree this commit holds.**

| Check | On `ddbe1e2` + this change — what is committed | Earlier, on `722cdfd` + this change |
|---|---|---|
| `./scripts/test.sh` | **Passed: 1,012 tests** (320 + 49 + 191 + 169 + 173 + 110), 0 failures, 0 warnings — `/tmp/papernest-restricted-final-unit.log` | 1,012 passed |
| New: `RestrictedPDFImportTests` 7, `RestrictedPDFExportTests` 15, `RestrictedPDFTests` 6 | **Passed** | Passed |
| `./scripts/build-mac-app.sh` | **Built**, 0 warnings | Built |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **BUILD SUCCEEDED**, 0 warnings | Succeeded, 0 warnings |
| `RestrictedPDFUITests` (new, 2) | iPad Pro 13-inch (M5), iOS 26.5: **2/2**. PaperNest iPhone Duo, iOS 27.1: **2/2** | iPad 2/2, iPhone 2/2 |
| `TextSelectionUITests` 2, `DocumentPrintUITests` 2 — the screens this touches | iPad **4/4**; iPhone **4/4** — `/tmp/papernest-restricted-final-ipad.log`, `…-final-iphone.log` | iPad 4/4, iPhone 4/4 |
| `DocumentFindUITests` 3, `PageLinksUITests` 2, `BookmarksUITests` 3, `NightModeUITests` 3 | **Not run again** on this base: `ddbe1e2` changed the export sheet's footer and nothing these suites reach | iPad 11/11. iPhone **9/11, then the two suites that failed 6/6 on their own**: a find test did not get its editor on screen in 30 s, and a Night Mode switch did not take a tap, with the load average over 150 from another session's simulator run (`/tmp/papernest-restricted-clean-iphone.log`, then `…-clean-iphone-2.log`) |
| **The three real USCIS forms through the app's own code** (a throwaway test in the worktree, deleted, never committed; run on the earlier base — nothing in `ddbe1e2` touches the importer, renderer or exporter) | — | **All three:** imported with the right page count (12, 14, 7); limits read as copying off, printing on; the stored original identical to the download; page 1 drawn; 1,800–2,700 characters of text read from page 1; a whole export identical to the download; 450, 440 and 161 form fields found, 268, 189 and 103 of them fillable text; text export refused; drawn on and made ready for printing, all pages present and still copying off; one field filled, the value read back, the filled copy still copying off and imported as a document |

UI runs called `xcodegen` and `xcodebuild test` directly, without the script's seeding step (see the Night mode
entry below for why); one device at a time, `-parallel-testing-enabled NO`.

**What the tests prove.** On synthetic fixtures (`SyntheticDocuments.restrictedPDF`, `restrictedAcroFormPDF`):

- A file with copying off, and one with printing off, is imported byte for byte and its pages draw. A file that
  is locked as well as restricted is still declined and leaves nothing behind.
- The limits read back are the file's; pages from several files are bound by every author at once; a picture
  has none.
- Untouched, the export is the file that came in. Each of TXT, Word, JPEG, PNG and HEIC is refused with nothing
  written. Drawn on, cut to some pages, laid on A4, or given a password, the exported PDF opens the same way the
  original did and still has copying off; four guesses at its owner password do not open it as owner; the pen
  stroke is on it and an untouched page kept its words.
- A file that only forbids printing keeps "no printing" through a rebuild, can still be exported as text, and is
  refused for the print panel. A form that allows printing reaches the print panel still closed to copying.
- An open document mixed with a restricted one is exported closed. A backup archive holds the restricted
  document as the original and the ordinary one open. An ordinary PDF is exported exactly as before.
- A restricted form's fields are read, a filled copy is as closed as the form, and the filled copy is accepted
  back as a document that still refuses a text export.
- Screens: only PDF is offered where copying is off (and where the limits could not be read); each refusal has
  its own wording; an open document knows its author's limits; Print shows no panel and says why when printing
  is off.
- `RestrictedPDFUITests`, in the running app: the restricted file **opens**; a word can be selected; Copy is there
  and disabled while Highlight works and saves one stroke; the export sheet has the PDF tile and none of the
  other five, with the reason under it, on screen, in English, French and Spanish.

Screenshots: `docs/screenshots/restricted-pdf-2026-11-13/` (a selected word with Copy unavailable; the export sheet
with PDF alone and the reason, in English and in French).

**Proved able to fail.** With the PDFKit write put back to a plain one, every export test that rebuilds a
PDF failed with `writeFailed` — the check on the finished file refusing to hand it over. With that check switched off as well,
they failed on their own assertions: not encrypted, copying allowed, owner password guessed. Both were put back.

**A separate thing these files showed, not fixed here.** A value typed into a form field is **not drawn on the
page inside PaperNest**. Measured on the I-765 with its family-name field filled: Apple's PDFKit draws the typed
name in the box; PaperNest's own picture of the same page has nothing there (0 dark samples where the name
sits), because the page is drawn with `CGContext.drawPDFPage`, which draws page content and not form fields. The
value is in the file — it reads back, and it is in what is exported and printed — but someone who fills a form in
Fill PDF Form and opens the saved copy sees empty boxes. That is true of every form, not only these, and it was
true before today; it only became easy to meet now that government forms open. It is its own piece of work.

**Not verified, plainly.**

- **No form was filled in the running app.** Fill PDF Form was exercised through the engine on the real files
  (fields read, one filled, the copy imported), not by typing into the form sheet on a simulator. Fill PDF Form is
  a Pro feature.
- **A filled form was not opened in Adobe Reader, and nothing was submitted to USCIS.** PDFKit dropped the XFA
  part when it wrote the filled copy (measured: the copy has none), which should make Adobe show the ordinary
  form and its values; "should" is not "seen". USCIS's own instructions ask for Adobe Reader. **Whether USCIS
  accepts a form filled in PaperNest is not known.** The forms carry a barcode at the foot of each page that
  PaperNest does not draw either.
- **Import through the app's file picker was not driven**: the UI test puts the restricted file into the library
  directly. The importer itself is covered by the unit tests and by the three real forms.
- The Mac was built, not used. Printing a restricted form was taken as far as the file handed to the print panel;
  whether the system's panel then withholds its own "Save as PDF" for such a file was not looked at.
- Only copying and printing are tracked. A file whose author also switched off commenting or form filling is
  treated as allowing them, and a rebuilt export always allows filling, commenting and accessibility and never
  document assembly.
- Redact and Compress have engines and no screens. Both rewrite a page into a new original, which would have no
  limits; whoever builds those screens has to refuse a restricted document or carry its limits. Compress already
  refuses an encrypted file. Recorded in `ARCHITECTURE.md`.
- French and Spanish strings are unreviewed by a native speaker, like the rest. No VoiceOver, Dynamic Type or
  physical-device pass.

## 2026-11-13 — Export: Save, Copy and Share act in one tap; no Export button (Claude, owner in session)

Owner: "In export feature Share button does not work directly … remove export button". Reproduced on iPhone 17
first: choosing Share and pressing Export only showed "Ready: 48 KB" with a second "Share…", which did open the
share sheet. Design and calls: top entry of `docs/CLEAN_NATIVE_DESIGN.md`. `ExportSheet.swift` also holds the
restricted-PDF session's uncommitted lines; that session agreed to this edit, and the commit takes only these.

| Check | Result |
|---|---|
| `./scripts/test.sh`, working tree, 21:08 | **Passed: 1012 tests** (320 + 49 + 191 + 169 + 173 + 110), 0 failures, 0 compiler warnings. The tree held the restricted-PDF session's uncommitted work and its tests. |
| `./scripts/swift.sh build` (macOS) | Clean, 0 warnings. **The Mac sheet and its share menu were not seen** (no screen access). |
| **This commit alone**, clean worktree, 21:15 | `./scripts/test.sh`: **passed, 985 tests** (314 + 49 + 191 + 163 + 158 + 110), 0 failures, 0 warnings. `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`: succeeded, 0 compiler warnings. No UI test was run on the commit alone. |
| **iPhone 17 / iOS 26.5**, 20:55 and 21:02 | **Passed:** `testExportShareOpensTheShareSheetInOneTap` (new), `testExportTilesSelectOneAtATimeAndCopyConfirms`, `testExportSaveOpensTheSaveDialogAndClosingItKeepsTheExport`, `SubscriptionUITests.testAFreeUserGetsThePaywallNamingTheRefusedFeature`, `ScannerWorkspaceUITests.testSavingAScanOpensExportAndClosingItReturnsHome`. `testReviewEditsSaveAndReopen` passed at 20:43 before the last two fixes, which do not touch its path. |
| **iPad Air 11-inch (M4) / iOS 26.5**, 20:57 and 21:05 | **Passed:** the same five. |
| What the new test shows | One tap on Share opens the system share sheet (a popover pointing at Share on both devices); a tap outside closes it and Share is usable again; Share again, then the share sheet's own Copy, closes the export sheet. The save test: on iPhone, closing the dialog keeps the export ("Ready" shown, no "Save…") and Save to Files opens the dialog again; on iPad, the dialog's Save closes the export sheet. |

**Found by running it, and fixed.** The first version used full option tiles for the three buttons; on the iPad
sheet they covered the Pages row, and `testExportTilesSelectOneAtATimeAndCopyConfirms` could not select Range.
They are compact buttons now. The tests first looked for the share sheet's Copy as a button (it is a cell named
`actionGroupCell`) and for the save dialog by "Save as" (it can open on its last folder view instead; its Save
button is in both). One run executed 0 tests because the shell passed every `-only-testing` as one argument; it
is not counted.

**A correction to what was said in session.** The runtime warning "Attempting to export a document using a
content type ("com.adobe.pdf") not included in its `writableContentTypes`" appears whenever a PDF is saved, with
the save code exactly as it is at `HEAD`. A change to the save dialog was made and reverted on the belief that it
caused this; it did not. The warning is older than this work and is not investigated here.

**Not run, or failing for another reason.** `testSettingsShowsTheLibraryAndExportsABackup` fails on both devices
before reaching Settings: it looks for `library-settings` on Home, which has none. It was last recorded passing in
October. Not this change: the save code it uses is unchanged. `testDocumentToolsBulkExportMakesOneArchiveFromTheSelection`
was not run. The Mac was not looked at.

## 2026-11-13 — The scanner asks before keeping a capture on iPhone too (Claude, owner in session)

Owner: "on iphone when scanned it automatically keeps it, just like ipad i should ask". A capture on iPhone is now
staged and shown with Keep Scan and Delete, exactly as on iPad, and joins the queue only on Keep. Three device
checks in `ScannerWorkspaceView` are gone; nothing else changed.

| Check | Result |
|---|---|
| `./scripts/test.sh`, 19:56 | **Passed: 985 tests** (314 + 49 + 191 + 163 + 158 + 110), 0 failures, 0 compiler warnings. The change is in an iOS-only file, so this run says only that nothing else moved. |
| iOS Simulator build (inside `xcodebuild test`) | 0 compiler warnings. |
| **iPhone 17 / iOS 26.5**, `ScannerWorkspaceUITests`, 19:50 | **4 passed, 0 failed**: `testCaptureIsKeptOrDeletedBeforeQueueing` (was iPad-only, as `testIPadKeepsOrDeletesCaptureBeforeQueueing`), `testPhotoModeKeepsTheWholeFrameAndTurnsAutoOff`, `testReviewEditsSaveAndReopen`, `testSavingAScanOpensExportAndClosingItReturnsHome`. |
| **iPad Air 11-inch (M4) / iOS 26.5**, the same four, 19:53 | **4 passed, 0 failed.** The Photo-mode test now runs here as well. |
| Looked at | The Keep-or-Delete screen on iPhone in French: title, hint, the page with its zoom controls, and the two buttons stacked because the French labels do not fit side by side. |

**What the tests show.** With a capture waiting, Save is not offered and the queue button is absent; Delete leaves
the queue as it was and Keep adds one; leaving the app and returning keeps the undecided capture; a second capture
through the shutter is staged the same way. In Photo mode the photo is also staged, and after Keep its corners
read `0, 0` and `100, 100`.

**Not run, not seen.** A camera, as before: the fixture bytes go through the same path a still takes, but the
automatic shutter leading into this screen has never fired on a device. Nothing else was re-run.

## 2026-11-13 — Home loses its Tools button; the phone's bar steps aside for selection (Claude, owner in session)

Owner, after seeing the redesign: "remove tools from top left corner i do not want at all". The grid button in
Home's header is gone on iPhone, iPad and Mac. `ToolsSheet` and its `-PaperNestDebugShowTools` hook stay in the
code, unreachable from the interface; what that costs is in the design entry (`docs/CLEAN_NATIVE_DESIGN.md`):
**importing pictures from the Photos library as documents has no other way in.**

Checking it turned up something older. **On iPhone the library's selection bar — the count, Select All and the
actions menu with Duplicate, Merge, Move, Export as ZIP and Delete — was drawn underneath the bottom bar and
could not be tapped.** Seen in the Simulator before the fix. The bottom bar now hides while the library is
selecting (`LibraryModel.isSelectingItems`) and returns on Done. **It is older than the redesign:** `dd405ea`, the
commit before it, was built and run on the same Simulator at 19:06 and hides the bar the same way.

| Check | Result |
|---|---|
| `./scripts/test.sh`, 18:59 | **Passed: 985 tests** (314 + 49 + 191 + 163 + 158 + 110), 0 failures, 0 compiler warnings. The tree held this change and nothing else of anyone's but two modified entitlements files. |
| `./scripts/swift.sh build` (macOS) | Clean, 0 warnings. **The Mac was not looked at**; the change there is one button fewer. |
| **iPhone 17 / iOS 26.5**, four runs 18:10–18:58, 23 tests | **22 passed, 1 failed.** Passed: `HomeToolsUITests` (4, which now assert no Tools button), `testHomeHasOneSetOfQuickActionsAndFourPhoneTabs`, `testHomeNewNoteCreatesAndOpensANotebook`, `testHomeRecentOpensADocumentAndSeeAllShowsTheGrid`, `testAFolderMadeInTheSidebarHoldsAMovedDocument`, `testSidebarNavigationKeepsWorkingAfterGoingBack`, `testPremiumHomeAtLargestTextSize`, `testPremiumDashboardActionsAndLocalizedLayout`, `testNotebookCreationOpensAndSurvivesRelaunch`, `testNoteImageMenuOffersCameraPhotosAndFiles`, `testStudioPenSavesAndReopensWithFloatingHistory`, `testPDFToolsSidebarAndPhoneMenuRouting`, `testSymbolStampsSpanishLifecycle`, `testNotebookPagesAddCancelUndoRedoAndReopenInAllLanguages`, `testPageCommentsEditCancelDeleteUndoAndReopenInAllLanguages`, `testShapesPlaceCancelUndoRedoAndReopenInAllLanguages`, `testDocumentToolsLocalizedSelectionOrderAndCancellation`, `testToolsScreenPicksTwoDocumentsAndMergesThem`. Failed: `testNotebookToolsAreSideBySide`, at "Empty notes must keep Add Page and Undo available" — the same message this file records at baseline `0edf804`; it reaches that through the new route. |
| **iPad Air 11-inch (M4) / iOS 26.5**, three runs 18:30–19:02, 13 tests | **13 passed.** `HomeToolsUITests` (5), `testHomeHasOneSetOfQuickActionsAndFourPhoneTabs`, `testHomeNewNoteCreatesAndOpensANotebook`, `testHomeSidebarSelectionFollowsNavigation`, `testNotebookCreationOpensAndSurvivesRelaunch`, `testPremiumHomeAtLargestTextSize`, `testStudioPenSavesAndReopensWithFloatingHistory`, `testToolsScreenPicksTwoDocumentsAndMergesThem`, `testDocumentToolsLocalizedSelectionOrderAndCancellation`. |
| Selection on iPhone | `testDocumentToolsLocalizedSelectionOrderAndCancellation` failed at 18:46 with the bar hidden (its taps landed on the bottom bar and left the screen), and passed at 18:54 with the fix, in en, fr and es. Its own French screenshot shows "Sélection : 2", "Tout désélectionner" and "Plus" along the bottom with the bar gone. |

**Tests changed, and why.** Thirteen `AppUITests` reached New Notebook through the Tools button; they now use
Home's New Note (`homeNewNote`). `testToolsScreenPicksTwoDocumentsAndMergesThem` opens the Tools screen by its
debug hook, waits from launch rather than from a tap, and scrolls to Merge, which sits in a second lazily built
grid. `testDocumentToolsLocalizedSelectionOrderAndCancellation` goes to the library through See All on iPad: the
wide layouts open on Home, and the test had been asking for the library's Select button without going there.

**Seen and not fixed.** On iPhone the library's large title ("All Documents") is drawn over the search field
until the list is scrolled, with an empty band under it. `dd405ea` does the same, so it is not from the Home
work; `docs/screenshots/sidebar-regression-premium-library-en-iphone.png` (2026-11-02) shows it correct, so it
came in between. It is the library screen's navigation bar. Cause not looked for.

**Not run, not seen.** The other UI tests. The Mac. A camera. Importing from Photos, which now has no way in.

## 2026-11-13 — Reader features R3: the reader's own bookmarks, schema v11 (Claude, owner's queue)

Third in this session's part of the owner's "most features of Adobe PDF reader" queue, and the last piece of R3
(links and Go to Page landed on 2026-11-12).

**What changed in the app.** The document's title menu has **Add Bookmark** — **Remove Bookmark** when the page
being read is already marked — and **Bookmarks…**. A marked page shows a red ribbon at its top corner. The list
shows every bookmark in page order, each called by its page ("Page 3") until it is given a name; tapping one goes
to its page and closes the list; each row's ⋯ menu renames or removes it (swipe to remove on iOS as well); and the
bookmark button in the list's bar marks or unmarks the page being read without leaving the list. An empty list
says so and says what to do. On a Mac and on an iPad's keyboard, Page > Add Bookmark is ⌘D, as in Preview and
Safari.

**What a bookmark is.** It belongs to the **page**, not to a page number: reorder the pages and it follows; delete
the page and it is hidden, undo and it is back; delete the page or the document for good and it goes with it. A
page has at most one. It is the reader's own place-mark, not part of the document: it is not drawn into exports
or prints, and **marking a page is not an edit** — it does not move the page's revision or the document's modified
date, so no thumbnail is re-rendered, no text is recognised again and the document does not jump to the top of
Recent. It is not on the undo stack either.

**Schema v11.** One new table and nothing rebuilt:
`bookmarks(id, page_id UNIQUE REFERENCES pages ON DELETE CASCADE, name, created_at, modified_at)`. The document a
bookmark is in is read from its page, never stored, so a page that moves between documents cannot leave a stale
copy behind. Because no synced table is rebuilt, `SyncSchema.triggerSQL` did not need to be run again; a test
compares every trigger before and after the migration.

**Bookmarks do not sync — decided, and written down** in `docs/ARCHITECTURE.md` → "Sync". No trigger queues a
bookmark and it has no record type; a test pins that, with sync on, adding, renaming and removing one leaves the
outbox exactly as it was. The reasons: every record type needs its own triggers, mapping, merge rule and
multi-device scenarios, and the five that exist have not yet exchanged a byte with a real iCloud container; and
the table is shaped so that adding it later needs no rebuild. With sync on, the Bookmarks list says in a line at
its foot that bookmarks stay on this device.

**How it is built.** `Sources/PaperNestCore/Bookmark.swift`; `Sources/PaperNestStore/Bookmarks.swift`
(`bookmarks(of:)`, `addBookmark(on:name:)`, `renameBookmark(_:to:)`, `removeBookmark(_:)`, each committed before
it returns); `Sources/PaperNestUI/Reader/ReaderBookmarks.swift` (the model, which reads the list back from the
store after every change, the list, the menu items and the ribbon). Shared files: `Schema.swift` (v11),
`StoreError.swift` (`bookmarkNotFound`), `DocumentView.swift` (one `@State`, `.documentBookmarks`, one focused
value, the menu items, the ribbon overlay), `PaperNestCommands.swift`, one block (`Bookmarks`) in
`Localization.swift` and the three strings files, and one hard-coded `10` in
`Tests/PaperNestSyncTests/SyncUnitTests.swift`, now `Schema.latestVersion`.

**Results.** The slice was verified twice, because the ground moved under it. First alone on `dd405ea` (Night
mode). While those runs were going another session committed the Home redesign as `6bf87ca`, so the commit this
slice would make was no longer the tree that had been tested; everything was run again alone on `6bf87ca`. **The
first column is the tree this commit holds.**

| Check | On `6bf87ca` + this slice — what is committed | Earlier, on `dd405ea` + this slice |
|---|---|---|
| `./scripts/test.sh` | **Passed: 982 tests** (311 + 49 + 191 + 163 + 158 + 110), 0 failures, 0 warnings — `/tmp/papernest-bookmarks-final-unit.log` | 982 passed, three times as the slice changed |
| `BookmarkTests` (new, 16, store), `ReaderBookmarksTests` (new, 9, model) | **Passed** | Passed |
| `PaperNestSyncTests` (49: `SyncSchemaTests` and the multi-device scenarios) on schema v11 | **Passed** — in the count above | Passed |
| `./scripts/build-mac-app.sh` | **Built**, 0 warnings | Built |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **BUILD SUCCEEDED**, 0 warnings | Succeeded |
| `BookmarksUITests` (new, 3), iPad Pro 13-inch (M5), iOS 26.5 | **3/3** — `/tmp/papernest-bookmarks-final-ipad.log` | 3/3, twice |
| `BookmarksUITests`, PaperNest iPhone Duo, iOS 27.1 | **2/3, then 3/3.** `testABookmarkIsStillThereAfterRelaunch`, the first test after the simulator booted, failed at launch: the editor was not on screen after 30 s (`/tmp/papernest-bookmarks-final-iphone.log`). The suite run again by itself: 3/3 (`…-final-iphone-2.log`). One pass after one failure | 2/3 with the third failing at launch (editor not on screen after 30 s, load average 200), 1/1 alone, then 3/3 |
| `DocumentFindUITests` 3, `TextSelectionUITests` 2, `PageLinksUITests` 2, `DocumentPrintUITests` 2, `NightModeUITests` 3 — iPad | **12/12** — same log | 11/12 — find 2/3, see "A tap lost" below — then find 3/3 |
| The same five suites — iPhone | **12/12** — `/tmp/papernest-bookmarks-final-iphone.log` | 12/12 |

Both rounds were run in a clean worktree (`~/Library/Caches/PaperNest/verify-reader-queue`) holding `HEAD` plus
only this slice, one device at a time, `-parallel-testing-enabled NO`. The UI runs called the last two lines of
`scripts/ui-test-ios.sh` directly and skipped its seeding, for the reason given in the Night mode entry below.
Logs of the first round: `/tmp/papernest-bookmarks-clean-*.log`.

**What the tests prove.** `BookmarkTests` (16), against a real `LibraryStore`:

- A marked page is listed, and the list is in the order of the pages however they were marked.
- A bookmark is on disk when the call returns: a second connection to the same library reads it straight away.
- Marking a marked page keeps the bookmark it has. Renaming tidies the name to one line, clips it at 120
  characters and allows an empty one. Removing is not an error the second time; renaming one that is gone is.
- A bookmark follows its page through a reorder.
- **Marking is not editing:** the page and the document compare equal, revision and dates included, before and
  after a bookmark is added, renamed and removed.
- A bookmark is listed only for its own document. A page that does not exist, a deleted page and a page of a
  document in Recently Deleted cannot be marked.
- A deleted page's bookmark is hidden and comes back when the deletion is undone; purging the page, or deleting
  the document for good, takes the row with it (counted in the table, not just in the list).
- A duplicated document starts with no bookmarks.
- A schema v10 library, built by running migrations 1–10 by hand, opens at v11 with its document, pages, favourite
  and label intact and can be bookmarked; and **every trigger that was there before the migration is there after**.
- With sync on, adding, renaming and removing a bookmark leaves the outbox exactly as it was.

**Proved able to fail.** Listing without regard to deleted pages, in the order bookmarks were made, failed three
of these tests in four places; then it was put back.

`ReaderBookmarksTests` (9), on the model the screens use: marking the page being read puts it in the list and in
the library; marking it again takes it away; an unnamed bookmark is called by its page's number **as the pages
stand now** ("Page 1" becomes "Page 3" when its page is moved there); a named one keeps its name and still says
its page; a saved change moves the session's change token so other windows reload; marking a page another window
has just deleted reports a failure and shows nothing false; a deleted page's bookmark leaves the list and
returns on undo.

`BookmarksUITests` (3) drive the running app and read the library on disk between steps:

- With nothing marked, **Bookmarks…** opens a list that says "No Bookmarks" and what to do. **Add Bookmark** on
  page 1 puts the ribbon on the page and one row in the library; the same on page 3 makes two, in page order;
  page 2, between them, shows no ribbon.
- The list shows "Page 1" and "Page 3". The second row's ⋯ menu renames it "Totals": the library has the name,
  the row says "Totals" and still says "Page 3" beneath. Tapping it closes the list and the reader is on page 3,
  ribbon showing.
- The title menu now offers **Remove Bookmark**; choosing it takes the ribbon and the row away. The last row is
  removed from the list's own menu and the list says it is empty again. The bookmark button in the list's bar
  marks the page being read and changes to its "remove" form.
- After all of that **no page's revision has moved**.
- A bookmark is still there after the app is terminated and launched again: ribbon on the page, row in the list.
- In French and Spanish the two menu items, the list's title and the empty message are named and on screen, and
  a page can be marked from the list.

**A tap lost, and one change of mine because of it.** In the first iPad run on this slice (on `dd405ea`)
`DocumentFindUITests.testFindCountsHitsStepsAcrossPagesAndCloses` failed: the find button was tapped 0.8 s after
the editor's toolbar appeared and no find bar came up in the next 5 s, with the load average near 400. It is the
same shape as the Spanish print-menu failure in the Print entry below — a tap on the navigation bar in the first
second of a document's life that leaves nothing on screen — and that one happened before bookmarks existed. **I
did not find the cause.** I did find something of mine that could only make it likelier: the bookmarks model
published its list every time it read it from the store, changed or not, and the title menu is drawn from that
list, so the navigation bar was rebuilt once more just after every document opened. The model now publishes only
a list that differs. Since then the find suite has passed 3/3 on each device, twice. **That is one suspect
removed and a clean re-run, not a diagnosis:** whether the bar really drops a tap while it is being rebuilt, and
whether a person could ever be quick enough to meet it, is not known.

**Why these tests take 165 seconds each on the iPhone.** On that simulator (iOS 27.1) a tap on any item of the
title menu makes XCUITest wait 60 seconds, once per launch — "App animations complete notification not received,
will attempt to continue" — before it goes on. Print's test and `PageLinksUITests`' Go to Page test show the same
wait in their logs; the iPad shows none. It is the title menu under test automation on that simulator, it was
there before bookmarks, and it is not something a person waits through. Not investigated further.

**Not verified, plainly.**

- **The Mac was looked at once, offscreen, and never used.** A throwaway test in the clean worktree drew the
  bookmarks list into a picture (`docs/screenshots/bookmarks-2026-11-13/mac-list-offscreen.png`; the technique
  another session recorded for when screen access is declined). It showed the rows and the empty message as they
  should be, and **one defect**: a Mac draws a `Menu` as a bordered pull-down with an arrow, far too much button
  for a ⋯ on every row. It is borderless on the Mac now. An offscreen picture has no window toolbar, so the list's
  Done and bookmark buttons were not seen; and Page > Add Bookmark (⌘D), Page > Bookmarks…, the ribbon and a
  click on anything have not been run by anyone.
- **⌘D was never pressed**, on a Mac or on an iPad keyboard. The iPhone simulator's log was searched during a run for the app's `MenuBuilder`
  category and for "shortcut" or "conflict": 184 UIKit lines from the app in the two minutes searched, none of
  them that. So UIKit logged no clash for ⌘D or ⌘P at launch on iOS 27.1; the iPad's log was not read.
- **Two windows on one document** — a bookmark made in one appearing in the other — rests on the unit test of
  the change token; it was not watched happen.
- The "bookmarks stay on this device" line at the foot of the list appears only with iCloud sync on, which no
  build here has. It compiles; it has never been on screen.
- A notebook's continuous pages: the ribbon and "go to" were only exercised on a three-page PDF, one page at a
  time. Rotated and cropped pages, and the ribbon in Night mode, were not looked at.
- Swipe-to-remove on a row was not exercised (the ⋯ menu was). VoiceOver, the largest Dynamic Type sizes and a
  physical device were not tried. French and Spanish: the menu items, the list's title, the empty message and a
  row — not the rename alert.
- Long lists: nothing measured a document with hundreds of bookmarks.

**Limits by design — say these rather than discover them.**

- **Bookmarks do not sync**, and are not in a library backup (that exports documents, not the database).
- One bookmark to a page. A duplicated, merged or split document's copies start with none.
- Adding and removing a bookmark is not on the undo stack.
- A PDF's own outline is still "Contents"; these are the reader's marks and are never written into a file.

## 2026-11-13 — Paywall names the refused feature; one list of what Pro unlocks (Claude, owner's request)

Owner, in session: "I want to build subscription paywall so free users can't use paid features", approved the
Free/Pro list, then "can you add paywall in app" and "leave ads for now". The boundary is in
`docs/PRO_SUBSCRIPTIONS.md`.

**What changed in the app.** Every Pro check now names its feature (`ProFeature`, eight cases) and a refusal opens
the paywall saying "Included in PaperNest Pro: <feature>" — including the places that used to show a plain alert
(Recognize Text, shapes, text markup, Split, duplicating notebooks past three). The paywall lists all eight
features instead of four. Duplicating a page is no longer a Pro check. **With no product IDs in
`Subscriptions.plist` nothing is blocked, exactly as before**; that file is still empty.

| Check | Result |
|---|---|
| `./scripts/test.sh` | **Passed**: 985 tests (314 + 49 + 191 + 163 + 158 + 110), 0 failures. First run failed `frenchUsesFrenchTypography` on my new French string (plain space before a colon); fixed and re-run. Three new tests in `SubscriptionStateTests`. |
| `./scripts/swift.sh build` (macOS) | **Passed**, no warnings. |
| `./scripts/ui-test-ios.sh "" -only-testing:PaperNest-iOSUITests/SubscriptionUITests` (iPhone simulator, Xcode 27.2) | **Passed**, 3 of 3, on the second run. New `testAFreeUserGetsThePaywallNamingTheRefusedFeature`: with products configured, a TXT export is refused, the paywall shows `textExport`, closing it returns to the export sheet and nothing was exported. First run: `testProfilePaywallDismissalAndLocalization` failed because the longer list put Continue with Free more than five swipes down at the largest Spanish type; the test now scrolls further. |

**Not verified.** The Mac app was not opened in a window. No iPad run. Only the export refusal was driven in the
Simulator; the other seven refusals are covered by unit tests of the store and by reading the code, not by
interaction. No purchase was made: the `PaperNest-Subscriptions` scheme run with test products, and the hosted
StoreKit tests, were not run in this session. The rest of the iOS UI suite was not re-run.

## 2026-11-13 — Home and scanner redesign (Claude, owner's brief and two reference boards in session)

What was built and every call made where the brief was silent: top entry of `docs/CLEAN_NATIVE_DESIGN.md`.
Home on iPhone, iPad and Mac; a four-item phone bar (Home, Notes, Scan, Files); a Folders screen; the iCloud card;
the scanner in its own dark surface with Document and Photo modes and a three-column iPad review; and, by two
later instructions the same afternoon, a saved scan that opens its export screen by itself and returns to Home.

**Read first.** (1) **The Mac was never seen in a real window** — screen access was asked for and declined. Its
detail column was looked at in an offscreen render; **its sidebar, and every click on the Mac, were not**. (2) **No
camera was involved in anything below.** The Simulator has none, so edge outlines, the automatic shutter, flash and
a real Photo-mode still are untested; the scanner tests feed fixture bytes through the same path a still takes.
(3) **Only 29 of the 113 UI tests were run**, the ones that pass through Home, the sidebar, the phone bar, folders
or the scanner. (4) Every run happened with other sessions building in this tree and the Mac's load average
between 60 and 480; where a result looks like load, it says so and says what would settle it.

| Check | Result |
|---|---|
| **This commit alone**, clean worktree, 16:45 | `./scripts/test.sh`: **passed, 957 tests** (302 + 49 + 175 + 163 + 158 + 110), 0 failures, 0 compiler warnings. `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`: succeeded, 0 compiler warnings. **A first attempt at the commit failed this same check and never reached the branch:** four files also held the reader session's uncommitted bookmark lines, and the patch that took only this work's lines put its block of `L10n` accessors one line too low, outside the type. The working tree was never wrong. The split now rebuilds each file from the working tree's own text. **No UI test was run on the commit alone**: the UI passes below ran on the working tree, which also held that bookmark work. |
| `./scripts/test.sh`, final source, 16:25 | **Passed: 982 tests** (311 + 49 + 191 + 163 + 158 + 110), 0 failures, 0 compiler warnings. **Not a clean checkout:** the tree also held the reader session's uncommitted print, night-mode and bookmark work, and its tests are in that count. |
| `./scripts/swift.sh build` (macOS), final source | Clean, 0 warnings. `./scripts/build-mac-app.sh` and `scripts/build-ios-sim-app.sh` last produced app bundles at 11:20, **before** most of this work; neither was rebuilt afterwards. |
| iOS Simulator build (inside `xcodebuild test`, own derived-data folder) | Compiled with 0 compiler warnings. The only `warning:` lines are the usual App Intents note and two runtime "priority inversion" diagnostics marked `[Internal]` during scanner tests, not looked into. |
| **iPhone 17 / iOS 26.5** (`883EEC1B`), final source, 20 selected tests, 16:03–16:12 | **19 passed, 1 failed, then that one passed alone.** `testPremiumDashboardActionsAndLocalizedLayout` ran out its 10 s wait for `notebook-tool-bar`; the hierarchy captured at the failure has the new notebook open with that tool bar in it, and the existence check itself took about 40 s to answer. Re-run alone at 16:14: passed (77 s). It had also passed on the two builds before. Treated as load; a quiet machine would settle it. |
| **iPad Air 11-inch (M4) / iOS 26.5** (`ED3A3A21`), final source, 20 selected tests, 16:15–16:24 | **20 passed, 0 failed**, 1 skipped by design (the Photo-mode test is phone-only). |
| Tests in those passes | `HomeToolsUITests` (5), `ApprovedLibraryUITests` (2), `DocumentTabsUITests` (1), `ScannerWorkspaceUITests` (4), and from `AppUITests`: `testHomeHasOneSetOfQuickActionsAndFourPhoneTabs`, `testHomeNewNoteCreatesAndOpensANotebook`, `testPremiumFolderActionCreatesARealFolder`, `testPremiumHomeAtLargestTextSize`, `testStudioHomeLocalizedAndAccessible`; phone only `testAFolderMadeInTheSidebarHoldsAMovedDocument`, `testHomeRecentOpensADocumentAndSeeAllShowsTheGrid`, `testSidebarNavigationKeepsWorkingAfterGoingBack`, `testBottomFilesReachesFolderCreationInEmptyLibrary`, `testPremiumDashboardActionsAndLocalizedLayout`; iPad only `testDashboardCanReturnToTheSameSidebarScope`, `testPremiumLandscapeDashboard`, `testHomeSidebarSelectionFollowsNavigation`, `testNotesSidebarCreatesAndReopensOnlyNotebooks`. |
| Three tests whose only change was the Home probe they start from, iPhone 17, 16:30 | `testFirstLaunchWelcomeAndRelaunchInAllLanguages` passed, `testWelcomeLargestTextKeepsContinueReachable` passed. `testNotebookToolsAreSideBySide` **failed** at "Empty notes must keep Add Page and Undo available" — the assertion this file already records failing with the same message at baseline `0edf804` (2026-11-12, Notes editor toolbar redesign). It got there through the new Home, the Tools button and a new notebook, which is all this change touches in it. Not fixed here: it is the editor's. |
| Saved scan → Export → Home (`testSavingAScanOpensExportAndClosingItReturnsHome`, and the end of `testReviewEditsSaveAndReopen`) | Passed on both devices. After Save and the location sheet, `export-start` appears with no alert and no editor; Cancel lands on Home with the scan as the newest recent row; relaunched, the scan opens with "Page 1 of 2". **Exporting itself from that sheet was not driven** — the sheet is the ordinary one, opened and closed. |
| Photo mode (`testPhotoModeKeepsTheWholeFrameAndTurnsAutoOff`, iPhone) | Passed. Document is selected first; choosing Photo turns Auto off and disables it; the shutter adds a page whose crop corners read `0, 0` and `100, 100`; no ID Card or Book control exists. Fixture bytes, not a camera. |
| iPad sidebar and Folders (`testIPadSidebarKeepsTheBrandAndFoldersIsOneDestination`) | Passed. Brand shows once in Notes, All Documents, Favorites, a folder and Home; Folders opens the Folders screen, makes a folder, stays selected while that folder shows, lists it as a card reading "0 items", and Home shows the same card. |
| Localization | `LocalizationTests` 5/5 inside the unit run. en/fr/es Home on iPhone looked at in screenshots, plus es at AX-XXXL; iPad Home looked at in en (light), fr (dark) and es at AX-XXXL. Nothing truncated; French and Spanish action names wrap to two lines and the cards keep one height. |

**Looked at, as pictures:** iPhone Home, Files tab, scanner capture (camera-unavailable state) and review, the
export sheet after a save and Home after closing it; iPad Home light and dark, the three-column scanner review,
Home in landscape (the test's own screenshot, taken mid-rotation). Mac Home detail column, offscreen, after its
fixes: banner, three actions, six table rows with sizes, See All as a link.

**Found by running it, and fixed.**

- `home-recent` on the list of recent rows replaced every row's own label for XCUITest (and so for anything
  finding a row by name). The list is now an accessibility container and the rows keep their labels.
- The wide sidebar's brand was in the accessibility tree twice, so VoiceOver would have read it twice.
- At AX-XXXL the iCloud card's symbol sat on top of its text; it now takes the width it needs.
- French and Spanish action names wrapped and left the cards different heights.
- The selected sidebar row was dark purple on dark grey in dark mode.
- On the Mac, the recent table cut off its last row, See All drew as a grey push button, and Size was "—" for
  every document. Size now comes from `LibraryStore.originalByteCount`.

**Tests changed, and why.** `HomeToolsUITests` is rewritten: Home no longer has a tool grid, and the wide sidebar
now carries the brand on purpose. `testStudioHomeHasContentFiltersAndNoQuickActionCards` became
`testHomeHasOneSetOfQuickActionsAndFourPhoneTabs`, and `testBottomFoldersReachesCreationInEmptyLibrary` became
`testBottomFilesReachesFolderCreationInEmptyLibrary`: the owner's brief reverses "no quick action cards" and
replaces the Documents and Folders tabs with Files. Two assertions that said "document did not open" were waiting
for a Crop button the editor moved into Document Utilities some time ago; the documents had opened, and the tests
now wait for `editor-back`. The scanner test waits for `editor-back` and the page label on reopen instead of
`editor-export`, for the reason in the next paragraph. `AppUITests.libraryPath` reads `PAPERNEST_UITEST_LIBRARY`
when set (see SESSION_HANDOFF): at 15:20 another session's `scripts/ui-test-ios.sh` re-seeded
`/tmp/papernest-uitest-library` under a run of these tests and four of them failed on an empty Home.

**Not this change, seen in passing.** On iPhone 17 a document titled "Scanner workflow" opened with Export and
Document Utilities folded into the navigation bar's system overflow beside Find, so `editor-export` was not on
screen; "Crop target" kept all three. That is the editor's toolbar. Noted for the reader-features session.

**Not run, not seen.**

- The other 84 UI tests, on either device. `testDocumentToolsLocalizedSelectionOrderAndCancellation` was edited
  (it now opens Files before All Documents on a phone) and **not run**: it needs
  `/tmp/papernest-file-tools-layout-library` re-seeded, which would have wiped it under another session.
- The Mac in a window: the sidebar's brand, six rows and iCloud card; the table's sorting, selection, double-click
  and context menu; clicking New Note, Import File and New Folder; the Folders screen; the Settings window opening
  from the iCloud card. None of it has been clicked or seen.
- A camera: live edge outline, automatic capture, flash, the system scanner from the ⋯ menu, a real Photo still.
- The iCloud card with a container. Every build here says "Not set up in this build"; the states it would show
  come straight from the sync controller and were not seen.
- VoiceOver by ear, iPhone in landscape, and iPad in a compact (Slide Over or split) window.
- One test that failed once and has not since: on iPad at AX-XXXL in Spanish, the Tools sheet was not open 5 s
  after the tap (load average above 250). It passed in the two later passes with a 15 s wait. Not explained.

## 2026-11-13 — Reader features R5: Night mode (Claude, owner's queue)

Second in this session's part of the owner's "most features of Adobe PDF reader" queue. This entry is **Night
mode** only; two-page view, the other half of R5, is not built.

**What changed in the app.** Display settings (the sliders button in the lower bar) has a **Night Mode** switch
under a new "Reading" heading. On, the page being read is shown light on dark: white paper black, black print
white, coloured ink a lighter shade of the same colour, and a highlight a dim band of its own colour under white
words. The canvas around the page goes dark with it. It is one setting for the whole app and is remembered. It is
a way of showing a page and nothing else: the switch is a preference, not part of the library, and what is stored,
exported and printed is the page as it always was.

**How it is built** (`Sources/PaperNestUI/Reader/NightMode.swift`). Two pieces that work together:

- `NightPalette` recolours the page's own picture pixel by pixel, off the main thread, on its way to the screen.
  The rule keeps a colour's hue and strength and turns its lightness over. One correction: a highlight is
  paper-pale, so it turns paper-dark, and a dark yellow needs less blue than a screen has — a plain turn-over
  clips it to black and the highlight is gone. Where that would happen the colour is lifted just far enough to
  fit. The last few night pictures are kept so turning back to a page does not show it blank.
- `nightFilter` (SwiftUI's `colorInvert` then `hueRotation(180°)`) is laid over the whole page surface, so that
  everything drawn *live* on the page turns too: the stroke under the pen, text being typed, a selection, the
  lasso. Those are other views — PencilKit's canvas and a `UITextView` among them — and a filter over the lot is
  the one way to turn all of them without editing each.

That filter is right for ink and wrong for highlights, which is why the picture is not left to it: the picture
is put through the *same* filter once before it goes under it. The filter is its own opposite, so the picture
arrives on screen in the palette's colours whatever arithmetic the system's filter really uses. Find's hits are
drawn over the page and would have gone almost black, so at night they are filled with the colours the filter
turns into an amber band and an orange one.

Shared files: `PageImageView.swift` (an `isNight` flag, default off, so thumbnails and every other page picture
are untouched), `DocumentView.swift` (the `@AppStorage`, one environment value, the popover's binding, the
canvas colour, and `nightFilter` as the last modifier on the page surface), `DocumentUtilitiesSidebar.swift`
(the row, and the reset for throwaway libraries), `Reader/DocumentFindBar.swift` (find's night colours).
**Not touched:** `InkCanvas.swift`, `PageZoom.swift`, gesture routing, `PageRenderer`, `ThumbnailCache`, the
store, the exporter.

**Results.**

| Check | Result |
|---|---|
| `./scripts/test.sh`, on the commit alone (clean worktree of `HEAD` + this slice) | **Passed: 957 tests** (302 + 49 + 175 + 163 + 158 + 110), 0 failures, 0 compiler warnings — `/tmp/papernest-night-clean-unit.log` |
| `NightModeTests` (new, 13) | **Passed** |
| `./scripts/build-mac-app.sh`, clean worktree | **Built**, 0 warnings |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`, clean worktree | **BUILD SUCCEEDED**, 0 warnings |
| `NightModeUITests` (new, 3), iPad Pro 13-inch (M5), iOS 26.5 | **3/3** — `/tmp/papernest-night-clean-ipad-1.log` |
| `NightModeUITests`, PaperNest iPhone Duo, iOS 27.1 | **3/3** — `/tmp/papernest-night-clean-iphone-1.log` |
| `DocumentUtilitiesUITests` (2; it uses the Display popover) | iPad **2/2**, iPhone **2/2** — the two logs above |
| `DocumentFindUITests` 3, `TextSelectionUITests` 2, `PageLinksUITests` 2, `DocumentPrintUITests` 2 — iPad | **9/9** — `/tmp/papernest-night-clean-ipad-1.log` |
| The same four suites — iPhone | **8/9, then the one failure 2/2 on its own.** Find 3/3, print 2/2, links 2/2, and `TextSelectionUITests` 1/2: `testPressingAWordSelectsItAndTheSelectionIsCopiedAndHighlighted` ran for **599 seconds** and failed at "Copy did not say it had copied", with this Mac's load average between 300 and 530 from another session's simulator run (`/tmp/papernest-night-clean-iphone-2.log`). Run alone straight afterwards the suite passed 2/2 in 70 seconds (`/tmp/papernest-night-clean-iphone-3.log`). One pass after one failure: reason to believe it was the machine, not proof |

**Why a clean worktree, and why not the script.** As for Print: this slice was laid alone on `2ce8567` in
`~/Library/Caches/PaperNest/verify-reader-queue` and everything above was run there, so the results are for the
tree this commit holds. The UI runs called the last two lines of `scripts/ui-test-ios.sh` directly (`xcodegen
generate`, then its `xcodebuild test`) and **skipped its seeding**: another session was running the same script
from the shared tree, and both delete and re-seed the same fixed libraries under `/tmp`. My first attempt, through
the script, removed `/tmp/papernest-uitest-library` under that session's run and then failed to seed it again
(SESSION_HANDOFF has the note to that session). None of these suites uses the seeded libraries; each makes its own.

**What the tests prove.** `NightModeTests` (13), on the palette, the picture and the filter:

- White paper is black and black print is white; greys swap ends and keep their order.
- Each of six highlighter colours, as the renderer leaves it on paper, stays a band that is at least as easy to
  tell from the page at night as by day (ΔE, at least 0.8 of the daytime difference and never under 15), keeps
  its hue, and carries white words at 4.5:1 or better.
- Each of nine ink colours stays at 4.5:1 or better against the night page and keeps its hue.
- Over a 9 × 9 × 9 grid of colours every result is a real colour, and anything 4.5:1 on white paper is at least
  3:1 on the night page.
- A bitmap is recoloured pixel for pixel (within one level), the picture it was made from is untouched, and the
  same picture asked for twice is made once.
- A page rendered by the real `PageRenderer`, with a pen stroke and a highlight on it, has dark paper, light ink
  and an amber highlight; and the day picture is still the day picture.
- A throwaway library resets the switch; a real one keeps it.
- The filter turns black light and white dark, and applied twice gives back each of seven colours within 3%.
- Find's hits at night are an amber band, or an orange one for the current hit, with white words at 4.5:1.

**Proved able to fail.** Taking the lift out of `NightPalette` made four assertions fail — the default yellow
and pure yellow in the palette test, and the highlight in the rendered-page test — then it was put back.

`NightModeUITests` (3) read the **pixels on the simulator's screen** at known points of the page:

- By day: white paper, the fixture's black square, an amber highlight. Night Mode switched on in Display settings:
  paper no brighter than 40 of 255, the black square at 215 or more, the highlight within 26 levels of the
  palette's amber (89, 73, 0) with blue under 30, red ink still red and light. The page's label and stroke count
  are unchanged, and — read from the library on disk by the test — **the page's revision, transform and every
  object on it are identical before, during and after**. Switched off, the day colours are back within 6 levels.
- **Live ink.** With Night Mode on and a black pen, a finger stroke is saved **black** (read from the library),
  and on screen it is light both while the ink canvas is still the one drawing it and after the pen is put down
  and the page's own picture draws it. This was the open question: the canvas is PencilKit's, a UIKit view, and
  the filter reaches it.
- In French and Spanish the switch is named, can be reached, is a full-width row and works.

**Defects of mine these runs found, all fixed.**

1. **Without a compositing group the filter was wrong for anything that multiplies.** SwiftUI hands a colour
   filter down to each view beneath it and blends them afterwards. For plain layers that is the same thing; for a
   multiplied layer it is not, and a find hit came out as nothing at all on black paper. Found by a unit test that
   renders through `ImageRenderer`; `nightFilter` now composites the page first.
2. **Find's hits vanished at night** for a different reason: a pale yellow turns nearly black under the filter.
   They are filled with other colours at night, chosen so the filter turns them into amber and orange.
3. **Display settings no longer fitted a phone's half-height sheet** once the Reading section was in it. It is
   as tall as its contents where there is room and scrolls where there is not (`ViewThatFits`); the iPad's popover
   is unchanged. `DocumentUtilitiesUITests`, which uses that popover, passes on both devices.
4. Between one night picture and the next the page showed blank dark paper. It keeps the last picture up until
   the new one is ready.

Screenshots: `docs/screenshots/night-mode-2026-11-13/` (the page by day and at night, a stroke under the pen at
night, the settings sheet in French).

**Not verified, plainly.**

- **The Mac was never seen.** It builds. There the ink canvas is `MacInkCanvas` and Display settings is a
  popover; neither was looked at with the switch on. The filter's arithmetic was measured on macOS through
  `ImageRenderer`, which is not a window.
- **Text being typed at night** was not exercised. The text view is a UIKit view under the same filter as the ink
  canvas, so it is expected to turn the same way; expected is not seen. Likewise the lasso, a shape being drawn,
  a placed picture being moved, and find's hits in the running app (those are unit-tested only).
- **Switching Night Mode while a text box is being typed in** rebuilds the page surface, because the filter is
  there only at night. What that does to the keyboard was not tried.
- Notebooks' continuous pages, rotated and cropped pages, scans and photographs were not looked at. A photograph
  is turned like everything else and looks like it; there is no option to leave pictures alone.
- **Cost.** Nothing timed the recolouring of a page at 400% (about thirteen million pixels; it runs off the main
  thread, in bands across the cores), and nothing measured what a filter over PencilKit's canvas does to pen
  latency on a real device. Only night mode pays either.
- The system's own dark appearance together with Night Mode, VoiceOver, the largest Dynamic Type sizes, Apple
  Pencil and a physical device.
- That export and print ignore the switch is true by construction — nothing in `PaperNestExport`,
  `PaperNestRender` or the store can see it — and no test exports with it on.

**Limits by design.** Night mode is about the page: the toolbars, the sidebar and its page thumbnails stay as
they are. It is one preference for the app on this device, not a property of a document, and it is not synced.
A throwaway library (every UI test and dev run) starts by day. Saturated colours keep their hue but not always
their strength: pure blue ink shows as light blue, because pure blue on black cannot be read.

## 2026-11-13 — Reader features R4: Print (Claude, owner's queue)

Next in the owner's "most features of Adobe PDF reader" queue (`docs/FEATURE_EXPANSION.md`, rows R1–R7). This
entry is **Print** only; read aloud, the other half of R4, is not built.

**What changed in the app.** **Print…** in the document's title menu, and in the menu bar's File menu with ⌘P
(the same command gives ⌘P on an iPad's keyboard). It makes the document into one PDF exactly as Export does —
ink, typed text and placed pictures on the pages, private comments left off, each page at its own size — and hands
that to the system's print panel, which owns everything from there: the printer, copies, range, paper, preview.
Nothing is stored and the library is not touched; the temporary PDF is removed when the panel closes.

**How it is built.** `Sources/PaperNestUI/Reader/DocumentPrint.swift`: `DocumentPrinter` reads the document's pages
from the store at the moment Print is chosen, calls the existing `Exporter` (`paperSize: .original`, no invisible
text layer, so it never meets the Pro gate), then shows `UIPrintInteractionController` on iOS or
`PDFDocument.printOperation` as a sheet on the Mac. A document that takes longer than 0.4 s to prepare shows a
"Preparing to print…" card with Cancel. The menu-bar command reaches the same `DocumentPrinter` through its own
focused value (`documentPrinter`) rather than a new field on `DocumentCommandContext`, because `RootView.swift`
was claimed by the Home redesign while this was written; it also means ⌘P pressed twice finds the first print
still busy and does nothing. `DocumentView.swift` gained eight lines: one `@State`, two modifiers and the menu item. `Apps/Mac/PaperNest.entitlements` gained `com.apple.security.print`: a sandboxed Mac app may not open the print panel without it.

**Results.**

| Check | Result |
|---|---|
| `./scripts/test.sh`, on the commit alone (clean worktree of `HEAD` + this slice) | **Passed: 944 tests** (289 + 49 + 175 + 163 + 158 + 110), 0 failures, 0 compiler warnings — `/tmp/papernest-print-clean-unit.log` |
| `DocumentPrintTests` (new, 10) | **Passed** |
| `./scripts/build-mac-app.sh`, clean worktree | **Built**, 0 warnings |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`, clean worktree | **BUILD SUCCEEDED**, 0 warnings |
| `DocumentPrintUITests` (new, 2), iPad Pro 13-inch (M5), iOS 26.5 | **2/2**, clean worktree, final test file — `/tmp/papernest-print-clean-ipad-2.log`. Before it: 2/2 in the shared tree, then 1/2 in the clean worktree (see below) |
| `DocumentPrintUITests`, PaperNest iPhone Duo, iOS 27.1 | **2/2**, clean worktree — `/tmp/papernest-print-clean-iphone.log`; again with the final test file, 2/2 — `/tmp/papernest-print-clean-iphone-2.log` |
| `DocumentFindUITests` 3, `TextSelectionUITests` 2, `PageLinksUITests` 2 — iPad Pro 13-inch | **7/7**, clean worktree — `/tmp/papernest-print-clean-ipad.log` (and 7/7 in the shared tree before it, `/tmp/papernest-print-ipad-2.log`) |
| The same three suites — PaperNest iPhone Duo | **7/7**, clean worktree — same log |

**Why a clean worktree.** The shared working tree also held the Home redesign and my own Night mode, both
uncommitted, and for part of the morning its test target did not compile at all (another session's probe file,
since removed). So this slice was laid alone on `HEAD` in a detached worktree
(`~/Library/Caches/PaperNest/verify-reader-queue`) and everything in the table marked "clean worktree" was run
there: those results are for exactly the tree this commit holds. UI runs were one device at a time,
`-parallel-testing-enabled NO`.

**What the tests prove.** `DocumentPrintTests` stands in for the print panel and reads the file it was handed:
the whole document arrives as one PDF under the document's name; a pen stroke is on the printed page (pixels
probed) and typed text is real text in it; a private comment is not in it; the pages are the ones saved *now*
(a deleted page is not printed); the temporary file exists while the panel is up and is gone afterwards, folder
included; a second Print while one is under way does nothing, and Print works again once it is over; cancelling
while the document is being made ready shows no panel, reports no failure and leaves no file; a document with no
pages shows no panel and no error; a document whose original cannot be read says so instead of printing.
`DocumentPrintUITests` chooses Print… from the title menu and waits for the real system panel: it shows
**Pages 1-3** and a preview cell **Page 1 of 3** for a three-page document; closing it leaves the editor on page 1
with its controls answering; Print works a second time; and the item is in the title menu as *Imprimer…* and
*Imprimir…*. Screenshots, both devices: `docs/screenshots/print-2026-11-13/`.

**One defect of mine found by these runs.** The first UI test looked for the panel by a button labelled "Print".
On iPadOS 26.5 that button is labelled "print" and the way out is "Close", not "Cancel", so the test failed on a
panel that was plainly on screen. It now finds the panel by its bar ("Options" on both versions) and accepts
either way out. A test defect; the app did not change.

**And one thing seen once and not explained.** On the iPad, in the clean worktree, the Spanish half of
`testPrintIsInTheTitleMenuInFrenchAndSpanish` failed: the title was tapped 1.4 s after the editor's toolbar
appeared and no menu was up afterwards (`/tmp/papernest-print-clean-ipad.log`). The French half of the same run,
the iPhone run and the earlier iPad run had all passed. The test now waits for the page itself before touching
the title, as `PageLinksUITests` always has, and passes. **Whether the menu never opened or opened and closed as
the document finished loading was not determined**, and it is the title menu's behaviour, not Print's: Rename,
Export and Go to Page hang from the same menu.

**Not verified, plainly.**

- **Nothing was printed.** No simulator has a printer, so the panel's own Print button stays disabled and no job
  was ever sent. What is proven is that the panel receives the right document. Save to Files and Share from
  inside the panel were not tried either.
- **The Mac was never seen.** It builds. File > Print…, ⌘P and the print sheet (`NSPrintOperation.runModal`) have
  not been run by anyone: Mac screen control has been declined twice in this project and was not asked for again.
- **The sandboxed Mac build was never run**, so the new entitlement is there by Apple's documentation, not by
  observation. And `Apps/Mac/PaperNest.iCloud.entitlements`, the file a build with iCloud on is signed with,
  **does not have it**: that file was modified in the working tree by someone else while this was written, so it
  was left alone. Until it gains the same key, a Mac build with iCloud on cannot print.
- ⌘P on an iPad hardware keyboard was not pressed. The iPhone simulator's log was searched for `MenuBuilder`
  during one run and showed nothing; that is not proof of no clash, because it was not established that the
  search would have shown one.
- The "Preparing to print…" card was never on screen: every document used here was ready in under 0.4 s. Its
  Cancel is covered by a unit test of the printer, not by a tap.
- Long documents: nothing measured how long a few hundred pages take to prepare, or the memory it needs.
- A notebook's template pages, rotated or cropped pages and scans were not printed in these tests; they go
  through the same `Exporter` paths the export tests already cover.
- No physical device, VoiceOver or Dynamic Type pass. French and Spanish: the menu item only — the panel is
  Apple's.

**Limits by design.** Print always prints the saved document; text still being typed is finished first, as for
Export. Private comments are never printed. There is no "print current page" of PaperNest's own: the system
panel's Range does that. Print needs no Pro.

## 2026-11-13 — iCloud sync (M2): engine, CloudKit adapter, status UI (Claude, owner's request)

Owner's brief in session: real two-way iCloud sync across iPhone, iPad and Mac. Design and file map:
`docs/ARCHITECTURE.md` → "Sync". Manual Apple steps: `docs/APPLE_SETUP.md` §2.

**The one thing to read first: this has never talked to iCloud's servers with data.** No container exists for the
bundle ID, so no record has been saved to or fetched from CloudKit. Everything below marked "pretend server" runs
the real store, merge rules, controller and asset mover against `Tests/PaperNestSyncTests/FakeCloud.swift`.

| Check | Result |
|---|---|
| `./scripts/test.sh` | **Passed: 934 tests** (279 + 49 + 175 + 163 + 158 + 110), 0 failures, 0 compiler warnings |
| Engine files alone on clean `HEAD` (separate worktree) | **Passed: 858 tests**; committed as `49cd82d` |
| `PaperNestSyncTests` (49: 30 multi-device scenarios, 19 unit) | **Passed**, pretend server |
| `xcodebuild` `PaperNest-iOS`, generic iOS Simulator, iCloud off | **Built**, 0 warnings; Info.plist container empty, no iCloud entitlement |
| Same, iCloud on (`PAPERNEST_ICLOUD_CONTAINER`, iOS iCloud entitlements passed on the command line) | **Built**; simulated entitlements carry CloudKit, the container and `aps-environment` |
| `xcodebuild` `PaperNest-macOS`, iCloud off | **Built**, 0 warnings |
| `PaperNest-macOS` with iCloud entitlements | **Not run.** Needs a provisioning profile for a container that does not exist yet |
| iCloud-on build launched in iPhone 17 Simulator (iOS 26.5), throwaway library | **Launched, no crash.** CloudKit logged real `account-status` calls; home shows the "Saved on this device" icon. Simulator not signed in to iCloud |
| Settings → iCloud Sync screen | **Not seen.** Simulator control was not granted, so nothing was tapped. Compiles; never looked at, in any language |
| Editor indicator, cloud badge, Download / Remove Download menu items | **Not seen**, same reason |
| iOS UI tests (`scripts/ui-test-ios.sh`) | **Not run** after this change |
| Real devices, same Apple Account | **Not run.** Outstanding |
| Thread sanitizer | **Not run** |

**What the pretend-server scenarios cover:** notebook iPad → iPhone → Mac and still editable ink; folders, rename,
move, favorite, label; offline edits then reconnect; independent strokes merge; rotate + crop merge; same page
turned two ways keeps both and reports a conflict; same text box edited twice keeps both; two renames converge;
Recently Deleted, restore and permanent delete across devices; edit beats delete (page, document, stroke); page
tombstones; folder deleted under an offline document; 100-page PDF with checksum; pictures, file items, signatures;
download on demand, corrupt download refused, eviction only when iCloud really has the file; originals leave
iCloud after 30 days; first-time migration of an existing library, twice, with no duplicates; migration cut short
and resumed; upload whose answer was lost; two devices with the same library; quota exceeded; account switch;
iCloud data deleted; sync off deletes nothing; out-of-order arrival; a record from a newer app; relaunch.

**Known limits.**

- **Vault:** the app has no Vault. Nothing to sync, nothing uploaded. If one is added it must not ride this path.
- **OCR results are not synced**; each device recognizes text itself.
- A page's objects deleted for good elsewhere arrive before their document only across separate fetch batches;
  within one batch documents are handled first. In the cross-batch case a restored document can come back
  without marks that were on it.
- A device offline for more than 30 days can reference an original another device has since removed from iCloud.
  It re-checks on every new reference, which narrows this; it does not close it.
- One `CKRecord` per stroke. A notebook with tens of thousands of strokes makes a slow first upload. Not measured.
- No iCloud storage figure is shown: CloudKit offers no quota API. Full storage is reported when a save is refused.
- No byte-level transfer progress; counts only.
- The recovery copy made when sync is first turned on is the database only. Originals are separate immutable files.
- French and Spanish strings for this slice are unreviewed by a native speaker, like the rest.
- Two-device checklist once a container exists: enable on device A with an existing library; enable on B; create,
  edit, rename, move, favorite, delete, restore on each; airplane-mode edits on both to the same page; kill the app
  mid-upload; sign out and into a second account; fill iCloud; delete iCloud data from A and watch B.

## 2026-11-12 (night) — Reader features R1, R2 and part of R3: find, select and copy, links, Go to Page (Claude, owner's request)

Owner: **"I want to implement most features of adobe PDF reader into my app"**, then **"You pick the order."** The
order and the ledger are under "Reader features" in `docs/FEATURE_EXPANSION.md`. This entry is the first two and
the links and Go to Page half of the third; bookmarks are not built.

**What changed in the app.**

- **Find.** A magnifier in the editor's toolbar (⌘F) opens a find bar under the tools: a field, "2 of 7", previous
  and next (⇧⌘G, ⌘G; Return is next), Done. Every hit on the page is lit yellow and the current one orange; moving
  to a hit on another page turns to it, and scrolls to it when the page is zoomed. Case and accents do not matter,
  a phrase is found across a line break, and the search starts from the page being read rather than from page 1.
  It searches a PDF's own text, recognised text and typed text boxes. A document with no text at all says
  **No Text** and points at Recognize Text, instead of "No Results" — which would read as "that word is not here".
- **Select and copy.** While reading (no drawing tool armed): press and hold a word on iPhone/iPad and drag on, or
  drag with the pointer on a Mac (double-click for a word). A small bar offers **Copy**, **Highlight**,
  **Underline**, **Strikethrough**. The three marks are saved as the same editable ink every highlight already is,
  so they undo, recolour, remove and export like the rest — and this is the first screen for word-level markup
  (inventory row 20), which until now could only mark whole recognised lines.

- **Links.** The links a PDF carries can be followed while reading. A link to another page turns to it, and
  follows that page through reorders; one whose page was deleted is not offered at all. A link out of the document
  **shows its whole address and asks** — Open, Copy Link, Cancel — because the words under a link say whatever their
  author liked. Only `http`, `https`, `mailto` and `tel` are made tappable; a `file:` path, a script or an app's
  private scheme is left as plain paper.
- **Go to Page…** in the title's menu (and the Page menu on a Mac): type a number. Past either end means that end.

**How it is built.** `PageTextLayout` (Core) holds a page's words and where they are, in upright source space: a box
per **character** from a digital PDF, a box per **word** from recognition, one box per typed text box.
`PageRenderer.textLayout(for:)` (Render) reads it; `searchTexts(for:)` reads text only, so find can hold every page
of a long document and work out boxes just for the page on screen. No schema change, nothing cached on disk.

**Results, final code.** Unit suite **885 tests, 0 failures, 0 warnings** (811 before; 74 new). `./scripts/build-mac-app.sh`
clean, and `xcodebuild … -destination 'generic/platform=iOS Simulator' build` clean. UI tests, each device run on
its own, `-parallel-testing-enabled NO`:

| Suite | iPad Pro 13-inch (M5), iOS 26.5 | PaperNest iPhone Duo, iOS 27.1 |
|---|---|---|
| `DocumentFindUITests` (new, 3) | 3/3 — `/tmp/papernest-reader-ipad-4.log` | 3/3 — `/tmp/papernest-reader-iphone-6.log` |
| `TextSelectionUITests` (new, 2) | 2/2 — `/tmp/papernest-reader-ipad-4.log` | 2/2 — `/tmp/papernest-reader-iphone-6.log` |
| `PageLinksUITests` (new, 2) | 2/2 — `/tmp/papernest-links-ipad-2.log` | 2/2 — `/tmp/papernest-links-iphone-2.log` |

`DocumentFindUITests` proves: the bar opens ready to type and **every typed letter lands**; three hits counted across
a three-page PDF; next and previous turn the page and wrap at both ends; a word that is not there says No Results
and disables the arrows; Done removes the bar and the highlights and leaves the editor's controls answering; a
blank notebook says No Text with its explanation; text typed onto a notebook page is found; and in French and
Spanish every part of the bar is on screen, none overlapping, with room to type. `TextSelectionUITests` proves: a
press on a word selects that word; Copy acknowledges, and **the word can then be pasted by hand into the find field**
(the clipboard really holds it); press-and-drag past the line's end selects the phrase; Highlight saves exactly one
stroke and lets go of the selection; a tap elsewhere lets go without changing the page; a press on empty paper
selects nothing. `PageLinksUITests` proves: both links of a page are offered and named ("Go to page 3", "Link:
https://…"); the web link raises a question that **shows the address**, and Cancel leaves the page where it was; the
internal link turns to page 3; and Go to Page from the title menu goes to 3, then to 1 for "0" and to 3 for "250".

**The unit tests that matter most** are in `PageTextReaderTests`: they render the page and look at the **pixels**
under a hit's box — ink inside it, clean paper in a sliver either side — for a plain PDF, `/Rotate` 90/180/270, an
offset crop box, and a page the reader turned in PaperNest. **Proved able to fail:** shifting the character index by
one made six of them fail, then was reverted. `PageLinkReaderTests` likewise: letting every URL scheme through
made the scheme test fail, then was reverted.

Screenshots from the final iPad and iPhone runs: `docs/screenshots/reader-2026-11-12/` (find with its hits lit, a
selected phrase with its actions, the link question showing its address, the French find bar on a phone).

**Committed:** the engine only, as `b2d52c0` — Core and Render sources, their tests and the hand-built fixture,
verified alone on a clean checkout of `0edf804` (809 tests). The screens, the UI tests and this entry are not:
they sit on top of this afternoon's uncommitted editor work. See Current claims in SESSION_HANDOFF.
**Update, 2026-11-13:** the owner said "commit it right now", and the screens, the UI tests and this entry went
in with the rest of the working tree — the toolbar, Document Utilities and iCloud sync screens included. Checked
on that tree first: 934 unit tests, 0 failures, 0 warnings; Mac and iOS Simulator builds clean.
**Re-run on the commit itself (`9fb1098`), on top of the sync screens:** the three reader suites, 7 tests. iPad Pro
13-inch/iOS 26.5: **7/7**, `/tmp/papernest-reader-ipad-postcommit.log`. PaperNest iPhone Duo/iOS 27.1: **6/7, then
7/7** — `testGoToPageTakesANumberFromTheTitleMenu` failed its first run *at launch*: the editor had not appeared
after 30 seconds, so nothing about Go to Page was reached (`/tmp/papernest-reader-iphone-postcommit.log`). Run
alone straight afterwards it passed (`/tmp/papernest-gotopage-iphone-rerun.log`). The Mac's load average was
between 89 and 145 at the time, with other builds running. That is a reason to believe it was the machine, not
proof: one pass after one failure. No other UI suite was re-run on the commit.

**Four defects of mine found by these runs and fixed.**

1. **The find field was 22 points wide in French on a phone** ("Aucun résultat" and "Terminé" took the row). The bar
   now drops the count and the arrows to a second row whenever the field would be under 240 points.
2. **The keyboard was lost after the first letter.** My first fix for (1) used `ViewThatFits`, which swaps one
   branch of views for another; the field in the new branch is a new field, and the swap happened the moment the
   first count appeared. Typing "BUDGET" left "B". **The test still passed its count**, because "b" also occurs
   three times in the fixture — it was the screenshot that showed it. Now a custom `Layout` (`FindBarLayout`) places
   the same five views either way, and the test asserts the field's value.
3. **A page with no hits still exposed an empty "search results" element** to accessibility (iPad, continuous
   notebook). Nothing is created for such a page now.
4. On a phone the bottom palette sat over what the keyboard left of the page, covering the hit just found. It
   stands down while the find field has the keyboard, as it already did for a text box.

**A trap, for whoever writes the next PDF fixture.** On the iOS 27.1 Simulator, a link whose `destination` is set
with PDFKit and written with `dataRepresentation()` reads back with **no page** (`page = -1`); on iOS 26.5 and on
the Mac the same code round-trips. So a link fixture authored inside an iOS test fails before PaperNest has read a
byte — my first `PageLinksUITests` did exactly that, on the phone only. `SyntheticDocuments.handBuiltLinkedPDF()`
writes the file out by hand instead, the same bytes everywhere, and with it the phone passes: **reading** links on
iOS 27.1 is fine. Whether iOS 27.1's *writer* is at fault or its reader of its own output is not known, and no
PaperNest feature writes a link.

**Not verified, plainly.**

- **The Mac was never seen.** Screen access was asked for once and declined. It compiles; nobody has watched find
  or a pointer drag-select on it. In particular **⌘F/⌘G on a Mac are unproven**: they are on the bar's own buttons
  because the system keeps a Find submenu under Edit with the same keys, and which wins has not been observed.
- **Open was never tapped.** The test cancels the question; nothing has been seen to hand a link to Safari, Mail
  or the phone. Links were read from two synthetic PDFs only — no PDF made by a word processor, no named
  destinations, no links on a rotated page in the running app (the mapping is the one the text boxes use, and that
  is pixel-tested).
- **No physical device.** The press-and-hold is a `UILongPressGestureRecognizer` added to the page's scroll view
  (`TextSelectionPress`, the `PagePinchZoom` pattern). XCUITest's synthesized press drives it; a real finger, an
  Apple Pencil, and whether a real scroll still feels right with it attached have not been tried. Read the
  2026-11-11 one-finger-scrolling entry before trusting a synthesized gesture here.
- iPad hardware-keyboard shortcuts, VoiceOver, Dynamic Type at the largest sizes and dark mode were not looked at.
  The selection bar was seen in English only.
- In the running app only an upright, uncropped digital PDF and a notebook were used. Rotated and cropped pages
  and recognised scans are covered by unit tests, not by a UI test.
- Long documents: laying out a 1,320-character page took 68 ms in a unit test, opening the file included. Nothing
  measured a thousand-page PDF in the app.

**Limits by design — say these rather than discover them.**

- A hit inside a **recognised** word lights the whole word, and one inside a typed text box lights the whole box:
  recognition gives no per-letter boxes and dividing a box by its letters drifts on a proportional font.
- A word hyphenated across a line break is two words to find.
- Text a crop hides is not found and cannot be selected; export still carries it, as before.
- Selection needs no drawing tool armed. **A notebook opens with the lasso armed**, so there it needs Markup off
  first. There are no drag handles yet: to change a selection, press again.
- Highlight from a selection uses the default colours and the same Pro gate as Annotate Text.
- Find does not look inside private page comments.

**Existing suites after these changes**, iPad Pro 13-inch (M5), iOS 26.5, `/tmp/papernest-reader-ipad-regress.log`:
`DocumentUtilitiesUITests` 2/2, `EditorFirstTouchUITests` 3/3, `NotesToolbarUITests` 3/3, `EditorWorkspaceUITests`
10/11 — the one red is `testPinchZoomWithLassoAndPen`, which the entry below already records as red at clean
`0edf804`. So the same 18 of 19 as before this work. **Not re-run:** the bulk of `AppUITests`, and none of these on
the phone.

## 2026-11-12 (later) — Document Utilities: one sidebar, one toggle, and the lower bar (Claude, owner's request)

Owner circled the PDF Tools panel on a device screenshot, then supplied a mockup and a written brief: replace the
page strip and the PDF Tools list with **one** right-hand Document Utilities sidebar behind **one** top-right
toggle, and refine the lower floating bar. Built on top of the toolbar slice below; same day, same uncommitted tree.

**What changed in the app.**

- **One panel.** Header with the app's own leaf mark (`BrandMark`), then two sections that fold independently and
  remember it: **Pages (n)** — a horizontal gallery of the document's real pages, the current one outlined, a menu on
  each (move earlier/later, rotate, duplicate, export, delete), and an Add Page menu — and **PDF Tools**, ten compact
  tiles two to a row plus the longer actions a row each. Every tile is the editor's existing button; nothing is a
  placeholder. iPad and Mac show it as the inspector column; a phone shows the same view as a bottom drawer.
- **One control.** A stacked-layers button at the top right on every device (`editor-panels`). The separate page-strip
  column, the phone's thumbnail strip and its toggle, and the two-switch panels popover are gone.
- **Lower bar.** Zoom out, fit, zoom in | drawing mode | display settings | current zoom. The armed tool's icon (a
  second Lasso) and the colour swatches are gone from it. Display settings holds zoom presets, Fit Page, Fit to Width
  (new; iPad/Mac) and Draw with Finger.
- **The current page is held when the panel opens or closes** (and on rotation or resize). It was not: the pages
  refit to the new width and the visible-page tracker moved the selection to a neighbour.

**Results, final code.** Unit suite **811 tests, 0 failures, 0 warnings.** Mac build clean. UI tests, each device
run on its own:

| Suite | iPad Pro 13-inch (M5), iOS 26.5 | PaperNest iPhone Duo, iOS 27.1 |
|---|---|---|
| `DocumentUtilitiesUITests` (new, 2) | 2/2 | 2/2 |
| `NotesToolbarUITests` (3) | 3/3 | 3/3 |
| `EditorFirstTouchUITests` (3) | 3/3 | 3/3 |
| `EditorWorkspaceUITests` | 10/11 — only `testPinchZoomWithLassoAndPen`, red at `0edf804` too | `testNotebookWorkspaceEnglish`, `testPDFWorkspaceEnglish`: passed |
| `AppUITests`: CompactNotebookTools, RoundEraser, StudioPen, NoteImageMenu | not run | 4/4 |

`DocumentUtilitiesUITests` proves: exactly one toggle and none of the old ones; the panel closing gives the page its
room back (iPad) or the drawer opening (phone); the Pages header carrying the real count; a tap on a thumbnail
selecting that page; each section folding without the other; the panel's close button being the same switch; the
page still being page 3 after closing; Delete Page in the panel removing a page from the library on disk; the lower
bar zooming 100 → 150 → 100, the display popover's presets, and Lasso appearing once.

**Five defects of mine found by these runs and fixed — the first two hung the app:**

1. **Hang at launch on iPad, full CPU.** I reset two `UserDefaults` keys in the editor's initializer. Changing
   defaults notifies every `@AppStorage` in the window; a view above the editor rebuilt, initialised the editor
   again, which reset the keys again. Found by sampling the stuck process (`DocumentWorkspace.body` →
   `DocumentView.init` → `NSUserDefaults` → `UserDefaultObserver`). Now a once-per-launch constant.
2. **Still hung after that.** I had made the inspector's visibility depend on the horizontal size class and widened
   the column from 320 to 340. **I changed both back in one step and the hang went away, so which of the two was
   sufficient is not isolated.** The column-or-drawer decision is by device kind now, which cannot flip.
3. Page thumbnails were not exposed as buttons, so nothing could find or activate them by role.
4. The current page changed when the panel closed (above).
5. On a phone, with the strip gone, the hidden top of a tall page lay under the toolbar and accessibility reported
   the tool buttons as covered (real taps still landed). One point of top padding keeps the scroll view out from
   under the toolbar. Also made the colour swatches eager instead of lazy, for the same findability reason.

**Tests changed, and why.** Passages that drove the old page-strip toggle and the panels popover's switches now drive
the one control. On a phone `EditorWorkspaceUITests.revealTool` reaches a tool through the Document Utilities drawer
instead of scrolling the native More menu; before that change the two phone workspace tests failed in that menu
(drag of 3 points per attempt on this short screen), and **that failure was never baselined**. The other session's
uncommitted `editor-panels` popover in `DocumentView.swift` is superseded by this at the owner's instruction and is
gone from the working tree; `Apps/iOS/UITests/PanelControls.swift` is untouched and still used.

**Unexplained, and I cannot rule my changes out:** on the iPhone Duo simulator a test that launches the app
immediately after another test terminated it sometimes gets an app with an **empty accessibility tree** for the whole
30-second wait. Seen four times today (twice after the Spanish run, twice elsewhere), never on the iPad, no crash
report written. Each affected test passed when run again. Cause not investigated.

**Not verified.** The Mac — never seen, so the resizable sidebar, hover and the toggle in a Mac toolbar are compiled
only. Dark mode by me. VoiceOver (including whether fix 5 matters to it). Fit to Width (no test drives it; hidden on
a phone). The thumbnail menu's move, rotate, duplicate and export (only delete and select are driven). Opening
pickers and the camera from the phone drawer (Signature and Pages are driven; the others rely on the same
drawer-steps-aside rule). 11-inch iPad, split view, landscape phone. The rest of `AppUITests`.

**Not built.** Drag-and-drop reordering of thumbnails (the menu's Move Earlier/Later does it instead). Continuous
versus single-page switching and page background in display settings — the viewer does not support switching, so
they are not offered. The mockup's search button. The More (…) menu still lists the same tools on every device.

## 2026-11-12 — Notes editor toolbar redesign (Claude, at the owner's direct request)

Owner supplied a new mockup and a written spec ("Paper NEST — complete notes editor toolbar redesign") and said to
implement it rather than stop at mockups. This is `PaperNestUI` work, done by Claude on that instruction.

**What is real now** — each line is a control that changes what is saved, not a picture of one:

- **Toolbar.** Pen, Highlighter, Eraser, Lasso | Shapes, Text, Image, Sticker, Insert | Undo, Redo, More. Named where
  every tool still fits, icon-only otherwise (measured in the language on screen). On a phone the row scrolls, More is
  pinned at its end and Undo/Redo stay in the lower palette. ⌥⌘1…9 pick the tools.
- **Settings.** One panel frame for all nine tools: popover anchored to the tool on iPad/Mac, bottom sheet on a phone.
  Every setting is saved as it is changed (`EditorToolSettingsStore`, `UserDefaults`, one JSON blob). A launch pointed
  at a throwaway library keeps settings in memory, so UI tests cannot leak state into each other.
- **Pen.** Six presets, each with its own width, colour and opacity. On the Mac every preset shapes its own line
  (`PenDynamics`); on iPad each maps to the PencilKit ink whose strokes survive storage (monoline / pen / fountain pen).
  Hold-to-straighten recognises line, ellipse, rectangle, triangle on both.
- **Highlighter.** Standard, Flat (new stored `InkStroke.cap`), Underline, Marker, Straight; each keeps its own width
  and strength. **Eraser.** Pixel/Stroke, size, and All ink / Handwriting / Highlights. **Lasso.** Mode plus which
  content it may pick up. **Shapes.** Eleven shapes dragged out on the page. **Text.** Type settings for the selected
  box or the next one. **Image.** Photos, Camera, Files. **Sticker.** Sixteen original stickers, placed as images.
  **Insert.** Blank/Lined/Grid page, text box, image, date & time, divider, import, duplicate, organise.

**Unit suite: 811 tests, 0 failures, 0 warnings** (`./scripts/test.sh`; was 757). New: `PenDynamicsTests`,
`StrokeSmoothingTests`, `StrokeSnappingTests`, `InkStrokeCapTests` (Core); `InkStyleRenderTests` (flat tip stops at the
stroke's ends, a faded pen of varying width is one even tone); `EditorToolSettingsTests`, `InkDrawingStyleTests`,
`ToolTargetTests`, `StickerLibraryTests` (UI); four additions to `ShapeAnnotationTests`. Two were red first and fixed
in the product, not the test: line recognition judged by path length rejected a jittery straight line, and three
French strings had a plain space before a colon.

**Builds.** `scripts/swift.sh build` (Mac) and `scripts/build-ios-sim-app.sh` both clean, 0 warnings.
Screenshots from the test runs: `docs/screenshots/notes-toolbar-2026-11-12/`.

**New UI tests — `NotesToolbarUITests`, 3/3 on both devices, final runs:**

| | PaperNest iPhone Duo, iOS 27.1 | iPad Pro 13-inch (M5), iOS 26.5 |
|---|---|---|
| `testEveryToolChangesWhatIsSaved` | passed (101.7s) | passed (127.2s) |
| `testRestingAtTheEndOfAStrokeStraightensIt` | passed (15.1s) | passed (25.7s) |
| `testTranslatedPanelsFit` (fr, es) | passed (66.8s) | passed (65.5s) |

The first one reads the library back from disk after every step: shipped pen stroke saved; ballpoint in the chosen
blue with one width end to end; straight-line highlighter saved as exactly two points; a dragged triangle saved as
twelve points; undo and redo of it; a sticker saved as a 96-point square image; a grid page added; the eraser's
"Highlights" choice surviving the panel being closed; text settings reachable. The second proves the PencilKit path
of hold-to-straighten: lifted at once the stroke keeps its points, rested on it is saved as two.

**Existing UI tests re-run, with a clean-checkout baseline wherever one failed.** "Baseline" is the same test at
`0edf804` in a separate `git worktree`, same simulator — nobody's uncommitted work in it.

| Test | Device | Working tree | Baseline at `0edf804` |
|---|---|---|---|
| `EditorFirstTouchUITests` (3) | iPhone Duo; iPad 13 | 3/3; 3/3 | not needed |
| `testCompactNotebookToolsAndPenControls` | iPhone Duo | passed | not needed |
| `testRoundEraserSizesPartialEraseUndoAndReopen` | iPhone Duo | passed | not needed |
| `testStudioPenSavesAndReopensWithFloatingHistory` | iPhone Duo | passed | not needed |
| `testNoteImageMenuOffersCameraPhotosAndFiles` | iPhone Duo | passed | not needed |
| `EditorWorkspaceUITests`, the other nine | iPad 13 | 9/9 | not needed |
| `testFrenchSignatureAtLargestTextSize` | iPad 13 | **passed alone (17.9s)**; failed once under load | passed (25.2s) |
| `testPinchZoomWithLassoAndPen` | iPad 13 | failed, 419.5 not < 398.525 | **failed, same numbers** |
| `testMixedLassoDefaultsToSelectionAndMovesAllObjectKinds` | iPhone Duo | failed, "0 selected" | **failed, same assertion** |
| `testNotebookToolsAreSideBySide` | iPhone Duo | failed, "Empty notes must keep Add Page and Undo available" | **failed, same message** |
| `testNotebookWorkspaceEnglish` | iPhone Duo | failed at `revealTool("editor-pages")` | **not run** |

- The three rows that fail in both columns are **not caused by this slice**. The pinch one is worth a note for
  whoever owns it: yesterday's fix was measured on an 11-inch iPad only, and on the 13-inch it is red at `0edf804`.
- `testNotebookWorkspaceEnglish` on the phone: every toolbar and settings step in it passed (pen settings, width,
  opacity, close, Signature through More). It then failed scrolling the *native More menu* to reach Pages — the log
  shows the in-menu drag moving 3 points per attempt. **No baseline was run, so whether this slice caused it is not
  known.** It passes on iPad.
- `testFrenchSignatureAtLargestTextSize` failed once at 208s while a second full build was running on the same Mac;
  in that run `testFirstZoomTapChangesTheZoomInPortrait` took 283s against its usual 13s. Run alone it passes. Do not
  run two `xcodebuild` jobs at once and trust the timings.
- One earlier working-tree run of `testNotebookToolsAreSideBySide` failed sooner, at the pen not being hittable
  straight after a notebook was created. It did not happen again, and the new test asserts Pen and Highlighter are
  hittable on a freshly opened page and passes on both devices. Read that as "not reproduced", not "explained".

**Assertions changed in tests that pinned the previous approved toolbar** — the owner's new mockup overrides each:
"Keep the primary toolbar icon-only" now applies to a phone only; "Eraser must sit directly after Pen" is now
Highlighter-before-Eraser; "Settings stay near Pen" now applies to iPad only (a phone gets a bottom sheet); the
48-point Text Box width now applies to a phone only. Settings forms are found as `tool-panel-scroll` instead of a
`collectionView`, and `app.closeToolSettings()` waits for the sheet to finish leaving before the next touch.

**Found on the way, about testing here rather than about the app:**

- On the iPhone Duo the page is centred in a viewport shorter than the page, so its top ~130 points are above the
  visible area. A drag aimed at the page element's own frame lands on the page strip. The new test aims at the
  reachable part of the page; that is likely why `testMixedLasso…` is red on this simulator at `0edf804`.
- `isHittable` on a button scrolled out of a horizontal scroll view does not return false, it records a failure.
- **Unexplained:** launched immediately after the Spanish run of `testTranslatedPanelsFit`, the app came up with an
  empty accessibility tree twice in a row. The translated test now runs last. The cause was not investigated.

**Not verified — please do not read any of these as done:**

- **The Mac was never seen.** Screen access to the dev build was declined in session, so the Mac toolbar, popovers,
  hover states, ⌥⌘ shortcuts, the Mac pen dynamics on screen, stroke smoothing and Mac hold-to-straighten are
  unit-tested and compiled, and nothing more.
- **Dark mode** was not looked at by me. The owner's own device screenshot (16:06) shows the toolbar in dark mode on a
  physical iPad in landscape with all nine named tools, Undo, Redo and More fitting; that is their observation.
- **No Apple Pencil.** Pressure, the pressure switch, tilt, and hold-to-straighten with a Pencil (which keeps
  reporting while held still) were exercised only by synthesized finger touches.
- **The eraser's Handwriting/Highlights limit on iOS** is unit-tested for what it selects, and the setting is
  UI-tested for persisting, but no test erases with the limit on. It gives PencilKit only the permitted ink and has
  the page draw the rest; whether that flickers on switching was not looked at.
- The Photos, Files and Camera pickers opened from the Image panel: the buttons are asserted, the pickers appearing
  after the panel closes is not. Insert → Date & Time, Divider, Duplicate, Organise: not driven by a test.
- VoiceOver, Dynamic Type other than one French largest-size launch, iPad portrait at 11 inches, split view, Stage
  Manager. French and Spanish need a native reader. `UIKit:MenuBuilder` shortcut-clash logging was not captured.
- The rest of `AppUITests` (roughly a hundred tests) was **not** run. Only the tests named above were.

**Not built** (from the owner's spec; nothing on screen pretends otherwise): shape fill, dashed and dotted outlines,
corner radius, rotation and grouping; object and selection erasers; lasso copy/cut/paste/duplicate/delete/recolor/
reorder/group; text underline, strikethrough, lists, spacing, box background and border, hyperlinks, find and
replace; image crop/rotate/flip/adjust/border/background removal/lock/replace; custom sticker import and emoji
stickers; tables, links, audio, checklists, dot-grid paper, paper size and margins; tilt; pencil graphite texture;
a repositionable toolbar; "save preset".

## 2026-11-11 — The pinch zoom test was aimed at the wrong element (Claude)

- `EditorWorkspaceUITests/testPinchZoomWithLassoAndPen` had been failing on iPad and crashing the runner on iPhone.
  It is a **test** defect, not a product one, and this is the change the 2026-11-10 entry said belonged to Codex.
- **The variable is the element, isolated by a four-cell probe rather than guessed** — same closing gesture, same
  scale, only the target and the zoom state varying:

  | | pinch the scroll view | pinch the paper |
  |---|---|---|
  | page fits (100%) | 100% -> 100%, **no change** | 100% -> **50%** |
  | page overflows (150%) | 150% -> 150%, **no change** | 150% -> **75%** |

  So overflow state is irrelevant and the scroll view is simply the wrong target. The scroll view is the whole
  viewport (481x1210 on an 11-inch iPad); a **closing** pinch starts its two touches near opposite edges of whatever
  element it is given, which on the scroll view puts them above and below the paper, so the recognizer never sees
  two touches on it. An **opening** pinch starts centred, which is why only the shrink half ever failed.
- Fix: pinch `document-page-image` instead of `document-page-scroll`, and give the closing pinch a negative
  velocity (UIKit reads the sign as direction; it had `velocity: 1` with `scale: 0.7`).
- **Results: `testPinchZoomWithLassoAndPen` passes on iPad (37.9s) and on iPhone (27.4s)**, where it previously
  failed and crashed respectively; `testZoomButtonsWithLassoAndPen` still passes on iPad (27.5s).
- **This corrects a claim in the 2026-11-10 entry.** That entry said pinch works "in both directions", citing a
  100% -> 50% shrink. That shrink started from a page that *fits*; the case a reader actually hits is shrinking one
  that overflows, and it had not been tested. It was tested now and does work — the conclusion held, but it had
  been resting on a narrower measurement than the wording implied.
- **Not done.** No physical iPad. No fr/es. The probe ran on an 11-inch iPad only, so the edge-touch geometry is
  measured at one viewport size.

## 2026-11-11 — iPad: a finger that cannot draw could not scroll either (Claude)

Owner: "i cannot scroll pages thirugh hands on ipad".

- **Root cause, in two settings that contradict each other.** While markup is armed the page scroll view raises its
  pan recognizer to `minimumNumberOfTouches = 2`, reserving one finger for drawing
  (`NotebookTouchScrolling(requiresTwoFingers: isMarkingUp)`). But on iPad **"Draw with Finger" defaults to off**
  (`isFingerDrawing = false`, phone-only override at `DocumentView.swift:888`), which runs PencilKit at
  `.pencilOnly` (`InkCanvas.swift:63`). With the Pen armed the finger was therefore refused by the canvas *and*
  refused by the scroll view. Only a Pencil worked.
- Fix: `PageScrollTouchPolicy.requiresTwoFingers(markingUp:tool:fingerDrawing:)`. One line changes in
  `DocumentView.swift`; the rule lives in a new UIKit-free file so it can be tested anywhere, and is read through a
  `pageNeedsTwoFingers` property because inlining it pushed `PageViewer`'s body past the type-checker's limit.
- **The first version of the fix was wrong, and the owner caught it.** It read `markingUp && fingerDrawing`, which
  frees the finger whenever "Draw with Finger" is off — including while **lasso** is armed. Lasso selects rather than
  draws, so that setting does not gate it and a finger lassoes regardless; handing the finger to the scroll view
  there would have stopped lasso selection working at all. The rule is now about the *tool*:
  `markingUp && (tool == .lasso || fingerDrawing)`. Added as a failing test first — only the lasso case went red
  against the previous rule, the other three stayed green — then made to pass.
- **Two wrong turns, both corrected by measuring, both worth recording.** First I claimed the cause was notebooks
  auto-arming markup; a probe disproved it — lasso scrolled on the **first** drag. Then a single long probe appeared
  to show "Pen armed: 10 drags, no movement", and I reported that as the bug. Re-measured from a **fresh launch per
  condition** it collapsed: lasso **1**, pen with finger drawing off **1**, pen with finger drawing on **1**, markup
  off **1**. The earlier figure was an artifact of state left by previous drags in the same session.
- **The simulator cannot test this at all, which is the important limitation.** Even with finger drawing ON — where
  `minimumNumberOfTouches` is 2 — a synthesized one-finger XCUITest drag still scrolled in 1. XCUITest's drags do not
  honour that requirement, so a UI test passes with or without the fix. A UI test written for this was deleted rather
  than kept: **it passed before the fix and so could never have caught the bug.**
- What is verified: `PageScrollTouchPolicyTests` — 3 tests, proved red by restoring the old `markingUp` rule (only the
  finger-cannot-draw case failed, the other two stayed green), green again after. Full unit suite **235 in the UI
  target**, 5 targets all passing. iOS Simulator and Mac builds clean, no warnings. On iPad, Codex's
  `testTwoFingerContactDoesNotDrawAndSingleFingerStillWrites`, `testNotebookScrollsBetweenExistingPages` and
  `testScrollAppendsOneMatchingNotebookPage` all **pass** — the first of those turns finger drawing on, so the path
  where the reservation still applies is unchanged.
- **Not verified: that this fixes the owner's problem.** The behaviour only differs under real touches, and no
  physical iPad was used. The owner should confirm on hardware.
- `DocumentView.swift` is inside Codex's "cross-platform editor zoom" claim of 2026-11-08, still active and
  unreleased. Entered on the owner's direct instruction, and said plainly here. `ls -lT` before editing:
  `EditorWorkspaceUITests.swift` untouched since 2026-11-08 15:22, tree carrying only this session's work.
  `PageZoom.swift`, `PageSelectionOverlay.swift`, `InkCanvas.swift` and all gesture routing **untouched**.

## 2026-11-10 13:55 CST — Brand mark everywhere, and My Space moved under Recent (Claude)

Two owner requests: put the real brand mark in the places still using a lookalike symbol, and move My Space below
Recent instead of beside it on iPad and Mac.

- **The mark, in all three remaining places.** `LibraryHome.swift` (dashboard header), and two in
  `SubscriptionViews.swift` (the Pro card title, and the page glyph inside `ProPaperIllustration`) drew the SF Symbol
  `leaf.circle` — Apple's generic leaf, close enough to pass at a glance and not our artwork. All three now go through
  a new shared `BrandMark.image(size:)` in `Sources/PaperNestUI/BrandMark.swift`, which the welcome screen also uses.
  The illustration glyph was included deliberately rather than left as decoration, because that makes the rule a clean
  invariant — no lookalike symbol anywhere in the module — which is something a test can actually hold.
- **Guards widened and proved red.** `BrandMarkTests` now asserts the invariant over **every** `.swift` file in
  `Sources/PaperNestUI` (with `BrandMark.swift` exempt, since it names the symbols in prose to say why they are
  wrong), plus that the three lockup files call the shared builder, plus the existing bundle check. Proved by putting
  `leaf.circle` back in the header: the invariant test and the builder test both failed while the bundle test still
  passed; green again after restoring, with `git status` confirming nothing left behind. A first version of the
  invariant test did not compile (`try` inside `&&`) and was fixed before it ever ran green.
- **My Space.** It sat in a fixed 240-point column beside Recent at regular width — a narrow strip next to a very
  wide list. The branch is gone; every size now stacks Recent then My Space, which is what the phone already did.
- **A regression I caused and caught by looking.** Stacking made the cards *narrower*, not wider: the adaptive grid
  kept its 95-point minimum, so across a full-width row it packed in more, smaller columns and "Documents" broke
  across two lines as "Docu-ments". The minimum is now 150 at regular width (95 compact, 220 at accessibility sizes).
  Confirmed fixed on the second iPad capture.
- Verified: **757 unit tests across 5 targets pass** (232/175/139/158/53); iOS Simulator and Mac builds clean with no
  warnings. `HomeToolsUITests` **all 5 pass on iPad Pro 13-inch/iOS 26.5**, including English, French and
  Spanish-largest-text, and both brand-heading tests. Seen on all three platforms with a seeded throwaway library:
  iPhone 17 Pro, iPad Pro 13-inch, and the native Mac app — and on Mac all three mark sites were opened and looked at,
  including the paywall illustration behind Profile → Upgrade to Pro. Screenshots
  `docs/screenshots/home-myspace-en-{ipad,mac}.png` and `docs/screenshots/pro-brandmark-en-mac.png`.
- **Not done / not verified.** The Pro card and paywall were seen on **Mac only**; not on iOS, and not in French or
  Spanish. No Mac window-resize check, so the Mac compact branch below 760 points is still covered only by the iPhone
  runs. Subscriptions remain deliberately unconfigured, so the paywall shows its unavailable state — that is expected
  and unrelated. The dashboard's own layout above Recent (search, capture actions, tools) was not touched.
- Both files are in Codex's `PaperNestUI` area, edited at the owner's explicit request; Codex has no active claim on
  either.

## 2026-11-10 13:20 CST — Welcome screen: brand mark, and the wide layout for iPad/Mac (Claude)

- **The welcome screen already existed on all three platforms**, with a two-column layout above 760 points, Mac-specific
  copy and en/fr/es strings — Codex built it on 2026-10-27 and released the files. The work here is the owner's two
  asks against that: make the lockup's mark the app icon's, and make the wide layout hold a large screen.
- **The mark.** The lockup drew `square.stack.3d.up.fill`, so the first screen after launch showed a different logo
  from the icon the user had just tapped. `scripts/make-app-icon.py` now also emits
  `Sources/PaperNestUI/Resources/Brand.xcassets/BrandMark.imageset` from the same brand art — alpha-only white, with
  `template-rendering-intent`, so SwiftUI tints it with `Theme.accent` and it follows light and dark mode. No colour
  had to be chosen: `Theme.accent` light is already `0x7545F8`, the exact purple sampled from the icon artwork.
- **The wide layout.** The illustration was pinned at 160 points, a stamp adrift on a 13-inch iPad, and the pinned
  action sat about 380 points below the copy with nothing between. The illustration now scales with window height
  (clamped 0.95–1.55), and above 900 points of height the action moves inline under the copy, forming one column:
  brand, illustration, title, subtitle, Get started. Shorter windows keep it pinned, where it cannot scroll out of
  reach — that branch is why a Mac window and iPhone landscape still behave as before.
- **A regression I introduced and caught by looking.** Moving `safeAreaInset` inside the `GeometryReader` left
  `minHeight` using the full height while the scroll viewport was shorter, which pushed the iPhone's third feature row
  behind the button. Fixed with two readers: the outer one decides where the action goes, the inner one measures
  *inside* the inset so content centres in the room actually left. Caught on a screenshot, not by a test.
- **Two guards, each proved red on its own.** `BrandMarkTests` checks the asset is in the built resource bundle and
  that the lockup draws it rather than a system symbol. Both failures are silent, so both were proved: reverting the
  lockup to `square.stack.3d.up.fill` failed the source check **while the asset check still passed**; deleting
  `Brand.xcassets` failed the asset check **while the source check still passed**. Each catches only its own fault.
  Both green again after restoring, and `git status` confirmed nothing was left behind.
- Verified: **756 unit tests across 5 targets pass** (231/175/139/158/53), iOS Simulator build clean with no warnings,
  Mac app build clean. Existing welcome UI tests **pass on both iPhone 17 Pro/iOS 27.1 and iPad Pro 13-inch/iOS 26.5** —
  `testFirstLaunchWelcomeAndRelaunchInAllLanguages` (which covers en/fr/es) and
  `testWelcomeLargestTextKeepsContinueReachable`, the accessibility-size case where the wide branch is deliberately
  off. Screenshots retained at `docs/screenshots/welcome-brandmark-en-{iphone,ipad}.png`.
- **Mac now verified by eye — 2026-11-10 13:39 CST, after the owner granted screen access.** The native dev app was
  launched against a throwaway library with a fresh `-PaperNestDebugWelcomeKey`. The lockup draws the leaf mark; the
  Mac-specific copy is correct (*Import a document…* and *Import PDFs, images and other files* with an import glyph,
  not the camera); the action renders inline under the copy as the tall-window branch intends. **The flow works, not
  just the layout**: pressing Get started completed the welcome and the app proceeded to the library. Screenshot
  `docs/screenshots/welcome-brandmark-en-mac.png`. This supersedes the earlier "never seen" caveat.
- **Found while there, not fixed:** the dashboard header (`LibraryHome.swift:119`) and two places in
  `SubscriptionViews.swift` draw the SF Symbol `leaf.circle` rather than the brand mark. It reads as a leaf, so the
  mismatch is subtle, but it is Apple's generic glyph and not our artwork — a third brand representation beside the
  icon and the welcome lockup. Out of scope for what the owner asked for here and untouched.
- **Not done / not verified.** The iPad simulator's panel grant went unanswered, so iPad captures came from
  `xcrun simctl io` instead. No new fr/es screenshots were taken this round, and no Mac window-resize check was run,
  so the Mac compact branch below 760 points is covered only by the iPhone runs. **A pre-existing problem was found and left alone:** in
  iPhone landscape the safe-area insets drop the usable width to just under the 760-point threshold, so it uses the
  compact layout in a 402-point-tall window and the title sits below the fold behind the button. That predates this
  change and is not fixed here.
- This lands in Codex's `PaperNestUI` area deliberately, at the owner's explicit request. Codex's welcome claim from
  2026-10-27 is released, so nothing was held; `docs/screenshots/welcome-*.png` from that work were left untouched and
  the new captures were added beside them under different names.

## 2026-11-10 — iPad: the first touch in a freshly opened document was being eaten (Claude)

- Owner report: "also on ipad i an not abe to zoom in and out fingers." The report named pinch; pinch turned out to
  be innocent. **What was broken is that the FIRST touch of any kind in a freshly opened document did nothing.**
- **Root cause, confirmed by direct manipulation rather than inference.** The tools inspector was auto-presented on
  iPad from the moment the editor appeared, whatever the window width. Where the window is too narrow for SwiftUI to
  lay `.inspector` out as a column it presents as an **overlay**, and that overlay's tap-outside-to-dismiss
  **swallows the first touch outside it**. Forcing `_isShowingPDFTools` to `false` made the first tap land
  (`Not selected` → `Selected`); restoring it made the tap vanish again.
- **Width, not orientation, is the switch** — measured, first tap on the pen after opening a notebook:
  **834pt (11-inch portrait) eaten**; **1032pt (13-inch portrait), 1210pt (11-inch landscape) and 1376pt (13-inch
  landscape) all landed.** So the overlay/column boundary sits between 834 and 1032, and the fix's 900pt constant is
  inside that measured bracket rather than guessed.
- **How the gesture layer was cleared of blame.** `testZoomButtonsWithLassoAndPen` failed on iPad with the *same*
  numbers as the pinch test (417.5 → 417.5), so two unrelated input paths were failing identically. Then a probe
  showed zoom tap 1 does nothing and tap 2 works (100% → 150% → 200% → 300% → 400%), and that the first tap on the
  **pen** is lost too. A 3-second wait does not rescue it, so it is not a settling artifact.
- **Pinch was never broken.** Traced through the existing `-PaperNestDebugZoomTrace` hook (its `print` does not reach
  the logs, so it was temporarily switched to `NSLog` to capture, then reverted). Pinching the **page** works both
  ways — 100% → 50% with a full healthy trace, `state=2` repeatedly then `state=3`. Pinching the **scroll view
  element** produces no recognizer callbacks at all, because XCUITest starts those two touches near the viewport
  edges, outside the page. That is a test-geometry artifact.
- **Fix, `DocumentView.swift` only:** auto-present the inspector only when the active window is at least
  `inspectorColumnMinimumWidth` (900pt), decided in `init` from `activeWindowWidth()`. **Deciding up front matters
  and was measured:** an intermediate version that presented from a later layout pass cost a 13-inch iPad in
  landscape its first tap anyway (reproduced twice, ~150s each), because presenting an inspector *after* the editor
  is on screen costs a touch of its own. The shipping fix keeps the original presentation path and changes only
  whether it is taken. macOS untouched.
- **The owner's "tools visible by default" still holds wherever it fits as a column** — including 13-inch portrait
  at 1032pt. Below 900pt it is one deliberate tap away on the toolbar instead of silently eating the first one.
  `EditorFirstTouchUITests` asserts both halves, keyed off the measured window width rather than orientation.
- **Results.** New `EditorFirstTouchUITests` (3 tests) was **red first**: portrait tool tap and portrait zoom tap
  failed, landscape passed — the landscape control proving the test was not simply broken. After the fix:
  **iPad 11-inch 3/3 pass, iPad 13-inch 3/3 pass, iPhone 3/3 pass**, and Codex's
  **`EditorWorkspaceUITests/testZoomButtonsWithLassoAndPen` now passes on iPad**, having failed before.
  Full unit suite **754 tests, 0 failures, 0 warnings**, exit 0. iOS Simulator build clean.
- **Still red, and deliberately not touched: `EditorWorkspaceUITests/testPinchZoomWithLassoAndPen`.** It pinches
  `document-page-scroll`, whose touch start points fall outside the page, so it fails and then crashes the runner.
  That is Codex's test and the one-line change (aim it at `document-page-image`) is theirs to make.
- **Not done.** No physical iPad. No fr/es pass. No VoiceOver or Dynamic Type. Split-view and Stage Manager widths
  were not exercised, only full-screen portrait and landscape on two iPad sizes. The 900pt constant is bracketed by
  measurement at 834 and 1032, not read from a documented Apple threshold.

## 2026-11-09 19:25 CST — Mac: the editor's bottom scrollbar removed, the right one kept (Claude)

- Owner asked, in session: "on mac remove scrollbar at bottom only keep it in right."
- **Identified by measurement, not by eye.** macOS overlay scrollbars fade and do not survive a screenshot, so the
  editor's scrollbars were enumerated through the accessibility tree instead, with a notebook zoomed in far enough
  to overflow both axes. **Before — three:** `AXScrollBar [277,700 1004×14]` (horizontal, along the bottom of the
  page area — the one the owner means), `AXScrollBar [1267,148 14×565]` (vertical, down the right of the page area
  — the one to keep), `AXScrollBar [1535,81 14×703]` (the PDF Tools sidebar's own).
- **Change: one modifier**, `.scrollIndicators(.hidden, axes: .horizontal)`, on the `PageViewer` scroll view
  (`document-page-scroll`, the `ScrollView([.horizontal, .vertical])` in `DocumentView.swift`), behind
  `#if os(macOS)`. iOS already shows these only while scrolling and is deliberately left alone.
- **After — two:** `AXScrollBar [1267,148 14×565]` and `AXScrollBar [1535,81 14×703]`. The horizontal bar is gone;
  the right-hand one and the sidebar's own are untouched, at identical frames. Dev app rebuilt, exit 0, 0 warnings,
  checked against a seeded throwaway library.
- **Panning was not separately exercised.** `scrollIndicators` is documented as presentation-only, and the page
  still overflows the viewport identically at the same zoom in the after-shot, which is what it would not do had
  the axis been disabled and the content re-laid-out to fit. But no horizontal pan gesture was performed, so
  "you can still pan sideways, you just cannot see the bar" is reasoned from those two facts, not measured.
- **Full suite: 754 tests across 5 targets, all passed** (229/175/139/158/53), exit 0, **0 warnings**.
- `DocumentView.swift` is under Codex's still-active "cross-platform editor zoom" claim. It was entered at the
  owner's direct instruction, after `ls -lT` showed it untouched since 2026-11-08 15:15 with a clean tree; only the
  indicator modifier was added, and no zoom logic, gesture routing, `PageZoom.swift` or `PageSelectionOverlay.swift`
  was touched. The handoff says the same.
- **Not done:** no fr/es pass, no iPad or iPhone check (the change is macOS-only by construction), no VoiceOver.

## 2026-11-09 18:50 CST — Mac signature save: the Name field nobody could see (Claude)

- **Owner report: "save signature feature is not working on mac."** The symptom, confirmed by the owner when asked
  rather than guessed, is **"unable to enter name"**.
- **Reproduced before anything was changed, and the first four attempts all PASSED** — which is the useful part of
  the record, because it is what ruled the other candidates out. Against throwaway libraries only, never a real one:
  (1) dev SwiftPM app, PDF document, typed name then drew then Save → saved, row `Everyday|633` in `signatures`;
  (2) lined notebook with two pen strokes and a **lasso selection active** ("2 selected"), matching the state in the
  owner's own window → saved, `Notebook Sig|779`; (3) quit, relaunch, reopen → **both signatures load**, `user_version`
  9; (4) Xcode `PaperNest-macOS` build (what the owner actually runs), **drew first then named** → saved,
  `Xcode Build Sig|983`. So the store, the premium gate, the `beforeAction` guard and persistence were all fine.
- **Root cause, measured not inferred.** Every pass above reached the Name field by accessibility `element_index` —
  something no person can do. Driving it the way a person does: the Name row renders the label **"Name"** and the hint
  **"Enter a name to save your signature."** and **nothing else** — no box, no border, no placeholder. The editable
  field is an **invisible 180×13 strip on the right** (`AXTextField [1344,402 180×13]`). A raw click on the one visible
  word lands on `AXStaticText 'Name'` and **focuses nothing**; the keystrokes went to the AXWindow and the field stayed
  empty. `canSave` requires a non-empty name, so Save Signature stays greyed out for good.
  Mechanism: `TextField(title, text:)` in a macOS `.formStyle(.grouped)` Form renders its title as an **external
  leading label**, not as the in-field placeholder iOS draws. Mac-only by construction.
- **Fix: one argument.** `prompt: Text(Self.namePrompt)` on that TextField, where `namePrompt` reuses the existing
  `signature.name` string — so **no new key enters the shared `Localizable.strings`** and iOS keeps rendering the same
  string it already rendered. No layout, spacing, colour or structural change: the owner asked in session that the
  signature section's design and template not be changed, and approved a prompt only.
- **The test was written first and proved able to fail.** `Tests/PaperNestUITests/SignatureNameFieldTests.swift`,
  4 tests. Red first (`type 'SignatureSheet' has no member 'namePrompt'`), green after.
  **Then the fix was deliberately reverted to check the test has teeth:** with only
  `, prompt: Text(Self.namePrompt)` removed, `theNameTextFieldStillHandsThatPromptToSwiftUI` **FAILED**
  (`Expectation failed: field.contains("prompt:")`, exit 1) **and the other three still passed** — recorded because it
  shows the three behavioural tests alone would not have guarded this fix at all. The guard reads the one line of
  `SignatureSheet.swift` through `#filePath`, the way `LocalizationTests` already reads source. Fix restored.
- **Full suite after the change: 753 tests across 5 targets, all passed** (228/175/139/158/53), exit 0, **0 warnings**.
  (An earlier run of the same suite was piped through `tail`, so its exit code was `tail`'s; it was re-run with the
  whole log captured before any of this was claimed.)
  **Correction, 19:25 CST — that 753 understated the tree it was committed with.** The run happened while
  `SignatureNameFieldTests` still had **three** tests; the fourth, the source-reading guard, was added afterwards
  during the revert check and the full suite was *not* re-run before `a2f84c6` was committed. So the guard test
  itself had only ever been exercised through `--filter`, and "753" named a tree one test smaller than the one that
  landed. The suite has since been run against the committed state: **754 tests** (229/175/139/158/53), 0 failures,
  0 warnings, exit 0. Nothing was failing at any point, but the count in that commit message describes the run, not
  the commit.
- **Native Mac verification of the fix**, dev app rebuilt, throwaway library `/tmp/pn-sigfix`, dark appearance: the
  Name row now draws a grey **"Name"** inside the field; **a raw click on that prompt text** (by coordinate, not by
  element) reports "caret placed"; name entered, stroke drawn, Save Signature enabled and pressed; row `Karan|270`
  present in `signatures`; app quit and relaunched, document and panel reopened, **the signature is listed with its
  preview and placement preview**. That is the full lifecycle end to end.
- **iOS, behaviourally: `PaperNest-iOS` builds clean for the iOS Simulator, exit 0, 0 warnings**, and the existing
  iOS signature lifecycle UI test **`AppUITests/testSavedSignaturePlacesAndSurvivesReopen` PASSED** — 1 test,
  0 failures, 110.007s, `** TEST SUCCEEDED **` (`scratchpad/ios-ui-sig.log`). That covers draw → name → save →
  place → reopen on iPhone, so the added argument broke nothing on iOS.
- **iOS, visually: MEASURED, and iOS is unchanged.** The open question was whether iOS, given a `prompt:`, would
  *also* draw the TextField's title as a visible label — an extra element that would shift the field and could
  truncate fr/es at the XXXL sizes Codex verified. The simulator panel would not grant device access and
  `Simulator.app` is not present under this Xcode, so this was settled instead with a **throwaway XCUITest probe**
  that navigated to the signature sheet and inspected the row directly (file added, run, then **deleted** — it is
  not in the tree or in any commit). Result, on "PaperNest iPhone Duo", `** TEST SUCCEEDED **`, 48.226s:
  **`placeholderValue = "Name"`** and **`visibleNameStaticTexts = 0`** — iOS draws the prompt as the placeholder,
  exactly where the title's placeholder already was, and renders **no separate "Name" label**. Field frame
  `(44.0, 349.33, 318.0, 22.0)`, one element, no added row content. So the iOS design is untouched and the
  `#if os(macOS)` fork is unnecessary.
- Test simulator used: **"PaperNest iPhone Duo" (F5269418)**, the project's own device, returned to Shutdown. The
  owner's iPhone 17 Pro Max (414752ED) was **not** booted, installed to, or touched, and neither was their running
  Mac Xcode instance (pid 27784).
- **Not done / not verified.** Real hardware keystrokes were never delivered — the background automation writes text
  through accessibility, so "typing on a physical keyboard reaches the focused field" is reasoned, not measured.
  No fr/es Mac pass. No physical hardware. VoiceOver and Dynamic Type untouched. The owner's own running Xcode
  instance (pid 27784) is a **pre-fix** build and will keep showing the old behaviour until they rebuild.

## 2026-11-09 12:38 CST — iOS dark and tinted icon appearances (Claude)

- Checked Apple's current HIG ("App icons", updated 2026-10-28) before designing, and it corrected two assumptions.
  **Dark icons want a colour background, not transparency** — "Color backgrounds generally offer the greatest contrast
  in dark icons", built from the light icon with complementary colours and "avoid excessively bright images". And the
  appearance list is now **six** (default, dark, clear light, clear dark, tinted light, tinted dark), with the system
  generating any variant not supplied by segmenting the bitmap into foreground and background.
- Dark is the same mark and framing on a deeper field (`TOP_DARK (74,42,160)` → `BOTTOM_DARK (44,22,104)`), mark
  softened to `(232,226,252)` rather than pure white. Tinted is derived from the dark icon's greyscale, so the mark
  cannot drift between appearances, and is written back as **RGB, not single-channel grey** — a colour-space mismatch
  between the three files is a reported cause of the tinted variant misrendering.
- `actool` compiles **clean with no diagnostics on both iphoneos and macosx**. `assetutil` confirms all three
  appearances reach the compiled catalogue: `(default)` 4 renditions, `UIAppearanceDark` 2, `ISAppearanceTintable` 2.
- Verified on iPhone 17 Pro / iOS 27.1. **Icon appearance is chosen in Home Screen Customize, and with that set to
  Default, turning on system dark mode does not change the icon** — the tile stayed pixel-identical at
  (133.3,89.7,249.2), the light asset. Note this is narrower than "icons ignore dark mode": the Customize panel also
  offers Dark → **Auto**, which does follow the system appearance, and that path was not exercised. Under
  Customize → Dark → Always the rendered tile measured **(69.6,39.2,151.8) against the dark asset's (70,39,152)** at
  the same relative point, so iOS draws our asset rather than a generated one.
- **Scope of the on-device check:** iPhone only, one device, and the sub-modes actually selected were Dark → *Always*
  and Tinted → *Light* with the default blue tint. **Tinted → Dark, the Auto options, other tint hues and iPad were
  not exercised.** The HIG counts "tinted dark" as an appearance of its own, so it is untested here.
- **Tinted was proved by deliberate falsification, not by appearance.** A tinted variant looks plausible whether the
  system uses our file or derives one, so the asset was temporarily inverted and reinstalled: the PaperNest tile
  inverted to a light field with a dark mark while every other icon was unchanged. The diagnostic was then discarded
  by regenerating from source, confirmed **byte-identical** to the pre-diagnostic file.
- Full suite after the change: **750 tests across 5 targets, all passed** (225/175/139/158/53), exit0.
- **Not done / not verified.** No `clear light` or `clear dark` variant. This was checked rather than assumed: a
  throwaway copy of the catalogue in the scratchpad, with one entry added at `"appearance": "luminosity",
  "value": "clear"`, makes actool emit **`warning: Unknown luminosity value "clear"`** and the entry is dropped — the
  compiled car still carries only `(default)`, `UIAppearanceDark` and `ISAppearanceTintable`. So a bitmap appiconset
  cannot express the clear appearances at all; supplying them means moving to a layered Icon Composer `.icon`, which
  Apple now prefers over bitmaps and which would also let us control which elements take Liquid Glass. The real
  catalogue was not touched by that probe.
  macOS appearance variants are untouched. Nothing checked on physical hardware or through App Store validation.
- Simulator cleanup: tapped Customize → Default, set the device back to light mode, and shut the simulator down.
  The Default tap was not screenshotted afterwards, so it is reported as done, not verified.

## 2026-11-09 11:36 CST — App icon: generator, catalogue, both build paths (Claude)

- The project had **no icon catalogue at all** — a hard App Store blocker found during the 2026-11-08 deployability
  analysis. Added `scripts/make-app-icon.py`, which derives everything from the approved mark
  `docs/brand/papernest-instagram-profile.png` (1080x1080, leaf-in-a-ring `#7545F8` on `#FAF9FF`) and draws it white
  on a brand-purple gradient, the way the approved redesign board draws it. Nothing is hand-edited; re-run the script
  if the mark changes.
- First run was **wrong and was caught by looking at the output**: keying on distance-from-purple against an arbitrary
  divisor gave the near-white background alpha 80, so every tile carried a pale square behind the mark. The real
  background-to-brand L1 distance is 320, sampled from the art (background exactly `(250,249,255)`, 1,055,286 px;
  mark `(117,69,248)`, 107,115 px). Re-keyed against the sampled background; the square is gone.
- **Two build paths, both wired.** `scripts/build-mac-app.sh` assembles its bundle by hand from SwiftPM and compiles no
  asset catalogue, so a catalogue alone would have left the app that actually runs here iconless; it now carries
  `Apps/Mac/PaperNest.icns` with `CFBundleIconFile`. The Xcode targets take `Apps/Shared/Assets.xcassets` with
  `ASSETCATALOG_COMPILER_APPICON_NAME`. Both come out of the one generator, so they cannot drift.
- Verified, not assumed: `actool` compiles clean for **iphoneos and macosx with no diagnostics**; dev Mac build exit0
  with `codesign --verify --strict` still passing; Xcode `PaperNest-iOS` **BUILD SUCCEEDED** (`Assets.car` +
  `CFBundleIconName` + `AppIcon60x60@2x.png` in the bundle, no icon/asset warnings); Xcode `PaperNest-macOS`
  **BUILD SUCCEEDED** (`AppIcon.icns` + `Assets.car`). `NSWorkspace.icon(forFile:)` renders the real mark for both the
  dev and Xcode Mac bundles, so macOS resolves it rather than falling back to the generic app icon.
- iOS Home screen **confirmed on iPhone 17 Pro / iOS 27.1**. First screenshot showed a dark placeholder glyph; that was
  SpringBoard's icon cache, not a build fault — the installed bundle's own `AppIcon60x60@2x.png` was already the right
  art, and the mark appeared after `launchctl stop com.apple.SpringBoard`. Five stale PaperNest installs from earlier
  sessions were removed first so the tile under test was unambiguous.
- Checked for a third, unwired build path after a stale `com.example.papernest.dev` iOS install turned up on the
  simulator. There is none: `scripts/build-ios-sim-app.sh` and `scripts/ui-test-ios.sh` both run `xcodegen` and
  build the `PaperNest-iOS` scheme, so they inherit the catalogue. Confirmed by running the Simulator script and
  finding `Assets.car`, `AppIcon60x60@2x.png` and `CFBundleIconName` in its output bundle. The `.dev` install is a
  leftover from when that script hand-assembled its bundle, which its own header comment describes.
- Full suite after the change: **750 tests across 5 targets, all passed** (225/175/139/158/53), exit0.
- **Not done / not verified.** No dark-mode or tinted iOS variant, and no layered iOS 26+ `.icon` (Icon Composer)
  asset — iOS uses the single light tile for every appearance. Not checked on a physical device, not checked on iPad
  hardware, and not run through App Store validation. The mark itself is the existing brand art, not a new design;
  "PaperNest" remains an uncleared placeholder name, so the icon inherits that risk.

## 2026-11-08 15:12 CST — iOS27 prefilled-name/no-keyboard comparison (Codex heartbeat)

- Temporarily prefilled NotebookCreationSheet name and skipped name focus/typing in the existing Notes creation helper; kept accessibilityXXXL, Notes entry, toolbar Create and editor assertion. iPad6528AE8B/iOS27 **1 passed,33.726s,exit0**, `/private/tmp/papernest-ios27-no-keyboard.log`,240-second bound.
- In contrast to prior normal-typing failures, this route successfully saves and reaches editor with toolbar Create. Evidence narrows investigation to keyboard/input/layout interaction; does not prove a specific framework bug or a durable fix. Next isolate focus-only versus typing, or keyboard dismissal with verified focus/geometry change. Normal typing regression remains open.
- Both temporary source edits reverted by exact replacement preserving unrelated changes. No retained product/test edits, staging or commits; diff whitespace check passed. Owned iPad27 ended shut down; other simulators untouched. Usage available at start (92% used); handoff current before further work.

## 2026-11-08 13:14 CST — iOS27 Form-action placement diagnostic (Codex heartbeat)

- Temporarily moved the unchanged Create action from confirmation toolbar into the name Form section. Existing focused Notes/XXXL test on iPad6528AE8B/iOS27 **failed1test,42.360s,exit65**, `/private/tmp/papernest-ios27-form-create.log`,240-second bound. Still fails waiting editor-text-box.
- Failure hierarchy `/private/tmp/pn-form-create-evidence/274C67A1-83BF-408B-8ADF-FBBE685F0011.txt` retains entered notebook-name with keyboard focus and Form notebook-create at x242,y388.5,w548,h93.5. Moving action out of toolbar did not resolve failure; no save-logic root cause established. Next useful isolation is keyboard input versus prefilled-name/no-keyboard creation, not repeated toolbar placement changes.
- Reverted diagnostic exactly with concurrent-change guard. No retained product/test edits, staging or commits. Fixed prior matrix heading placement. Owned simulator shut down; user's booted simulator untouched. Own claims released.

## 2026-11-08 12:21 CST — XXXL notebook creation compared through Notes (Codex heartbeat)

- Added `AppUITests.testLargeTextNotebookCreationFromNotes` using existing real Notes creation helper and a disposable UUID library. This bypasses nested Tools presentation while keeping accessibilityXXXL and identifier-based Create tap.
- iPad13/iOS27 (6528AE8B): **1 failed,43.363s,exit65**, `/private/tmp/papernest-ios27-notes-creation.log`,240-second bound. Failure waiting editor-text-box; exported hierarchy `/private/tmp/pn-notes-creation-evidence/7423C6A0-DAC3-478F-A923-548C18DF0AAF.txt` retains notebook-name with entered name, keyboard focus and notebook-create at x703.5,y170.5,w88.5,h36. Thus failure is not exclusive to nested Tools sheets. Cause remains unresolved; no save-logic defect inferred.
- Control iPad13/iOS26.5 (046CA563): **1 passed,18.525s,exit0**, `/private/tmp/papernest-ios265-notes-creation.log`,240-second bound. Same focused test successfully reaches editor.
- Retained test as reproducible regression; no speculative product edits. Next isolate iOS27 keyboard/toolbar event delivery using a non-toolbar action or no-keyboard creation comparison. No staging/commits; diff whitespace check passed. Both owned simulators ended shut down, user simulator untouched. Own claims released.

## 2026-11-08 11:14 CST — iOS27 Create visual-coordinate diagnostic (Codex heartbeat)

- Exported prior failure attachments to `/private/tmp/pn-create-recheck-evidence`; inspected 6BDDC612-FE73-4BF2-B4A0-9F7BBCDC1D48.png. Visible Create center is near normalized0.725,0.291 while AX reports a different vertical location. Ran one temporary test-only tap at that observed visual center. **Failed35.032s,exit65** waiting notebook toolbar; `/private/tmp/papernest-ios27-visual-tap.log`,180-second bound. No shape assertions reached.
- This rules out a simple successful workaround by tapping the prior visible location; it does not establish why event delivery/creation fails. Temporary hard-coded tap fully reverted to identifier-based tap. No retained source change, product fix, staging or commits. Further runtime/presentation investigation remains; docs claim released.

## 2026-11-08 10:12 CST — iOS27 notebook creation issue still reproduces (Codex heartbeat)

- Reran existing testLargeTextShapeSlidersAndSystemColorPicker after redesign on iPad6528AE8B/iOS27 at accessibilityXXXL. **Failed33.499s,exit65**, `/private/tmp/papernest-ios27-creation-recheck.log`,240-second bound. Failure remains AppUITests.swift:1302 waiting for notebook-tool-bar after tapping Create. Failure hierarchy still contains notebook-create at x703.5,y180.5,w88.5,h36; creation sheet remains open. Shape sliders/color checks were not reached.
- Confirms prior blocked route persists; does not establish an application-save defect or fix the previously observed AX/visual-coordinate discrepancy. No speculative product change. Further targeted creation geometry investigation required; prior iOS26.5 pass and iOS27 seeded-document signature pass cover different routes.
- No source edits/staging/commits. Own documentation claim released.

## 2026-11-08 09:12 CST — iOS27 French XXXL signature interaction (Codex heartbeat)

- Existing focused testFrenchSignatureAtLargestTextSize **1 passed,26.629s,exit0** on iPadPro13/iOS27 simulator6528AE8B. `/private/tmp/papernest-signature-fr-xxxl-ios27.log`,240-second bound. Verifies Signature navigation, reachable Cancel, disabled empty-signature placement inside viewport and dismissal at accessibilityXXXL.
- No source changes/staging/commits. This test seeds an existing document: it does NOT exercise or resolve the earlier iOS27 notebook-creation keyboard/AX geometry discrepancy. No new screenshot visual review, drawing/save-at-XXXL or spoken VoiceOver claim. Own documentation claim released.

## 2026-11-08 08:12 CST — Embedded signature accessibility header fixed (Codex heartbeat)

- Initial iPad French XXXL interaction test passed19.299s,exit0 (`/private/tmp/papernest-signature-fr-xxxl-ipad.log`), but screenshot exposed title split Si-gna-ture and Cancel split Annu-ler. Functional assertions alone missed the visual problem. Cause: title and Cancel shared a narrow HStack in the embedded inspector.
- SignatureSheet now stacks embedded title/Cancel at accessibility Dynamic Type sizes, preserving normal-size header and existing actions. Fixed iPad French XXXL test **passed17.339s,exit0**, `/private/tmp/papernest-signature-fr-xxxl-ipad-fixed.log`,240-second bound. Visually inspected `/private/tmp/pn-signature-xxxl-ipad-fixed/9F0BDFF7-601E-44B1-85C1-106E0EC37C9C.png`: full single-line Signature and Annuler, placement wraps below. Body remains scrollable and narrow; no full drawing-at-XXXL or VoiceOver claim.
- Mac app build **passed,exit0**, `/private/tmp/papernest-signature-header-mac.log`,180-second bound. iOS compiled through test. No native Mac interaction/full unit rerun/staging/commits. Own claims released.

## 2026-11-08 07:09 CST — French largest-text signature layout regression (Codex heartbeat)

- Added focused `EditorWorkspaceUITests.testFrenchSignatureAtLargestTextSize`, using a disposable real document and accessibilityXXXL. Opens Signature through native More, asserts reachable Cancel, disabled empty-signature placement fully within viewport, captures screenshot and dismisses. **1 passed,18.464s,exit0** on iPhone63992C10/iOS26.5; `/private/tmp/papernest-signature-fr-xxxl.log`,240-second bound.
- Visually inspected `/private/tmp/pn-signature-xxxl/04E720C5-DC7B-43D8-8A13-5325C297E1D9.png`: full Signature title; bottom Placer la signature wraps fully onto two lines; saved-signature content wraps at the requested large size. Drawing form is below the visible scroll region; this test does not claim drawing/saving at XXXL or spoken VoiceOver validation.
- Test-only addition, no product edits/staging/commits. Simulator runner ended shut down. Documentation/source claims released; remaining checks retain their prior status.

## 2026-11-08 06:09 CST — Spanish signature header dark verification (Codex heartbeat)

- Existing Spanish PDF workspace UI test **1 passed,51.395s,exit0**, iPhone63992C10/iOS26.5, `/private/tmp/papernest-signature-header-es-dark.log`,210-second bound. Inspected retained `/private/tmp/pn-signature-es-dark/B3F2EFA5-08CA-4D10-A02E-8DD80C3D5C8B.png`: dark sheet shows full Firma title, Cancelar and bottom Colocar firma label; body wraps without horizontal truncation at standard text size. Placement is correctly disabled in the empty-signature state.
- No source edits/staging/commits. This is localized layout/navigation validation, not a second full signature-placement or measured-contrast audit. XXXL and spoken VoiceOver remain pending. Own simulator restored light/shut down; user's simulator untouched. Docs claim released.

## 2026-11-08 05:06 CST — Bottom signature action lifecycle verified (Codex heartbeat)

- Existing AppUITests.testSavedSignaturePlacesAndSurvivesReopen **1 passed,65.018s,exit0**, iPhone17Pro/iOS26.5 simulator63992C10, `/private/tmp/papernest-signature-bottom-dark.log`,240-second bound. Dark appearance configured before launch and confirmed after completion. Exercises draw-before-name validation, keyboard-open naming/save, bottom action placement, history and relaunch/reuse following the signature header layout change.
- No source changes/staging/commits. English only; accessibility XXXL/localized layout follow-up, spoken VoiceOver and physical capture remain pending. Own simulator restored light/shut down; user simulator untouched. Documentation claim released.

## 2026-11-08 04:12 CST — French signature header crowding fixed (Codex heartbeat)

- Root cause: standalone compact sheet placed Cancel and long localized Place Signature in the same inline navigation bar as title. Existing retained French screenshot reproduced Signat... at standard size. Standalone iOS now places the unchanged placement action in a bottom safe-area inset; embedded inspector and macOS toolbar remain unchanged. Identifier, localization, disabled guards and placement logic preserved.
- Existing French PDF workspace UI regression **1 passed,50.969s,exit0**, `/private/tmp/papernest-signature-header-fr.log`,240-second bound,iPhone63992C10. iOS test build passed. Inspected retained `/private/tmp/pn-signature-header-fixed/3E8AC479-F437-4A74-9800-BFB201C301FB.png`: full Signature title and full placement label visible in light mode, body wraps. `git diff --check` passed.
- No new full signature placement lifecycle, dark/XXXL/iPad or Mac run for this layout-only change; follow-up verification remains. No staging/commits. Own claim released.

## 2026-11-08 03:07 CST — Retained dark editor screenshot review (Codex heartbeat)

- Exported retained attachments from `Test-PaperNest-iOS-2026.11.08_02-01-04--0600.xcresult` to `/private/tmp/pn-dark-editor-review`. Visually inspected Spanish initial PDF screenshot532D6BA7-32EE-4312-8455-155403B9E84F.png and French signature screenshot668D1F2B-4A06-4E0B-A2F8-F04C48D43962.png. Dark surfaces are confirmed in the actual app, beyond simulator configuration.
- **Open visual finding:** French signature navigation title truncates to `Signat...` at standard text size between Annuler and the long disabled Placer la signature action. Body text wraps within the sheet; this does not invalidate the earlier interaction pass. Next UI fix should relieve compact header crowding while preserving localized action/accessible labels. Spanish editor horizontal tools/palette show partial trailing items; reachability was covered by interaction tests, not a full visibility claim.
- No new tests or source edits. This is a two-screen visual review, not a measured contrast or complete accessibility audit. No staging/commits; docs claim released.

## 2026-11-08 02:05 CST — iPhone redesigned editor dark interactions (Codex heartbeat)

- Existing EditorWorkspaceUITests **4/4 passed,exit0**: English notebook49.446s; PDF English46.585s,French47.771s,Spanish47.555s. iPhone17Pro/iOS26.5 simulator63992C10, `/private/tmp/papernest-editor-dark-iphone.log`,300-second bound. Dark appearance configured before launch and confirmed during run. Thumbnail toggle, compact Text target, Pen settings and Signature/Pages routes exercised at standard Dynamic Type.
- No source edits/staging/commits. No visual contrast/spoken VoiceOver or physical-device claim. Own simulator restored light/shut down; user's iPhone untouched. This completes the existing editor workspace cases under dark system appearance on both iPhone and iPad. Documentation claim released.

## 2026-11-08 01:01 CST — iPhone scanner dark-appearance workflow (Codex heartbeat)

- Existing ScannerWorkspaceUITests.testReviewEditsSaveAndReopen **1 passed,44.913s,exit0**, iPhone17Pro/iOS26.5 simulator63992C10. `/private/tmp/papernest-scanner-dark-iphone.log`,240-second bound. Dark appearance set before launch and confirmed after completion. Synthetic review covers naming, zoom/pan, enhancement, rotation, crop/reset, duplicate/reorder/delete, destination save, automatic editor opening and relaunch/reopen.
- No source edits/staging/commits. English/standard Dynamic Type only; no physical camera, visual contrast or spoken VoiceOver claim. Own test simulator restored light/shut down; user iPhone414752ED untouched. Own documentation claim released.

## 2026-11-08 00:01 CST — iPad scanner dark-appearance workflow (Codex heartbeat)

- Existing ScannerWorkspaceUITests.testReviewEditsSaveAndReopen **1 passed,48.532s,exit0**, iPadPro13/iOS26.5 simulator046CA563. `/private/tmp/papernest-scanner-dark-ipad.log`,240-second bound. Dark appearance set before launch and confirmed after run. Synthetic two-page review exercises naming, zoom/pan, enhancement, rotation, crop/reset, duplicate/reorder/delete, save destination and automatic opening, then relaunch/reopen.
- No source changes/staging/commits. Standard English/text size; no camera hardware, spoken VoiceOver or visual contrast audit claimed. Own simulator restored light/shut down. Documentation claim released.

## 2026-11-07 23:05 CST — Redesigned iPad editor dark-appearance interactions (Codex heartbeat)

- Existing EditorWorkspaceUITests **4/4 passed,exit0** under dark simulator appearance: notebook English41.064s; PDF English38.336s,French37.521s,Spanish37.680s. iPadPro13/iOS26.5 simulator046CA563; `/private/tmp/papernest-redesign-dark-ipad.log`,300-second bound. Exercises thumbnail toggle, compact Text target, Pen settings, Signature and Pages routes. Standard Dynamic Type as configured by these tests.
- No source edits/staging/commits. Interaction evidence is not a contrast or spoken VoiceOver audit. Physical capture/Pencil, iOS27 geometry and further accessibility checks remain pending. Own simulator appearance restored light and shut down; user's iPhone untouched. Own documentation claim released.

## 2026-11-05 22:48 CST — Dark-appearance iPad XXXL interaction passed (Codex)

- Existing `testLargeTextShapeSlidersAndSystemColorPicker` **1 test passed,76.631s,exit0** on iPadPro13/iOS26.5 simulator046CA563. `/private/tmp/papernest-ipad-dark-large.log`,210-second bound. Simulator appearance set to dark before launch and queried as dark after completion. Exercises notebook creation, readable sidebar-width assertion, shape position/width, native custom color picker and saved markup at accessibility XXXL.
- This is an interaction pass under dark system appearance, not a visual contrast or spoken VoiceOver audit. No source edits, full unit/Mac rerun, staging or commits. Restored own test simulator to light and shut it down; user's iPhone untouched. iOS27 geometry discrepancy remains unresolved. Own docs claim released.

## 2026-11-05 21:55 CST — iPad French/Spanish stamp lifecycle passed (Codex)

- **2 tests passed,exit0:** French75.825s and Spanish71.097s on iPadPro13/iOS26.5 simulator046CA563. `/private/tmp/papernest-stamps-ipad-fr-es.log`,300-second bound,parallel testing disabled. Placement,cancel,undo/redo,relaunch/reopen assertions completed. Together with prior English pass, all three split stamp locale cases now verified on iPad as well as iPhone.
- No source edits, staging or commits; no full unit/Mac rerun. Native Mac/VoiceOver/physical stamp checks and separate iOS27 geometry investigation remain pending. Documentation claim released.

## 2026-11-05 20:53 CST — iPad English stamp lifecycle passed (Codex)

- Existing `testSymbolStampsEnglishLifecycle` **1 test passed,0 failures,77.307s,exit0** on iPadPro13/iOS26.5 simulator046CA563. `/private/tmp/papernest-stamps-ipad-en.log`,240-second bound,parallel testing disabled. Placement,cancel,undo/redo and relaunch/reopen assertions completed through current default-visible inspector.
- No source edits, staging or commits. Own simulator ended shut down; user iPhone414752ED untouched. French/Spanish iPad stamp cases remain pending, as do native Mac/VoiceOver/physical-device checks and the separate iOS27 geometry issue. No full unit or Mac rerun for this verification-only pass. Own documentation claim released.

## 2026-11-05 19:53 CST — Remaining stamp locales passed (Codex)

- **2 tests passed,exit0:** English lifecycle122.900s, French119.379s, iPhone414752ED. `/private/tmp/papernest-stamps-en-fr.log`,360-second bound,parallel testing disabled. Includes placement,cancel,undo/redo and relaunch/reopen assertions. Together with prior Spanish pass, all three split locale cases have completed successfully.
- No source changes, full unit/Mac reruns, staging or commits. iPad/native Mac/VoiceOver/physical stamp interactions not verified here. Own documentation claim released; handoff current.

## 2026-11-05 18:48 CST — Bounded stamp locale tests (Codex)

- Split the combined three-locale XCTest into `testSymbolStampsEnglishLifecycle`, `testSymbolStampsFrenchLifecycle`, `testSymbolStampsSpanishLifecycle`, all calling shared unchanged lifecycle assertions. Allows independent bounded verification after the earlier combined timeout.
- First Spanish command returned0 but **executed0tests**, `/private/tmp/papernest-stamps-spanish.log`; not counted as validation. Refreshed owned test-source mtime to trigger recompilation. Retry **passed1test,123.239s,exit0**, `/private/tmp/papernest-stamps-spanish-rebuild.log`,240-second bound,iPhone414752ED. Verified Spanish place/cancel/undo/redo/relaunch through existing test assertions.
- English/French wrappers compile but were not executed in this pass; run separately next. No product changes/full unit/Mac reruns/staging/commits. Own claims released.

## 2026-11-05 — Signature Save validation and default-visible PDF sidebar (Codex)

- Owner clarified **Save Signature greyed out on iPad** and requested the Mac/iPad right sidebar visible by default. Normal pre-fix iPad lifecycle passed79.941s,exit0 (`/tmp/papernest-signature-regression-ipad.log`), so normal lift did not reproduce the report. Source traced a matching state: visible live points were separate from saveable strokes and disabled Save until DragGesture.onEnded. Interrupted/cancelled capture could therefore leave visible named ink unavailable to Save. This is a reproduced state-path defect, not a claimed physical-device reproduction.
- Extracted existing capture state into SignatureDraft without changing its old validation, then added a real-store test omitting the release callback: **failed3 assertions,exit1** (`/tmp/papernest-signature-interrupted-red.log`): canSave false, save false, no persisted signature. Fix validates visible capture points too, flushes them once before saving, retains them as strokes on failed writes, and finalizes capture on GestureState reset (including cancellation). Late release is idempotent. Required-name guidance localized in en/fr/es. No subscription gate, schema, real-library or core placement changes.
- `./scripts/test.sh --filter 'SignatureWorkflowTests|LocalizationTests'` **9 passed,exit0**, `/tmp/papernest-signature-interrupted-green.log`: interrupted capture saves the exact visible ink, late callback does not duplicate it; original export/reopen/atomic undo, stale-page recovery and SQLite-lock retry tests pass; localization parity/usage/format tests pass.
- `./scripts/build-mac-app.sh` **passed,exit0**, `/tmp/papernest-signature-save-mac.log`. Native Mac final build/disposable `/tmp/papernest-signature-regression`: inspector visible on launch, existing signature loaded, New Signature → draw → missing-name hint/Save disabled → type name/Save enabled → save → placement preview → place (2 strokes from2 separate signatures). Earlier investigation also verified undo/redo and reopened placed ink. Owner authorized closing disposable test window; closed, user Xcode app untouched.
- iPhone17Pro/iOS26.5 signature lifecycle **passed70.210s,exit0**, `/tmp/papernest-signature-save-iphone.log`: draw before naming, missing-name hint and disabled Save, enter name with keyboard still open, Save enabled, save/place, undo/redo, relaunch/reuse. Initial combined iPad run: default-visible sidebar en/fr/es **passed142.051s**; signature test **failed27.605s** at the StaticText-only hint lookup before attempting Save (exit65), `/tmp/papernest-signature-save-ipad-final.log`. The isolated retry still failed at the hint lookup32.405s,exit65 (`/tmp/papernest-signature-save-ipad-retry.log`); its full AX tree showed the footer below the650-point sheet viewport, beyond the partially visible Save row. Moved the localized hint directly under Name. Final iPad signature lifecycle **passed67.822s,exit0**, `/tmp/papernest-signature-save-ipad-final2.log`, including hint/name validation, keyboard-open save, placement, undo/redo and relaunch/reuse. Final Mac rebuild also passed, `/tmp/papernest-signature-save-mac-final.log`. Final iPhone hint-layout lifecycle **passed65.850s,exit0**, `/tmp/papernest-signature-save-iphone-final.log`. `git diff --check` passed. Own test apps/simulators closed; user Xcode Mac process27980 and simulator414752ED untouched. Simulator builds passed; Xcode emitted its existing skipped-AppIntents-metadata warning, no Swift source errors. Physical iPad/Apple Pencil cancellation, app termination during capture, new VoiceOver/large-text sweep and full unit rerun are not verified. Only transient sheet state was moved; existing saved signatures and document objects stay in LibraryStore.

## 2026-11-05 17:51 CST — Stamp lifecycle verification timed out (Codex)

- Existing combined en/fr/es symbol-stamp lifecycle test **timed out at360seconds,exit124**, `/private/tmp/papernest-stamps-regression.log`, iPhone414752ED. It progressed through English/French and into Spanish; interruption occurred waiting for a markup row near elapsed338.74s of test time. No completed test pass claimed.
- No assertion failure logged before interruption. Follow-up: split/focus locale cases so each bounded run can complete, preserving placement/cancel/undo/redo/relaunch assertions. No product changes, staging or commits. No native Mac/VoiceOver/physical checks or full unit suite run. Own docs claim released.

## 2026-11-05 16:50 CST — iPad comment lifecycle passed (Codex)

- Existing combined three-locale comment lifecycle test **passed,exit0**, iPadPro13/iOS26.5 simulator046CA563, through updated inspector/reveal helper. Verified create/edit/cancel/delete, undo/redo and relaunch/reopen in English,French,Spanish. `/private/tmp/papernest-comments-ipad-retry.log`,360-second bound,parallel testing disabled.
- Previous runner connection failure did not recur; not a claim of diagnosing its cause. No source edits, full unit/Mac reruns, staging or commits. Native Mac comment/VoiceOver/physical-device checks not run. Own claim released.

## 2026-11-05 — Hideable PDF tools on Mac and iPad (Codex)

- DocumentView now uses a native trailing inspector for existing secondary PDF/editor actions on Mac and iPad. Sidebar toggle beside Text and a fixed close button; starts hidden, scrolls vertically, native compact iPad presentation. iPhone retains its More menu. Both presentations share the original actions and guards. No model/store/subscription changes. New labels localized in en/fr/es.
- Initial iPad regression **failed,exit65,28.991s**, `/tmp/papernest-pdf-sidebar-ipad.log`: the parent accessibility identifier replaced child identifiers, so the panel list could not be found. Native Mac inspection also caught the panel heading covered by the top tool inset. Removed the parent identifier and moved the inspector outside the editor insets.
- Corrected iPadPro13/iOS26.5 regression **passed,exit0,155.664s**, `/tmp/papernest-pdf-sidebar-ipad-final.log`. Creates a real notebook separately in en/fr/es; opens inspector, closes/reopens with both controls, opens/cancels Signature, opens/dismisses Pages, inserts a Shape and undoes it, closes inspector and verifies Pen remains reachable. Screenshots `screenshots/pdf-tools-sidebar-ipad-{en,fr,es}.png`; French screenshot inspected for wrapping and panel placement. Result `Test-PaperNest-iOS-2026.11.05_16-13-36--0600.xcresult` under the inline-text cache. These interactions preceded a final disabled-row opacity-only refinement.
- Native Mac disposable library `/tmp/papernest-pdf-sidebar-mac` seeded from synthetic Interactive Form.pdf: sidebar opening, both hide controls, reopening, scrolling, Fill PDF Form → cancel, Signature → cancel, Pages → Done **verified**. Corrected header/close control and page-width recovery inspected. Screenshot `screenshots/pdf-tools-sidebar-mac.png`. Test window closed; owner's separate Xcode app left untouched.
- Final `./scripts/build-mac-app.sh` **passed,exit0**, `/tmp/papernest-pdf-sidebar-mac-final2.log`, including disabled-row opacity refinement. `./scripts/test.sh --filter LocalizationTests` **5 passed,exit0**, `/tmp/papernest-pdf-sidebar-l10n.log`. `git diff --check` passed. Initial and corrected iOS Simulator test builds passed. Final `xcodebuild build -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination generic/platform=iOS\ Simulator -derivedDataPath <cache>/inline-text` **passed,exit0**, `/tmp/papernest-pdf-sidebar-ios-final-build.log`, including arm64/x86_64 Simulator compilation and the final opacity refinement. No compiler warnings/errors in final Mac/iOS logs.
- iPhone17Pro/iOS26.5 **passed,exit0,151.495s**, `/tmp/papernest-pdf-sidebar-iphone.log`: same en/fr/es Signature/Pages/Shape+Undo flow, asserting no inspector and retaining the native More menu. Both owned test simulators ended shut down; user simulator414752ED and Xcode Mac process11151 untouched.
- Not run: physical-device deployment, narrow iPad multitasking, VoiceOver spoken traversal, a new accessibility-size/dark-mode sweep, every individual PDF operation end-to-end, or full unit suite. Existing operations/persistence are reused; verified navigation is not a claim of new PDF capability. No staging or commits.

## 2026-11-05 — Hide iPad sidebar branding across destinations (Codex)

- Root cause: sidebarTitle hid PaperNest only while dashboardVisible and path empty. Switching to Notes, Documents, Favorites or a folder restored Brand.displayName. RootView now returns an empty sidebar title for all regular-width iOS destinations. Dashboard branding and detail destination titles remain; compact iPhone Home and native Mac behavior stay unchanged. No model/store/localization changes.
- New real UI regression reproduced **1 unwanted PaperNest heading in Notes vs expected0**, `/tmp/papernest-sidebar-brand-red.log`, exit65. That initial run subsequently ended with test-runner signal TERM, so later destinations were not verified in it. The next build succeeded but the test runner could not launch: **Mach error -308, server died**, `/tmp/papernest-sidebar-brand-ipad.log`, exit65. Booted only the own iPad simulator and waited for boot completion, then reran unchanged built tests.
- Final iPadPro13/iOS26.5 **2 tests passed,exit0,39.785s**, `/tmp/papernest-sidebar-brand-ipad-retry.log`: Notes → All Documents → Favorites → create/open Study UI folder → Home, asserting no sidebar brand in each destination and one dashboard brand on Home; existing one-Home/one-brand/Profile open-dismiss regression also passed. Screenshot `screenshots/ipad-sidebar-no-brand-folder.png` inspected: untitled sidebar, retained toggle/navigation, detail folder title intact.
- `./scripts/build-mac-app.sh` **passed,exit0**, `/tmp/papernest-sidebar-brand-mac.log`; iOS Simulator compilation passed. `git diff --check` passed. Own iPad simulator shut down; user simulator414752ED untouched. No physical-device install, new locale/VoiceOver audit, full unit rerun, staging or commits. CLEAN_NATIVE_DESIGN records the persistent sidebar rule.

## 2026-11-05 15:44 CST — iPad comments runner failure (Codex)

- Attempted existing en/fr/es comment lifecycle test on iPad26.5 simulator046CA563. **Command failed exit65**: `PaperNestUITests-Runner ... exited with code 0 before establishing connection`. No test case/assertions ran; this is not a comment feature failure or pass.
- `/private/tmp/papernest-comments-ipad.log`,360-second bound; result `Test-PaperNest-iOS-2026.11.05_15-41-30--0600.xcresult` in default DerivedData. Build completed before runner connection failure. iPad lifecycle remains pending, prior iPhone pass unchanged.
- No source changes, full unit/Mac reruns, staging or commits. Own documentation claim released.

## 2026-11-05 — One Home label on iPad; faithful design samples (Codex)

- Owner reported Home twice on iPad. RootView’s regular-width dashboard had a large Home navigation title in addition to the sidebar Home item. iOS detail dashboard now has an empty inline navigation title; sidebar selection, logo/greeting/Profile and search remain. Compact iPhone branch and Mac title are unchanged. No data or localization changes.
- Extended existing Home/brand/Profile UI regression: before fix **2 visible Home labels vs expected1**, `/tmp/papernest-home-title-red.log`, exit65,16.396s. Final iPadPro13/iOS26.5 **2 UI tests passed,exit0,34.150s**, `/tmp/papernest-home-title-ipad.log`: single Home/single brand with Profile open/dismiss (10.911s), and repeated Home/Favorites/Notes selected-state navigation. Screenshot `screenshots/home-single-title-ipad.png` visually inspected: redundant heading gone, original circular leaf logo retained.
- `./scripts/build-mac-app.sh` **passed,exit0**, `/tmp/papernest-home-title-mac.log`. iOS Simulator build passed as part of UI tests. `git diff --check` passed. Own test simulator ended shut down; user simulator414752ED untouched. Full unit suite, new locale/VoiceOver checks and physical-device deployment were not run for this presentation-only change. No commits/staging.
- Added owner’s persistent preview rule to CLEAN_NATIVE_DESIGN: reuse the exact project logo and existing components; change only requested elements. Compact editor header/page-strip concept remains a preview pending approval, not implementation.

## 2026-11-05 — Round precision eraser and real size controls (Codex)

- Owner requested round erasing, better reliability and sizes; confirmed **only the part rubbed over**. Precision is the default; optional Whole Strokes remains. Eraser opens anchored settings on a second tap/click with round preview, Small/Medium/Large, a continuous size slider and separate mode selection. Independent eraser preference does not change pen/highlighter width. Labels use L10n EN/FR/ES.
- Fixed Mac fast-crossing misses: the old endpoint-to-segment checks missed two long crossing segments when both sets of endpoints were outside the radius. `/tmp/papernest-eraser-red.log` executed34 Mac canvas tests with1 regression failure. New source-space capsule clipping catches crossings and splits strokes analytically, preserving pressure samples, color, tool and time. Guarded applyInkChanges reuses the first ID, orders new pieces beside it, and saves one reversible transaction; stale objects/pages are rejected. Text/images remain untouched. Circular Mac hover/drag outline matches the view-space footprint; partial erasure commits on mouse-up.
- Partial-geometry tests initially failed to compile because InkEraser did not exist (`/tmp/papernest-eraser-partial-red.log`). A later workflow test initially called a private helper (`/tmp/papernest-eraser-workflow.log`); corrected to observe history completion. Final focused43 tests passed (`/tmp/papernest-eraser-workflow2.log`). Full `./scripts/test.sh` **724 tests passed, exit0** (200+174+139+158+53), `/tmp/papernest-eraser-unit-final.log`. Covers circular vs square boundaries, sparse drags, size effects, styles/pressure, exact undo/redo/reopen, stale-write refusal, and localization parity.
- iOS precision uses native fixedWidthBitmap and reconciles masked paths into existing structured ink. Native testing caught unsupported requested widths (`/tmp/papernest-eraser-native-{tools,range}.log`, exit65): iOS26.5 precision range16.4...80.4; vector eraser range0...0. The size preference is now relative, mapped across the actual [PencilKit supported range](https://developer.apple.com/documentation/pencilkit/pkerasertool-swift.struct/erasertype-swift.enum/validwidthrange), with a percent accessibility value and actual round preview. Whole-stroke size controls are hidden on iOS because that native mode has a fixed footprint. Final **4 hosted PencilKit tests passed, exit0**, `/tmp/papernest-eraser-native-final.log`, iPhone26.5: distinct supported sizes/types plus existing native stroke-identity/pending-edit/geometry regressions.
- Mac app build passed `/tmp/papernest-eraser-mac-final.log`. Native disposable Mixed lasso fixture: each preset changed size; circle appeared at pointer; rubbing the middle split one stroke into2; direct SQLite comparison confirmed text/image unchanged and exact Undo restoration, Redo/reopen retained the cut. Screenshot `screenshots/eraser-partial-mac.png`. Additional user-like erasing was observed after reopening; paused further Mac input and asked whether to leave the disposable window open. Current Xcode/real library untouched.
- First iPad UI test failed tapping a size row's transparent middle (`/tmp/papernest-eraser-ipad-ui.log`, exit65), before the erasing assertions. Added full-row contentShape to size/mode buttons. Second iPad run reached erasing but left ink unchanged (`/tmp/papernest-eraser-ipad-ui2.log`, exit65): the test tapped the finger-drawing row center instead of its native switch. Test now targets the switch and asserts it is enabled. An intermediate test build failed because synchronous XCTest wait is unavailable in an async test (`/tmp/papernest-eraser-ipad-ui3.log`); corrected to awaited fulfillment.
- Subsequent UI4/diagnostic runs still failed: recording showed a save-error alert after the gesture; input coordinates were correct. A hosted shared-seed fragment regression reproduced missing reconciliation (5 tests,1 failed with3 assertions), `/tmp/papernest-eraser-split-red.log`. Coordinator now reconciles each seed family together with distinct stored fragment IDs. Final **5 hosted tests passed, exit0**, `/tmp/papernest-eraser-split-green.log`.
- Final **iPad UI test passed,47.273s,exit0**, `/tmp/papernest-eraser-ipad-family.log`: Small/Medium/Large selection, enabled finger input, real middle cut into2 pieces, unchanged text, exact single Undo/Redo and relaunch/reopen. Inspected `screenshots/eraser-controls-ipad.png` and `screenshots/eraser-partial-ipad.png`. **iPhone UI test passed,30.230s,exit0**, `/tmp/papernest-eraser-iphone-final.log`, same erase/Undo/Redo/reopen assertions. Inspected compact screenshot `screenshots/eraser-controls-iphone.png`.
- Full unit run preceded the hit-target-only adjustment. Final Mac source compile **passed, exit0**, `./scripts/swift.sh build --product PaperNestMac`, `/tmp/papernest-eraser-mac-checked.log`; the already-running test app bundle was not overwritten. Full unit run also preceded the iOS-only seed-family fix; that change is covered by the final5 hosted tests and both final device UI flows. Physical Pencil/palm rejection and new locale/VoiceOver runtime checks remain unrun; no claim of flawless behavior on every device.

- Final Mac delivery build **passed,exit0**, `./scripts/build-mac-app.sh`, `/tmp/papernest-eraser-mac-delivery.log`. After owner confirmed no use of the disposable window, closed it before rebuilding. Final native test on copied synthetic `Round eraser`:8/36/64 presets changed the accessible slider, Parts of Strokes default, visible circular pointer, middle rub created2 fragments with text unchanged; SQLite matched exact pre-cut payloads after Cmd-Z and post-cut payloads after Cmd-Shift-Z. Relaunch showed2 editable strokes and retained text. Screenshot `screenshots/eraser-partial-mac-final.png`. Closed the disposable app afterward; process exit verified. No real library touched. Own iPhone/iPad test simulators returned to shutdown; user simulator414752ED untouched. `git diff --check` passed. No staging or commits.

## 2026-11-05 14:54 CST — Comment lifecycle regression (Codex)

- Initial existing en/fr/es lifecycle test failed at Undo due duplicate menu and underlying editor toolbar accessibility identifiers; `/private/tmp/papernest-comments-regression.log`, exit65. Cell-scoped query still matched both in XCTest (`/private/tmp/papernest-comments-scoped.log`, exit65).
- Changed only this test's three history queries to enumerate matching buttons and select a hittable element, retaining all behavior assertions. **Final test passed,263.219s,exit0**, all three locales: create/edit/cancel/delete, undo/redo and relaunch/reopen. `/private/tmp/papernest-comments-hittable.log`,300-second bound,iPhone414752ED.
- No product changes, staging or commits. iOS test compilation passed; full unit/Mac suites not repeated for test-only selectors. No iPad/native Mac/VoiceOver pass claimed. Own documentation/test claim released.

## 2026-11-05 — Remove duplicate iPad Home branding (Codex)

- Root cause: regular-width iOS showed `Brand.displayName` in the sidebar navigation bar and again in the dashboard header. RootView now leaves the sidebar title empty while the dashboard is visible with no pushed document. Dashboard branding/Profile, native sidebar controls and destination titles remain. Compact iPhone and macOS title behavior are unchanged. No new strings or persistence changes.
- New isolated-library XCUITest reproduced **2 visible PaperNest labels instead of1**, `/tmp/papernest-home-brand-red.log`, exit65,14.901s. It also exercises opening/dismissing Profile. This is an executed UI regression, not a screenshot-only check.
- `./scripts/build-mac-app.sh` **passed, exit0**, `/tmp/papernest-home-brand-mac.log`; no compiler warnings. Final iPadPro13/iOS26.5 **2 UI tests passed, exit0**, `/tmp/papernest-home-brand-ipad.log`: single-brand/Profile10.395s and existing Home/Favorites/Notes selection/navigation26.137s. iOS Simulator build passed. Exported screenshot `screenshots/home-single-brand-ipad.png` visually confirms a single dashboard brand and retained Profile/sidebar controls. `git diff --check` passed. Own simulator returned to shutdown; user simulator untouched. No full unit rerun for this presentation-only change. No physical-device deployment or new locale/VoiceOver audit claimed.

## 2026-11-05 — Approved Notes toolbar option B (Codex)

- Owner chose option B from the concept preview after requesting a pause before implementation. Implemented original vector writing tools: purple ink detail on Pen, pink eraser end, yellow highlighter nib, dotted Lasso, simple Image/T/More. Shared 24-point icon grid, 44-point targets, quiet lavender selection/hover, and compact centered surface that scrolls at narrow widths. Existing tool order, anchored popovers, L10n labels, accessibility identifiers and action routing remain. Lower active-tool artwork matches the top row. Files: `Sources/PaperNestUI/NotebookToolIcon.swift`, `DocumentView.swift`, design/test/handoff docs. No model/store, localization or subscription changes.
- Earlier draft Mac build passed (`/tmp/papernest-icon-refinement-mac.log`); iOS run was deliberately interrupted when owner asked for the preview (`/tmp/papernest-icon-refinement-ios.log`, BUILD INTERRUPTED). Not a passing test. After approval, initial iPhone tool workflow passed55.384s, `/tmp/papernest-option-b-phone.log`.
- Native Mac inspection caught incomplete vector path joins and inaccessible Image/More menu labels in the first custom Canvas draft. Corrected explicit path starting vertices and accessible face labels. Final Mac build **passed, exit0**, `/tmp/papernest-option-b-mac-final.log`, no compiler warnings. Native disposable notebook: all seven toolbar controls present in AX; Pen selected and settings opened at its top anchor; Image menu shows Photos/Import; More exposes existing PDF/annotation/page actions. Final screenshot `screenshots/notes-option-b-mac.png`. Own test process closed; owner's Xcode app89306 untouched.
- Final iOS26.5 run on both devices **passed, exit0**: iPhone17Pro59.473s and iPadPro13 64.174s, `/tmp/papernest-option-b-final-devices.log`. The unchanged interaction test verifies icon-only ordering, anchored width/opacity/color controls, eraser selection, restored pen settings, Image options, inline text entry and More → Shape. Final iOS Simulator build passed; no compiler warnings. Extracted screenshots `screenshots/notes-option-b-iphone.png` and `notes-option-b-ipad.png` inspected: all seven icons fit, centered on iPad, with settings anchored below Pen.
- `git diff --check` passed. Full unit suite not repeated for this presentation-only change. Spoken VoiceOver, physical device input and a fresh en/fr/es/XXXL sweep are not claimed. Mac launch argument `-AppleInterfaceStyle Dark` did not change the observed light appearance, so this is not a dark-mode verification pass; existing adaptive theme tokens remain in use.


## 2026-11-05 — Lasso selects visible text and mixed objects (Codex)

- Owner narrowed the repeat report to Mac text boxes, alone or alongside ink/images. The previous full-frame containment required enclosing invisible margins (new text boxes default to240×90), so a loop around the actual letters omitted the entire object. Lasso now uses visible glyph centers from the same CoreText layout used to render text. A hit selects the whole editable text object. Empty whitespace does not count; font/alignment/wrapping/clipping follow the renderer and PageGeometry maps source coordinates. Existing image/whole-stroke selection, freehand contour, group move, data and option-B toolbar remain intact.
- Red regression: `/tmp/papernest-text-lasso-red2.log` executed8 geometry tests with5 issues: visible-text selection failed for all4 rotations, and the text was missing from a mixed group. An earlier compile attempt had the test-only `QuarterTurn`/`QuarterTurns` typo (`/tmp/papernest-text-lasso-red.log`), corrected before the executed red run. After implementation, `/tmp/papernest-text-lasso-green.log` passed12 geometry/workflow,5 rendering and3 export tests (including12 font-trait cases).
- Final `./scripts/test.sh` **passed, exit0,719 tests** (195+174+139+158+53), `/tmp/papernest-text-lasso-unit.log`. Added aligned/wrapped/whitespace glyph coverage; existing text raster/export and mixed move/history/reopen tests pass. `./scripts/build-mac-app.sh` **passed, exit0**, `/tmp/papernest-text-lasso-mac.log`; no compiler warnings. `git diff --check` passed.
- Native Mac, disposable `Mixed lasso` library: tight Rectangle enclosing the visible words but excluding the frame's bottom selected1 text object; a mixed rectangle excluding the text frame's right edge selected all3 kinds. Repeated the tight loop successfully. The first gesture immediately after changing shape returned0; a direct click and subsequent rectangle gestures worked, so no claim of a fully automated curved freehand mouse test. Group drag moved all3 by the same source delta; SQLite payloads exactly matched the before snapshot after Cmd-Z and the moved snapshot after Cmd-Shift-Z. Quit/reopen showed moved objects and Lasso active. Screenshot `screenshots/lasso-visible-text-mac.png`. Own app closed; owner's running Xcode app94985 and real library untouched.
- Updated real-store XCUITest fixture to use short `Hi` in a240×90 box. First selects visible text only; then selects all3 while leaving empty text-box margins outside, moves, checks exact shared displacement/Undo/Redo, clears, Select All and relaunches. Combined iPhone/iPad run `/tmp/papernest-text-lasso-devices.log` **exit65**: iPhone17Pro26.5 **passed50.464s**; iPad26.5 failed because XCTest timed out acquiring a background assertion for target app97648 (xcresult14-17-43), not a selection assertion. iOS Simulator compilation passed without compiler warnings. Isolated iPad `test-without-building` with parallel testing disabled **passed, exit0,1 test32.578s**, `/tmp/papernest-text-lasso-ipad-retry.log` (xcresult14-22-53). No source change between attempts. Both devices now have passing interaction coverage.
- Limits: freehand content hit testing is covered by geometry tests; native mouse interaction here uses Rectangle because CUA exposes only straight endpoint drags. No fresh physical-device/VoiceOver/locale sweep. No user-facing strings or persistence schema changed. The user's already-running Xcode binary must be rebuilt/relaunched to load the source fix; its current bundle was not overwritten.

## 2026-11-05 13:38 CST — Import regression after inline-editor changes (Codex)

- **3 existing UI tests passed, exit0**, iPhone17ProMax414752ED: destination creation/save/automatic opening, en/fr/es cancellation, text-clipping audit including SpanishXXXL. `/private/tmp/papernest-import-post-inline.log`, 240-second bound, parallel testing disabled, default DerivedData.
- Justified by intervening editor/navigation-guard changes; no product/test edits. iOS compilation passed. No full unit/Mac reruns, new iPad/physical/provider import or VoiceOver verification. No staging/commits; own claim released, other chat icon-design claim preserved.

## 2026-11-05 — Preserve the freehand lasso after mouse release (Codex)

- Owner confirmed the rectangle appears **only after release**. Root cause: `PageSelectionOverlay` kept points only during the drag, cleared them on release and unconditionally drew individual/group rectangles. Its movement hit region was also the group's bounding rectangle. The previous native Mac check used Rectangle mode and did not catch this freehand presentation defect.
- Freehand selections now retain their drawn contour in PageGeometry source coordinates relative to current selected bounds. The display and drag hit area use that contour; group movement, Undo/Redo and zoom keep it aligned. Rectangle, click selection and Select All retain rectangular bounds. Changing selection mode, clearing selection or changing page resets the contour. No persisted objects, subscription gates or localized strings changed.
- Regression coverage: a concave loop excludes a text box inside its overall rectangle but outside the loop; movement hit testing likewise excludes that area. Retained vertices follow group translation and return on Undo, including cropped/rotated page mapping at different zooms. Initial test compile failed because the new contour type was absent (`/tmp/papernest-freehand-red.log`); this is missing-API evidence, not an executed UI failure. After implementation, **10 geometry/mixed-history tests passed, exit0**, `/tmp/papernest-freehand-green.log`.
- `./scripts/build-mac-app.sh` **passed, exit0**, `/tmp/papernest-freehand-mac.log`; no compiler warnings. `git diff --check` passed. Owner's running Xcode Mac app was inspected read-only and left running; no real-library edit or replacement of its running bundle. Rebuild/relaunch that app to load these source changes.
- iPhone17Pro / iOS26.5 mixed-selection regression **passed, 1 UI test,28.969s,exit0**, `/tmp/papernest-freehand-ios.log`: Rectangle selects all three kinds, shared displacement commits, Undo/Redo match exact objects, Select All and default Lasso/reopen remain intact. iOS Simulator build passed without compiler warnings. Own simulator returned to shutdown.
- Limits: the retained freehand contour is covered by geometry tests and code integration, not a newly automated curved mouse-path UI test. Existing CUA drag supports straight endpoints. Physical trackpad/Pencil and spoken VoiceOver were not rerun; full suite not repeated for this focused visual/hit-region fix.

## 2026-11-05 — Mixed-content lasso and default notebook selection (Codex)

- Owner clarified that handwriting, text boxes and images must be selected together, with Lasso active when opening a notebook. Added shared freehand/rectangle selection and Select All on iPhone/iPad/Mac. Single click/tap selects an object; double-click/tap text opens native inline editing; single-object Edit also opens text/image controls. Existing PDF default mode is unchanged.
- Group movement preserves structured text styling, complete ink strokes and immutable image references. One guarded SQLite transaction and one history action; stale page geometry or changed objects reject the entire move. Source movement uses PageGeometry. Preview is transient transparent rendering, never flattened notebook storage. Whole-object bounds, three-view-point edge tolerance, crop/rotation/zoom and topmost hit tests have unit coverage.
- Initial full suite: **713 tests passed, exit0** (190+174+138+158+53), `/tmp/papernest-mixed-lasso-unit.log`. New store/model tests: mixed move/history/reopen and stale/invalid request refusal. Four selection renderer tests check transparent alpha, mixed layers, crop/rotation, omitted missing assets and scale validation.
- iPad Pro13 / iOS26.5: **2 UI tests passed, exit0,87.514s**, `/tmp/papernest-mixed-lasso-ipad.log`. Mixed workflow29.765s and inline placement/formatting/reopen57.749s. Test seeds real synthetic text/ink/image objects through LibraryStore, draws a rectangle, asserts three selected, drags, reads actual committed object coordinates, checks shared displacement and exact Undo/Redo, clears, Select All, relaunches and checks default Lasso and durable content.
- Read-only review caught two edge cases: clicking cropped objects could snap their position; a preview finishing after drag start could duplicate visible originals. Fixed by ignoring click jitter, bounding movement against crop plus original extents, and freezing a drag's preview while synchronizing original hiding with its captured IDs. Added clipped-object click/inward/outward regression. **8 focused geometry/workflow tests passed**, `/tmp/papernest-mixed-lasso-review-unit.log`.
- Final full suite after review fixes: **714 tests passed, exit0** (191+174+138+158+53), `/tmp/papernest-mixed-lasso-final-unit.log`; no compiler warnings. Read-only follow-up review confirms both edge cases resolved with no further important findings. `git diff --check` passed.
- Final iPhone17Pro / iOS26.5: **2 UI tests passed, exit0,69.954s**, `/tmp/papernest-mixed-lasso-phone.log`: mixed selection23.372s and inline placement/formatting/reopen46.582s. New controls use L10n EN/FR/ES; existing text objects remain accessible after default selection changes.
- Final iPad Pro13 / iOS26.5 after review fixes: **2 UI tests passed, exit0,90.350s**, `/tmp/papernest-mixed-lasso-ipad-final.log`: mixed selection32.293s and existing compact icon/pen/eraser/image/text controls58.057s. iOS Simulator compilation passed. iPhone selection screenshot `screenshots/lasso-mixed-selection-iphone.png` inspected: toolbar stays on page above the group, no clipped controls.
- Mac app build **passed**, `/tmp/papernest-mixed-lasso-mac-build.log`, no compiler warnings. Native disposable `Mixed lasso` notebook: selected Rectangle, enclosed all three objects, dragged the group, Cmd-Z/Cmd-Shift-Z, deselected on paper, double-clicked text into focused inline editor, quit/relaunched and confirmed Lasso default plus saved positions. SQLite payload comparisons matched exact pre-move and post-move states for Undo/Redo. Screenshot `screenshots/lasso-mixed-selection-mac.png`. Own Mac test process closed; no real library opened.
- Limits: selection covers editable annotations/inserted images, not the printed content of a flattened scan or original PDF. Partial-stroke selection, group resize/rotation, cross-page copy/paste and group deletion are not implemented by this change. Physical Apple Pencil and spoken VoiceOver not retested. If preview rendering is still loading at drag start, moving outlines provide feedback until commit; it never shows a stale/duplicated bitmap. No database migration, original modification, staging or commits.

## 2026-11-05 — Initial ink-lasso diagnosis (Codex; superseded by mixed selection above)

- Owner reports unreliable selection. Found PencilKit reloads unchanged drawings on SwiftUI refresh and also reloads stale metadata during a pending move, destroying native selection/preview. Added an iOS-hosted canvas test target/scheme in project.yml because the generated package scheme has no test action; initial attempt `/tmp/papernest-lasso-ios-red.log` correctly reported that scheme limitation. No generated project hand editing.
- iPad26.5 native PencilKit regression tests reproduced both failures: `/tmp/papernest-lasso-ios-red2.log`, three issues across two tests; external-edit/geometry reload control passed. After preserving unchanged/pending state and avoiding equal-tool reassignment, **3 tests passed, exit0**, `/tmp/papernest-lasso-ios-green.log`. Tests exercise actual PKCanvasView/PKDrawing identities and transformed ink, not a simulated selection state.
- Mac boundary regression reproduced asymmetrical missed strokes on the right/bottom edges: `/tmp/papernest-lasso-mac-red.log`. Inclusive edge checks passed with the existing suite: **30 tests, exit0**, `/tmp/papernest-lasso-mac-green.log`. Follow-up covers three-screen-point tolerance, self-crossing loops, zero-area gestures and click-to-select, independent of zoom. Final results below when complete.
- Full suite after the lasso changes: **702 tests passed, exit0**, `/tmp/papernest-lasso-final-unit.log` (183+174+134+158+53). Mac build passed, `/tmp/papernest-lasso-mac-build.log`. Native disposable notebook: click selected one stroke; drag moved it; Cmd-Z and Cmd-Shift-Z restored/reapplied its position with selection retained; quit/reopen preserved the new position. Screenshot `screenshots/lasso-selection-mac.png`; test app closed.
- First iPad lasso UI attempt failed to move the stroke, `/tmp/papernest-lasso-ipad-ui.log`, exit65. The helper used a single tap and immediate drag; [Apple’s Markup instructions](https://support.apple.com/en-vn/guide/ipad/ipad6350b8dc/ipados) specify selection and touch-and-hold before movement. Capturing intermediate screenshots and correcting that gesture before drawing conclusions about the product fix.
- Corrected native touch-and-hold UI flow passed on iPad26.5, 56.675s, `/tmp/papernest-lasso-ipad-ui3.log`. Owner then clarified mixed text/ink/image selection; shared mixed selection below supersedes this ink-only editor path. Native pending-drawing preservation remains relevant to pen/eraser updates. No partial-stroke selection claim.

## 2026-11-05 — PDF forms, reusable signatures and page workspace (Codex)

- Integrated Fill PDF Form, Signature and Pages in the existing More dropdown beside Text Box. New native sheets use existing LibraryStore, PageGeometry, exporter/importer, Pro gate and document history. Original assets remain immutable; no schema migration, staging, commits or real-library tests. File maps and capability limits: `superpowers/plans/2026-11-05-pdf-workspace.md` and `2026-11-05-inline-text.md`.
- Full unit suite passed twice: **693 tests, exit0** (174 UI +174 Store +134 Import/render +158 Export +53 Core), `/tmp/papernest-pdf-full.log` and `/tmp/papernest-pdf-full-final.log`. No Swift compiler warnings. Includes real AcroForm copy/reopen/original-byte preservation, unsupported/read-only/repeated field refusal, bounded malformed hierarchy, signature scaling and crop/rotation, SQLite-lock draft retry, atomic placement and duplicate-page history. Later conflict-recovery verification is recorded below.
- Focused core safety red/green: **30 passed, exit0**, `/tmp/papernest-form-signature-safety-green.log`. Red evidence `/tmp/papernest-form-signature-safety-red-executed.log` and `-flat-red-executed.log` caught incorrect signature widths/flat strokes, read-only checkbox flags and repeated-widget serialization. Interim CGPDFDictionaryRef pointer-identity approach failed on both SDKs; replaced with depth64/node4096 bounded traversal. `/tmp/papernest-pdf-workspace-phone1.log` failed compilation during that in-flight fix; no interaction pass claimed.
- iPhone26.5 phone2: signature capture/save/place/undo/redo/relaunch/reuse **passed64.433s**; fr/es inline keyboard/XXXL **passed67.051s** with stable page width. Overall exit65: page test attempted offscreen Delete; form test tapped the switch row rather than actual switch. Phone3 exposed duplicate Undo matching behind the sheet and confirmed the switch never changed before saving. Phone4 form flow **passed50.628s**, including text+checkbox+readonly value after save/reopen; overall exit65 from the page helper using the editor behind the sheet. Tests now target the sheet navigation bar and scroll its own actions. Logs `/tmp/papernest-pdf-workspace-phone{2,3,4}.log`.
- iPad Pro13 / iOS26.5: **5 UI tests passed, exit0,311.979s**, `/tmp/papernest-pdf-workspace-ipad1.log`: pen controls/icon toolbar70.757s; duplicate/reorder/rotate/delete/undo/extract74.476s; inline placement/immediate typing/Bold/reopen48.960s; filled PDF copy/reopen54.148s; reusable signature/placement/history/reopen63.637s. Screenshots `pdf-form-ipad.png`, `signature-ipad.png`, `inline-text-ipad.png` under screenshots. Simulator build passed as part of this run. Xcode emits its non-app warning about skipped AppIntents metadata; no source compiler warnings.
- Mac builds passed through final page-toolbar correction: `/tmp/papernest-pdf-mac-build7.log`, exit0. Native disposable `/tmp/papernest-pdf-workspace-ui`: form text/checkbox save and reopen; reusable signature capture, name, save, restart, placement sliders, rotated-page placement, Cmd-Z/Cmd-Shift-Z; page duplicate/restart, move-up, rotate, delete/undo, extract with source retained, duplicate undo/redo. Screenshots `pdf-form-mac.png`, `pdf-pages-mac.png`, `signature-mac.png`. User's Xcode-launched real app was untouched; own test processes closed.
- Mac failure and resolution: initial save committed valid output but replacing the Form with success content hung in AccessibilityViewGraph/AttributeGraph. Sample `/tmp/papernest-pdf-mac-sample.txt`, repeated diagnostic logs `/tmp/papernest-pdf-mac-runtime{,2,3,4}.log.gz`. Clearing focus alone and keeping the Save toolbar item alone failed. Retaining the field hierarchy and showing success within it passed; final runtime logs5–8 remained responsive. Mac menus changed to compact borderless buttons, and explicit HStack makes both Undo/Redo visible. Signature slider identifiers now survive parent grouping.
- Final XXXL screenshot inspection caught overlapping SF Symbols even though earlier interaction tests passed; bounded icon artwork fixed it. Final fr/es screenshots replaced by phone2 artifacts, `inline-text-keyboard-{fr,es-XXXL}.png`, visibly unclipped, paper/caret stable above keyboard. Accessible menu labels retain Dynamic Type.
- Final review found a two-window conflict could retain a draft but trap every guarded exit. Added explicit Save as New Text Box, Copy Draft Text and confirmed discard, plus a recovery banner when the page disappears. Four new session tests cover exact draft/style/IME preservation, independent undo/redo, failed copy on deleted page, and draining pending saves without replaying discarded edits. Focused **11 passed**, `/tmp/papernest-inline-recovery-tests.log`. Full first run failed only French punctuation-spacing validation in the new confirmation; corrected to narrow no-break space. Final full **697 tests passed, exit0**, `/tmp/papernest-final-unit-green.log` (178+174+134+158+53). Final Mac build **passed exit0**, `/tmp/papernest-final-mac-build.log`. No source compiler warnings. Recovery UI runtime results are recorded below.
- Final iPhone page workflow **passed67.466s** and basic inline reopening **passed41.386s**, `/tmp/papernest-pdf-workspace-phone-final.log`; overall exit65 because the new recovery controls overlapped the main toolbar. The first safe-area inset correction hid contextual controls after keyboard appearance (double-counted layout insets); diagnostic runs retained this failure rather than counting it as a pass. Final correction/results follow below. Native Mac final typed text with Bold persisted after app quit/relaunch in `/tmp/papernest-inline-mac-library`; own app closed.
- Viewport regression corrected: replaced the zero-valued page preference with direct global-frame geometry observation and translated the actual content viewport into page coordinates. Diagnostic3 captured viewport402×267 with already-applied top188/bottom419 ancestor insets, proving double subtraction was wrong; all temporary diagnostics removed. Final iPhone **2 tests passed, exit0,114.329s**, `/tmp/papernest-inline-viewport-fixed-phone.log`: fr/es XXXL69.347s; real SQLite conflicting edit → retain draft → save independent text box → reopen44.981s. The recovery button is asserted below the main toolbar. Additional red/green layout regression covers selection scrolled beyond either viewport edge. Full **698 unit tests passed, exit0**, `/tmp/papernest-final-unit-698.log` (179+174+134+158+53). Mac build4 passed exit0, `/tmp/papernest-final-mac-build4.log`.
- Final iPad viewport/recovery regressions **2 passed, exit0**: conflict recovery55.724s and inline creation/format/reopen49.648s, `/tmp/papernest-inline-viewport-fixed-ipad.log`. Final iPhone after reserving space for the resize handle **3 passed, exit0**: fr/es XXXL64.190s, conflict recovery44.864s, handles/movement/resize/outside-save40.381s, `/tmp/papernest-inline-final-phone.log`. Focused layout/session suite **12 passed**, `/tmp/papernest-inline-layout-final-tests.log`; Mac build5 passed. Native Mac selected the saved box, inspected controls above it, focused inline editor, typed and saved again; owner-approved test-window close completed.
- Limits: this implements text and checkbox AcroForms, not radio/choice/XFA/repeated-name fields; visual handwritten signatures, not certificate signing. Rendered/edited PDF exports do not retain interactive fields. Old incorrectly normalized saved signature widths cannot be inferred/repaired. No full Goodnotes/Acrobat parity claim. Spoken VoiceOver, physical-device interaction, every new-sheet locale/dark-mode combination, native IME input and forced OS termination remain unverified.

## 2026-11-05 — Inline text editing and PDF tools (Codex)

- Replaced text-entry sheet routes with native on-page UITextView/NSTextView editing; tap placement focuses the caret. Contextual font/size/color/bold/italic/alignment/delete and overflow controls, dedicated move/resize handles, serialized autosave, guarded navigation/window close/quit and existing document undo/redo. Additive default-decoded font traits preserve legacy TextBox JSON; selected text excluded from backing renders; PageGeometry supplies coordinate mapping. More now sits directly beside Text Box on all platforms and reuses existing PDF actions. No migration, staging, commits or real-library mutation.
- Full `./scripts/test.sh`: **671 tests passed, exit 0** (168 UI + 168 Store + 134 Import/render + 151 Export + 50 Core), `/tmp/papernest-inline-full-final.log`. Includes seven session tests for concurrent flushes, terminal/delete coordination, native composition commit, empty-text backgrounding, conflict retention/retry; style/export tests exercise all 12 font/trait combinations. No compiler warnings. Subsequent view-only alignment/visibility adjustments are covered by final builds below.
- iPhone 17 Pro / iOS 26.5 basic inline flow: **1 UI test passed, 44.475 seconds, exit 0**, `/tmp/papernest-inline-phone4.log`. iPad Pro 13 / iOS 26.5 same flow: **1 passed, 56.569 seconds, exit 0**, `/tmp/papernest-inline-ipad1.log`. Both verify creation, immediate keyboard/typing, Bold with caret retained, Done, reselect and relaunch/reopen. UUID disposable libraries only.
- Native Mac disposable `/tmp/papernest-inline-mac-library`: placed and immediately typed text, continued typing after Bold, quit while editing and reopened retained text; selected existing text, chose Serif/24pt/italic/center/blue, moved/resized via separate handles, outside-click deselected, and Undo/Redo visibly restored/reapplied box dimensions. More beside Text Box opened existing Crop sheet; canceled without modifying page. `docs/screenshots/inline-text-more-mac.png`. Alignment preview was corrected and inspected before the later PDF workspace verification.
- Investigation record: initial red test correctly failed because old text sheet opened (`/tmp/papernest-inline-red.log`). Phone1/2 failed before text placement due repeated DocumentView/command-context updates; stabilized focused command context in state. Phone3 then reached typing/Bold but failed Done lookup because parent accessibility identifier replaced child identifier; explicit containment fixed it. Logs `/tmp/papernest-inline-phone{1,2,3}.log`. Initial Mac forwarding implementation failed Swift 6 Sendable checking, then corrected; builds 1/2/3/5 and final builds passed. Diagnostic logging removed. These failures are not counted as passes.
- Expanded iPhone formatting/history/More → Crop **passed, 133.424s**, and handle movement/resize/outside deselection **passed, 36.902s**, `/tmp/papernest-inline-expanded-phone.log`. Combined command exit65 because its locale helper initially scrolled the wrong direction. Second locale attempt revealed keyboard-driven page shrinking; session now captures page scale at placement/selection, independent of keyboard layout. Third attempt passed French but stopped at the Spanish XXXL navigation menu; added a Notes accessibility identifier to the existing large-text menu and taught the test to open it. Final **fr/es XXXL UI test passed, 70.762s, exit0**, `/tmp/papernest-inline-locales-phone4.log`, including unchanged page width after keyboard appearance. Screenshots `screenshots/inline-text-keyboard-{fr,es-XXXL}.png`.
- Native Mac window close while editing also preserved text after reopening. Font/size/bold/italic/center/color and dimensions survived reopening; preview alignment corrected and inspected. Final Mac build3 passed (`/tmp/papernest-inline-mac-build-final3.log`); subsequent session scale fix also compiled in the PDF workspace Mac builds above.
- Remaining limits: spoken VoiceOver, physical-device testing, native IME keyboard composition and forced OS termination have not been verified. Formatting remains uniform per text box, matching the existing model; it does not introduce rich-text runs.

## 2026-11-05 06:33 CST — Icon toolbar XXXL regression (Codex)

- After the other chat's icon-only Notes toolbar change, reran existing `testLargeTextShapeSlidersAndSystemColorPicker` on iPad26.5 simulator046CA563. **Passed, 1 test, 79.632 seconds, exit0**, 240-second bound; `/private/tmp/papernest-icons-large-regression.log`.
- Covers XXXL notebook creation, sidebar width, More → Shape, position slider/width change, native custom color selection, save and More → Manage Markup saved row. This verifies that the changed toolbar preserves this previously tested large-text workflow.
- No source changes, full unit/Mac reruns, staging or commits. Spoken VoiceOver, new icon-row clipping audit, physical-device interaction and iOS27 AX mismatch remain unverified here. Own documentation claim released.

## 2026-11-05 — Icon-only Notes toolbar (Codex)

- Shared iPhone/iPad/Mac notebook toolbar: slanted pencil, Eraser beside Pen, direct Image and Text Box, icon-only primary row with localized accessibility labels/tooltips and 44-point targets. Secondary tools remain in More. Pen settings now anchor to the top tool, also when invoked from the bottom palette. Existing text entry/size/alignment/color sheet and image import paths reused; NotebookToolbar crash-prevention boundary preserved. No model, storage, subscription or localization key changes.
- Test-first iPhone run failed at the intended missing Image assertion (`/tmp/papernest-icon-tools-red.log`). After implementation, iPhone focused UI test passed (1 test, 50.421 seconds, exit0), including popover position, width/opacity preservation, Eraser, Image options, Text Box controls/save and More → Shape (`/tmp/papernest-icon-tools-phone.log`). Screenshot `screenshots/notes-icon-tools-iphone.png` inspected.
- Initial iPad26.5 run failed at Opacity after test scrolled the last collection view (sidebar), dismissing the popover; screenshot confirms correct top anchor. Corrected test to find the Form containing the width slider and keep its frame for scrolling. `/tmp/papernest-icon-tools-ipad.log`, exit65. Final iPad26.5 rerun **passed**, 1 test, 56.906 seconds, exit0 (`/tmp/papernest-icon-tools-ipad-final.log`), including all insertion and More-menu checks. Screenshot `screenshots/notes-icon-tools-ipad.png`; own test simulators returned to shutdown.
- `./scripts/test.sh`: **657 tests passed**, exit0 (159 + 167 + 133 + 150 + 48); `/tmp/papernest-icon-tools-unit.log`. `./scripts/build-mac-app.sh`: **passed**, exit0; `/tmp/papernest-icon-tools-mac.log`. Signed generic iOS device build: **passed**, exit0; `/tmp/papernest-icon-tools-device.log`. No compiler warnings in these logs. Device app update installed on paired iPad00008112 without uninstall, exit0 (`/tmp/papernest-icon-tools-install.log`). Hardware interaction not rerun.
- Native Mac with disposable `/tmp/papernest-pen-controls-mac-library`: selected Pen and opened anchored panel, inspected width/color/opacity, opened Image options, entered Text Box, saved and observed editable movable mark. Screenshot `screenshots/notes-icon-tools-mac.png`. Own Mac process stopped. No real library used, staging or commits.
- Limits: image import option navigation checked, actual image selection not repeated for this placement change; no new spoken VoiceOver or French/Spanish runtime sweep. Existing localized labels retained and localization unit checks passed. Prior iOS27 simulator keyboard/AX discrepancy remains separate.

## 2026-11-05 05:31 CST — iPad26.5 large-text workflow passed (Codex)

- Changed only the existing test slider destination from normalized0.15 to0.85 (initial displayed value25%), keeping the changed-value assertion. This gives XCTest a larger movement; no product code or assertion bypass.
- **1 UI test passed, exit0**, 83.309 seconds, 240-second bound: XXXL notebook creation, sidebar width, Shape → Position slider change, width selection, system custom color change, save dismissal, More → Manage Markup and saved row. iPad Pro13 simulator046CA563, iOS26.5. Log `/private/tmp/papernest-ipad-slider-far.log`.
- Does not prove why the smaller requested motion previously produced no change, and does not resolve iOS27 creation/AX geometry failure. iOS test compilation passed; full unit/Mac suites not repeated for one test-target value. No physical device/VoiceOver claims, staging or commits. Own claims released.

## 2026-11-05 04:31 CST — iPad runtime comparison (Codex)

- Ran unchanged XXXL shape test on iPad Pro13 simulator046CA563, **iOS26.5**, instead of prior iOS27 simulator. Creation, notebook toolbar, sidebar-width assertion, More → Shape and Position controls succeeded. This narrows the prior creation failure, but different simulator state prevents attributing it solely to OS version.
- Overall **failed exit65**, 40.181-second test, 240-second bound: slider remained `25%` after XCTest requested normalized0.15 at AppUITests.swift:1327. Color picker/save assertions were not reached. Log `/private/tmp/papernest-ipad-large-265.log`. Needs separate slider hit/automation diagnosis; no assertion bypass or product changes made.
- Restored initially shutdown simulator046CA563 to shutdown. User's iPhone simulator untouched. No source changes, full unit/Mac builds, staging or commits; own claims released. iOS27 keyboard/AX mismatch remains unresolved.

## 2026-11-05 03:31 CST — Create action not reached (Codex)

- Temporarily instrumented Create with a synchronous tap counter. Isolated test failed exit65 (`/private/tmp/papernest-ipad-create-counter.log`); post-tap AX value remained `diagnostic-taps-0`, showing the action was never entered. Removed all counter instrumentation after the run.
- Added and inspected pre-tap screenshot: `/private/tmp/pn-create-shot/18A266DA-288A-4BB2-A229-02C2969DBCEB.png`. Visible Create center is around (748,400) points on the 1032×1376-point iPad; AX reports button rect (703.5,180.5,88.5,36). Screenshot shows compact keyboard bar while AX describes a full keyboard. This identifies a geometry disagreement, not a storage/save failure. Its underlying cause remains unconfirmed.
- Retained screenshot attachment in the test for future failures; no product code changes retained. Next isolate simulator keyboard/AX geometry before changing app behavior. Native/physical reproduction, picker checks and full suites not run; no staging/commits. Own claims released.

## 2026-11-05 02:28 CST — iPad Create hit-test experiment (Codex)

- Replaced the failing XXXL test's Create tap temporarily with an explicit element-center coordinate tap. Isolated rerun **failed exit 65**, same absent toolbar assertion; hierarchy again showed enabled Create, populated name and creation sheet still open. `/private/tmp/papernest-ipad-create-center.log`, 240-second bound.
- Reverted the experiment; no retained source change in this pass. Keyboard dismissal and explicit-center tapping have both failed to resolve the behavior. Next diagnostic should capture the pre-tap screen and instrument entry/completion of the save action to distinguish hit routing from save/presentation behavior. No claim of backend failure or app crash.
- No product changes, full unit/Mac reruns, staging or commits. Own claims released; iPad XXXL shape/custom-picker check remains incomplete.

## 2026-11-05 01:34 CST — iPad XXXL creation diagnosis (Codex)

- Isolated large-text test reproduced failure after Create, exit 65 (`/private/tmp/papernest-ipad-large-isolated.log`). Previous xcresult exported no failure attachments. Added `app.debugDescription` to the failed toolbar assertion for actionable evidence.
- AX hierarchy confirms New Notebook sheet remains open, entered name present, Create enabled, no editor toolbar. This is not evidence of a process crash. A test-only keyboard-dismiss experiment also failed at the same assertion (`/private/tmp/papernest-ipad-large-keyboard.log`) and was reverted. Only diagnostic assertion text retained.
- Root cause remains unresolved: investigate toolbar hit/action at XXXL. Shape picker and menu verification not reached. No product changes, commits/staging or full unit/Mac reruns; own claims released. Both runs bounded at 240 seconds.

## 2026-11-05 00:30 CST — iPad annotation verification (Codex)

- Combined focused run on iPad simulator 6528AE8B, 300-second bound, default DerivedData, parallel testing disabled: **overall failed exit 65**, `/private/tmp/papernest-ipad-annotations-0027.log`.
- `testShapeSaveFailureKeepsDraftAndCanRetry` **passed** (85.989 seconds): database lock triggered expected error, selection retained, rollback/retry saved exactly one markup row. Exercises updated menu helper at standard text size.
- `testLargeTextShapeSlidersAndSystemColorPicker` **failed** (37.202 seconds), AppUITests.swift:1284: notebook toolbar absent after tapping Create at accessibility XXXL. It did not reach the shape/menu helper or custom color picker. Root cause not established; inspect creation screenshot/hierarchy next. Do not treat this as proof of a menu scrolling regression or a crash.
- No source edits, full unit/Mac builds, physical-device checks, staging or commits. iOS compilation succeeded. Native Mac/VoiceOver and iPad XXXL picker verification remain pending. Own documentation claim released.

## 2026-11-04 23:30 CST — Large-text More menu test repaired (Codex)

- Failure hierarchy from the previous xcresult showed More open, a five-page vertical menu at 0%, and only early entries materialized. Manage Markup is present in product menu code but below those entries at XXXL. Updated only AppUITests.swift `revealEditorTool` to await the native menu, wait for the requested action and scroll the menu when absent.
- Initial immediate-scroll attempt failed at the first Shape lookup (`/private/tmp/papernest-menu-scroll-2325.log`, exit 65): checking hittability before menu presentation settled caused premature scrolling. Added explicit menu/target existence waits.
- Final existing `testLargeTextShapeSlidersAndSystemColorPicker` **passed, 1 test, exit 0**, iPhone 414752ED, 70.979 seconds, 240-second bound. `/private/tmp/papernest-menu-scroll-final.log`. Verified slider, width, native custom color change, save dismissal, scrolling to Manage Markup and saved row. This resolves the prior test navigation failure without a product change.
- No full unit/Mac builds for this test-helper-only change; iOS test compilation passed. Broader helper callers, iPad, spoken VoiceOver and native Mac were not rerun. No staging/commits. Own claims released.

## 2026-11-04 22:24 CST — Large-text shape/picker verification failure (Codex)

- Existing `testLargeTextShapeSlidersAndSystemColorPicker` **failed, exit 65**, iPhone simulator 414752ED at accessibility XXXL. Log `/private/tmp/papernest-large-shapes-2222.log`; result `Test-PaperNest-iOS-2026.11.04_22-21-26--0600.xcresult` in default DerivedData Logs/Test. Bounded 240 seconds, actual test 64.822 seconds.
- Earlier assertions completed: shape position slider changed, 4-point width selected, native custom color picker opened, azure color selected, changed color value observed, Save enabled and sheet dismissed after save. Final `editor-manage-markup` button lookup failed at AppUITests.swift:1367 after the reveal helper. Saved-row assertion was not reached. Do not call the full workflow passed or infer data loss from a missing navigation element.
- Follow-up: inspect failure accessibility hierarchy and compact More-menu routing at XXXL after sheet dismissal; determine product versus test-selector issue. No source/test edits, full unit/Mac builds, staging or commits. Native Mac/system-picker and spoken VoiceOver checks remain unrun here. Own documentation claim released.

## 2026-11-04 — Compact Notes toolbar and Pen controls (Codex)

- Shared notebook toolbar now has Pen, Eraser, Highlighter, Lasso and More. Existing shapes/text/images, editing, annotations, OCR and page actions retain their workflows under More. Fine Pen/Highlighter width, presets, stroke preview, custom color and opacity use the existing drawing engines; separate widths survive tool switches within the editor. Color changes preserve opacity and selected swatches ignore opacity for hue matching. Eraser retains whole-stroke behavior. New strings are in en/fr/es; no model/schema/persistence/subscription changes.
- Test-first simulator run `/tmp/papernest-pen-controls-red-sim.log` failed at the intended Pen/Eraser ordering assertion. Earlier physical attempts `red.log` and `red2.log` failed during notebook creation interactions, before the target assertions; no physical-device pass is claimed for this change.
- First green attempt failed to compile a test-only `lastMatch` query; corrected. Subsequent iPad test exposed scrolling against an offscreen popover (`green2.log`). Native Mac screenshot also showed the panel anchored incorrectly to the entire palette. Moved presentation to the settings button, with Done inside the panel and a scrollable Form; kept the NotebookToolbar evaluation boundary. Improved width presets to a compact row with a vertical Dynamic Type fallback.
- Intermediate iPhone interaction test passed, 1 test, exit 0 (`/tmp/papernest-pen-controls-phone.log`): adjacent Eraser, hidden secondary tools, width/opacity adjustment, opacity retained through color change, tool switching, width retained, More → Shape. This preceded the final popover anchoring correction.
- `./scripts/test.sh`: **657 tests passed, exit 0**, including localization (`/tmp/papernest-pen-controls-unit.log`, repeated in `unit-final.log`). Repeat predates only final presentation-anchor/header correction. Final Mac build passed (`/tmp/papernest-pen-controls-mac-final2.log`), no Swift compiler warnings. Native Mac disposable library verified compact row, repeated-Pen settings, width preset, opacity, color preservation, Eraser and More → Shape. Final corrected popover visually inspected fully inside the window, Done within the panel; width preset changed from 2.0 to 4.0 points.
- Overlapping intermediate simulator runs `ipad-final.log` and `phone-final.log` were canceled while superseded by the anchor correction; Xcode produced interruption/abort diagnostics. These are not passes. Final runs are serial; outcomes recorded below when complete.
- Final iPad new-controls test **passed** in `/tmp/papernest-pen-controls-ipad-verified.log`; inspected `screenshots/notes-pen-controls-ipad.png` and `screenshots/notes-pen-opacity-ipad.png`. The paired existing drawing test initially failed because its finger toggle was below the visible Form; updated it to scroll to the control. Final drawing → save → relaunch → reopen rerun **passed, 1 test, exit 0**, `/tmp/papernest-pen-controls-drawing-verified.log`.
- Final `./scripts/test.sh`: **657 passed, exit 0**, `/tmp/papernest-pen-controls-unit-verified.log`. Final signed iOS device build **passed**, `/tmp/papernest-pen-controls-device-build.log`; installation to connected iPad **succeeded**, `/tmp/papernest-pen-controls-device-install.log`. Installed without uninstalling or touching the real library. `git diff --check` passed.
- Final iPhone control test **passed, 1 test, exit 0**, `/tmp/papernest-pen-controls-phone-verified.log`. Final iPhone and iPad control tests verify Eraser order, secondary actions under More, width/opacity changes, color preserving opacity, switching tools retaining width and More → Shape. Screenshot `screenshots/notes-pen-controls-iphone.png`. New en/fr/es runtime and Dynamic Type/VoiceOver audits were not completed in this slice; translated strings passed localization tests. Spoken VoiceOver, Apple Pencil hardware and final physical-device interaction remain unverified. Native Mac checks used `/tmp/papernest-pen-controls-mac-library`; simulator/device tests use disposable libraries. User content untouched.

## 2026-11-04 21:24 CST — Injected shape save-failure UI (Codex)

- **1 existing XCUITest passed, exit 0:** `testShapeSaveFailureKeepsDraftAndCanRetry`, iPhone 17 Pro Max simulator 414752ED. Created a disposable notebook, selected ellipse, held a SQLite `BEGIN IMMEDIATE` lock, attempted save, verified the expected error alert and retained ellipse selection, released the lock, retried and verified exactly one markup row.
- Log `/private/tmp/papernest-shape-failure-2122.log`; xcresult `Test-PaperNest-iOS-2026.11.04_21-22-02--0600.xcresult` under default DerivedData Logs/Test, including failure-alert screenshot attachment. Direct xcodebuild test with parallel testing disabled, 180-second bound. iOS compilation succeeded; test duration 35.844 seconds.
- No product/test edits, staging or commits. No full unit/Mac build reruns. This verifies the simulated database-contention failure path on iPhone, not all filesystem failures, native Mac failure UI, spoken VoiceOver or physical-device behavior. Own documentation claim released.

## 2026-11-04 — Physical iPad sidebar focus correction (Codex)

- Owner confirms Full Keyboard Access is off. Earlier settings attribution below is retracted. Temporary public-UIKit diagnostic captured the focused SwiftUI List collection cell with `UIFocusHaloEffect`; log `/tmp/papernest-sidebar-focus-tree.txt`. Diagnostic removed from production source after investigation.
- List-level `.focusEffectDisabled(!showsHome)` also left the rectangle unchanged; removed. Its physical UI test passed but visual check failed: `/tmp/papernest-sidebar-list-focus.log`. Diagnostic build/test passed: `/tmp/papernest-sidebar-focus-tree.log`.
- Fix: remove custom iPad `listRowBackground` capsule and foreground/item-tint overrides, allowing native List selection and focus to render together. Explicit navigation actions, native selection tags, compact iPhone behavior and Mac rendering retained. No accessibility settings or user-library changes.
- Final signed physical iPad build and `testHomeSidebarSelectionFollowsNavigation`: **passed, 1 test, 0 failures, exit 0**; `/tmp/papernest-sidebar-native-focus.log`. Repeated Favorites → Home, Notes → Home transitions and native selected-state assertions passed. Inspected both Home and Notes screenshots: one rounded blue selection, no outer rectangular outline. Artifacts: `screenshots/sidebar-ipad-home-native-focus.png`, `screenshots/sidebar-ipad-notes-native-focus.png`. xcresult `notebook-device/Logs/Test/Test-PaperNest-iOS-2026.11.04_20-40-06--0600.xcresult`. UUID sandbox temporary library only; test app terminated.
- `./scripts/build-mac-app.sh` and `./scripts/build-ios-sim-app.sh`: **passed, exit 0**, logs `/tmp/papernest-sidebar-native-focus-{mac,sim}.log`. No Swift compiler warnings; Simulator command emitted the existing placeholder operatingSystemVersion diagnostic. `git diff --check` passed. Full unit suite, new locale/Dynamic Type/VoiceOver, Mac interaction and hardware-keyboard interaction tests not rerun for this styling-only correction.

## 2026-11-04 — Home/Notes outer square focus-outline investigation (Codex)

- Physical iPad selection screenshots reproduce a thin blue rectangle outside the app’s existing blue capsule. Navigation and selected-state assertions passed before styling changes. Artifact `screenshots/sidebar-ipad-system-focus-outline.png`; log `/tmp/papernest-sidebar-square-before.log`, exit 0, 1 UI test. Mac isolated test app Home/Notes retained native rounded row selection; no extra app-drawn square found.
- Tested `.contentShape(.accessibility, Capsule())` and `.focusEffectDisabled()` independently on the actual iPad. Both physical interaction runs passed, but screenshots showed the same outer rectangle: **neither solved the appearance issue**, both removed. Logs `/tmp/papernest-sidebar-square-{rounded,focus}.log`, exit 0 each. Initial inference, since disproved by owner confirmation and runtime inspection: the outline was attributed to Full Keyboard Access. Apple's [Full Keyboard Access guide](https://support.apple.com/en-gb/guide/ipad/ipad5f765d6f/ipados) documents system-controlled focus appearance. No system accessibility preferences changed; no claim of a programmatically confirmed enabled setting.
- Two exploratory compilation failures: `.focusEffect` ContentShapeKinds is unavailable on iOS (`/tmp/papernest-sidebar-square-after.log`); `UIAccessibility.isFullKeyboardAccessEnabled` is not a public UIKit member (`/tmp/papernest-sidebar-square-diagnostic.log`). Removed both. No private APIs used.
- Final product source is restored to the prior verified implementation. Retained only test improvements: existing Home selection regression can use the sandbox UUID temporary library on a physical device, and now attaches the Notes-selected screenshot too. Mac build passed (`/tmp/papernest-sidebar-square-mac.log`); full unit/StoreKit/locale tests not rerun for this investigation. Final restored physical build and existing Home/Favorites/Notes selection test **passed, 1 test, exit 0** (`/tmp/papernest-sidebar-square-final.log`; `Test-PaperNest-iOS-2026.11.04_20-33-18--0600.xcresult`). Restored app installed on the iPad. `git diff --check` passed.
- Tests used isolated synthetic/empty libraries; user content, existing notebook crash fix, subscription and navigation behavior preserved. No commits/staging.

## 2026-11-04 20:25 CST — Physical iPad notebook crash fix verified (Codex)

- Owner unlocked the connected iPad Pro 12.9-inch (6th generation), iPadOS 27.0.1. Ran the prepared signed candidate using `xcodebuild test-without-building -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'platform=iOS,id=00008112-001618212E07401E' -derivedDataPath ~/Library/Caches/PaperNest/build-17de0868e51d/notebook-device -only-testing:PaperNest-iOSUITests/AppUITests/testNotesPlusCreatesAndReopensNotebookOnDevice`.
- **1 physical-device interaction test passed, 0 failures, exit 0.** The test selected Notes, used its toolbar +, named/created the notebook, reached the editor, selected Pen and asserted the ink canvas, terminated/relaunched, selected Notes again and reopened the stored notebook into the editor. The app remained running in foreground through the final assertion. Log `/tmp/papernest-notebook-device-green.log`; result `Test-PaperNest-iOS-2026.11.04_20-24-54--0600.xcresult` under the device DerivedData Logs/Test directory.
- This validates the NotebookToolbar body-boundary fix against the physical-device stack-overflow path identified in the four original crash reports. The fixed build is installed on the iPad. The test used only a UUID-named temporary library inside the app sandbox; user documents and notebooks were not accessed or modified. Test app terminated normally at teardown; no lingering test process.
- Earlier 657 unit tests, Mac build, iOS Simulator interaction and signed device test build remain applicable; no source changed during this verification. No staging or commits. Broader physical drawing/Apple Pencil, locale/accessibility and long-session stress checks are not claimed by this targeted regression.

## 2026-11-04 20:23 CST — iPad import verification (Codex)

- **All 3 focused UI tests passed, exit 0**, on iPad simulator 6528AE8B-27E3-44B5-9348-B654556BE3F9. Verified new folder → Save and Open → editor, cancellation in en/fr/es, and text-clipping accessibility audit in all three locales with Spanish accessibility XXXL.
- Log `/private/tmp/papernest-import-ipad-2019.log`; result `Test-PaperNest-iOS-2026.11.04_20-19-25--0600.xcresult` under default DerivedData Logs/Test. Direct xcodebuild test, parallel testing disabled, unsigned simulator build, 240-second bound. No other xcodebuild process present at start. Simulator compilation passed; existing Xcode metadata/runtime diagnostics remain.
- Read-only product verification: no source changes, full unit/Mac build reruns, staging or commits. Native Mac import interaction, spoken VoiceOver, real camera/provider import and physical-device notebook candidate verification were not run. Earlier intermittent crash/idle failures remain undiagnosed; this run does not establish a fix. Own documentation claim released.

## 2026-11-04 — Physical iPad notebook opening crash investigation (Codex)

- Owner reproduced from Notes → + on the connected iPad. Retrieved only PaperNest crash reports from systemCrashLogs using devicectl; did not read or alter the real library. Device: iPad Pro 12.9-inch 6th generation, iPadOS 27.0.1. Four reports at 20:03:37/42/46/59. Local diagnostic copies `/tmp/papernest-ipad-notebook-crash{,2}.ips` (not committed). Both inspected reports show `EXC_BAD_ACCESS/KERN_PROTECTION_FAILURE`, stack guard region, in `DocumentView.filterBinding`/copying DocumentView, called through filterMenu → editingTools → notebookTools → safeAreaInset → DocumentView.body. This is a physical-device stack overflow during SwiftUI view construction; prior Simulator passes did not cover it.
- Candidate fix: a real nested `NotebookToolbar: View` evaluates the large toolbar in its own body rather than constructing it synchronously within the parent body's safe-area inset. Controls, state, navigation, data and existing editor behavior are unchanged. This is a structural evaluation boundary, not a delayed timer or swallowed exception.
- Added `testNotesPlusCreatesAndReopensNotebookOnDevice`: Notes toolbar + → named notebook → editor → pen/canvas → terminate/relaunch → Notes → saved notebook/editor. Added debug-only UUID temporary-library launch argument resolved inside the app sandbox, so the same test works on physical iPad without host /tmp paths or real-library changes.
- `./scripts/test.sh`: **657 passed**, exit 0 (159 + 167 + 133 + 150 + 48), no compiler warnings/errors. `/tmp/papernest-notebook-stack-unit.log`.
- `./scripts/build-mac-app.sh`: **passed**, exit 0. `/tmp/papernest-notebook-stack-mac.log`.
- iPad Simulator: **new interaction test passed**, exit 0; iOS Simulator compilation passed. `/tmp/papernest-notebook-stack-sim.log`; result `Test-PaperNest-iOS-2026.11.04_20-08-32--0600.xcresult`. Existing Xcode AppIntents/Simulator automation diagnostics only. `git diff --check` passed.
- Physical pre-fix test attempt: built, but **did not run** because Xcode required the iPad to be unlocked. Asked owner to unlock; canceled the waiting process with SIGINT (exit 75) to prepare the candidate build. `/tmp/papernest-notebook-device-red.log`. The retrieved real crash reports are the failure evidence; this is not an automated red-test result.
- Physical candidate `xcodebuild build-for-testing -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'platform=iOS,id=00008112-001618212E07401E' -derivedDataPath ~/Library/Caches/PaperNest/build-17de0868e51d/notebook-device -allowProvisioningUpdates`: **passed**, exit 0; `/tmp/papernest-notebook-device-build.log`. It built/signed the candidate and tests but did not install or run them. Physical candidate verification remains pending unlock. Do not describe the hardware crash as verified fixed based on Simulator success. No commits, staging, schema or saved-content changes.

## 2026-11-04 — Notes library on iPad and Mac (Codex)

- Reproduced the owner's report: Notes selected on Mac showed the document-import empty state; the initial iPad regression failed at the missing “No Notebooks Yet” assertion (exit 65, `/tmp/papernest-notes-library-red.log`). Existing `StudioNavigationTests` already passed both notebook/document-filter and persistence tests (`/tmp/papernest-notes-routing-model.log`).
- `LibraryView` now provides a localized notebook empty state and New Notebook actions using the existing creation sheet, templates, durable save and subscription quota. Notes hides scan/import controls, clears bulk selection when changing content kind and immediately filters displayed rows while reload completes. No schema/model/persistence changes.
- Native Mac testing also exposed ignored library-row clicks and a retained editor path when switching between destinations sharing `.all`. `RootView` now routes plain row buttons explicitly, clears the detail path when selecting a library destination and applies selection tags after count badges. Verified All Documents is selected after the tag-order change; Notes selects separately and contains only the notebook.
- `./scripts/test.sh`: **657 passed** (159 + 167 + 133 + 150 + 48), no compiler warnings/errors; `/tmp/papernest-notes-library-unit.log`. Run after the library/localization change, before the later RootView-only navigation adjustment.
- `./scripts/build-mac-app.sh`: **passed**, exit 0, including final navigation adjustment; `/tmp/papernest-notes-library-mac-final.log`. No Swift compiler warnings/errors.
- iPad initial green: **1 UI test passed**, exit 0, `/tmp/papernest-notes-library-green.log`. Subsequent direct editor → Documents transition and existing Home selection regression: **2 passed**, exit 0, `/tmp/papernest-notes-library-final-ui.log`. These built the iOS Simulator app; the latter precedes the final tag-order adjustment. Final tag-order build plus the additional Documents selected-state assertion: **2 UI tests passed, exit 0**, `/tmp/papernest-notes-library-verified-ui.log`; result `Test-PaperNest-iOS-2026.11.04_19-53-19--0600.xcresult`. Command: `xcodebuild test -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'platform=iOS Simulator,id=6528AE8B-27E3-44B5-9348-B654556BE3F9' -derivedDataPath ~/Library/Caches/PaperNest/build-17de0868e51d/pro-ipad -only-testing:PaperNest-iOSUITests/AppUITests/testNotesSidebarCreatesAndReopensOnlyNotebooks -only-testing:PaperNest-iOSUITests/AppUITests/testHomeSidebarSelectionFollowsNavigation`. Existing Xcode AppIntents metadata warning and Simulator debugger/accessibility diagnostics; no Swift compiler warnings/errors. `git diff --check` passed.
- Native Mac interaction in disposable `/tmp/papernest-notes-final-mac`: created a notebook from Notes; editor opened; returned to Home; restarted the test app; selected Notes and reopened the saved notebook; switched directly from editor to All Documents (both synthetic document and notebook visible), then Notes (only notebook visible). On the final tag-order build, All Documents and Notes both report native selected rows. `screenshots/notes-library-mac-dark.png`; iPad `screenshots/notes-library-ipad-light.png`. Initial CUA action/state calls twice timed out; fresh reads and later actions succeeded, no app crash observed.
- **Unrun for this slice:** physical iPad, iPhone runtime, French/Spanish runtime layout, spoken VoiceOver and new ink persistence. Localized keys pass parity tests; existing notebook persistence/editor implementation unchanged. Tests used synthetic copies only; real libraries and the owner's running Xcode app were untouched. No staging or commits.

## 2026-11-04 19:19 CST — Isolated import verification passed (Codex)

- With no other xcodebuild process present at start, ran existing import tests on iPhone 17 Pro Max 414752ED, default DerivedData, parallel testing disabled, 240-second bounds. No product or test code changed.
- **1 test passed, exit 0:** create a new destination folder, save the imported image, automatically open its document editor. `/private/tmp/papernest-import-isolated-1916.log`; result `Test-PaperNest-iOS-2026.11.04_19-15-50--0600.xcresult` in default DerivedData Logs/Test.
- **2 tests passed, exit 0:** destination cancellation and text-clipping accessibility audit in English, French and Spanish, Spanish at accessibility XXXL. `/private/tmp/papernest-import-locales-1917.log`; result `Test-PaperNest-iOS-2026.11.04_19-17-09--0600.xcresult`. This run exercised all three locales in both tests.
- The prior intermittent UIKit crash and idle timeout are not diagnosed or declared fixed. Successful isolated reruns do not prove concurrency caused those earlier failures. iOS compilation succeeded; full unit/Mac builds were not repeated for this read-only verification. Native Mac import interaction, spoken VoiceOver, physical camera/provider import and fresh iPad reruns remain unrun here.
- Own documentation claims released. No staging, commits, signing changes or other agents' process changes.

## 2026-11-04 — Icon-only Home Profile on all platforms (Codex)

`LibraryHome.swift` now uses the existing circular person symbol without visible Profile text or default rectangular button chrome. Shared iPhone/iPad/Mac implementation retains the existing Profile sheet, `home-profile` identifier, localized Profile accessibility label, Dynamic Type and a 44-point minimum target. No subscription, account, data or persistence changes. No new tests added for this small styling change; reused the existing interaction suite.

- `./scripts/build-mac-app.sh`: **passed**, exit 0, no Swift compiler warnings; `/tmp/papernest-profile-icon-mac.log`.
- `xcodebuild test -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'platform=iOS Simulator,id=017A2927-1657-4C93-836B-318FAD1D21AF' -derivedDataPath ~/Library/Caches/PaperNest/build-17de0868e51d/pro-xcodeproj -only-testing:PaperNest-iOSUITests/SubscriptionUITests/testProfilePaywallDismissalAndLocalization`: **passed, 1 test**, exit 0. English/French/Spanish, Spanish accessibility XXXL; Profile → upgrade → Continue with Free → Profile → Home. `/tmp/papernest-profile-icon-iphone.log`.
- Same test on iPad `6528AE8B-27E3-44B5-9348-B654556BE3F9`, derived data `pro-ipad`: **passed, 1 test**, exit 0, same locales and interaction flow. `/tmp/papernest-profile-icon-ipad.log`. Both simulator app builds passed. Xcode emitted its existing no-AppIntents-framework metadata warning and runtime automation diagnostics.
- Native Mac: inspected Home dark appearance (icon only, no square background), opened Profile using the icon, dismissed with Done and confirmed return to Home. AX retains localized Profile description. Screenshot: `screenshots/home-profile-icon-mac-dark.png`. Used `/tmp/papernest-profile-icon-mac`, not a real library.
- `git diff --check`: passed. Full unit/StoreKit suite and spoken VoiceOver were not rerun; subscription integration unchanged. Mac non-English/light appearance and physical-device checks were not run for this slice.
- **Requested automatic Apple Account photo is unavailable:** Apple's public [Sign in with Apple credential](https://developer.apple.com/documentation/authenticationservices/asauthorizationappleidcredential) exposes authorized account/name/email data, not an avatar. Installing the app supplies no account-photo source. Repository audit found no existing authentication/photo integration. The UI uses the honest person-symbol fallback; no fabricated photo or unnecessary account system was added. A user-selected custom image is a separate possible enhancement, not implemented here.

## 2026-11-04 — Home sidebar selection on Mac and iPad (Codex)

Home now participates in native List selection through a view-only destination enum, alongside Notes and existing library scopes. Removed the extra Home/Notes button chrome; New Folder uses a plain style. Mac uses native blue row selection. iPad uses an explicit blue capsule with white text/icons and plain button actions routed through the same selection binding; compact iPhone rows retain their existing native labels and lavender tint. No model, persistence, subscription or localization changes.

- Regression reproduced before the fix: `testHomeSidebarSelectionFollowsNavigation` failed because Home's cell was not selected at launch. `/tmp/papernest-sidebar-red.log` (exit 65).
- Native-selection pass: **2 iPad UI tests passed**, including repeated Favorites → Home navigation and Home search into the existing seeded document. `/tmp/papernest-sidebar-green.log`. Screenshot revealed iPadOS 27 rendered a neutral pill despite blue tint, so visual work continued.
- Two intermediate iPad styling runs failed Favorites navigation (`/tmp/papernest-sidebar-blue.log`, `/tmp/papernest-sidebar-blue-tags.log`). Failure capture confirmed a tap on the correct sidebar row without a navigation change; moving the selection tag alone did not resolve it. The final styled iPad row explicitly routes its button action through the selection binding while preserving native selected-row state.
- Final `xcodebuild test -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'platform=iOS Simulator,id=6528AE8B-27E3-44B5-9348-B654556BE3F9' -derivedDataPath ~/Library/Caches/PaperNest/build-17de0868e51d/pro-ipad -only-testing:PaperNest-iOSUITests/AppUITests/testHomeSidebarSelectionFollowsNavigation`: **passed, 1 test**, exit 0; `/tmp/papernest-sidebar-final.log`. Checks selected Home at launch, two Favorites/Home cycles, Notes/Home selection and deselection. Final screenshot inspected: `screenshots/home-sidebar-ipad-light.png`; blue capsule, white Home icon/text, no square background.
- Final `./scripts/build-mac-app.sh`: **passed**, exit 0, `/tmp/papernest-sidebar-mac-final.log`; no Swift compiler warnings. iOS simulator compilation passed in the UI run; Xcode emitted its existing no-AppIntents-dependency metadata warning and runtime automation diagnostics.
- Native Mac interaction: Home/Favorites/Home passed in the final build; Home/Notes/Home and New Folder → Cancel also passed during the initial native selection pass (same Mac actions). Final AX tree reports selected Home. Dark screenshot inspected and saved as `screenshots/home-sidebar-mac-dark.png`. Disposable libraries only. An initial screenshot automation call timed out; subsequent native checks succeeded.
- `git diff --check`: passed. Full unit suite, iPhone runtime, locale/Dynamic Type reruns, iPad dark/Mac light and spoken VoiceOver were not rerun for this focused sidebar fix. Existing en/fr/es labels and large-text sidebar helper retained. Physical-device checks remain unrun.

## 2026-11-04 18:27 CST — Import verification retry (Codex)

- Existing three focused import tests selected on iPhone 17 Pro Max simulator 414752ED, default DerivedData, parallel testing disabled. Compilation proceeded past the prior SubscriptionStore blocker. **Run timed out at 300 seconds, exit 124**, not a pass: `/private/tmp/papernest-import-recovery-1821.log`.
- Create-folder test reached the new-folder text field, then XCTest reported no app-idle notification. Typing resumed around 208 seconds, followed by Save; editor-export was not observed before interruption. Locale-cancellation and text-clipping tests were not reached in this run.
- Three-second process sample `/private/tmp/papernest-import-idle-sample.txt`: main thread waited in the normal run loop throughout the sample. This does not establish an app deadlock or its cause; prior intermittent crashes remain unresolved. Concurrent Home Tools tests used separate devices/build directories; their processes and files were untouched.
- No product/test changes, no full unit/Mac rerun, no native Mac/VoiceOver/physical-device checks, no staging or commits. Own documentation claim released. Retry the isolated import flow after concurrent simulator work settles.

## 2026-11-04 17:26 CST — Import destination locale/accessibility verification

## 2026-11-04 — Home Tools relocation (Codex)

Owner's latest mockup places Scan/Import → Tools → Recent on Home and explicitly includes Mac. Added four compact cards (Merge, Extract, Split, ZIP) backed by the existing `ToolsSheet.Tool` catalog. Cards open the same document pickers; See All opens the full Tools screen. Removed global toolbar Tools entries from RootView and LibraryView. Editor tools, store operations and Pro checks unchanged. Two columns on compact iPhone, adaptive columns on iPad/Mac, wrapping labels and vertical icon/text at accessibility sizes. Existing en/fr/es L10n labels reused. Scan remains iOS-only with the existing availability check; Mac has Import. Updated legacy UI test entry helper for relocated Tools.

- `./scripts/test.sh`: **657 passed**, `/tmp/papernest-home-tools-unit.log`; no compiler warnings.
- Final Mac build **passed**, `/tmp/papernest-home-tools-mac-verified.log`, with no compiler warnings. Final iPhone/iPad simulator apps also compiled in the focused UI runs.
- Initial iPhone interaction failed after successful Merge picker navigation because a parent accessibility identifier masked the See All button ID; fixed by assigning the section identifier to its heading only. `/tmp/papernest-home-tools-iphone.log`.
- Second iPhone run completed all English tool routes, then failed its French row-alignment assertion (7-point vertical offset between unequal-height cards). Top-aligned grid items and shortened Merge/Extract labels using existing translations; retained full VoiceOver names. `/tmp/papernest-home-tools-iphone-final.log`. The interim iPad run was stopped to test this final layout; interruption produced an Xcode cancellation diagnostic, not a passing result.
- Final iPad run **passed** all four Home card routes and See All in en/fr/es, with Spanish accessibility XXXL, `/tmp/papernest-home-tools-ipad-verified.log` (1 combined XCTest, 3 locales). iPhone English/French routes and two-column alignment passed within `/tmp/papernest-home-tools-iphone-verified.log`, but its Spanish Split tap failed: failure AX snapshot showed the 314-point-high card beginning at y=707 on an 874-point screen, with its center beneath bottom navigation. XCTest's `isHittable` accepted the exposed strip. Fixed the test to scroll whole cards clear of navigation; no product bypass. Targeted final Spanish XXXL rerun **passed** (1 XCTest, all four pickers plus See All), `/tmp/papernest-home-tools-iphone-large.log`, xcresult `pro-xcodeproj/Logs/Test/Test-PaperNest-iOS-2026.11.04_18-25-38--0600.xcresult`. Test cases are now separated by locale for focused reruns.
- Final screenshots: `docs/screenshots/home-tools-{iphone,ipad}-*.png`. Inspected iPhone French and iPad English; labels wrap and grid widths adapt. Native Mac dark screenshot inspected through computer-use.
- Native Mac layout was inspected in a throwaway library: four cards in one row, other navigation intact, no Tools toolbar button. Initial native automation hit repeated `timeoutReached` and a stale-state warning. A final retry **passed** all four Home → correct document picker → Back → Done flows plus Home See All → full Tools → Done, in English/dark appearance, against `/tmp/papernest-home-tools-mac-final-check`. Toolbar contains sidebar/search, not Tools. User library and independently running Xcode app untouched. VoiceOver spoken traversal and native Mac fr/es interaction remain unrun.


## 2026-11-04 — Pro paywall and Home Profile (Codex)

Implemented native adaptive paywall/Profile, StoreKit product/entitlement/renewal service, exact eligible seven-day introductory offer, first-welcome offer handling, restore/manage and compatible Free/Pro checks. All strings use en/fr/es L10n. Product/legal configuration is intentionally empty: no production purchase or promised trial is available until the owner supplies real products and published URLs. No database migration or content removal.

Verification (disposable libraries and local synthetic StoreKit fixture only):

- Regular suite: **657 passed** (159 UI policy/model/localization, 167 Store, 133 Import, 150 Export, 48 Core), `/tmp/papernest-pro-final-unit.log`. Post-review rerun also passed all **657**, `/tmp/papernest-pro-verified-unit.log`, with no compiler warnings.
- Mac app build passed, `/tmp/papernest-pro-mac-final.log`; post-review build also passed with no compiler warnings, `/tmp/papernest-pro-verified-mac.log`.
- iPad iOS 27 dark: **2 XCUITests passed**, including en/fr/es Profile → paywall → Continue Free → Home, Spanish accessibility XXXL, and welcome dismissal/relaunch without granting a trial. `/tmp/papernest-pro-ipad-ui.log`; xcresult `pro-ipad/Logs/Test/Test-PaperNest-iOS-2026.11.04_17-40-41--0600.xcresult` under the build cache. Inspected English and Spanish large-type dark screenshots; fixed overlapping benefit icons found in the earlier iPhone large-text screenshot. Screenshots in `docs/screenshots/pro-*`.
- Earlier iPhone iOS 26.5 navigation test passed in all three locales. `/tmp/papernest-pro-ui.log`. Final post-review iPhone rerun: **2 tests passed**, `/tmp/papernest-pro-iphone-final.log`, result `pro-ipad/Logs/Test/Test-PaperNest-iOS-2026.11.04_17-48-34--0600.xcresult`. Both platform simulator test runs built the iOS app successfully.
- StoreKit hosted tests exercise Apple's local StoreKit, not a mock access flag. Verified trial purchase/eligibility, delayed pending approval, restoration, expiry and refund assertions have passed during runs, but early combined suites **failed** on stale cancellation/expiry observations. The eight-second timeout was too short for observed renewal update delivery. `/tmp/papernest-pro-storekit-{debug,final,diagnosed,latest}.log`. Two-second accelerated billing retry/grace checks also failed (state had expired); revised to force renewal at real-time speed. Final post-review run **passed all 3 StoreKit tests (including both billing retry/grace cases)**, `/tmp/papernest-pro-storekit-verified.log`: verified eligible seven-day trial, ineligibility after purchase, auto-renew cancellation with access, expiry, annual purchase/refund, injected failure, Ask to Buy/pending update, restoration, and retry/grace. Runtime delivery was handled by bounded 45-second polling (lifecycle finished in 15.9 seconds); force-renewal at real-time speed made retry/grace deterministic in this run. No production code bypass was added.
- Initial issues corrected: observable task deinit isolation, missing close localization, French nonbreaking-space punctuation, conditional export-sheet modifier placement, duplicate hosted-test PRODUCT_NAME. Initial SwiftPM-only StoreKit helper and iOS 26.5 local session could not establish StoreKitTest; iOS 27 with debugger enabled loads the fixture. Injected userCancelled became ASD unknown error 907, so normal PurchaseResult.userCancelled is separately unit-tested; injected failure and Ask to Buy are tested through StoreKit.

Outstanding release checks: real App Store Connect product IDs/pricing/one-week offers and legal/support URLs; sandbox/TestFlight billing/account-change/cross-device restore; configured paywall plan/CTA UI interaction; native Mac interaction and VoiceOver. First-launch UI checks currently cover the unconfigured/no-trial path, not an eligible sandbox account. StoreKit local tests do not replace these release checks.


- Added independent locale-cancellation and text-clipping audit UI tests. Synthetic disposable library/file only. English/French/Spanish cancellation passed in `/private/tmp/papernest-import-locales-interaction.log` (1 test, exit 0; Spanish at accessibility XXXL). Initial screenshot inspection found the duplicate navigation heading truncated in French and Spanish XXXL despite tappable controls. Removed that duplicate in ImportLocationSheet; the existing picker heading wraps and remains visible. Corrected French/Spanish screenshots inspected at `/private/tmp/pn-import-heading-final/`.
- Initial combined audit crashed the app during French verification: `/private/tmp/papernest-import-locales-audit.log`, exit 65. Crash report `~/Library/Logs/DiagnosticReports/PaperNest-2026-11-04-172200.ips`: EXC_BREAKPOINT in UIKitCore collection-view layout, repeated `_updateVisibleCellsNow`, SwiftUI UpdateCoalescingCollectionView. Root cause not established; do not claim this crash fixed by the heading change.
- Post-change `/private/tmp/papernest-import-locales-final.log`: **text-clipping audit test passed** across all three locales, including cancellation. However the separate cancellation test suffered an unexpected launch exit before assertions; the overall command **failed exit 65**. Preserve that distinction. Mac build passed (`/private/tmp/papernest-import-heading-mac.log`), no compiler warnings. UI test build has AppIntents metadata warning.
- Final serial cancellation rerun **blocked at compilation**, exit 65 (`/private/tmp/papernest-import-locales-cancel-final.log`): concurrently added, actively claimed `SubscriptionStore.swift:64` references MainActor task properties from nonisolated deinit. This session did not edit that file or the Pro/Profile slice. Re-run the two focused import tests after that slice settles; retain the intermittent launch/audit crash as unresolved until reproduced/diagnosed.
- Bounded checks: 180–300 seconds. No full unit suite repeated for this heading-only change. No native Mac interaction, VoiceOver, real camera or device verification. No commits, staging or signing edits; claims released.

## Device signing fix — 2026-11-04

- Screenshot reported rejected placeholder bundle ID and missing provisioning profile. Config/Signing.local.xcconfig was absent. Confirmed selected team against local development certificate; created the existing git-ignored override with team 48U7V37436 and bundle ID com.karanpatel.papernest.dev48u7v37436. Generated project and product sources untouched.
- xcodebuild -showBuildSettings confirms resolved team/ID and automatic signing; /tmp/papernest-signing-settings.log. Signed generic-iOS build with -allowProvisioningUpdates **passed exit 0**, /tmp/papernest-device-signing-build.log. Strict deep codesign verification **passed**; built app reports the configured team and identifier.
- This verifies signing/build, not physical-device install or launch. No unit/UI tests rerun for local configuration only. New identifier represents a separate installation from any earlier bundle ID; no installed app or user data was deleted. Claims released; no staging/commits.

## 2026-11-04 — Import destination and automatic opening

- Shared iPhone/iPad/Mac import flow now asks for Home (no folder), an existing folder, or a new named folder before saving. All library Files/drop/paste, Photos and camera entry points opt in; adding/replacing pages inside a document stays in-place. Cancellation writes no imported item. File access remains security-scoped while the destination sheet is open. Navigation waits for destination-sheet dismissal and successful storage; batch imports open the first successful item, with file items using the existing preview. Password-unlocked documents also open after storage. en/fr/es strings added together.
- Wide Home routing now uses its detail stack rather than opening in the sidebar; compact Home retains its existing push. Model tests cover cancelled writes, new-folder save/open, existing-folder file import and wide navigation, root overriding current folder, and invalid images not opening.
- Test-first compile failed as expected with missing destination API (`/private/tmp/papernest-import-location-red.log`). Full `./scripts/test.sh` passed **651 tests** (153 UI + 167 Store + 133 Import + 150 Export + 48 Core), 600-second bound: `/private/tmp/papernest-import-location-unit.log`. Final focused tests after batch-open refinement: **4 passed**, `/private/tmp/papernest-import-location-tests-final.log`. No compiler warnings.
- Mac app builds passed, latest `/private/tmp/papernest-import-location-mac-final.log`, 240-second bound; no compiler warnings. iOS compiles as part of focused UI tests. Direct xcodebuild used to preserve owner signing settings instead of project-regenerating ui-test-ios.sh.
- iPhone 17 Pro Max focused import/create-folder/auto-open test passed, `/private/tmp/papernest-import-location-ui-phone-retry.log`. Initial query incorrectly treated inline Picker options as StaticText; corrected to match the accessible option. iPad initial query selected an underlying Home New Folder button; a scoped descendant query also failed. Exported hierarchy shows picker identifier is inherited by option buttons; final test uses identifier AND label. Initial failures retained in `/private/tmp/papernest-import-location-ui-ipad{,-retry}.log`; final iPad test **passed (1 test, 0 failures)** in `/private/tmp/papernest-import-location-ui-ipad-final.log`, exit 0 within 240 seconds. Xcode reports its AppIntents metadata-extraction warning for the UI-test bundle (no framework dependency), not a Swift compiler warning.
- Test uses a synthetic PNG through a DEBUG import hook and the real destination sheet, storage and editor; it does not exercise the system file picker. Physical camera, iCloud file-provider delays, native Mac interaction, VoiceOver and translated layout remain unrun. Existing studio redesign and earlier uncommitted work preserved; no commits/staging.

## Unified studio redesign — 2026-11-04

Core redesign details and explicit remaining scope: `UNIFIED_STUDIO_REDESIGN.md`. Existing uncommitted photo/encoding/navigation changes preserved. No schema migration or real-library testing.

- `./scripts/test.sh`: **647 passed** (149 + 167 + 133 + 150 + 48); final log `/tmp/papernest-studio-final-unit.log`, no compiler warning/error matches. Adds synthetic temporary-library round-trip tests for Notes/Documents filtering, two-page scan import/open, and favorites outside the recent ten.
- `./scripts/build-mac-app.sh`: **passed**, latest log `/tmp/papernest-studio-mac-final.log`, no compiler warning/error matches. This is a build result, not native Mac interaction verification.
- `./scripts/build-ios-sim-app.sh`: **passed**, `/tmp/papernest-studio-ios.log`; Xcode emitted simulator-placeholder operatingSystemVersion diagnostics. Subsequent focused UI builds also compile the iOS target.
- First new iPhone UI run: Home passed; ink test failed querying PencilKit as `Other`. Exported AX hierarchy proved `ink-canvas` is a `ScrollView`. Test changed to the existing descendant query pattern; rerun **passed** with finger stroke persisted across termination/relaunch. Logs `/tmp/papernest-studio-ui.log`, `/tmp/papernest-studio-ink-ui.log`. Do not count the initial failed test as product success.
- Independent read-only review: fixed Notes sidebar retaining an existing document navigation path on iPad/Mac. Reviewer retracted its separate Home-import destination concern after checking the existing nil-selection guard.
- Multi-flow iPhone run: filter/title workflow, Home navigation/no-card checks, and locale interaction test passed; handwriting failed. The captured video exposed a flexible Divider expanding the tool row over the canvas. Fixed with a bounded height and added a canvas-height assertion. Spanish XXXL screenshot also exposed fragmented brand/tab layout despite passing interaction checks; fixed with stacked header/filters and an accessibility navigation menu. Log `/tmp/papernest-studio-final-ui.log`. These initial layout screenshots are **not** counted as visual passes.
- Corrected iPhone run: **2 passed**, localized Home (en/fr/es; es at XXXL) and notebook finger stroke/save/terminate/reopen. Canvas-height assertion prevents the toolbar expansion regression. `/tmp/papernest-studio-layout-ui.log`. Corrected Home (en/fr/es) and Notes screenshots inspected, saved under `docs/screenshots/studio-*`.
- iPad Pro 13-inch, iOS 26.5, dark mode: localized Home interaction **passed**; en/fr/es screenshots inspected, including es XXXL. Initial Notes settings flow failed because the Form's popover collapsed to 81 points; its scrollable height is now explicitly 480 points and the settings finger-drawing identifier is distinct from the toolbar toggle. `/tmp/papernest-studio-ipad-ui.log`. Corrected Notes rerun recorded below.
- Corrected iPad Notes test **passed**, `/tmp/papernest-studio-ipad-final-ui.log`: enabled finger drawing, stored one stroke and reopened it after termination. The preceding rerun tapped the center of SwiftUI’s labeled switch row rather than its control; the test now taps the trailing switch and asserts its value before writing. Dark Notes screenshot inspected and saved as `docs/screenshots/studio-notes-ipad-dark.png`.
- Added an iPad Home → recent notebook reopening assertion. Two attempts that changed the split-view selection lost the document push and failed (`/tmp/papernest-studio-ipad-navigation-ui.log`, `/tmp/papernest-studio-ipad-navigation-fixed-ui.log`). The final implementation pushes directly into the existing wide Home detail stack without switching its root. **Final rerun passed** (1 test, 0 failures), `/tmp/papernest-studio-ipad-navigation-path-ui.log`; latest Mac build also passed after this fix.
- Follow-up static review found no further important issues.
- **Unrun:** physical camera capture/permissions/interruption, Apple Pencil pressure/palm rejection/squeeze, VoiceOver, native Mac interactions, exhaustive legacy UI suite, large-document performance and force-termination during an in-flight write. Existing synthetic fixture tests and successful stroke reopen do not stand in for these gates.

# Test matrix

## 2026-11-04 — Remove duplicate bottom Search

- Owner requested removal of redundant bottom Search. Removed compact bottom button and corresponding large-text navigation-menu action; existing home search field remains. No new strings or backend changes.
- Unsigned iOS device build passed exit 0, bounded 180 seconds: `/private/tmp/papernest-remove-bottom-search.log`. No compiler warnings/errors; git diff --check passed. Runtime layout, accessibility interaction and full suite not rerun for this small removal. Signing configuration preserved; no staging/commits; claims released.

## 2026-11-04 — iPhone bottom Folders button

- Owner reports bottom Folders does nothing. Source inspection: both compact navigation actions scroll to an ID on text nested inside a List section header. Moved the target to a real, always-present New Folder row; reused localized label/action and sidebar-new-folder identifier. No backend changes or signing/project regeneration.
- Bounded unsigned physical-iOS build passed (240 seconds maximum), no compiler warnings: `/private/tmp/papernest-folder-build.log`. Mac app build passed (240-second maximum): `/private/tmp/papernest-folder-mac.log`.
- Direct xcodebuild test on iPhone 17 Pro Max simulator 414752ED-CE8A-4298-BB66-9FBCAA962A99 passed: **1 test, 0 failures**, 240-second bound, `/private/tmp/papernest-folder-ui.log`. Regression test taps bottom Folders in an empty library, reaches New Folder, creates a folder and checks its empty state. Test build emitted AppIntents metadata-extraction warning (no framework dependency); no Swift compiler warning. Original implementation was not runtime-reproduced before modification.
- Used direct Xcode build/test to preserve owner's generated-project signing edits; did not run ui-test-ios.sh (regenerates project). Full unit suite not repeated for this view-only change. Physical phone retest, populated-folder scrolling, iPad and VoiceOver remain unrun. No commit/staging. Claims released.


## 2026-11-04 18:12 UTC — Notes Photo Library insertion recovered

- DocumentView Image tool now offers Photos and Files using existing en/fr/es labels. Photos uses the system picker restricted to images with compatible encoding; captures the target Page before opening, loads data asynchronously, checks cancellation before placement, and uses the existing addImage placement/undo path. Loading disables another Image selection; failed transfers/placement report an alert. Existing Files command remains available. No backend changes or new strings.
- Recovered completed verification: full suite **644 passed exit 0** (`/private/tmp/papernest-notes-photos-unit.log`, 600-second bound). Subsequently added `NotePhotoPlacementTests` **1 passed exit 0** (`/private/tmp/papernest-note-photo-placement.log`, 180-second bound), proving filename-less photo data produces one image object with preserved proportions on the intended notebook page and model reload keeps one page. This is model coverage, not system-picker interaction, not a fresh-process relaunch, and not an undo test.
- Mac/iOS app builds both **passed exit 0**, 600/180-second bounds, logs `/private/tmp/papernest-notes-photos-{mac,ios}.log`. No compiler warnings. Current first-launch preflight remains **69**, `/private/tmp/papernest-nov4-1812-first-launch.log`; runtime picker presentation, cancellation/reselection, cloud downloads, language layouts and VoiceOver remain unrun. No new successful interaction claim or repeated blocked UI-test launch.
- Product/tests unchanged during recovery; recorded outcomes and released claim. No staging, commits or pending processes. JPEG scan fix remains separately uncommitted and intact.

## 2026-11-04 — Scan JPEG conversion is all-or-nothing

- `DocumentCameraView` delegates conversion to `ScanCaptureEncoding.pages`. Empty capture or a nil JPEG result now returns failure immediately; successful captures keep every page in order. No partial array reaches `.scanned` or library/add/rescan saves. Existing localized scan-failure alert is reused; no strings or backend changes. Updated obsolete comment claiming the camera wrapper had never compiled.
- Added `ScanCaptureEncodingTests`: ordered success, empty capture, and failures at first/middle/last page, including no subsequent encoding after failure. Initial test-first compile failed because the helper did not exist (`papernest-scan-encoding-red.log`). Extracted original compactMap policy and demonstrated the real regression: **5 assertion issues**, exit 1 (`papernest-scan-encoding-regression.log`). Then changed to guarded sequential conversion.
- Final full suite **644 tests passed, exit 0** (146 UI, 167 Store, 133 Import, 150 Export, 48 Core), `/private/tmp/papernest-scan-encoding-green.log`, 600-second bound. Mac build **passed exit 0**, 600-second bound; iOS app build **passed exit 0**, 180-second bound. Logs `/private/tmp/papernest-scan-encoding-{mac,ios}.log`. No compiler warnings. iOS build still reports outdated CoreSimulator/device support disabled.
- Regression injects nil encoding results; it does not reproduce a real UIImage encoder failure on hardware. Camera interaction and alert presentation remain unrun due to existing device/simulator limitations. No repeat known-blocked UI-test launch, no staging or commits. `git diff --check` passes. All claims released; no processes pending.

## 2026-11-04 — Owner-requested scanning review

- Source inspected: DocumentCameraView, library camera completion, document Add/Rescan completion, LibraryModel importImages/prepareImages, and localized camera permission strings. iPhone/iPad use VNDocumentCameraViewController; native Mac has no camera controller. Scan availability checks, cancellation, generic failure alerts, current-folder import and add/replace routes exist. No separate PaperNest post-camera review screen: library completion imports directly after the system camera finishes.
- **Finding, not device-reproduced:** DocumentCameraView's delegate uses `compactMap` on JPEG encoding and fails only when every page is absent. If any individual `jpegData` returns nil, that page is silently dropped while the remaining pages are reported as a successful scan. Follow-up should make capture conversion all-or-nothing and test partial encoding failure. No code changed in this review.
- Bounded `./scripts/test.sh --filter 'LibraryWorkflowTests|RecognitionWorkflowTests|ImportTests'` **passed exit 0**, 180-second bound; `/private/tmp/papernest-scan-review-tests.log`. Filter matched **150 tests** (17 UI workflow/photo tests and 133 Import-target tests), no compiler warnings. Includes three-page scan ordering and rescan replacement/undo/redo/relaunch. Synthetic/imported image coverage is not real camera capture.
- Unrun: actual edge detection/perspective/camera quality, camera permission denial on device, large capture-session memory, interrupted capture and save, VoiceOver camera interaction, and real scan→relaunch→export gate. Known simulator setup blocker persists; physical capture still requires device/signing. No new builds or UI-test pass claimed, no staging or commits.

## 2026-11-04 13:09 UTC — Tools hub verification recovered and completed

- Tools hub uses matching action/Photos cards, visible localized document-tool prompts, adaptive columns and one column at accessibility sizes. Existing action identifiers and handlers retained. Export format catalog is explicitly nonisolated immutable data; this removes warnings from nonisolated catalog tests without weakening actor checks.
- Recovered prior filtered UI suite: **143 passed, exit 0**, `/private/tmp/papernest-tools-hub-ui-final.log`. Prior full suite failed in concurrent backend `measureCopyVersusRebuild()`; that is historical, superseded by current run. Prior targeted Tools interaction invocation timed out before tests started (**124**, 45-second bound), `/private/tmp/papernest-tools-hub-interaction.log`.
- Current HEAD `0b57b56`: full suite **641 passed, exit 0** (143 UI, 167 Store, 133 Import, 150 Export, 48 Core), `/private/tmp/papernest-tools-recovery-unit.log`, 600-second bound. Mac build **passed exit 0**, same bound; iOS Simulator app build **passed exit 0**, 180-second bound. Logs `/private/tmp/papernest-tools-recovery-{mac,ios}.log`. No compiler warnings in these logs. iOS build still reports outdated CoreSimulator and disabled device support; successful compilation does not prove interaction/layout.
- No runtime screenshots, accessibility audit or native interaction verification claimed. All previous runtime gaps remain. The UI changes were already committed externally as `f001dd1` when this recovery began; this Codex pass made no commit and changed only these verification/handoff notes. Claims released; no processes pending.

## 2026-11-04 — First coordinated UI/UX refinement (iPhone, iPad, Mac)

- Owner confirmed three platforms and requested UI work now. Export choices explicitly stack at accessibility Dynamic Type sizes on iOS; tile subtitles wrap and centre. Saved markup labels allow three lines with a 44-point row minimum. Mac Export/Markup sheets use 360 minimum, 620 ideal, 680 maximum height; export ideal width 540. These are layout changes, not proven fixes for the earlier runtime findings. No new strings or backend edits.
- Bounded Mac build **passed exit 0** (`/private/tmp/papernest-ux-sheets-mac.log`, 600-second bound), no compiler warnings. iOS Simulator app build **passed exit 0** (`/private/tmp/papernest-ux-sheets-ios-build.log`, 180-second bound), no compiler warnings; Xcode still logs CoreSimulator 1174.9.2 versus required 1174.21 and disables simulator device support. A termination attempt after completion found no process; no build was cancelled.
- Full unit invocation **failed exit 1 during compilation**, 600-second bound, `/private/tmp/papernest-ux-sheets-unit.log`: concurrently introduced `WholeSourceCopyTests.swift` used an invalid Page initializer and referenced missing `Exporter.wholeSourceAsset`. That backend file and the concurrently changing `Exporter.swift` were not edited by Codex. No passing unit result claimed for this slice; rerun after backend work settles.
- No runtime screenshots, iOS UI tests, Mac interaction or accessibility pass claimed. Xcode setup and absent desktop-control tooling still block those checks. Existing audit failures remain open. `git diff --check` passes. No staging/commits; design continuation recorded in CLEAN_NATIVE_DESIGN. All Codex file claims released.

## 2026-11-04 09:01 UTC — Simulator preflight still blocked

- Usage available. Re-read brief, current claims and newest results; no staged paths. Bounded `xcodebuild -checkFirstLaunchStatus` again returned **69** immediately; log `/private/tmp/papernest-nov4-0901-first-launch.log`. Xcode setup blocker remains. No repeat UI timeout, builds or unit tests: no source changed since the preceding verified baseline. App interaction checks remain unrun. Handoff preserved, documentation claim released, no active processes or commits.

## 2026-11-04 UTC — Codex resumed: current baseline passes; Simulator setup blocked

- Current HEAD `fc1637c`; read Claude’s Nov 3 UI coverage handoff and checked claims/index before work. No product/backend edits, staging or commits.
- `./scripts/test.sh`, bounded 600 seconds: **616 passed, exit 0** (143 UI, 167 Store, 133 Export, 125 Import, 48 Core). Log `/private/tmp/papernest-nov4-unit.log`. `./scripts/build-mac-app.sh`, bounded 600 seconds: **passed, exit 0**, log `/private/tmp/papernest-nov4-mac.log`. No compiler warning/error matches in either log. These do not establish app interaction success.
- `xcodebuild -checkFirstLaunchStatus`: **exit 69**, 30-second bound, `/private/tmp/papernest-nov4-first-launch.log`. Installed CoreSimulator is `1174.9.2`; Xcode’s simctl wrapper requires `1174.21` and invokes `xcodebuild -runFirstLaunch`. Initial device-list probe stalled in that child and was terminated. `./scripts/ui-test-ios.sh`, bounded 45 seconds: **timeout, exit 124 before device discovery/test execution**, `/private/tmp/papernest-nov4-ios.log`; process group terminated. No UI test passed or failed an assertion: none started. Owner must complete Xcode setup (`sudo xcodebuild -runFirstLaunch`) before Simulator checks can resume.
- Visually inspected all three saved `opaque-light-*-ipad.png` images from Oct 29: Position/Start horizontal slider visible; Thick fully visible and selected; native Custom Color popover visible. Scrolled neighbouring content remains clipped at sheet edges. This closes only the old screenshot-review task, not the failed accessibility audits or verification of newer UI.
- Unrun: current iPhone/iPad interactions for export formats/password input, text/image editing and language settings; native Mac/VoiceOver/two-window interaction (no desktop-control tool available); real camera/device gate; broader accessibility audits. Next: restore Simulator prerequisites, then verify Claude’s new shared UI and remaining accessibility failures before feature work. No running verification process remains.


## 2026-10-29 UTC — Final opaque-toolbar light iPad largest-text check

- `/private/tmp/papernest-opaque-nav-ipad-light-large.log`: **passed, exit 0**, 73.282 seconds, 900-second bound. Final toolbar source on light iPad: sidebar width assertion, largest-text position slider, Thick selection, native color popover, save and saved markup row. Existing assertions unchanged.
- Exported `docs/screenshots/opaque-light-*-ipad.png`; screenshots not visually inspected this pass. No passing full audit claimed. Final phone dark/localized and native Mac/VoiceOver/device checks remain unrun. No source/backend edits, fresh unit/Mac builds, staging or commits. Simulator remains light; no pending process. Weekly usage was 96% consumed at start.

## 2026-10-29 UTC — Recovered opaque-toolbar iPhone verification

- Recovered the completed bounded run after usage interruption: `/private/tmp/papernest-opaque-nav-phone-large.log` **passed, exit 0**, 66.992 seconds under 900-second timeout. Final opaque-toolbar source on light iPhone at largest text: position slider, Thick width selection, native color picker, save and saved-markup verification all passed. No rerun needed.
- Exported three screenshots as `docs/screenshots/opaque-nav-*-iphone.png`; width screenshot inspected: toolbar title/actions and selected Thick row visible, scroll-edge content remains clipped as expected during scrolling. This is not a passing accessibility-audit claim. iPad light/final largest-text and final phone dark/localized checks remain unrun.
- Documentation/evidence only; no fresh unit/Mac tests, source/backend edits, staging or commits. Previous 502-test/Mac results remain historical. No pending processes or claims. Weekly usage 95% consumed at recovery; handoff saved.

## 2026-10-29 UTC — Shape/Stamp opaque navigation background

- `ShapeAnnotationSheet.swift` iOS navigation now requests a visible opaque `secondarySystemBackground`. Purpose: stable Cancel/Add backing while Form content scrolls beneath navigation. No strings/actions or backend changes; macOS unaffected by the conditional modifiers.
- `/private/tmp/papernest-opaque-navigation-audits.log`: **both audits still failed, exit 65**, 900-second bound. Initial audit unchanged: 19 Dynamic Type + 2 clipped-Style contrast activities. Scrolled audit decreased from 13 contrast activities to 9; the four Cancel/Add activities disappeared. Remaining cropped chooser content still fails. No assertion or issue filter changes. This is a toolbar improvement, not a passing accessibility audit.
- Activity associations exported in `docs/screenshots/opaque-nav-scrolled-issues.json`. Inspected full screenshot `opaque-nav-shape-dark-ipad.png` and selected remaining issue crops; opaque backing removes chooser text behind the toolbar while below-edge obscured content remains. `/private/tmp/papernest-opaque-nav-unit.log`: **502 tests passed, exit 0** (64 UI + 143 Store + 125 Import + 122 Export + 48 Core). `/private/tmp/papernest-opaque-nav-mac.log`: **passed, exit 0**; no compiler warnings/errors in either log, both bounded to 600 seconds. `/private/tmp/papernest-opaque-nav-localized.log`: **passed, exit 0**, 90.407 seconds, 900-second bound: dark iPad en/fr/es shape/stamp selection/cancel and Comments editor navigation.
- Restored iPad light. Final source not checked on iPhone, light mode or largest text; native Mac interaction/VoiceOver/device checks remain unrun. No files staged or committed.

## 2026-10-29 UTC — Scrolled audit evidence mapped completely

- Reviewed all 11 available element crops from the 13 saved contrast activities in `visible-style-activity-associations.json`, plus `fully-visible-shape-style-dark-ipad.png`. Activity numbers match `visible-style-issue-N.png`: 1/8 Cancel, 2/9 Add; 4/5 blurred first-row shape labels, 6 Line, 7 Arrow; 11/12 blurred first-row stamp labels, 13 Star. Activities 3/10 have no element screenshot and are not assigned a label. Twelve activities say Contrast failed, one (12) Contrast nearly passed. Four console error lines were grouped reports, not a count of affected elements.
- Full Shape image shows Style fully visible but chooser rows scrolled into the translucent navigation/scroll-edge region. This explains where the blurred crops come from, not whether the accessibility audit is a false positive. Visible Cancel/Add findings and obscured chooser-label findings must be investigated separately. No sampled solid-colour ratio is a substitute for runtime contrast across these composited states.
- Next targeted experiment: inspect the sheet navigation/scroll-edge background treatment against both initial and scrolled audits, and retain chooser accessibility/scroll reachability. Do not recolour the selected tile based on the earlier incorrect attachment association; do not suppress issues. Initial clipped-Style finding remains open.
- Evidence review only: no new tests/builds, source changes, simulator changes, staging or commits. Existing audit results remain failed; native Mac, VoiceOver and device checks remain unrun.

## 2026-10-29 UTC — Correct audit association and visible-Style diagnostic

- **Correction to the two preceding contrast reviews:** `xcresulttool get test-results activities` associates the original dark audit's two contrast failures with **Style**, both using the same clipped-heading payload. Rectangle/Add were neighbouring exported attachments, incorrectly paired by list position. Prior pixel calculations concern unrelated crops, not the failing elements. Saved exact activity associations in `docs/screenshots/dark-audit-contrast-activity-associations.json`; inspected corrected crop `dark-audit-style-contrast-corrected.png`. No app palette change made on the incorrect attribution.
- Added separate `testVisibleAnnotationStyleContrast`, keeping the original initial-viewport audit unchanged. It scrolls the Form left margin, asserts Style is fully within an inset visible viewport and hittable, captures a screenshot, then audits contrast/clipping. No issue suppression; final version continues after findings to collect Shape and Stamp. Test-only change, English, ordinary-size dark iPad.
- First run `/private/tmp/papernest-visible-style-dark.log`: **failed, exit 65**, 20.224 seconds; stopped after Shape contrast failure. Its actual activity-linked crop is Cancel (saved `visible-style-dark-contrast-failure.png`). Final collection run `/private/tmp/papernest-visible-style-dark-all.log`: **failed, exit 65**, 35.749 seconds, four error lines; activity tree has repeated issue activities. Fully-visible Style assertions completed on both sheets. Saved `visible-style-activity-associations.json` and available element crops `visible-style-issue-*.png`; inspected first two (Cancel, Add). Other issue crops remain to inspect before attributing all failures. Both runs bounded to 900 seconds.
- This does not establish a passing contrast audit, nor justify suppressing the initial clipped-Style finding. Next inspect the remaining activity-linked crops and the scrolled toolbar backgrounds; do not use export-list adjacency. iPad restored light. No app/backend edits or fresh unit/Mac runs. No staging/commits.

## 2026-10-29 UTC — Codex contrast evidence review (association corrected below)

**Correction, 09:35 UTC:** Rectangle/Add were neighbouring attachments, not the contrast failures. The activity tree links both contrast issues to the clipped Style heading. Pixel calculations below describe unrelated crops and must not guide fixes.

- Inspected the saved dark Rectangle/Add element crops and the full Shape audit screenshot. PIL RGB histogram: Rectangle dominant background `(59,60,71)`, solid text `(255,255,255)`; Add dominant background `(37,37,39)`, solid accent `(165,176,255)`. Standard sRGB relative-luminance calculation gives approximately **10.92:1** and **7.47:1** for those specific pairs. This samples solid screenshot pixels only, excludes antialias edges and alternate states, and is **not** a replacement for the failed accessibility audit or evidence of a false positive.
- Source inspection: chooser selected fill uses `Theme.accent.opacity(0.12)`, title inherits plain button text, Add uses native toolbar styling; dark Theme accent is `0xA5B0FF`, matching the crop. No palette change justified solely by these crops. Next compare issue-to-element attachment association and runtime audit state, including any text-size/state transitions; retain all failure assertions. Full screenshot still shows Style at lower viewport boundary; do not dismiss its light-mode finding.
- Evidence-only review; no tests/builds rerun, no source/backend edits, no staging or commits. Existing 21-finding dark audit remains failed. Usage was 87% consumed at start; handoff kept current.

## 2026-10-29 UTC — Codex current dark iPad audit findings

**Correction, 09:35 UTC:** The counts remain valid; the Rectangle/Add attribution below was wrong. Both contrast findings belong to Style. Use the activity-tree associations, not exported-list adjacency.

- `/private/tmp/papernest-final-dark-audit.log`: **failed, exit 65**, existing four-sheet audit under 900-second bound. Current dark iPad source: **21 findings**, 19 “Dynamic Type font sizes are partially unsupported” and 2 “Contrast nearly passed”; no clipping findings. No suppression or expected-failure filters. Interaction successes do not imply audit success.
- Exported attachments to `/private/tmp/papernest-final-dark-audit-evidence`. Inspected both contrast element screenshots: selected Rectangle title and Add button, retained as `docs/screenshots/dark-audit-rectangle-contrast.png` and `dark-audit-add-contrast.png`. These are concrete contrast targets; do not assume all current findings concern toolbars. The prior light-mode Style finding remains unresolved; absence in this dark run does not close it.
- Restored iPad light. No source/test/backend edits or fresh unit/Mac build. Native Mac/VoiceOver/device checks not run. Nothing staged or committed.

## 2026-10-29 UTC — Codex iPad offscreen Thick tap investigation

- Unchanged dark iPad rerun `/private/tmp/papernest-dark-ipad-reproduce.log` reproduced the missing `shape-width-4` failure after tapping, exit 65, 51.074 seconds. Original recording frames inspected and retained as `docs/screenshots/dark-ipad-thick-offscreen-before.png` and `dark-ipad-thick-sheet-dismissing.png`: Thick was below the sheet's visible area, then the sheet dismissed. The helper trusted `isHittable` and assumed the final collection view was the Form; logged drag bounds instead matched the sidebar.
- Test-only `reveal` helper now excludes named Sidebar/Pages collections, intersects Form/screen/navigation bounds, requires the whole target inside that viewport plus hittability, and scrolls slowly with endpoint hold along the Form's left margin. Selection, picker and saved-row assertions unchanged. No app/backend code or user-facing strings changed.
- Failed experiments retained: `/private/tmp/papernest-dark-ipad-visible-control.log` (containment with old collection order), `/private/tmp/papernest-dark-ipad-form-selection.log` (correct collection but right-edge drag), `/private/tmp/papernest-dark-ipad-form-center.log` (centre overlaps interactive preview); all exit 65. Right-edge repeated drags left content unchanged; centre run left Position partially below the sheet. Final left-margin `/private/tmp/papernest-dark-ipad-form-margin.log` **passed, exit 0**, 74.871 seconds: slider, Thick, real system color popover, save and saved markup row. All runs bounded to 900 seconds.
- Final iPad width screenshot `docs/screenshots/form-margin-readable-large-text-width-ipad.png` inspected: Thick fully visible and selected; sheet stays open. Position/picker screenshots also exported. Restored iPad light. iPhone light largest-text helper regression `/private/tmp/papernest-form-margin-phone.log` **passed, exit 0**, 66.595 seconds, also bounded to 900 seconds; full slider/width/picker/save/saved-markup flow. Final helper not rerun on iPad light or iPhone dark; earlier results on those combinations used the preceding helper. No fresh unit/Mac runs for test-only change; full audit/native/VoiceOver/device gaps remain open. Nothing staged or committed.

## 2026-10-29 UTC — Codex dark iPad largest-text failure

- `/private/tmp/papernest-final-dark-large-ipad.log`: **failed, exit 65**, 52.001 seconds, bounded to 900 seconds. Existing `testLargeTextShapeSlidersAndSystemColorPicker` on final source, dark iPad Air 13 M4. Sidebar check and start-X slider interaction completed; failure at AppUITests.swift:1305 querying `shape-width-4` after tapping Thick: “Failed to get matching snapshot: No matches found”. System picker and save/Manage Markup checks were **not reached**. Root cause not established; do not call this a verified app defect or a harmless test flake.
- Exported attachments to `/private/tmp/papernest-final-dark-large-ipad-shots`; hierarchy copied to `/private/tmp/papernest-dark-large-ipad-failure-hierarchy.txt`. Position screenshot retained at `docs/screenshots/dark-large-ipad-failure-6195F497-3557-417A-8739-095EA0658DDE.png` (not visually inspected this pass). Next: compare the failed hierarchy/recording and reveal helper's scrolling at the Thick selection; preserve the assertion and reproduce before changing code.
- Restored iPad light. No source/test/backend edits, no new unit/Mac runs, nothing staged or committed. Prior light iPad and dark phone successes do not close this dark iPad failure. Usage was 89% consumed at the start; preserved handoff for continuation.

## 2026-10-29 UTC — Codex final iPhone dark-mode annotation verification

- `/private/tmp/papernest-final-dark-phone.log`: **2 passed, exit 0**, 156.647 seconds under a 900-second bound. Existing localized annotation test passed English/French/Spanish shape/stamp selection/cancel and Comments editor navigation. Existing largest-text test passed English start-X slider, Thick width selection, actual system color picker interaction, shape save and saved markup row verification. Final source, iPhone 17 Pro, dark appearance.
- Exported 12 screenshots as `docs/screenshots/final-dark-*-iphone.png`. Inspected Spanish Comments, English largest-text width and system picker: ordinary Comments labels/help fit; largest-text width choices and selected checkmark readable; actual native picker visible. Content scrolls beneath the fixed toolbar at largest size; this pass does not resolve the separate toolbar Dynamic Type/contrast audit findings. Restored iPhone to light.
- No app/test/backend edits. No fresh unit suite or Mac build for this verification-only pass. Full audit, localized largest-text flows, native Mac interaction, VoiceOver, injected disk I/O failure and physical camera remain unrun here. No files staged or committed.

## 2026-10-29 UTC — Codex final annotation dark-mode regression

- `/private/tmp/papernest-comments-final-dark-ipad.log`: existing `testAnnotationStyleLayoutInAllLanguages` **passed, exit 0**, 91.121 seconds, under a 900-second bound. iPad Air 13 M4 in dark mode, ordinary text, English/French/Spanish: shape/stamp chooser selection and cancellation plus Comments add/editor/cancel navigation. Final Comments wrapping and two-column chooser source exercised; no source or test edits.
- Exported nine screenshots as `docs/screenshots/final-dark-readable-*-ipad.png`. Visually inspected French Comments, Spanish Shape and English Stamp: title/help readable, chooser labels fit, selection checkmark visible. Style remains below the initial viewport; this is not evidence resolving its audit finding. Restored iPad to light appearance.
- No fresh unit/Mac build (verification-only pass); previous 502-test/build results are historical. Full accessibility audit, largest text, iPhone dark mode, native Mac interaction, VoiceOver and physical camera not run here. Desktop-control tools remain unavailable. Existing audit failures remain open. Backend untouched; nothing staged or committed.

## 2026-10-28 — Codex Add Comment clipping investigation

- Repeated audit finding was on the Add Comment title. First experiment put vertical fixed-size wrapping on the title inside Label: `/private/tmp/papernest-comment-title-audit.log` still reported Text clipped, exit 65. Replaced that with an explicit first-baseline HStack, decorative icon hidden from accessibility, and wrapping localized title; retained the button, identifier, 44-point minimum and save availability rules.
- `/private/tmp/papernest-comment-row-audit.log`: overall **failed, exit 65**, but Add Comment clipping no longer reported. Toolbar contrast/Dynamic Type and other-sheet failures remain, with no audit suppression. Backend untouched.
- `/private/tmp/papernest-comment-row-ipad.log`: **1 passed, 1 failed overall, exit 65**. The four-sheet audit retained 27 findings (toolbar contrast/Dynamic Type and Style heading contrast), but no Add Comment clipping. The existing English/French/Spanish annotation-style and Comments editor navigation flow passed in 88.213 seconds. Both simulator runs bounded to 900 seconds; no issue filters or weakened assertions.
- `/private/tmp/papernest-comment-row-unit.log`: **502 tests passed, exit 0**; `/private/tmp/papernest-comment-row-mac.log`: **build passed, exit 0**. Both bounded to 600 seconds, no compiler warnings/errors. Saved and visually inspected `docs/screenshots/comments-wrapping-iphone.png` and `docs/screenshots/comments-wrapping-fr-ipad.png`: ordinary-size labels/help fit. Final change checked in light mode; no dark-mode, VoiceOver, native Mac interaction, physical camera, or maximum-size screenshot claim. No files staged or committed.

## 2026-10-28 — Final single-column dashboard phone check

- `/private/tmp/papernest-dashboard-ax-phone-final.log`: **1 passed, exit 0**, 900-second timeout. Final grid source passes largest-text phone branding/navigation assertions and opens notebook creation. Screenshot `docs/screenshots/dashboard-single-column-largest-iphone.png` exported and inspected: branding and Note label fit; other actions require scrolling. English/light only; no full accessibility audit or localized maximum-type claim. No source changes or repeat unit/Mac builds in this verification-only pass. Remaining failures and native/device gaps unchanged. Nothing staged/committed.

## 2026-10-28 — Codex sidebar-root dashboard regressions

- No source edits; checking final sidebar preference placement. Phone `/private/tmp/papernest-sidebar-regression-phone.log`: **2 passed, exit 0**, dashboard create/reopen and layout in en/fr/es plus largest-text notebook entry and compact navigation. 900-second bound. Screenshots exported as `sidebar-regression-*-iphone.png`; largest-text Home inspected.
- Dark iPad `/private/tmp/papernest-sidebar-regression-ipad.log`: **2 passed, exit 0**, same en/fr/es dashboard and maximum-type notebook entry. Exported `sidebar-regression-*-ipad.png`. Screenshot review found a visual regression despite passing interactions: the now-wider sidebar left two accessibility-size action columns narrow enough to hyphenate Notebook.
- Fixed only `LibraryHome.swift` quick-action grid: a single flexible column at accessibility sizes, existing ordinary-size layouts retained. Final `/private/tmp/papernest-dashboard-ax-single-column.log`: largest-type dark iPad test **passed, exit 0**; inspected `dashboard-single-column-largest-ipad.png`, New Notebook fits on one line with readable hint. `/private/tmp/papernest-dashboard-ax-unit.log`: **502 passed**, exit 0 (64 UI + 143 Store + 125 Import + 122 Export + 48 Core); `/private/tmp/papernest-dashboard-ax-mac.log`: passed, exit 0. No compiler warnings/errors. Unit/Mac bounded to 600 seconds; UI to 900. iPad restored to light.
- Final single-column source not rerun in French/Spanish, phone, or native Mac interaction; localized phone/iPad tests above preceded that small change. No passing full audit claimed. Remaining contrast/Dynamic Type/Comments clipping, landscape, native VoiceOver/two-window and camera gaps remain. No files staged/committed.

## 2026-10-28 — Codex large-text sidebar width restored

- The width preference was attached to the nested List after the dashboard introduced a ScrollViewReader. Moved `navigationSplitViewColumnWidth` to the outer sidebar ScrollViewReader in `RootView.swift`; unchanged min/ideal values, no new strings or backend changes. The existing >=400-point test was kept unchanged.
- `/private/tmp/papernest-sidebar-root-ipad.log`: **passed, exit 0**, 80.158 seconds, 900-second bound. Full largest-type iPad flow now passes: sidebar width assertion, start-X slider, Thick width, real system color picker/popover dismissal, save and saved stroke in Manage Markup. Exported `sidebar-root-*-ipad.png`; position screenshot inspected and confirms a wider sidebar with All Documents on one line. Light mode, English only for this final source change.
- `/private/tmp/papernest-sidebar-root-unit.log`: **502 tests passed**, exit 0 (64 UI + 143 Store + 125 Import + 122 Export + 48 Core), no compiler warnings/errors. Count includes Claude's concurrent backend additions; Codex did not edit them. `/private/tmp/papernest-sidebar-root-mac.log` passed, exit 0, no compiler warnings/errors. Both bounded to 600 seconds.
- Prior final-helper ordinary en/fr/es iPad Notes regression passed before moving the width preference. Final-source phone, ordinary-size/dark/localized sidebar and native Mac interaction not rerun; no passing full audit claimed. Existing toolbar contrast/Dynamic Type, Add Comment clipping, iPad Style viewport, native VoiceOver/two-window and camera gaps remain. No files staged or committed.


## 2026-10-28 — Codex held-drag iPad regression

- Final helper revision checked with existing largest-text and en/fr/es Notes tests under 900-second timeout: `/private/tmp/papernest-held-drag-ipad.log`. Largest-text flow **failed before reaching the shape sheet**: sidebar width 320 points vs existing minimum 400 at AppUITests.swift:1269. No assertion weakened; system sidebar constraint/readability needs investigation. This does not test the final helper at largest type on iPad. Recovered final result: ordinary en/fr/es Notes regression PASSED; **1 passed, 1 failed overall**, exit 65. This was before the RootView correction below. Screenshots exported as `held-drag-notebook-tool-bar-*-ipad.png`.

## 2026-10-28 — Codex largest-type shape flow and toolbar test scrolling

- Existing iPhone `testLargeTextShapeSlidersAndSystemColorPicker` rerun under 900-second timeout: `/private/tmp/papernest-large-shape-resume.log` **failed, exit 65**, at `revealEditorTool` for Manage Markup. It successfully adjusted start-X, selected Thick, changed the actual system picker color and saved before failing. The earlier width-selection failure did not reproduce.
- Log shows 16 alternating fixed 257-point toolbar drags overshooting the target at maximum Dynamic Type. Test helper now uses the clipped distance with bounded drag length; existing full-visibility/hittability assertions remain. No app or backend code changed. First proportional-distance rerun `/private/tmp/papernest-large-shape-scroll-fix.log` still failed the largest-type flow at the same helper: drags of 80–120 points still alternated across the target. That run passed the ordinary-size en/fr/es Notes toolbar regression (1 passed, 1 failed overall). Final helper requests slow velocity and a 0.3-second endpoint hold to stop scrolling momentum. `/private/tmp/papernest-large-shape-scroll-held.log` **passed, exit 0**: largest-type slider, Thick selection, actual system color picker, saved shape and Manage Markup row verification, 71.654 seconds. Existing visibility/hittability checks remain. Final-version ordinary-type multilingual regression and iPad were not rerun; the earlier ordinary-size pass used proportional distance without the endpoint hold. No app source changed, so unit/Mac commands were not repeated for this test-helper-only revision; previous 496-test/Mac results are historical, not new runs. Failure-run screenshots retained as `resumed-*-iphone.png` (width screenshot inspected); final passing-run screenshots exported as `verified-*-iphone.png`. Broader audit contrast/Dynamic Type/Add Comment clipping findings, native Mac/VoiceOver/two-window checks and real camera remain open. No files staged or committed.

## 2026-10-28 — Codex shape/stamp chooser width

- Prior iPad screenshot showed English Rectangle hyphenated in a three-column adaptive grid. Ordinary-size chooser now uses two flexible columns on all platforms; accessibility sizes retain the existing full-width rows. No label, action, backend or localization changes.
- Recovered final bounded results after the usage interruption: `/private/tmp/papernest-chooser-unit.log` passed 496 tests, exit 0; `/private/tmp/papernest-chooser-mac.log` passed, exit 0, no compiler warnings/errors. `/private/tmp/papernest-chooser-ipad.log` passed the localized interaction test in en/fr/es, exit 0. Exported screenshots as `docs/screenshots/chooser-readable-*-ipad.png` and inspected all three Shape screenshots: Rectangle/Rectángulo now fit on one line. This was light mode, ordinary type. Matching iPhone `/private/tmp/papernest-chooser-phone.log` passed, exit 0: en/fr/es shape/stamp selection, cancel and Comments editor navigation. Screenshots exported as `chooser-readable-*-iphone.png`; Spanish Shape inspected with all four labels fitting. Dark mode and accessibility-size chooser were not rerun for this width change. Nothing staged or committed. No claim that the wider audit is resolved; toolbar Dynamic Type/contrast, Add Comment clipping and iPad Style viewport finding remain open.

## 2026-10-28 — Codex annotation text contrast continuation

- Applied explicit `Color.primary` to Shape/Stamp help and Style heading, plus Manage Markup Saved Marks heading, empty state and help. The preceding Comments pass demonstrated that hierarchical `.primary` inherits the Form footer color; explicit system primary text avoids it and adapts to dark mode. No strings, operations or backend files changed.
- `./scripts/test.sh`: `/private/tmp/papernest-sheet-contrast-unit.log`, exit 0, **496 passed** (64 UI + 143 Store + 121 Import + 120 Export + 48 Core), no compiler warnings/errors. Mac build `/private/tmp/papernest-sheet-contrast-mac.log`: exit 0, no compiler warnings/errors. Both bounded to 600 seconds.
- iPhone existing four-sheet accessibility audit: `/private/tmp/papernest-sheet-contrast-phone.log`, **failed overall, exit 65**, bounded to 900 seconds. Changed text no longer reports contrast failures. Remaining contrast findings are toolbar Cancel/Add/Done buttons; Dynamic Type findings and Add Comment clipping remain. No issue filters or suppression added. Ordinary-size Shape and Manage Markup screenshots inspected; four screens retained as `docs/screenshots/contrast-accessibility-audit-editor-*-iphone.png`.
- iPad dark run `/private/tmp/papernest-sheet-contrast-ipad.log`: **1 passed, 1 failed**, exit 65. `testAnnotationStyleLayoutInAllLanguages` passed en/fr/es shape/stamp selection, cancel and Comments editor navigation. Four-sheet audit still fails: Shape Style contrast, Dynamic Type findings and Add Comment clipping remain. Shape screenshot shows Style partially below the sheet viewport; the report is retained, not dismissed as a false positive. Ordinary-size English Rectangle also hyphenates in the three-column chooser. These need follow-up layout/scroll investigation. Screenshots exported before pruning as `contrast-*-ipad.png`; inspected English Shape and French Comments (dark appearance confirmed). iPad restored to light. Native Mac interaction, VoiceOver, physical camera and two-window conflicts remain unrun. Tools redesign remains pending. Nothing staged or committed.

## 2026-10-28 — Codex resumed verification and Comments contrast

- Usage check allowed ordinary work. Shared index empty; Claude backend files left untouched. No native desktop-control tools exposed in this session. Bounded device listing `/private/tmp/papernest-resume-devices.log` exited 0 and found only the Mac and simulators, no physical iPhone/iPad. Native Mac interaction, VoiceOver, two-window conflicts and real camera remain unrun.
- Baseline `./scripts/test.sh`, bounded to 600 seconds: `/private/tmp/papernest-resume-unit.log`, exit 0, **496 tests passed** (64 UI, 143 Store, 121 Import, 120 Export, 48 Core). No compiler warnings/errors in log. Mac build `/private/tmp/papernest-resume-mac.log`, exit 0. These ran before the two comment text-style changes below.
- Existing four-sheet iPhone audit, 900-second bound: `/private/tmp/papernest-resume-annotation-audit.log`, **failed, exit 65**. Shapes/stamps: Dynamic Type and contrast findings; Comments: Add Comment potential clipping at larger sizes, Done Dynamic Type/contrast, empty-state/help contrast; markup manager: Done Dynamic Type and multiple contrast findings. No audit issues suppressed. `Test-PaperNest-iOS-2026.10.28_02-20-38--0500.xcresult`; attachments exported to `/private/tmp/papernest-resume-audit-shots` before pruning. Four ordinary-size screens saved as `docs/screenshots/resume-accessibility-audit-editor-*-iphone.png`; Comments screenshot inspected. Ordinary-size visibility does not clear the large-type clipping finding.
- First correction: Comments empty-state and privacy footer used hierarchical primary text contrast. `/private/tmp/papernest-resume-comments-contrast.log` still failed (exit 65), but the empty-state finding disappeared. Footer contrast remained, so its style now uses explicit `Color.primary` rather than an inherited hierarchical style. Final audit `/private/tmp/papernest-resume-comments-final.log` **failed overall, exit 65**, but neither the empty-state nor privacy-footer contrast finding remains. Comments still has Add Comment clipping and Done Dynamic Type/contrast findings; other sheets remain failing. Final Mac build `/private/tmp/papernest-resume-comments-final-mac.log` passed with no compiler warnings/errors. Final screenshot saved as `docs/screenshots/resume-comments-contrast-iphone.png`. No iPad/dark/localized rerun for this two-style correction; no claim those checks passed. No issues suppressed. Nothing staged or committed. `/private/tmp/papernest-resume-comments-unit.log` passed 496 tests, no compiler warnings/errors; `/private/tmp/papernest-resume-comments-mac.log` passed. These two checks precede the final explicit-color adjustment.


## 2026-10-27 — Codex Notes toolbar and first-launch welcome

- Notes actions now appear side by side in a labeled horizontal scrolling row; main actions do not require More. Rotate/filter retain parameter menus. Existing localized labels reused. Toolbar remains when empty so Add Notebook Page/Undo stay available. Compact page viewer receives drawing state.
- Notes phone: `/private/tmp/papernest-note-bar-phone-final.log`, **passed**, exit 0: en/fr/es direct Shape save, Undo/Redo, Add Page/cancel, Comments, delete last page, Undo and add again. First run `/private/tmp/papernest-note-bar-phone.log` failed on offscreen hittability; helper fixed to check geometry before dragging inside the row. Initial English screenshot saved/inspected. Final result bundle was pruned before its localized screenshots could be exported; those images are not claimed reviewed.
- Notes iPad initial `/private/tmp/papernest-note-bar-ipad.log`: **1 failed, 1 passed**, exit 65. Imported-document shape/history passed. Notebook test failed revealing Comments because the reported scroll frame includes the sidebar; helper now clips gestures to the editor column. Rerun pending.
- Welcome: native one-screen introduction, persistent Get started, no account/permission demand; en/fr/es copy, Mac-specific import wording. Existing UI tests bypass via debug-only flag; welcome tests use isolated persistent keys.
- Current-tree `./scripts/test.sh`: `/private/tmp/papernest-welcome-unit.log`, **423 passed**, exit 0 (64 UI, 127 Store, 89 Import, 101 Export, 42 Core); Mac build `/private/tmp/papernest-welcome-mac.log` passed exit 0. No Swift compiler warnings/errors. Claude's concurrent backend additions account for count changes; Codex changed no backend. Welcome simulator checks pending.
- Welcome phone first run `/private/tmp/papernest-welcome-phone.log` failed: an identifier on the outer container propagated to the button and ScrollView, hiding their test identifiers. Removed that container identifier. `/private/tmp/papernest-welcome-phone-final.log`: **2 tests passed**, exit 0, localized first-launch/continue/relaunch and French largest-type continue. Screenshot review prompted smaller illustration spacing and clipping at the safe-area edge; final polish rerun pending.
- `/private/tmp/papernest-welcome-notes-ipad-final.log`: **2 welcome tests passed, 1 Notes test failed**, exit 65. Welcome en/fr/es persistence and largest French type passed in dark mode; screenshots exported. Notes completed English but the French selector used the localized system label “Sidebar”, so dragging again landed outside the editor. Changed it to locate the sidebar by the stable Home button identifier; rerun pending.
- Final welcome phone polish `/private/tmp/papernest-welcome-phone-polished.log`: **2 passed**, exit 0. Inspected en/fr/es and maximum French type screenshots: English/Spanish full intro fits, French third feature requires scrolling, CTA stays fixed; scrolled text now clips below the status area. Final Mac compile `/private/tmp/papernest-welcome-mac-polished.log` passed, no Swift warnings/errors. `/private/tmp/papernest-welcome-unit-final.log` again passed **423 tests** after localized copy changes. Standard Xcode AppIntents metadata/OS-version diagnostics remain toolchain messages, not Swift compiler warnings.
- Fresh read-only reviews: Notes empty-page toolbar loss fixed and covered by deletion/undo workflow. Welcome Mac subtitle no longer mentions camera scanning in French/Spanish. No additional concrete review findings.
- Final iPad `/private/tmp/papernest-notes-ipad-localized.log`: **2 passed**, exit 0. Full Notes workflow passed in en/fr/es (direct tools, scroll both directions, shape save, history, page creation/cancel, Comments, last-page deletion and recovery); final clipped welcome remains usable at maximum French type in dark mode. The two intermediate iPad Notes failures above are resolved by a locale-independent sidebar selector plus viewport-aware gestures. Saved toolbar screenshots in en/fr/es; inspected French plus earlier English layout. Welcome screenshots inspected in all three languages on both devices and maximum French type; iPad restored to light.
- Scope: focused regressions, not a complete app suite or accessibility audit. No files staged or committed.
- Native Mac interaction, VoiceOver, new largest-type Notes audit, real Pencil/camera, prior rotation and annotation-audit failures are not cleared by these runs.


## Premium reference redesign — Codex, 2026-10-27 (implemented; open verification findings)

- Owner deferred Vault and VPN to the next version. No protection UI or fake states added. Live dashboard uses real summaries and existing notebook/import/folder flows.
- First Mac build passed, exit 0: `/private/tmp/papernest-premium-build.log`. Later navigation changes still being checked.
- Full unit command `/private/tmp/papernest-premium-unit.log` exited 1: UI 64, Store 123, Import 77, Core 42 passed; Export ran 89 with two assertions failing in Claude’s active `aMixedDocumentExportedWithAPasswordKeepsEveryPage` at EncryptedExportTests:161/163 (drawn second-page text and title missing). Backend left untouched; this is not a green full run.
- After Claude’s backend fix, `/private/tmp/papernest-premium-unit-final.log` passed 397 tests. Following the accessibility-layout revision and newer shared-tree backend changes, `/private/tmp/papernest-premium-unit-accessible.log` passed **411 tests** (64 UI + 126 Store + 86 Import + 93 Export + 42 Core), exit 0, no compiler warnings/errors.
- Initial phone run: localized notebook creation/reopening and grid/list/crop/export passed; Home Recent failed because the new VStack did not expose a containing accessibility element. Added `.accessibilityElement(children: .contain)`. Xcode subsequently stalled in post-test `simctl diagnose`; interrupted only this run/diagnostic child (exit 75). Later runs use `-collect-test-diagnostics never` plus 900-second timeout; no test failures are suppressed.
- `/private/tmp/papernest-premium-phone-final.log`: **5 tests passed**, exit 0. Recent opening/See All, grid/list → rotate/crop/export, en/fr/es dashboard notebook creation/reopening, actual folder creation, and largest-type notebook entry. `/private/tmp/papernest-premium-ipad.log`: **4 passed**, exit 0, dark mode: same localized dashboard flow, folder creation, largest-type entry, and Home → Favorites → Home → same Favorites plus multi-character global search. Screenshots inspected in all three languages.
- Screenshot review found poor largest-text phone branding/tab wrapping despite the interaction test passing. Revised header to stacked text/settings, bottom navigation to a full-width menu at accessibility sizes, shortened localized compact action labels, made decorative action icons fixed-size, replaced the large-type Recent segmented picker with a menu, and hid large-type sidebar badges to free label width. New phone regression assertion rejects a fragmented multi-line brand. Final phone rerun `/private/tmp/papernest-premium-phone-accessible.log` passed both localized dashboard and largest-type tests, exit 0; inspected and replaced screenshots. Brand now fits on one line; compact en/fr/es action labels fit. Final Mac build `/private/tmp/papernest-premium-mac-accessible.log` passed, exit 0, no Swift compiler warnings/errors.
- Read-only independent review found retained Home selection, search field destruction after the first character, and missing dashboard drop/paste import. Fixed with an explicit sidebar binding, search submission into All Documents, and dashboard drop/paste handlers. Native Mac drop/paste interaction remains unrun.


### Final coverage and limits

- `/private/tmp/papernest-premium-ipad-accessible.log` passed the largest-type interaction and an initial rotation smoke check. **Do not count that initial rotation check as landscape coverage:** screenshot inspection showed portrait. Strengthened the test to rotate after launch and assert actual window dimensions. `/private/tmp/papernest-premium-ipad-landscape.log` then **failed**, exit 65: app remained 1024×1366 after requesting landscape. Both source and built Info.plist allow all four iPad orientations. Cause remains unresolved; no orientation entitlement or fullscreen workaround was added. `testPremiumLandscapeDashboard` remains an unsuppressed regression check. Screenshot retained as `premium-home-rotation-attempt-ipad.png`, not advertised as landscape.
- Final iPad largest-type screenshot shows readable dashboard controls and an adaptive Recent menu; **sidebar “All Documents” still hyphenates awkwardly** in the system-constrained column, even with badges removed. Not claimed fixed. Phone maximum-type header and bottom navigation no longer fragment their words. These are visual/interaction checks, not a passing full accessibility audit.
- Saved/inspected `docs/screenshots/premium-home-{en,fr,es}-{iphone,ipad}.png`, matching library images and both largest-type images. Phone light, iPad dark. iPad appearance restored to light. No real documents or invented production folders/users were used.
- Native Mac build is verified; native Mac clicking, keyboard shortcut/focus/hover behavior, drag/paste interaction, VoiceOver, Reduce Motion/Transparency interaction, narrow multitasking windows and real camera capture remain unrun. Computer-use tools are still unavailable. Existing annotation audit failures and the prior Thick-width test failure remain open in the preceding audit record.
- Reference differences are deliberate where no service exists: owner deferred Vault/VPN; no fake profile/avatar, Shared collaborators or encrypted storage. Note action opens the real notebook editor, not a new rich-text service. Native camera remains VisionKit; Mac has no camera shortcut without a capture implementation. Folder names/data stay user-owned; no sample folders are seeded. Global search uses the native search field, without a new ⌘K command. The entire reference brief is **not claimed complete**.
- All changes left uncommitted and unstaged. Review findings resolved in UI only; Claude’s backend changes untouched. Build/test timeouts: 600 seconds units/Mac, 900 seconds XCUITest. Xcode logs its existing AppIntents metadata and OS-build diagnostics; no Swift compiler warnings found in the final builds.

## UI readability polish — Codex, 2026-10-26 (superseded by reference redesign; open audit findings)

- UI-only: adaptive shape/stamp chooser at ordinary sizes, full-width stroke-width rows at accessibility sizes, primary-contrast wrapping help and Add Comment text, wider text-first iPad sidebar at accessibility sizes. Existing L10n en/fr/es strings reused; no backend changes.
- Full unit suite **360 passed** (64 UI + 123 Store + 77 Import + 54 Export + 42 Core), exit 0, no compiler warnings/errors: `/private/tmp/papernest-polish-unit-final.log`. Mac build exit 0, no compiler warnings: `/private/tmp/papernest-polish-mac.log`. Both bounded to 600 seconds.
- Localized shape/stamp/comment flows passed on phone (light) and iPad (dark), en/fr/es. Reviewed source units and Mac build also passed: `papernest-polish-unit-reviewed.log`, `papernest-polish-mac-reviewed.log`.
- `/private/tmp/papernest-polish-ipad.log` failed overall: the unsuppressed four-sheet accessibility audit still flags Dynamic Type, Style contrast and comment clipping. The largest-type flow reached Line width but lost the sheet after tapping Thick; cause not resolved, and that flow is **not passed**. Its slider screenshot confirms wider text-first sidebar labels. Keep this separate from later dashboard tests. New reference redesign supersedes colors; native Mac/VoiceOver and real-device camera are still unrun. Nothing staged or committed.

## Text to PDF — Claude, 2026-10-26

Half of ledger row 33, and the reference converter's "Text to PDF". A `.txt` was kept as an opaque file item — previewable and shareable, but with no pages, so it could not be annotated, cropped, reordered or exported. `TextToPDF.render` lays it out with CoreText and `DocumentImporter.importTextAsDocument` puts the result through the ordinary import path, so it becomes a normal document. No schema change, no new strings.

- **Pagination is real, not estimated, and that is the point of the slice.** `CTFramesetter` breaks the lines and `CTFrameGetVisibleStringRange` reports how much of the string each page actually consumed. Estimating by character count falls apart as soon as a line wraps, and whatever runs past the bottom of the frame is silently lost — a conversion that looks clean and is not. `textLongerThanAPageBreaksAcrossPagesWithNothingLost` probes lines 1, 50, 99, 100, 101, 150 and 200 **by number** across the break, so a dropped line is obvious rather than plausible.
- A line wider than the page wraps rather than clipping — all 80 occurrences of the probe word survive — and a single unbreakable 400-character word still appears, so CoreText's character fallback is exercised rather than assumed.
- **The pages carry real text, not a picture of it**, proved by extracting it back with `PDFTextExtractor` from the vector-PDF indexing slice. A converted document is therefore searchable by its own words with no recognition involved, which `theConvertedDocumentIsSearchableByItsOwnWords` asserts alongside `recognition(for:) == nil`. That round trip is the strongest available evidence that nothing was dropped.
- **Conversion is explicit.** Importing a `.txt` still stores it as a file item exactly as before; `importingATextFileNormallyStillKeepsItAsAFile` pins that, because keeping a file as the bytes it arrived with is the right default and existing behaviour depends on it.
- Empty or whitespace-only text is refused with `ImportError.empty` rather than producing a blank one-page document, and the refusal leaves nothing in the library.
- Test-first reds: 16 × missing `TextToPDF`, then 8 × missing `importTextAsDocument`. A missing `import PaperNestCore` was corrected before the green run. Greens: `green-txt2pdf.log` (7), `green-txtconv2.log` (12).
- **Final full suite: 360 passed** (64 UI + 123 Store + 77 Import + 54 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-txt2pdf.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED.
- **Not run / not claimed:** **no UI offers the conversion** — there is no "Text to PDF" action in any screen, so this is not user-reachable. No independent reviewer pass; no native Mac, iOS interaction or real-device check. Helvetica at 11pt on A4 with 54pt margins is hard-coded: no font, size, paper or margin choice, and no right-to-left or vertical-script handling has been tested beyond the Cyrillic and Japanese strings in `accentsAndNonLatinTextSurvive`. DOCX, XLSX and PPTX to PDF are not here; they need a real Office renderer and belong to the F5 decision.
- Plan: `docs/superpowers/plans/2026-10-26-text-to-pdf.md`. Nothing committed.

## SQLite text truncation at a NUL — Claude, 2026-10-26

The finding from the DOCX slice, fixed. `SQLiteDatabase.bind` passed `-1` to `sqlite3_bind_text`, and `Statement.text` read with `String(cString:)`, so **both directions stopped at the first NUL** and one unprintable character took the rest of the string with it, silently. Both now use explicit byte counts.

- **The blast radius was narrowed before choosing a fix**, rather than patching the call site that happened to surface it: item and folder names are already sanitized at the edge (`LibraryModels.swift:118` filters control characters); `original_filename` comes from a filesystem where NUL cannot occur; and a recognition result travels as JSON, where a NUL is the escape `\u0000` and survives. What was genuinely reachable was text from recognition or a PDF flowing into `search_index.content`, which made a document **silently and partly unsearchable**.
- **Fixed the mechanism, not that one path.** `-1` plus `String(cString:)` is a trap for every text column anyone adds next, and the store is meant to be the single authority for metadata — one that does not return what it was given undermines that. `sqlite3_column_bytes` is called after `sqlite3_column_text`, which is the order that fixes the column's type and so its length.
- **The open question was whether FTS5 tolerates a NUL in content, and the test decided it rather than a guess.** It does: `wordsAfterANULAreStillFindable` passes, so `unicode61` treats it as a separator and the word after it indexes normally. The planned fallback — sanitizing indexed text at the edge, following the precedent names set — is therefore **not** needed, and no lossy cleanup was added that nothing requires.
- Test-first red, unusually legible: `red-nul.log` shows `"Before\u{0}After" → "Before"`, with round-trip, searchability and reopen-persistence failing while the ordinary-text control passed — which is what showed the defect was narrow rather than a general text regression. Green: `green-nul.log` (4 tests).
- **Final full suite: 348 passed** (64 UI + 123 Store + 65 Import + 54 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-nul.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. **This is the point of that run:** the change sits in the hot path of every text read and write — names, OCR, comments, tags, migrations, the search index, localization parity, the pixel-probe export checks — and nothing moved. Four focused tests would not have been evidence that it is safe.
- **Not run / not claimed:** no independent reviewer pass. No existing library has been opened with the new read path, only libraries created during the tests, so a migration-era database with unusual bytes is unexercised; nothing in the change is schema-dependent, but that is reasoning rather than a test. No native Mac, iOS interaction or real-device check. A NUL can now be stored, so anything that later renders stored text should strip control characters at its own edge the way the DOCX writer does — that is presentation, not storage.

## Basic DOCX export — Claude, 2026-10-26

F4's last export deliverable ("TXT and basic DOCX") and half of ledger row 34. A `.docx` is a ZIP of XML parts, so this writes the three a word processor needs — `[Content_Types].xml`, `_rels/.rels`, `word/document.xml` — through the existing `ZipWriter` rather than adding a dependency. Text follows the plain-text writer's precedence: recognition first, then the text a digital PDF carries; one paragraph per recognized line, an explicit page break between pages. **Basic means the words in a real Word file, not layout**: tables, columns and positioned images stay F5 rather than being approximated.

- **Escaping is the correctness story.** Recognized text is whatever was printed on the paper, so an ampersand is ordinary; one unescaped `&` or `<` yields a file no word processor can open. `ampersandsAndAnglesAreEscapedSoTheFileStillParses` feeds it `Tom & Jerry <b> "quoted" 5 > 3` and then parses the output with `XMLParser`. Characters XML 1.0 forbids are dropped rather than written, since one would make the whole document unreadable.
- Structure is verified **independently of the writer**: `/usr/bin/unzip` lists the parts and extracts them, and `XMLParser` parses `word/document.xml`, `[Content_Types].xml` and `_rels/.rels`. Same refusal as TXT: a document with no text throws `noTextToExport` instead of producing an empty Word file.
- Test-first red: 4 × missing `ExportFormat.docx`. Green: `green-docx3.log` (8 tests).
- **A finding in the store, recorded not fixed.** `SQLiteDatabase.bind` calls `sqlite3_bind_text(stmt, i, v, -1, SQLITE_TRANSIENT)` at `SQLite.swift:170`. Length `-1` makes the C API read to the NUL terminator, so **any string containing a NUL is silently truncated on the way into the database.** Found because a control-character test fed text through `indexEmbeddedText` and the text arrived as `Before` instead of `Before\0After\1End`. Not changed here: storing raw NULs in text columns is not obviously better than dropping them, item names are already sanitized deliberately (`cleansControlCharactersAndEmptyNames`), and changing bind semantics mid-feature would touch every text column. Worth a decision of its own. The test now uses the path where the escaper genuinely matters — a recognition result travels as JSON in `page_recognition`, where a NUL is the escape `\u0000`, survives storage and decodes back — so the drop behaviour is really exercised.
- **A build failure of my own making, worth knowing about.** The first run died on `codesign: invalid or unsupported format for signature` for `PaperNestImportTests.xctest`, with no compile error and no concurrent build. The bundle had been corrupted when I killed `swift-test` mid-build during the Vision deadlock investigation hours earlier, in the build cache both sessions share. Removing that one bundle fixed it. Killing a build here leaves debris that resurfaces later looking unrelated.
- **Final full suite: 344 passed** (64 UI + 119 Store + 65 Import + 54 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-docx.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED.
- **Not run / not claimed — the important one: nobody has opened the file in a word processor.** Structure is checked by `unzip` and `XMLParser`, which proves it is a well-formed OOXML package, **not** that Word, Pages or Google Docs renders it. That is whole-app verification and is recorded as owed in `docs/CODEX_BRIEF.md`; this must not be offered in any screen until someone has opened one. Also not here: no UI (no DOCX tile), no independent reviewer pass, no native Mac or iOS interaction check. Ink, text boxes and page comments are not exported; only recognized and embedded text is. Layout, fonts, styles, headers, images and tables are absent by design.
- Plan: `docs/superpowers/plans/2026-10-26-docx-export.md`. Nothing committed.

## App verification backlog — Codex, 2026-10-26 (first pass; open findings)

- Read CODEX_BRIEF, current ownership/claims and Vision trap before editing. No backend files changed; no staging or commit. Manual recognition in `DocumentModel` now awaits `recognizeOnADedicatedThread` instead of calling synchronous Vision on MainActor. Source inspection confirmed the blocking call; no before/after latency measurement is claimed.
- Full `./scripts/test.sh`: **336 passed** (64 UI + 119 Store + 65 Import + 46 Export + 42 Core), exit 0, no compiler warning/error matches. Log `/private/tmp/papernest-audit-unit.log`. `./scripts/build-mac-app.sh`: exit 0, no compiler warnings, `/private/tmp/papernest-audit-mac.log`. Both ran under 600-second process-group timeouts.
- **iPhone 17 Pro, dark mode: 3 interaction tests passed**, exit 0: `/private/tmp/papernest-audit-phone2.log`, xcresult `Test-PaperNest-iOS-2026.10.26_13-29-53--0500.xcresult`. Largest accessibility text category (`UICTContentSizeCategoryAccessibilityXXXL`) verified visually; notebook creation, shape start-X slider changes its accessible value, system custom-colour grid selection changes the sheet value, shape saves and appears in Manage Markup. Manual Recognize Text → content search also passes (not a latency benchmark).
- **Failed-save UI observed:** a second SQLite connection holds `BEGIN IMMEDIATE` on a unique disposable library. Shape save shows the localized error after the real database timeout, keeps the ellipse draft, and retry after rollback saves exactly one markup row. This is database contention, **not injected disk I/O failure**; disk-full/unwritable-file behavior remains unrun. No production failure hooks or backend changes were added.
- Initial iPhone run failed because the test matched `Close` while UIKit exposed `close`. Captured hierarchy established the cause; corrected to a case-insensitive match, then tested actual colour selection and dismissal. Initial log `/private/tmp/papernest-audit-phone.log`, exit 65. Not an application defect. Xcode emits an AppIntents metadata-extraction warning (no framework dependency) and OS-build parsing diagnostics; no Swift compiler warnings.
- Three iPhone screenshots saved under `docs/screenshots/audit-*-iphone.png`; inspected large-text slider, selected system colour and failure alert. Initial iPad run `/private/tmp/papernest-audit-ipad.log` exits 65: failed-save/retry passes, large-text test fails locating an offscreen menu entry (test must scroll), and automated audit **fails Dynamic Type** on the native Shape toolbar Add button. Audit attachment says the user cannot change this element's font size; its element screenshot shows Add. The audit stopped at the first surface, so the other sheets were not audited in that run. Investigation and full finding collection are in progress; this is not a passing accessibility check.
- **Expanded iPad automated audit remains failing:** `/private/tmp/papernest-audit-ipad2.log` collected all four surfaces rather than stopping at the first failure. Findings: Shape Add/Cancel Dynamic Type; Stamp Add/Cancel and placement-help Dynamic Type, Style contrast and a clipping flag; Comments Done Dynamic Type, Add Comment contrast/clipping; Manage Markup Done Dynamic Type. These are audit findings requiring triage, not a VoiceOver certification. Normal-size screenshots show readable content; some flags concern scroll-boundary content, so do not assume every flag is visible truncation. Evidence: `docs/screenshots/audit-accessibility-audit-editor-*-ipad.png` and xcresult attachments. No audit issue filter or expected-failure suppression was added.
- A controlled typography experiment set Shape/Stamp toolbar buttons to `.font(.body)`; `/private/tmp/papernest-audit-ipad3.log` still reported toolbar Dynamic Type failures. **Rejected and reverted**, so no unsupported typography fix remains. The large-text iPad automation also needed to scroll inside the visible menu viewport (not the offscreen Manage Markup row), and to select the presented Form rather than the background Pages collection. Final control rerun passed; see below.
- **Current-tree recheck after Claude’s backend additions:** 360 unit tests pass (64 UI + 123 Store + 77 Import + 54 Export + 42 Core), exit 0, no compiler warnings/errors: `/private/tmp/papernest-audit-unit-final.log`. Mac build also exit 0, no compiler warnings: `/private/tmp/papernest-audit-mac-final.log`. Both bounded to 600 seconds. These are build/unit outcomes, not a passing accessibility audit.
- iPad custom-picker run `/private/tmp/papernest-audit-ipad-controls.log` reached and adjusted the slider, selected azure from the system grid, then failed trying to tap an AX `close` control that is not visually present in the iPad popover. The screenshot and hierarchy confirm a `PopoverDismissRegion`; test updated to dismiss by tapping outside the popover on iPad, retaining close-button dismissal on iPhone. **Final iPad control rerun passed**, exit 0: `/private/tmp/papernest-audit-ipad-controls-final.log`, xcresult `Test-PaperNest-iOS-2026.10.26_19-03-52--0500.xcresult`. This covers the largest text category in dark mode, menu/form scrolling, changed start-X slider value, actual system colour selection, popover dismissal, save and the resulting markup row. Three iPad screenshots (including the earlier passing failure/retry flow) saved as `audit-*-ipad.png` and inspected. Simulator appearance restored to light after testing.
- Scope limits: these new interactions are **English only**; the older en/fr/es flows were not rerun here. Start-X slider was driven, not all four endpoint sliders. Largest-type coverage is notebook creation and shape/custom-picker navigation, not every recent sheet. Text-markup, notebook-page insertion and comment-editor accessibility still need their own passes. The four-sheet automated audit is intentionally unsuppressed and currently fails; do not report the full XCUITest suite as green.
- **Additional visual finding:** at the largest text category, iPad sidebar labels wrap into short word fragments in the narrow sidebar (visible behind the sheet in the final screenshots). This is a readability issue to address in the next design pass; it was not changed here.
- **Blocked / not run:** no computer-use tools available to this session, so native Mac annotation interaction, VoiceOver listening/navigation and native two-window conflict interaction have not been performed. A successful Mac build does not close these checks. `xcrun xctrace list devices` found only the Mac and simulators, no attached physical iPhone/iPad; real camera capture and M1 gate remain blocked on a device/provisioning. Other save-failure surfaces and injected disk I/O failure still unrun. No new feature surfaces added before this backlog pass.

## Text export (TXT) — Claude, 2026-10-26

F4's outstanding TXT deliverable and row 34's "PDF to Text". A document's words could be searched inside PaperNest but never got out: every export was a PDF or an image. `ExportFormat` gains `.txt`, `ExportError` gains `.noTextToExport`, and a new `TextExport.swift` writes one section per page. No schema change, no new strings.

- **Text comes from the best source the page really has**, never invented: current completed recognition first, because those lines keep their structure, then the text a digital PDF already carries, read back through new `LibraryStore.embeddedText(for:)` and `PageRenderer.embeddedText(for:)` (placed beside the existing `recognizedLines(for:)` so the exporter reaches stored text through the renderer rather than holding its own store reference). `recognizedLinesWinWhenAPageHasBoth` pins the precedence.
- **Pages are separated by a form feed (U+000C)**, the conventional ASCII page break. A worded separator such as "Page 2" would need a localized string in a file another session owns, and would turn a machine-readable file into one in a particular language.
- **A document with no text anywhere is refused** with `noTextToExport` rather than writing a file of nothing but separators and calling it a successful export of an empty document. The throw happens before the write and `export`'s own `catch` removes the directory, so a refusal leaves nothing behind.
- Only text that is **current for the page** can appear: `recognizedLines(for:)` refuses a result from an older revision, and a page's embedded text is cleared when its content is replaced. `rescanningAPageTakesItsOldTextAway` proves the second half, so a rescanned page cannot export words describing paper it no longer shows.
- **Cross-lane surface checked before claiming, not assumed.** Adding to a public `CaseIterable` enum is how one would accidentally change another session's UI. Verified: nothing iterates `ExportFormat.allCases`; the export sheet's format tiles are hand-written one per format, so no tile appears by itself; `contentType(for:)` derives from the file extension, so a `.txt` maps to plain text without help; and `ExportError` is not referenced anywhere in `PaperNestUI`. Both new cases therefore break nothing and surface nowhere.
- Test-first reds: 8 × missing `embeddedText`, then 4 × missing `ExportFormat.txt` and 2 × missing `ExportError.noTextToExport`. Greens: `green-readback.log` (4 store), `green-textexport.log` (7 export).
- **Final full suite: 336 passed** (64 UI + 119 Store + 65 Import + 46 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-textexport.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. Nothing was left in the temporary root.
- **A real limitation, stated rather than hidden:** embedded PDF text is stored normalized for the search index, so its whitespace is collapsed and such a page exports as **one paragraph rather than its original lines**. Good enough to get the words out; not the page's layout. Fixing it means extracting at export time with `PDFTextExtractor`, which lives in `PaperNestImport` — a module `PaperNestExport` does not depend on, so it needs a layout decision (likely the Recognition module ARCHITECTURE already plans) rather than a quick import.
- **Not run / not claimed:** **no UI** — there is no TXT tile in the export sheet, so this is not user-reachable, and a tile should not appear until it works. No independent reviewer pass; no native Mac, iOS interaction or real-device check. DOCX is deliberately not here: it needs a real container writer and validation by opening the result in an external editor. Ink, text boxes and page comments are not exported as text; only recognized and embedded text is.
- Plan: `docs/superpowers/plans/2026-10-26-text-export.md`. Nothing committed.

## File compression — Claude, 2026-10-26

Finishes the gap F2d left: a photo kept as a *file item* could not be reduced at all, which is the everyday "get it under a size limit" case. `LibraryStore.originalByteCount(of:)` now also reads `file_items.byte_count`, so one API sizes both kinds of item, and `Exporter.compress(fileNamed:data:preset:)` re-encodes image bytes through the existing `downsample`/`encode` helpers and returns the same `CompressionResult`. No second way to express a preset, no schema change, no new strings.

- **A file it cannot reduce is refused, not mangled.** Non-image bytes throw `CompressionError.unsupportedFormat`, and every step that can fail runs *before* a temporary directory exists, so a refusal writes nothing. Both are tested.
- **A loose file has no page size**, so a preset's dpi cannot apply; the presets gained a pixel target instead (2400/1600/1200 on the longest edge). Aspect ratio is asserted to within 2%, so nothing is cropped to hit a size.
- The honesty contract is tested as a property rather than a lucky fixture: `originalByteCount` matches the input, `savedByteCount` is never negative, and `isSmaller` always agrees with the byte comparison. Most photos arrive already compressed, so the larger-output branch is the common one; the document-level `anAlreadyCompactOriginalReportsNoSavingRatherThanAFakeOne` covers it concretely.
- Test-first reds: the file-item size test failed returning 0 while the deleted-file guard already passed; then `CompressionError` was missing. Greens: `green-filesize.log` (8 store), `green-filecompress2.log` (13 export).
- **A test defect of mine, fixed in the test rather than the code.** `aRefusedFileLeavesNoTemporaryDirectoryBehind` counted `PaperNestExport-*` entries in the **shared** process-wide temporary root while sibling tests created and removed their own there in parallel, so it measured them rather than itself. `Exporter(renderer:temporaryRoot:)` accepts a root, so the test now owns one. This is the second time that shared root has caused a false failure — see the trap note in SESSION_HANDOFF.
- **Final full suite: 325 passed** (64 UI + 115 Store + 65 Import + 39 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-filecompress.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. Nothing was left in the temporary root.
- **Not run / not claimed:** **nothing here is user-reachable** — there is no Compress action in any screen, so this produces bytes and numbers for a UI that does not exist yet, and it should not ship until that UI shows the real before/after rather than a promise. No independent reviewer pass; no native Mac, iOS interaction or real-device check. Only image files are reducible: a PDF *file item* is refused, because shrinking one means rasterizing pages, which would destroy selectable text exactly as it would for a document. Replacing a stored file with its reduced copy, or saving the copy as a new item, is a separate decision and is not done here. Folder and archive compression remain.
- Plan: `docs/superpowers/plans/2026-10-26-file-compression.md`. Nothing committed.

## Compression presets (F2d) — Claude, 2026-10-26

Size reduction on purpose, with measured before-and-after bytes. Row 35 was Partial because export quality tiers existed but nothing was presented as compression and no size was ever compared. `CompressionPreset` (`light`/`strong`/`smallest`) maps to explicit dpi and JPEG quality; `Exporter.compress` writes the PDF and returns a `CompressionResult`; `LibraryStore.originalByteCount(of:)` supplies the "before" — the originals the live pages are made of, a shared original counted once, deliberately **not** the size of a previous export, whose size would depend on the settings it was made with. Engine only: no UI, no schema change, no new strings.

- **The honesty behaviour is the point of this slice, and it is tested both ways.** Re-encoding an already-compact original makes it *larger*; `anAlreadyCompactOriginalReportsNoSavingRatherThanAFakeOne` asserts the output really is bigger as a precondition, then that `isSmaller == false` and `savedByteCount == 0`. A negative saving is never dressed up as a positive one. `reportsTheSavingItActuallyMade` checks the saving equals the measured difference when there is one.
- **A vector PDF cannot be shrunk by this path, by design.** `pdfSource` passes vector pages through untouched, because rasterizing text to save bytes destroys both quality and selectable text. `aVectorPDFKeepsItsTextInsteadOfBeingRasterizedToSaveBytes` asserts the text is still extractable from both pages at the `smallest` preset. This was not "fixed" by rasterizing.
- **`PDFImageQuality`'s cases are deliberately unchanged.** It is `CaseIterable` and drives the export sheet's picker, so a fourth case would have appeared in that UI unbidden. An internal `RasterQuality` carries a preset's dpi and quality, `PDFImageQuality` gained a computed `rasterQuality`, and an internal `export(…rasterQuality:…)` overload threads it to the private PDF path. The public API and the picker are untouched.
- Test-first reds: 12 × missing `originalByteCount`, then missing `CompressionPreset`/`CompressionResult`. Greens: `green-itemsize.log` (6 store), `green-compress.log` (7 export).
- Coverage: a document's size equals its original's; a shared original counted once; two originals add up; a deleted page and a document in Recently Deleted excluded; a template-page notebook reports zero; a stronger preset really produces a smaller file and `smallest` smaller still; the output is a valid PDF keeping every page; compression leaves `modified_at`, page revisions and the originals untouched; the output directory is removable and leaves nothing behind.
- **Final full suite: 317 passed** (64 UI + 113 Store + 65 Import + 33 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-compress.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. The run re-checked the exporter's temporary root and found nothing left behind.
- **Not run / not claimed:** no UI, so nothing is user-reachable yet — a Compress action belongs with whoever owns the sheets, and it must not ship until it shows these real numbers. No independent reviewer pass; no native Mac, iOS interaction, real-device, VoiceOver or Dynamic Type check. `originalByteCount(of:)` covers **page-based items only**: a general file item keeps its size on its own payload and is not counted, so compressing a stored photo or PDF *file* remains to do. Image-format output (JPEG/PNG presets) and folder/archive compression are not part of this.
- Plan: `docs/superpowers/plans/2026-10-26-compression-presets.md`. Nothing committed.

## Automatic text recognition — Claude, 2026-10-26

Text is now read without being asked. Previously nothing was searchable by its contents until the user opened **More → Recognize Text** page by page, and a rescanned page kept its old, wrong text. Built in the shape of `EmbeddedTextIndexer`: `LibraryStore.pagesNeedingRecognition(engineVersion:limit:)` names the work, `AutomaticTextRecognizer` (actor, batched, cancellable) does it, and `LibrarySession` runs it after the library is ready and after each change, coalesced. No schema change (`page_recognition` already carried `source_revision`, `status` and `engine_version`) and no new strings. The existing render → recognize → `saveRecognition` path is reused, so recognition itself is unchanged.

- Work is decided from stored state, not a queue, so a pass is interruptible and resumable: a page qualifies with no result, a `source_revision` that no longer matches (a rescan), a `pending` result, or a different `engineVersion`. A **failed** result for the same paper and engine is left alone, so an unreadable page is not retried every launch — a rescan or an engine change earns another attempt.
- **Pages that already carry their own text are skipped.** A non-empty `pdfText` row means a digital PDF's real words are already indexed, and recognizing a raster of those words would be worse; an *empty* marker (a scan with no text layer) is exactly the OCR case. This is what the previous slice's marker made possible, and **the launch order is load-bearing**: embedded text runs before recognition, with a test that fails if it does not.
- Test-first reds: `red-task1.log`-equivalent runs failed on the missing `pagesNeedingRecognition` and `AutomaticTextRecognizer` APIs; the launch test failed on the renamed `backgroundTextWork`. Greens: `green-recog-task1.log` (11 store), `green-recog-task2.log` (6 pass), `green-recog-launch.log` (3 launch).
- **A deadlock I introduced, found and fixed — worth reading before touching Vision.** The first full run **hung for four hours**. Two targets had passed, then `PaperNestImportTests` froze with no compiler or test process doing work. A `/usr/bin/sample` of the stuck process showed five of the new tests simultaneously inside `AutomaticTextRecognizer.recognizeMissing`, all parked in `semaphore_wait_trap` under `-[VNControlledCapacityTasksQueue dispatchSyncByPreservingQueueCapacity:]`. **Vision's task queue dispatches synchronously**, so `recognize(_:)` parks the thread it is called on until Vision has capacity; called from an actor that is a Swift concurrency cooperative thread, of which there are about one per core, and enough concurrent recognitions park every one — including the threads Vision needs to finish the work the others wait on. The existing Vision tests never hit it because their `@Test` functions are **synchronous** and run on ordinary threads.
- The first hypothesis was tested and **rejected**: a 6-way concurrent regression passed in 1.2 s on this 8-core machine, because two threads stayed free to drain Vision. Two experiments settled it — the Import target run with `--no-parallel` passed 65 tests in 4.17 s, and raising the regression to **16 concurrent passes** reproduced the hang deterministically. Fix is the root cause, not the symptom: `TextRecognizer.recognizeOnADedicatedThread(_:)` runs the blocking call on its own serial queue, off the cooperative pool. Marking the suite `.serialized` was deliberately **not** done; it would have hidden this in tests while leaving production able to park the pool. Evidence: 16 concurrent passes went from an indefinite hang to 2.703 s, and the original failing scenario (Import target, parallel) passes 65 tests in 3.245 s.
- **Final full suite: 304 passed** (64 UI + 107 Store + 65 Import + 26 Export + 42 Core), exit 0, **0 warnings**, 0 failures: `verify-recog2.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. The run re-checked the exporter's temporary root and found nothing left behind. The Core target reports one more test than the previous slice's run because Codex's committed stamps work grew `ShapeAnnotation` from four kinds to seven, which its parameterized geometry test covers; nothing here touched Core.
- **Still blocking the main thread, and not mine to change:** `DocumentModel.recognizeText(on:)` calls the synchronous `recognize(_:)` on the MainActor, so manual recognition stalls the UI for as long as Vision takes. It cannot deadlock the way the pass did, but it should adopt `recognizeOnADedicatedThread(_:)`. That file belongs to whoever owns `DocumentModel.swift` next.
- **Not run / not claimed:** no independent reviewer pass; no XCUITest for automatic recognition on iPhone or iPad; no native Mac or real-device check; no VoiceOver, Dynamic Type or sanitizer run. **The cost of a first-launch sweep over a large library is unmeasured** — the pass is low priority, batched and resumable, but OCR of hundreds of unread pages has not been timed. The user language override and the recognition status surface are deliberately out of scope.
- Plan: `docs/superpowers/plans/2026-10-26-automatic-recognition.md`. Nothing committed.

## Symbol stamps — Codex, 2026-10-26

- Checkmark, cross and five-point star presets save as one ink object per stamp. Reuses exact Page snapshot validation, history, Manage Markup and export; schema unchanged. Native sheet has a dedicated Stamp mode and separate preset list; ordinary Shape mode retains its default rectangle.
- Test-first RED: `/private/tmp/papernest-stamps-red.log` (missing presets/list APIs). Focused GREEN: `-focused.log` (6 tests with expanded parameter cases): all presets under crop/quarter-turns/reversed drags; invalid narrow boxes; PencilKit corner preservation; real model save/reopen/PDF pixel output and page-add/stamp mixed undo/redo.
- Full suite **284 tests passed** (62 UI + 96 Store + 58 Import + 26 Export + 42 Core), no compiler warning/error matches: `/private/tmp/papernest-stamps-unit.log`. Mac build passed: `-mac.log`.
- Fresh independent read-only review found no concrete issues.
- iPhone 17 Pro localized workflow **passed en/fr/es**: `/private/tmp/papernest-stamps-phone.log`, xcresult `Test-PaperNest-iOS-2026.10.26_07-40-43--0500.xcresult`. Checks ordinary Shape mode still defaults to rectangle, Stamp defaults to checkmark, cancellation leaves no ink, all stamp selectors, actual drag coordinate change, color selection, save, undo/redo and relaunch persistence. Three screenshots inspected/saved as `docs/screenshots/stamp-placement-*-iphone.png`; labels/actions fit and star placement matches its preview. iPad Air 13-inch (M4) passed the same en/fr/es workflow: `/private/tmp/papernest-stamps-ipad.log`, xcresult `Test-PaperNest-iOS-2026.10.26_07-46-09--0500.xcresult`. Three iPad screenshots inspected/saved as `stamp-placement-*-ipad.png`; labels and preview fit, style controls are reached by scrolling. No implementation changes after the passing full suite or review. The complete device suites were not repeated.
- Scope: symbol stamps only, not text/status stamps or custom-image stamps. No native Mac stamp interaction, real-device Pencil, VoiceOver/large type, system custom-picker/endpoint-slider interaction, new sanitizer or image-specific export pixel test claimed; shared export rendering is reused and PDF output is tested.


## Shared-asset backup fix — Claude, 2026-10-25

`SettingsView.startBackup` and `BulkExportModel.start` resolved a file item's original with a hardcoded `kind: .file`, while the audited preview path resolves the asset record's own kind. `assets` is keyed by SHA-256 and its insert is `ON CONFLICT(id) DO UPDATE SET availability = 'local'`, so the row keeps the kind of whichever import arrived first, and `AssetFileStore.url(for:kind:)` names the file from that kind. A file item sharing an original stored as a PDF therefore resolved to a `.bin` that was never written. `LibraryBackup` reads each entry with `Data(contentsOf:)` and its `catch` deletes the working directory and rethrows, so **one such item failed the entire Settings backup and the entire bulk ZIP export**, not just its own entry. This was the regression the handoff asked for before touching those paths.

- Test-first red: `red-assetkind.log` — new `SharedAssetBackupTests` failed on both paths because the export never became ready (`model.output` and `model.backupOutput` both nil). The scenario is built with the public `createFileItem` taking an asset staged as `.pdf`, the same construction the existing `previewResolvesTheRecordedKindOfASharedAsset` test uses, so it is reachable rather than hypothetical.
- Fix: a single `LibraryStore.originalURL(for:)` that resolves the record's kind and throws `assetMissing` when there is no row, with both call sites using it. A resolver rather than two corrected call sites, because the bug was two sites diverging from one correct one. Green: `green-assetkind.log`.
- **A sweep confirmed these were the only two.** Every remaining `assets.url(...)` / `assets.read(...)` / `assets.remove(...)` call in `Sources` now takes its kind from a record or a database row: `LibraryStore` lines 73, 292, 853, 860, 873 and 933, `EmbeddedTextIndexer`, and `FileItemViews`. No hardcoded asset kind remains in the codebase.
- **A mistake of mine, and what it exposed.** My two new tests produced `ExportOutput`s without removing their temporary files, which broke the pre-existing `cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind`: it asserts that `exporter.temporaryRoot` — the process-wide system temp directory — holds no `PaperNestExport-*` entry. Only the full suite caught this; my focused run passed. Fixed by deferring `removeTemporaryFiles()` in both tests. The run after that still failed, on four stale directories left by the two pre-fix runs; removing them made the suite green. Worth knowing: **that test fails on residue from any earlier crashed or failed run**, because it asserts on shared global state rather than on directories the test itself created. Not changed here, since it is not my test, but it is a real fragility.
- **Final full suite: 283 passed** (62 UI + 96 Store + 58 Import + 26 Export + 41 Core), exit 0, **0 warnings**, 0 failures: `verify-assetkind3.log`. Final Mac build passed and the `PaperNestUI` iOS Simulator build reported BUILD SUCCEEDED. The same run re-checked the temporary root afterwards and found **0 leftover export directories**, so the cleanup is verified rather than assumed.
- **Not run / not claimed:** no independent reviewer pass; no native Mac or iOS interaction check of Settings backup or the bulk export sheet (both are driven here through their models, as the existing bulk-export tests do); no real-device, VoiceOver or Dynamic Type run. No schema, localization or layout change.
- **Still open, deliberately.** The underlying first-writer-wins kind is unchanged: the same bytes arriving under two kinds still produce two physical files (`<sha>.pdf` and `<sha>.bin`), so content-addressed dedup is defeated across kinds and the second file is only swept once the row is gone. Every reader is now consistent, so this is storage waste rather than a correctness bug. Fixing it properly means either making `assets.kind` authoritative on conflict or naming files by hash alone, which is a file-layout change and a larger slice than this.

## Vector PDF text indexing — Claude, 2026-10-25

Digital (vector) PDFs are now findable by their own body text, not only by their title. A fourth `search_index` field, `pdfText`, sits beside `title`, `ocr` and `text`; no migration (FTS5, `field` unconstrained, index derived and rebuildable), schema stays v7, and no new user-visible strings. Indexed text is deliberately **not** keyed to `page.revision`: the words come from the immutable original, so a crop, rotation or ink stroke leaves them true. Only `replacePageContent` (the single page-content write path, which rescan undo and redo both re-enter) clears them.

- Test-first, API-missing reds: `red-task1.log` (16 × missing `indexEmbeddedText`, 2 × missing `pagesMissingEmbeddedText`), `red-task2.log` (missing `EmbeddedTextIndexer`, then 4 genuine behavioral failures: rescan did not clear the old words or requeue the page, and duplication did not carry them). Batch and URL extractor APIs also run red on argument labels before implementation. Greens: `green-task1.log`, `green-task2.log`, `green-launch.log`, `green-batch.log`, `green-url.log`. Logs are session-local under this session's scratchpad, not `/private/tmp`.
- **Final full suite (after the performance fix): 281 passed** (60 UI + 96 Store + 58 Import + 26 Export + 41 Core), exit 0, **0 compiler warnings**: `verify-final.log`. That is the measured 259-test baseline plus exactly the 22 tests added here (10 Store, 11 Import, 1 UI). The run included Codex's uncommitted shape-annotation work, so it is not a clean-tree baseline.
- **Final Mac build passed** (`scripts/build-mac-app.sh`, exit 0, 0 warnings) and **iOS Simulator build of `PaperNestUI` passed** (`xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator'`, BUILD SUCCEEDED).
- Coverage: per-page extraction from a vector PDF; no text from a scanned page, an out-of-range index or non-PDF bytes; several pages read in one parse; reading an original off disk and a missing file; body words found by `search` when the title does not match; an empty marker row recorded for a page with no text layer, which answers no search and stops the page being read again; a write rejected when the page no longer shows the content the text came from; reindexing replacing rather than accumulating; indexing leaving `modified_at` and `revision` untouched; a missing page rejected; rescan clearing the old words and requeueing the page; a look-only edit keeping words findable; duplicate/merge/extract carrying the text and the marker; delete removing it with `integrityCheck` clean; a second indexer pass over a scanned PDF having nothing to do; image pages left alone; and opening a library making its digital PDFs findable while launch still completes first.
- A new `scannedPDF` fixture (raster content, no text layer) was added to `Tests/Support/SyntheticDocuments.swift`, so "looked, found nothing" is distinguishable from "not looked at".
- Originals are read off disk through the asset record's own kind (the pattern `FileKind.prepareTemporaryCopy` uses), so PDFKit memory-maps them and indexing a large PDF does not hold the whole file in memory. **The memory behavior is reasoned and mapped, not measured**; no large-PDF performance run was done.
- **Measured and fixed a stall on the store actor.** The first version of `pagesMissingEmbeddedText` used a correlated `NOT EXISTS` against `search_index`, whose `page_id` is an `UNINDEXED` FTS5 column, so the check scanned the whole index once per page. Probed on a 2,000-page library (200 documents × 10 PDF pages): **0.300 s with everything already indexed**. That query runs on the store actor from `didChange()`, which has ~29 call sites including ink and undo, so it blocked user edits on every stroke. Reading the already-checked set once instead — `p.id NOT IN (SELECT page_id FROM search_index WHERE field = ? AND page_id IS NOT NULL)` — brings it to **0.0019 s (155× faster)**; the all-missing case went 0.0455 s → 0.0022 s. The `page_id IS NOT NULL` is required: title rows carry a NULL page id, and a single NULL inside `NOT IN` makes the whole query match nothing. The probe was a throwaway, so these numbers are **not** reproduced by `./scripts/test.sh`.
- Two follow-ups from self-review, both fixed with the measurement above: pages whose original is not on this device are no longer fetched at all (a `JOIN assets ... availability = 'local'`), so 50-plus `remoteOnly` pages at the front of the sort order cannot starve every local PDF behind them once sync exists; and `PDFTextExtractor.text(at:)` now returns nil when a file cannot be opened, distinct from opening it and finding no text, so an unreadable original is retried on a later pass instead of being marked permanently checked.
- Library changes arriving during a pass are coalesced into one further pass rather than queueing one each, so a burst of strokes costs one indexed lookup that finds nothing to do.
- **Not run / not claimed:** no independent reviewer pass. Author self-review plus one advisory review found the store-actor stall, the starvation case and the unopenable-file case above; all three are fixed, and no second pass was made over the fixes. Also: no XCUITest for searching by PDF contents on iPhone or iPad; no native Mac interaction check; no real-device, VoiceOver, Dynamic Type, dark-mode or sanitizer run; no localization change, so no new layout checks. The `LibrarySession` launch hook is covered by one unit test that awaits the pass; it has not been observed in a running app.
- **Known limitation, inherited from recognized text:** a soft-deleted page's words stay findable until the next launch purges them, because `search()` filters deleted items but not deleted pages. This matches existing `ocr` behavior and was not changed here.
- Plan: `docs/superpowers/plans/2026-10-25-pdf-text-indexing.md`. Nothing committed or pushed.

## Shape annotations — Codex, 2026-10-25

- Integration recheck on 2026-10-26 after Claude’s independent commits: **283 tests passed** (62 UI + 96 Store + 58 Import + 26 Export + 41 Core), no compiler warning/error matches. `/private/tmp/papernest-shapes-integration-final.log`; Mac build passed in `-integration-mac.log`. Shape production code is unchanged from the verified device runs.

- Outlined rectangles, ellipses, lines and arrows save as one editable ink object. Native sheet has drag preview, accessible endpoint sliders, preset/custom color and widths 1/2/4 points; exact Page snapshot and active parent guard the atomic save. No migration (schema stays v7).
- Test-first API failures: `/private/tmp/papernest-shapes-{core,store,model}-red.log`. Focused green: `-focused.log`; crop/rotation/reversed endpoints, invalid geometry/style, stale/deleted parent, reopen, PDF raster output and mixed page-creation/shape undo/redo.
- Mixed history regression first failed in `-history-red.log`; notebook insertion undo now compares semantic page columns, exact objects/OCR/order/deletion stamp, ignoring only cache revision and modified_at after fully undone ink. Existing external-edit conflict coverage retained.
- First full suite caught French colon spacing; corrected four strings to nonbreaking spaces. Initial corrected suite passed 258 tests and Mac build passed.
- Fresh independent review found PencilKit smoothing of sparse corners. Reproduced in `-pencil-red.log`, fixed generated rectangle/arrow control vertices, focused green in `-pencil-green.log`. Rotated/scaled round-trip checks enforce outline deviation <0.5 source point and visits to every corner. One fix pass, no re-review.
- Visual QA caught a false-positive initial phone flow: default arrow remained while the form scrolled. Added localized coordinate accessibility values and a position-change assertion; UI RED in `-drag-red.log`. Priority alone also failed; expanded the gesture frame to match the preview row and offset coordinates back to the centered paper. Position now changes and screenshot confirms the requested direction. Margin scrolling in the test avoids the intentional drawing surface.
- Imported-document history regression RED in `-doc-history-red.log` proved the menu had only exposed history on notebooks. Both document More menus now expose the existing history actions. New imported-PDF add/undo/redo flow included in final device runs. Initial iPad run was deliberately interrupted to replace obsolete gesture code (not a pass).
- Final combined suite: **276 tests passed** (59 UI + 96 Store + 54 Import + 26 Export + 41 Core), including Claude’s concurrently added vector-PDF indexing coverage. Shape-only state previously passed 259 tests. `/private/tmp/papernest-shapes-unit-final.log`; final Mac build passed in `-mac-final.log`. An intermediate combined run hit Claude’s intentionally unfinished indexer API (`-combined-inflight.log`); no unrelated code was changed to fix that.
- Final iPhone 17 Pro: **2 UI tests passed** — localized shape flow en/fr/es plus imported-document add/undo/redo. Position-change assertion, all four kind selectors, cancel-without-save, color selection, saved-mark count, undo/redo and relaunch persistence. Log: `/private/tmp/papernest-shapes-phone-final.log`; xcresult `Test-PaperNest-iOS-2026.10.25_23-06-37--0500.xcresult`. Three screenshots inspected and saved at `docs/screenshots/shape-placement-*-iphone.png`; title/actions and localized labels fit, dragged arrow points in the requested direction.
- Final iPad Air 13-inch (M4): localized shape flow **passed en/fr/es** in `/private/tmp/papernest-shapes-ipad-placement-final.log`, xcresult `Test-PaperNest-iOS-2026.10.25_23-16-30--0500.xcresult`. Three screenshots inspected/saved as `shape-placement-*-ipad.png`. The prior run (`-ipad-final.log`, xcresult `23-12-36`) passed imported-document add/undo/redo and existing finger drawing/history/relaunch; its shape flow failed only because test scrolling used the screen margin outside the centered sheet. Corrected the test to use the form margin beside the preview, then repeated only the affected localized flow. Phone final predates this test-only coordinate correction; all production shape code is the same. No full device suite repetition is claimed.
- Verification limits: Native Mac shape interaction, system custom-picker/endpoint-slider interaction, real-device Apple Pencil, VoiceOver, large Dynamic Type, dark mode and sanitizer checks remain unrun. Image export uses the existing shared ink renderer; the new shape-specific pixel test exercises PDF output.


## Page comments — Codex, 2026-10-25

- New private page comments use schema v7 (widens page_objects kind constraint). Add/edit/delete, exact-object guarded undo/redo, duplicate/reopen persistence; explicitly excluded from PDF/image exports. Existing ink/text/image rows preserved.
- Test-first logs: `/private/tmp/papernest-comments-store-red.log`, `-model-red.log` (missing APIs). Focused green: `-focused.log` (5 store + 2 model tests), covering valid/corrupt migration, text limits, deleted parent/page, stale edit/undo and restored-ID collision, duplication/reopen and PDF export privacy.
- Final full suite: **254 tests passed** (57 UI + 85 Store + 47 Import + 26 Export + 39 Core), no warning/error matches: `/private/tmp/papernest-comments-unit-final.log`. Final Mac build passed: `-mac-final.log`.
- Independent review found mixed comment/page undo invalidation and draft loss in the conflict recovery instructions. Mixed history reproduced red (`-mixed-red.log`); fixed private comment persistence to preserve the rendered page row while touching item modification time. Draft model regression first failed on missing API (`-draft-red.log`); explicit Save as New Comment now preserves both versions. Both regressions green (`-review-green.log`), then full suite passed. No second reviewer pass claimed.
- Initial iPhone UI test reached relaunch but failed a cursor-position assumption: text was inserted at the caret instead of appended. Corrected test captures the actual edited text and asserts exact persistence.
- Final iPhone localized flow passed in en/fr/es: `/private/tmp/papernest-comments-phone-final.log`, xcresult `Test-PaperNest-iOS-2026.10.25_12-41-50--0500.xcresult`. Exercises blank-save disabled, create, edit cancellation, saved edit, deletion, undo/redo and relaunch persistence. All three editor screenshots inspected; title/actions and export notice fit above keyboard (`docs/screenshots/page-comment-editor-*-iphone.png`).
- iPad Air 13-inch (M4) localized flow passed in en/fr/es: `/private/tmp/papernest-comments-ipad.log`, xcresult `Test-PaperNest-iOS-2026.10.25_17-42-16--0500.xcresult`. Same create/edit/cancel/delete/history/relaunch coverage; three editor screenshots inspected (`docs/screenshots/page-comment-editor-*-ipad.png`), labels/controls and wrapped export notice fit above keyboard.
- Native Mac interaction, real-device checks, large Dynamic Type/VoiceOver, and injected I/O failure UI not run. Stale-draft conflict and Save as New are model-tested; no native multiwindow conflict UI pass claimed. Focused UI flows only; complete existing UI suite not rerun. Xcode OS-build parsing diagnostics appeared but both final UI runs report TEST SUCCEEDED.

## Additional notebook pages — Codex, 2026-10-25

Notebooks now offer Add Notebook Page in the existing add-pages menu. Blank/lined/grid A4 paper defaults to the selected template; insert after selection or append without one. Selection changes after the store commit. Cancel writes nothing; save failures keep the form open. Undo/redo validates the page row, objects, OCR and surrounding order atomically, preserves newer edits, and clears obsolete history on conflicts. No migration or dependency changes.

- Checkpoint `7444b4d` saved all preceding work after **236 passing tests** (`/private/tmp/papernest-checkpoint-tests.log`).
- Test-first store/model failures: `/private/tmp/papernest-pages-red.log`, `-model-red.log`; focused green: `-store-green.log`, `-model-green.log`.
- Fresh reviewer found rapid native Undo→Redo discarded an unarmed inverse. Reproduced four failed assertions in `/private/tmp/papernest-pages-history-red.log`; fixed by serializing native requests and invalidating queued requests on conflict. Focused green: `-history-green.log`. Regression tests cover immediate undo/redo/undo and conflict with a queued redo.
- Review follow-up reproduced mixed delete/notebook history ending with two pages rather than one (`/private/tmp/papernest-pages-mixed-red.log`). All document history callbacks now share the serial queue; mixed regression passed (`-mixed-green.log`).
- Fresh page edits now await pending history; new-edit race reproduced and fixed (`/private/tmp/papernest-pages-new-edit-red.log`, `-new-edit-green.log`).
- Final independent review: no remaining actionable data-loss or regression issues found; reviewer did not edit files or run tests.
- Final full unit suite: **245 passed** (53 UI + 80 Store + 47 Import + 26 Export + 39 Core), no compiler warning/error matches. `/private/tmp/papernest-pages-unit-final.log`. Covers all paper templates; empty/middle/end insertion; invalid notebook/anchor; deleted/purged/conflicting states; undo/redo; reopening; two-page PDF export; localization parity.
- Final Mac build passed: `/private/tmp/papernest-pages-mac-final.log`. Native Mac sheet and keyboard interaction remain unrun.
- First iPhone UI attempt failed because the test targeted More rather than the compact editor’s separate Add Pages menu. Investigation also found compact history controls missing; added them. Corrected iPhone run passed the add/cancel/default-paper/undo/redo/relaunch flow in en/fr/es (`/private/tmp/papernest-pages-phone.log`). Screenshots `docs/screenshots/notebook-add-page-*-iphone.png` inspected: titles, controls and wrapped Spanish footer fit.
- Initial iPad Air 13-inch (M4) flow passed in en/fr/es: `/private/tmp/papernest-pages-ipad.log`, xcresult `Test-PaperNest-iOS-2026.10.25_06-18-45--0500.xcresult`. All three new-sheet screenshots inspected; labels/controls/footer fit (`docs/screenshots/notebook-add-page-*-ipad.png`).
- iPhone rerun after native rapid undo/redo fix passed in en/fr/es: `/private/tmp/papernest-pages-phone-final.log`, xcresult `Test-PaperNest-iOS-2026.10.25_06-21-26--0500.xcresult`. This run preceded the later shared-history queue and fresh-edit wait.
- iPad shared-history regression passed **2/2**: existing PencilKit drawing/undo/redo/reopen (41.720 s) plus notebook flow in en/fr/es; `/private/tmp/papernest-pages-ipad-final.log`, xcresult `Test-PaperNest-iOS-2026.10.25_06-24-11--0500.xcresult`. This build includes shared history serialization and precedes fresh-edit waiting.
- Final-source iPhone 17 Pro check passed in en/fr/es (130.101 s, zero failures): `/private/tmp/papernest-pages-phone-verified.log`, xcresult `Test-PaperNest-iOS-2026.10.25_06-27-55--0500.xcresult`. Includes all review fixes and fresh-edit waiting. Xcode emitted OS-build parsing diagnostics; tests succeeded.
- Not claimed: full existing UI suite, real-device Pencil/camera, VoiceOver, large Dynamic Type, native Mac interaction, or injected storage-failure UI. Store/model failures are covered; save-error form retention is implemented.

## Notebook creation — Codex, 2026-10-24

Implemented Tools → New Notebook: enter a name, choose blank/lined/grid paper, and create one A4 template page. The item is stored as a notebook in the current folder (root from home), created atomically through the existing store API, and opened after dismissing the creation sheet. Empty names disable Create; double submission/dismissal during save is disabled; errors leave the form open. No schema changes or new dependencies. Existing editor/ink/render/export paths are reused.

- Test-first evidence: `/private/tmp/papernest-notebook-red.log` failed on the missing `LibraryModel.createNotebook` API. Initial sheet compile failed on the Section header/footer initializer and was corrected.
- Full unit suite: **236 tests passed** (48 UI + 76 Store + 47 Import + 26 Export + 39 Core), no compiler warnings. `/private/tmp/papernest-notebook-unit.log`. New parameterized test covers all three templates, normalized name, folder, reopen, valid one-page PDF export, and store integrity.
- Mac build passed, no compiler warnings: `/private/tmp/papernest-notebook-mac.log`. Native Mac sheet interaction not run.
- iPhone 17 Pro: notebook create/relaunch and existing Tools merge tests both passed; `/private/tmp/papernest-notebook-phone.log`. iPad Air 13-inch M4: notebook create/relaunch passed; `/private/tmp/papernest-notebook-ipad.log`. Both report TEST SUCCEEDED.
- Localization key/format checks passed for en/fr/es. French/Spanish visual layout and accessibility-size screenshots are not newly verified. Real Pencil drawing on the new page, cancellation/storage-failure UI, and native Mac interaction are not claimed tested in this slice.
- Scope remains partial for full notebooks: adding more template pages, planners, text/image editing and notebook-specific navigation remain follow-ups. No subscription limits introduced.
- Source: new NotebookCreationSheet.swift; LibraryModel.swift; ToolsSheet.swift; Localization.swift and en/fr/es strings; new NotebookCreationTests.swift; appended AppUITests notebook test. Qwen-reserved sheets untouched. Author review completed; no independent reviewer was available in this session. Nothing committed or pushed.

## F3b — markup colors and saved-mark controls (Codex, 2026-10-24)

- Final full unit suite **passed 235 tests** (47 UI + 76 Store + 47 Import + 26 Export + 39 Core), no compiler warnings. `/tmp/papernest-f3b-unit-final2.log`. Initial implementation passed 233; API tests first ran red in `-store-red.log` and `-model-red.log`, focused green in `-store-green.log`. A test-only `try` placement compile error in `-unit-final.log` was corrected before the passing final run.
- New coverage: custom color validation, atomic recolor/removal, exact page/object snapshot rejection, empty/duplicate/non-ink/foreign-page selections, deleted-parent protection, preserving other ink/text/OCR, undo/redo through both operations, reopen, and actual recolored pixels in exported PDF.
- Independent review found two issues: ink undo/redo bypassed snapshot checks; the open manager did not observe changes from other windows. Fixed with atomic `applyInkChanges` guards (including IDs expected absent anywhere in the library), conflict refresh/error and invalid undo-history clearing, plus manager reload on `session.changeToken` with cancellation/request guards. Three conflict scenarios were reproduced red then passed green: `/tmp/papernest-f3b-conflict-red.log`, `-conflict-green.log`. Store tests also verify no partial writes, foreign-ID collisions and coexistence with unrelated edits. Independent follow-up could not finish due to the reviewer's usage limit; author review and regression tests were completed.
- Final Mac build **passed**, no compiler warnings: `/tmp/papernest-f3b-mac-final.log`. Native Mac manager interaction remains **unrun**.
- iPhone 17 Pro: initial annotation regression + manager/color workflow **passed 2/2** (101.350 s and 210.299 s): `/tmp/papernest-f3b-phone.log`, xcresult `Test-PaperNest-iOS-2026.10.24_06-34-22--0500.xcresult`. After review fixes, manager/color workflow **passed again** (210.014 s) in en/fr/es: `/tmp/papernest-f3b-phone-final.log`, xcresult `Test-PaperNest-iOS-2026.10.24_06-42-00--0500.xcresult`. Exercises real OCR, green preset, selecting/closing without a write, blue recolor, preserving the other mark, removal to empty and persistence after relaunch.
- iPad Air 13-inch (M4): **passed 2/2**, existing PencilKit drawing/undo/redo/reopen (43.974 s) and new manager/color workflow in en/fr/es (258.476 s). `/tmp/papernest-f3b-ipad.log`, xcresult `Test-PaperNest-iOS-2026.10.24_12-00-54--0500.xcresult`. Manager screenshots inspected in all three languages: labels fit and selection outline aligns; lower actions are reached by scrolling in the native form. Evidence: `docs/screenshots/markup-manager-*-ipad.png`. Initial iPhone manager and annotation-color screenshots in en/fr/es inspected: titles/labels fit; dashed selection outlines align with the intended mark. Final-run manager screenshots were also inspected and saved under `docs/screenshots/markup-manager-*-iphone.png`; annotation color-layout evidence is `docs/screenshots/markup-colors-*-iphone.png`.
- A native sRGB conversion probe on Mac returned valid `[0, 1, 0, 1]` for Display-P3 green. This is a color-boundary check, not a manual custom-picker UI pass. Custom colors are unit-tested; system custom-picker interaction and native two-window refresh remain **unrun**. No real-device, VoiceOver, large Dynamic Type, dark-mode or sanitizer pass is claimed for F3b. Focused UI coverage only; the complete iPhone suite was not repeated for F3b.

## F3a — recognized-line text markup (Codex, 2026-10-23)

- `./scripts/test.sh`: **228 passed** (45 + 72 + 47 + 26 + 38), no failures or compiler warnings. `/tmp/papernest-markup-unit-final.log`. Nine new tests cover source geometry for all three styles, narrow/thin boxes, invalid coordinates, stale/replaced OCR rejection, atomic invalid-selection failure, OCR currency through ink changes, undo/redo, reopen and a pixel check on a cropped/rotated PDF export with searchable text intact. New API tests were run red before implementation. The reviewer’s renderer regression was also run red/green: 0.1-point underline/strike disappeared and 1.2-point marks expanded to 1.25. Constant-width pens now draw one path at their exact width; variable-width freehand batching is unchanged. Four parameterized bitmap cases check visibility, thickness and containment. Logs: `/tmp/papernest-markup-width-red.log` and `/tmp/papernest-markup-width-green.log`.
- `./scripts/build-mac-app.sh`: **passed**, no compiler warnings; `/tmp/papernest-markup-mac-final.log`. New native Mac annotation UI has **not** been manually exercised.
- iPhone 17 Pro: `testRecognizedLinesCanBeMarkedAndKeptAfterRelaunch` **passed** (101.028 s). Real OCR → highlight (en), underline (fr), strikethrough (es), cancel without adding ink, and persistence after each relaunch. `/tmp/papernest-markup-phone.log`; xcresult `Test-PaperNest-iOS-2026.10.23_14-44-30--0500.xcresult`. Picker screenshots in all three languages inspected: no clipped controls/text. Saved highlight and combined marks visually inspected. Evidence: `docs/screenshots/text-markup-*-iphone.png`.
- iPad Air 13-inch (M4): annotation workflow **passed** (102.302 s) and existing PencilKit drawing/undo/redo regression **passed** (2/2 total). `/tmp/papernest-markup-ipad.log`; xcresult `Test-PaperNest-iOS-2026.10.23_20-27-49--0500.xcresult`. Picker screenshots in en/fr/es and the combined saved marks inspected; controls fit, saved marks align with the text. Evidence: `docs/screenshots/text-markup-*-ipad.png`. Final follow-up after the exact-width renderer fix also **passed 2/2**, annotation workflow 104.814 s: `/tmp/papernest-markup-ipad-final.log`, xcresult `Test-PaperNest-iOS-2026.10.23_20-33-46--0500.xcresult`. Saved iPad evidence files now come from that final run; the final combined marks were visually rechecked.
- Full iPhone suite was run earlier for the audit (17 passed, 1 skipped); it was not repeated after F3a. The focused iPad follow-up compiles the final iOS code; the earlier iPhone run predates only the shared exact-width rendering fix. No real-device, VoiceOver, Dynamic Type, dark-mode annotation or new sanitizer check is claimed.
- Independent review resumed after a usage-limit interruption and identified the exact-width renderer issue above. The fix has a passing regression; independent follow-up reported no remaining actionable findings. Author review checked the source-space mapping, exact OCR snapshot identity, transaction boundary, undo registration, duplicate-save guard and localized strings.


## Mac audit and file-preview follow-up (Codex, 2026-10-23)

- `./scripts/test.sh`: **219 passed** (44 + 68 + 46 + 26 + 35), no compiler warnings; `/tmp/papernest-oct23-unit.log`. Includes a red/green regression for a file item sharing an asset stored as PDF. Temporary copies now resolve the asset record’s kind instead of assuming `.bin`.
- `./scripts/build-mac-app.sh`: **passed**, no compiler warnings; `/tmp/papernest-oct23-mac.log`. Subsequent Mac Tools/footer and raw-file save changes also built; `/tmp/papernest-oct23-mac-tools.log`, `/tmp/papernest-oct23-mac-file-save.log`.
- Full iPhone 17 Pro UI run: **17 passed, 1 skipped, 0 failures**; `/tmp/papernest-oct23-phone.log`, xcresult `Test-PaperNest-iOS-2026.10.23_05-19-08--0500.xcresult` in cache `build-17de0868e51d`. This full run predates the final Tools footer and writable-type changes; focused follow-up **passed 3/3** (file preview, Export save dialog, Tools merge); `/tmp/papernest-oct23-focused-final.log`, xcresult `Test-PaperNest-iOS-2026.10.23_14-37-14--0500.xcresult`.
- Native Mac interaction used only `/tmp/papernest-mac-audit-20261022`. Library grid and document preview viewed. Hidden layout-picker label fixes a narrow vertically wrapped label while preserving accessibility. Export previously hung in an AttributeGraph cycle; isolating the form identified `ViewThatFits`. Mac now uses a stable horizontal row. Export opened, saved a valid one-page PDF, reopened and switched to JPEG.
- Mac Tools initially retained Done over the pushed document picker, hiding Continue. Moving each Mac action into its own content footer fixed it: Continue disabled without selection, enabled after selecting, then extraction of page 2 produced and opened a new one-page document.
- Mac QuickLook displayed actual synthetic en/fr/es text; Info showed type, filename, size and dates; closing Info preserved preview; Done dismissed it. Save a Copy initially wrote text bytes as `.pdf` because `ExportedFile` advertised only PDF/image/ZIP. Advertising raw `.data` with the caller-supplied type now saves `.txt`; `cmp` confirmed byte equality. Settings window viewed with live counts, storage, language and About. Backup action not yet exercised on Mac.
- Earlier focused iPad preview/error checks: **2/2 passed**; `/tmp/papernest-preview-ipad-final.log`. iPhone screenshots inspected for actual text and French error/dismissal.
- Still unverified: Mac fr/es layouts, full Mac import/crop/reorder/keyboard flows, sandboxed panel permissions, external app interoperability, real camera/Pencil. Native UI-control tools became unavailable before the remaining Mac checks; do not infer a pass from a build.


## File tools — F1 initial slice (2026-10-22)

- `./scripts/test.sh`: **144 tests passed**, zero failures; no Swift compiler warnings. Logs: `/tmp/papernest-file-tools-unit-final.log`. New suites: `ColorLabelTests`, `DocumentCompositionTests`, `LibraryReloadTests`; workflow `composedDocumentsExportInOrderAfterTheSourcesAreDeleted` verifies a real PDF export after merge/extract/duplicate and deleting all sources.
- `./scripts/build-mac-app.sh`: **passed** on the final code, zero Swift compiler warnings. Log: `/tmp/papernest-file-tools-mac-final.log`. Mac UI interaction/visual checks remain unrun.
- `./scripts/ui-test-ios.sh 63992C10-33B4-4CE3-91C3-EE23ECC595A5`: **11 passed, 1 skipped** (iPad-only Pencil), zero failures. Includes existing folder/crop/settings/export/navigation/filter tests plus two new file-tool workflows. Log: `/tmp/papernest-file-tools-ui-full.log`; xcresult `Test-PaperNest-iOS-2026.10.22_05-54-02--0500.xcresult` under the cache's `xcodeproj/Logs/Test`.
- After review fixes, both new phone workflows **passed again**, including the added checks for Blue while selecting and Done after delete-all. Log: `/tmp/papernest-file-tools-ui-final.log`; xcresult `Test-PaperNest-iOS-2026.10.22_05-59-53--0500.xcresult`.
- Final short-title/selection-border layout rerun and focused iPad workflow: **pending** at this checkpoint. Logs will be `/tmp/papernest-file-tools-layout-final.log` and `/tmp/papernest-file-tools-ipad.log`.

Coverage: v3→v4 migration, persistent/removable labels, atomic batch rollback; distinct fresh object/page/item IDs, source order and explicit merge order, labels, name deduplication, missing/deleted/wrong-owner selections, missing files/asset rows/remote-only bytes, late SQLite failure rollback, independent mutable content and lifetime after deleting originals, current/stale OCR and index remapping. No OCR engine is claimed. UI covers duplicate/merge/extract/relaunch, keep-originals, merge reorder and cancel, empty-page selection disabling Create, plus en/fr/es screens.

Found during verification: the initial UI test expected Export to remain visible after opening a long-named result; iOS put it in overflow. SQLite and the AX hierarchy confirmed save/open succeeded; the test now asserts page thumbnails. Review regression demonstrated canceled/outdated reloads could publish stale rows; generation/scope/search checks now reject them. Screenshot QA found crowded French/Spanish sheet titles and selected-grid borders touching metadata; titles are shortened and borders now surround previews. Toolchain logs emit AppIntents metadata warnings and Simulator diagnostics; these are not Swift compiler warnings. No new device, sanitizer, camera or native Mac interaction test is claimed.


Only checks that were actually run are recorded as passed. "Not run" means not run.

## Environment (session 1, 2026-10-20)

- MacBook (Apple silicon, arm64, 16 GB), macOS 26.6.2 (25G83)
- Command Line Tools 26.2: Swift 6.2.3, macOS 26.2 SDK. No iOS SDK and no simulators through most of the session.
- Xcode 27.1 (27A9275) appeared in `/Applications` mid-session. After the owner accepted its license, the later results ran under Xcode (Swift 6.4, iOS 27.1 and macOS 27.0 SDKs, iOS 27.1 simulator runtime). The earlier results used `DEVELOPER_DIR=/Library/Developer/CommandLineTools`.
- The checkout is on the iCloud-synced Desktop, so build output goes to `~/Library/Caches/PaperNest/build-<hash>` (`scripts/env.sh`). Inside the synced folder, `codesign` rejected test bundles because of iCloud's Finder-info attributes.

## Automated results

| Command | Result |
|---|---|
| `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./scripts/test.sh` | **Passed: 87 tests in 18 suites** (parameterized tests count once; 105 cases in all), 0 failures, 0 compiler warnings. The final code passed 11 consecutive full runs. |
| `./scripts/test.sh --sanitize=thread` (CLT) | **Blocked**: macOS refused to load the CLT sanitizer runtime ("Sanitizer load violates platform policy") |
| F2c: Photos import, HEIC, and two test defects (Claude, 2026-10-22 17:25–18:40) | `./scripts/test.sh`: **passed, 218 tests** (43 + 68 + 46 + 26 + 35), 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 17 passed, Markup skipped, twice in a row** after the fix described below. **HEIC, verified before claimed.** Photos from the system library are almost always HEIC and the sniffer did not know it, so a picked photo would have been kept as an opaque file rather than an editable page. ImageIO was checked first on this machine — it writes HEIC, reads it back as `public.heic`, and keeps dpi — and only then was `AssetKind.heic` added. Detection is by content (`ftyp` box plus a HEIF-with-HEVC brand); `avif` shares the container and is deliberately **not** claimed. Completeness is checked by walking the top-level box chain, because the format has no end marker and ImageIO decodes a truncated file without complaint. **Schema v6** widens `assets.kind` through the same rebuild path as v5; sync now has to take **v7 or later**, and the three documents that named an older number were corrected. `HEICImportTests` ×6: the platform really round-trips HEIC; a 600×900 photo at 300 dpi becomes a 144×216 pt page; the type comes from the bytes even when the file is named `notes.txt`; a truncated HEIC is rejected rather than imported part-blank; an `avif` brand is not claimed; and a HEIC page renders landscape. **Photos import.** `LibraryModel.importPhotos` makes **one document per photo** — a photo of a receipt is a document, not a page of some other one — reports a photo it cannot read while still importing the rest, and lands them in the folder on screen. `PhotoImportTests` ×3 cover all three. The picker itself is `PhotosPicker` on the Tools screen: it is the system's own UI driven by the user, so the UI test asserts the entry point exists and the unit tests cover everything after it, rather than pretending to drive it. **Not built:** video from Photos, which needs a streaming transfer representation instead of loading whole items into memory. **Two test defects fixed, both found by running rather than assuming.** (1) `cancellingTheBackupLeavesNothingBehind` observed progress and then cancelled, which a small library can win by finishing first; it failed about **one full run in two**. The export is now held at page three until the cancel has been issued, and three consecutive full runs are clean. (2) `testFilterStripAndTitleMenu` looked the title menu up as `buttons["Crop target"]` with a `staticTexts` fallback, but the button is labelled `"Crop target, Actions Menu"` and the StaticText is not reliably present — it had been **passing on luck** and failed once the device was restarted. It now matches by label prefix with an existence check, the same fix already applied to the recognition test. **Environment note, not a product failure.** One UI run before the fix showed three unrelated failures including *"Simulator device failed to launch com.example.papernest. No such process"*; all three passed after `simctl shutdown` and a clean boot. The app had been launched manually through `simctl` earlier in the session. Restart the device before investigating a spread of unrelated UI failures. |
| F2b finished: archiving a selection, files included (Claude, 2026-10-22 16:45–17:20) | `./scripts/test.sh`: **passed, 209 tests** (40 + 68 + 40 + 26 + 35), 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 17 passed, Markup skipped**. An archive entry can now be a **document** (rendered to PDF as the app shows it) or a **file** (copied byte for byte under the name it came in with): `LibraryExportEntry` and `Exporter.exportArchive`, with `exportLibrary` kept as a wrapper so existing callers are unchanged. Progress counts pages for documents and one unit per file, so a mixed selection still reports sensibly. **Two real gaps closed, both found by asking what a selection containing a file would do:** (1) **Export as ZIP… silently skipped file items** — the action was gated on `pageCount > 0`, so selecting a video and a document archived only the document; (2) **the Settings backup dropped every file** for the same reason, which made "Export All Documents" a backup that quietly left things out. Both now include files, and the footer in en/fr/es says so instead of promising documents only. The Tools screen's archive picker accepts file items too, while merge, extract and split still refuse them. New `BulkExportTests`: a mixed selection produces `Notes.txt` and `Letter.pdf` **in selection order**, the text file comes back **byte for byte** (not re-encoded) and the PDF still holds its text; a selection of only files still produces an archive, where before it failed with `noPages`; and the Settings backup carries both kinds. A selection of only **page-less documents** is still an error rather than an empty archive. **Not built:** compression presets with before-and-after sizes (reference row 35) — this is archive creation, not size reduction; RAR creation, which the owner's screenshots do not ask for. **Not verified:** the Mac; an archive larger than the 2 GiB default budget. |
| F2b: reading archives, and F2a preview completion (Claude and Codex, 2026-10-22 15:20–16:40) | **Both agents were in the tree at once for part of this; see the note under this row.** Final combined state: `./scripts/test.sh` **passed, 206 tests** (37 + 68 + 40 + 26 + 35), 0 failures, 0 compiler warnings; `./scripts/build-mac-app.sh` and the iOS Simulator build **passed, 0 warnings**; `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro) **TEST SUCCEEDED — 17 passed, Markup skipped**. **Claude — ZIP extraction.** New `ZipReader` (PaperNestImport) parses the central directory, inflates method 8 through `Compression`, verifies CRC-32, and refuses what it cannot open safely. `ZipReaderTests` ×9 use adversarial fixtures: **path traversal in five shapes** (`../escape.txt`, `/etc/passwd`, `notes/../../escape.txt`, a backslash form and a drive letter), a **real symlink** archive from `/usr/bin/zip --symlinks`, a **real encrypted** archive from `zip -P`, an **expansion-ratio bomb**, a **total-size budget**, CRC corruption, and a file that is not an archive at all. Every refusal leaves the destination absent, checked in each test. `LibraryModel.extractArchive` unpacks into a folder named after the item, sending each extracted file through the page importer first and keeping anything else as a file item; `ArchiveExtractionTests` ×3 prove a PDF inside an archive becomes a real one-page document, a `.txt` beside it stays a file with its bytes intact, the archive itself is kept, and an encrypted or fake archive adds **nothing** — no folder, no items — while showing a plain message. **Codex — file previews finished.** Three real defects in the preview Claude had written the hour before: the `QLPreviewItem` getters needed `nonisolated` under strict concurrency; a presentation modifier on the empty List sections of `LibraryHomeSections` **did not present at all**, so Recent now routes through a root-owned `FilePreviewPresentation`; and the temporary copy was being deleted in `onDisappear`, which is wrong because a child presentation can cover the parent — it is now owned by a `PreparedFileCopy` that cleans up on release, and Show Info reuses the preview's copy instead of making a second. Codex also added `testMissingFilePreviewCanBeClosedInEveryLanguage`, which checks a **failed** preview can still be dismissed in en, fr and es — the original could trap the user in a full-screen cover with no way out. **Process failure, recorded on purpose.** Claude ran `git add -A` in the shared checkout while Codex was mid-slice, so commit `5abebea` contains Codex's in-flight preview helper and Recent routing under a message describing only Claude's version. Codex recorded the same event from its side. The commit stands; the handoff now carries a work division and the rule that staging is by explicit path. **Not verified:** the Mac (unchanged — still never viewed); RAR, which is not implemented; archives larger than the default 2 GiB budget; extraction on a real device. |
| F2a step 3: QuickLook preview for file items (Claude, 2026-10-22 15:25–16:05) | Tapping a file now opens it with the system's own preview instead of a row of metadata; **Show Info** keeps the details sheet, in the ⋯ menu. `./scripts/test.sh`: **passed, 191 tests**, 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings** — the Mac path compiles `QLPreviewView` from QuickLookUI, the iOS path `QLPreviewController`. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 16 passed, Markup skipped**; the rewritten `testAFileItemPreviewsAndShowsItsTypeSizeAndACopy` taps the file, waits for the preview, dismisses it, then opens Show Info and checks the original name and Save a Copy. Same test on the **iPad Air 13-inch (M4): passed** (21.1 s). **QuickLook supplies its own Done button only when it presents itself**; here SwiftUI owns the presentation, so the dismissal is ours (`file-preview-done`). iOS uses a full-screen cover, the Mac a sheet with Done and Show Info beneath the preview. **Fixed in passing: a temporary-file leak.** `FileKind.temporaryCopy` wrote a copy into a new directory under the system temporary directory for Share and Save a Copy, and nothing ever removed it — every details sheet left one behind. Both the details and preview sheets now discard it on dismiss (`FileKind.discardTemporaryCopy`). **Environment flake, recorded rather than hidden:** the first run of this test failed with *"PaperNestUITests-Runner encountered an error (Early unexpected exit, operation never finished bootstrapping — the test runner exited with code 0 before establishing connection)"*. The same test passed on an immediate rerun and in two later full runs. Nothing in the app changed between them; this is the Simulator's runner-bootstrap flake, not a product failure. **Not verified:** the Mac preview on screen (`QLPreviewView` compiles and is wired, but the Mac UI has still never been viewed); preview of a large video or an Office document; French and Spanish on this screen. |
| F2a step 2: files in the library (Claude, 2026-10-22 13:50–15:10) | **Any file can now be kept, shown and copied back out.** `./scripts/test.sh`: **passed, 191 tests** (31 + 68 + 31 + 26 + 35), 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 16 passed, Markup skipped**; the new `testAFileItemShowsItsTypeAndSizeAndOffersACopy` also **passed on the iPad Air 13-inch (M4)** (13.6 s). **Streaming import:** `AssetFileStore.store(contentsOf:kind:originalFilename:)` copies and SHA-256-hashes in one pass with a 1 MiB buffer, so a large video never has to be held in memory. `StreamingAssetTests` ×5: a file spanning several buffers plus a partial one hashes identically to the whole-file path; the streaming and in-memory stores agree and deduplicate to one file on disk; a damaged stored file is replaced rather than trusted; a missing source leaves no staging file behind; an empty file still round-trips. **Import:** `FileItemImporter` sniffs the type through the file's own `contentTypeKey`, reads under `NSFileCoordinator` with security-scoped access, and creates the item. `FileItemImportTests` ×6 cover any type, folders, duplicate names, content-addressed deduplication with each item keeping its own filename, and a missing file leaving nothing behind. **A dynamic UTI is never stored:** the system invents one for an unknown extension, and it means nothing on another device or after sync, so such files are recorded as `public.data` — found by a test that expected the honest value. **UI:** the library's Import now offers every type and falls back to a file item when something cannot become pages (Add Pages and Replace Page stay restricted to PDF/JPEG/PNG); a file tile shows a type-derived symbol and its size where a document shows its page count; tapping a file opens a details sheet with kind, original name, size, dates, Share and Save a Copy, which copies from the asset file rather than loading it. The seeder has the same fallback, so `papernest-seed` can seed a file item. **Contract change, deliberate:** importing a `.txt` used to fail with "unsupported type". It now becomes a file item, and the M1 gate test `importEditRelaunchAndExportKeepsPagesAndOrientation` was updated to assert the new behaviour (4 items, one of kind `.file`, no error) rather than the old. **Also:** a `LabeledContent` row is one accessibility element labelled "<label>, <value>" — match it by prefix or substring, not by the value alone. **Not built:** QuickLook preview (the owner chose it; the details sheet is the stand-in until then), Photos import, a system Inbox, ZIP/RAR, and compression presets. **Not verified:** the Mac, and a genuinely large file on a device. |
| F2a step 1: schema v5 and file items in the store (Claude, 2026-10-22 12:40–13:40) | `./scripts/test.sh`: **passed, 180 tests** (31 + 63 + 25 + 26 + 35), 0 failures, 0 compiler warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone): **TEST SUCCEEDED — 15 passed, Markup skipped** (no UI in this step). **A data-loss trap was found and proved before any code was written.** The design called for widening two CHECK constraints, which SQLite can only do by rebuilding the tables. With `PRAGMA foreign_keys = ON` — which this store sets — `DROP TABLE items` performs an implicit delete that **cascades into `pages`**. A standalone sqlite3 experiment confirmed it: *pages before: 2 → pages after: 0*, items intact. Written as first sketched, the v5 migration would have silently emptied every document in a user's library on upgrade. `Schema.Migration` now carries `rebuildsTables`, and `LibraryStore.migrate` runs those migrations with foreign keys off and verifies them with `PRAGMA foreign_key_check` inside the transaction before the version bump, restoring enforcement with a `defer`; a dangling reference throws `StoreError.migrationBrokeReferences` and rolls the migration back. **Schema v5:** `items.kind` and `assets.kind` rebuilt to accept `'file'`, plus a `file_items` table (item_id, asset_id, uti, original_filename, byte_count). New `FileItemMigrationTests` ×3: a v4 library with a folder, two documents, **two pages**, a tag, a color label, an asset and a search row survives the upgrade with every row intact and `foreign_key_check` clean; the rebuilt tables accept `'file'` and still reject nonsense kinds; and **a library upgraded from v4 is byte-identical in `sqlite_master` to one created fresh at v5**, so later migrations cannot diverge between them. **Store API:** `createFileItem`, `filePayload`, `ItemSummary.file`, `ItemKind.file`, `AssetKind.file` (extension `bin`), `FilePayload`. New `FileItemTests` ×6: a file keeps its bytes, name and UTI across a reopen and reports no pages; files share folders, favorites, color labels, search, trash and restore with documents; **the asset sweep keeps bytes a file item still references** — the hazard the design named — when a document that shared the same content-addressed bytes is permanently deleted; duplicating a file shares the bytes and outlives the original; merge, split and extract refuse file items with `invalidOrder` and change nothing; and storage usage counts a file's bytes while adding no pages. The page importer now rejects uninterpretable bytes explicitly rather than falling through. **Not built yet (F2a step 2):** streaming import for large files, QuickLook previews and thumbnails, the details sheet, library cells for file items, and share/save-a-copy. Nothing in the UI shows a file item yet. |
| F4b: searchable PDF export (Claude, 2026-10-22 11:45–12:30) | `./scripts/test.sh`: **passed, 171 tests** (31 + 54 + 25 + 26 + 35), 0 failures, 0 compiler warnings. Exported PDFs now carry each page's recognized text as an invisible layer, so a scan can be searched and its words selected in any reader. `ExportOptions.includesRecognizedText` (default on) controls it; `PageRenderer.recognizedLines(for:)` applies the same currency rule as search, so only a `.completed` result matching the page's revision is written. New `SearchablePDFTests` ×7, all reading the exported file back with PDFKit: the words are extractable; **"Quarterly" lands where it was read** — 10% from the left and 8% from the top, within 2–3 points — and the full line spans the 60% of the page width it was recognized at, within 5%; the layer is **invisible** (a pixel sweep across the text band matches an export made without it); the option off writes nothing; pending, failed and older-revision results are not exported; a vector PDF keeps its own selectable text without any recognition; and a **cropped, 90°-rotated page still places its text on the paper**. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 15 passed, Markup skipped** (no UI change in this slice). **Two bugs found and fixed while testing:** (1) placing a line by its page-space bounding box squeezed a rotated page's text into a sliver — only the letter "R" of "Rotated words" survived extraction; the layer is now drawn in **source space** with the page transform concatenated onto the CTM, so crop and rotation are handled by the geometry rather than by hand. (2) `CTLineDraw` overrides `CGContext.textMatrix` from the line's own runs, so the horizontal stretch was silently dropped and every line exported at its natural width (0.38 of the page instead of 0.60); the stretch now goes on the CTM. **Also worth knowing:** swift-testing reports a failure when an optional inside a `#expect` expression is nil, even when the overall condition is true — bind `pdf.page(at:)?.string` to a local first. **Not verified:** opening an exported file in Preview, Acrobat or Files (structural checks and PDFKit extraction only); a real photographed scan; the Mac. **Not built:** a UI toggle for the text layer (it is always on when current text exists), and text extraction from vector PDFs into the search index. |
| F4a: text recognition and search inside pages (Claude, 2026-10-22 10:15–11:40) | `./scripts/test.sh`: **passed, 164 tests** (31 + 54 + 25 + 19 + 35), 0 failures, 0 compiler warnings. New `TextRecognizer` (Vision, on device, `VNRecognizeTextRequest`, accurate level, en-US/fr-FR/es-ES filtered against `supportedRecognitionLanguages()` so no unsupported language is claimed) and `PageRenderer.renderSourceForRecognition`, which renders the **upright, uncropped, unfiltered** source — text is read from the paper, not from the current view of it. `TextRecognitionTests` ×5 run real recognition on synthetic printed pages: the words come back in reading order; boxes use a **top-left origin** in source space (Vision's bottom-left is flipped in exactly one place) and are **not** inflated to `NormalizedRect.minimumSide`, for which `NormalizedRect.exact` was added; a blank page yields nothing; an unsupported language throws; and a crop + rotation + grayscale leave the recognized text and its boxes unchanged. `LibraryStore.saveRecognition` now keeps `search_index` in step in the same transaction, indexing only a `.completed` result whose `sourceRevision` matches the page — so Codex's existing "stale result cannot become current" test still holds — and `replacePageContent` drops a page's OCR rows, because a rescan puts different paper on the page. `RecognitionSearchTests` ×6 and `RecognitionWorkflowTests` ×2 cover: a word only the page carries finds the document, re-running replaces rather than appends, an unfinished result leaves nothing findable, accents fold, deletion removes the text, a stale result is kept but unfindable, recognition for a missing page is rejected, the text survives a relaunch, **rotation keeps it findable** and **a rescan does not**. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 15 passed, Markup skipped**, including the new `testRecognizeTextMakesAWordOnThePageSearchable` (22.4 s: opens a 3-page sample, runs Recognize Text from the overflow menu, returns to the library, types "Quarterly" — a word printed on page 1 and absent from the title — and finds the document). Same test on the **iPad Air 13-inch (M4): passed** (21.7 s). **Found while testing:** the iPhone document toolbar has **no ⋯ menu at all** (only iPad and Mac do), so the action was unreachable on the main scanning device; it now sits in each layout's one overflow menu — the bottom bar's ⋯ on iPhone, the toolbar's ⋯ on iPad and Mac. Also: SwiftUI menu items do not expose `accessibilityIdentifier` to XCUITest, so menu entries are matched by label, as the rest of this suite already did. **Not verified:** recognition on a real photographed scan (synthetic printed pages only); handwriting (Vision's printed-text path only); the Mac; performance on a long document (no numbers taken); the French and Spanish menu entries on screen. **Not built yet in F4:** searchable-PDF export, a recognition status/progress surface outside the open menu, automatic recognition after a scan, and re-recognition prompts after a rescan. |
| Tools screen (Claude, 2026-10-22 09:40–10:05) | One home for the tools that work, reached from a wrench button in the library toolbar (every platform) and the iPhone home's toolbar. `Sources/PaperNestUI/ToolsSheet.swift`: a **Create** group (Scan, Import…) and a **Documents** group (Merge Documents, Extract Pages, Split into Pages, Export as ZIP…), each document tool pushing a picker that enforces its own rule — merge needs two or more, split only offers documents with more than one page, and rows a tool cannot use are shown disabled with their page count rather than hidden. Picked order is preserved, so a merge starts in the order the user tapped. **No placeholder tiles:** every tile runs today. `./scripts/test.sh`: **passed, 151 tests**, 0 failures, 0 warnings. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 14 passed, Markup skipped**, including the new `testToolsScreenPicksTwoDocumentsAndMergesThem` (29.6 s: Tools → Merge → picks one document and checks Continue is **disabled**, picks the second and checks it is enabled → names the result → the merged document opens → relaunch finds `Tools merged, 2 pages` with both originals intact). `scripts/ui-test-ios.sh 62328381-…` (iPad Air 13-inch M4): **TEST SUCCEEDED** (26.6 s). New disposable library `/tmp/papernest-tools-screen-library`, seeded in `scripts/ui-test-ios.sh`. **Found and fixed during the run:** the Tools entry was first a third large button in `CaptureActions`, which pushed the Folders section's **+** off the iPhone home and broke `testAFolderMadeInTheSidebarHoldsAMovedDocument`; it moved to the toolbar and that test passes again. Screenshots `docs/screenshots/f1-tools-screen-{en,fr,es}.png`, captured with a new screenshot hook `-PaperNestDebugShowTools YES`: **French and Spanish were inspected and fit** — "Fusionner des documents" and "Combinar documentos" wrap to two lines inside their tiles, "Exportar como ZIP…" fits on one line, and Scan is correctly disabled with no Simulator camera. **Not verified:** the Tools screen on the Mac (never viewed); the picker's own layout in fr/es (only the tile grid was captured); VoiceOver. |
| F1 follow-up: export a selection as one ZIP (Claude, 2026-10-22 09:00–09:35) | `./scripts/test.sh`: **passed, 151 tests** (29 + 48 + 20 + 19 + 35), 0 failures, 0 compiler warnings. The archive writer needed no change — `Exporter.exportLibrary(_:archiveName:)`, already used by the Settings backup, takes any item list — so the new code is `BulkExportModel`/`BulkExportSheet` and the menu entry. New `BulkExportTests` ×3: (1) the archive holds **only** the chosen documents, **in selection order** (`unzip -Z1` → `B.pdf`, `A.pdf`, not library order), skipping a page-less document selected between them; the extracted PDFs have the right page counts and text (PDFKit); the library is byte-for-byte unchanged afterwards; and `finish()` deletes the temporary archive and returns to idle. (2) Cancelling returns to idle at once, never becomes ready afterwards, and leaves no `PaperNestExport-…` directory behind. (3) An empty selection never starts an export, and a selection whose documents all have no pages **fails** instead of writing an empty archive. `./scripts/build-mac-app.sh` and the iOS Simulator build: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 13 passed, Markup skipped**, including the new `testDocumentToolsBulkExportMakesOneArchiveFromTheSelection` (16.4 s: Select → Select All → ⋯ → Export as ZIP… → waits for the "Ready: <size>" status and the Save button → Done returns to the library). `scripts/ui-test-ios.sh 62328381-…` (iPad Air 13-inch M4): **TEST SUCCEEDED**, bulk export (15.2 s) and split (21.2 s). The UI test reads the split test's library without changing it, which the unit test above independently proves. **Not verified:** the Save panel and Share sheet destinations for this archive (the single-document equivalents are covered by `testExportSaveOpensTheSaveDialog…`); the French and Spanish sheet on screen; the Mac. **Deliberately not claimed:** this is archive creation, not file-size reduction — explicit compression presets with before/after sizes remain F2/F4. |
| F1 follow-up: split a document into one document per page (Claude, 2026-10-22 08:20–08:55) | `./scripts/test.sh`: **passed, 148 tests** (26 + 48 + 20 + 19 + 35), 0 failures, 0 compiler warnings. New `DocumentSplitTests` ×4, written before the implementation: (1) one document per live page in stored order, after a reorder, keeping the source's folder and color and leaving the source's pages and name untouched — and identical caller-supplied names still land as distinct siblings (`Lease 2/3/4`); (2) soft-deleted pages are skipped, page objects are copied with fresh IDs and the same payload, and the parts stay readable after the original is permanently deleted (reopened store, `integrityCheck` clean); (3) empty, missing and recently-deleted sources are rejected with nothing created; (4) a synthetic `page_objects` trigger failing on the **last** page rolls back the two documents already created — `items`, `pages`, `page_objects`, `search_index` and `assets` row counts unchanged — and the same split then succeeds. `./scripts/build-mac-app.sh` and `xcodebuild -scheme PaperNestUI … iOS Simulator build`: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro): **TEST SUCCEEDED — 12 passed, Markup skipped**, including the new `testDocumentToolsSplitMakesOneDocumentPerPageAndKeepsTheSource` (23.9 s: splits a 3-page document from its ⋯ menu, finds `Split target — Page 1`, relaunches, finds all three parts and the untouched 3-page original, and checks that Split is **disabled** on a one-page document). `scripts/ui-test-ios.sh 62328381-…` (iPad Air 13-inch M4): **TEST SUCCEEDED**, the split test (21.0 s) and the merge/extract test (56.7 s). The UI test seeds a new disposable library `/tmp/papernest-file-tools-split-library` from `Samples/multilingual-letter.pdf` (3 pages), added to `scripts/ui-test-ios.sh`. **Not verified:** the French and Spanish menu labels were not looked at on screen (they are plain menu rows; `LocalizationTests` covers key and format-argument parity); splitting on the Mac; splitting a very large document (no performance numbers taken). |
| F1 document tools (select, duplicate, merge, extract, color labels) — verification of the uncommitted slice, Claude, 2026-10-22 06:03–06:25 | `./scripts/test.sh`: **passed, 144 tests** (20 + 44 + 19 + 26 + 35), 0 failures, 0 compiler warnings. New suites: `DocumentCompositionTests` (selection and stored page order, fresh identities, color kept by duplicate/extract and dropped by merge, copies outlive permanently deleted originals, a missing or `remoteOnly` asset aborts, a late `page_objects` failure leaves all 8 tables row-for-row unchanged and `integrityCheck` clean, missing or deleted destination folders rejected, unfinished or stale recognition cannot become current), `ColorLabelTests` (relaunch, all-or-nothing batch, v3 → v4 migration), `LibraryReloadTests` (an outdated reload cannot publish rows into a newer selection), and workflow `composedDocumentsExportInOrderAfterTheSourcesAreDeleted`. `./scripts/build-mac-app.sh` and `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`: **passed, 0 warnings**. `scripts/ui-test-ios.sh 63992C10-…` (iPhone 17 Pro, iOS 26.5): **TEST SUCCEEDED — 11 passed, the iPad Markup test skipped as designed**, including `testDocumentToolsDuplicateMergeExtractAndKeepOriginals` (59.2 s) and `testDocumentToolsLocalizedSelectionOrderAndCancellation` (92.5 s). **All nine en/fr/es screenshots were exported from the result bundle and looked at** (selection bar, merge sheet, extract sheet): no truncation anywhere, saved as `docs/screenshots/f1-tools-{selection,merge,extract}-{en,fr,es}.png`. Spanish is the tightest selection bar ("Selección: 2 · Deseleccionar todo · Más" spans nearly the full width at the default text size); `ViewThatFits` stacks it when it no longer fits. **iPad Air 13-inch (M4), iOS 26.5: both new tests failed at first, on iPhone-specific assertions; fixed at the owner's request and now passing (see the end of this row).** (1) `…KeepOriginals` line 356 waits for `page-thumbnail-1`, which only exists in the compact-width `PageScroller` (`DocumentView.swift:632`); the iPad uses the regular-width page column. The merge itself worked: the app hierarchy captured at the failure shows the document open with the navigation bar titled "Combined test" and All Documents at 3. (2) `…LocalizedSelectionOrderAndCancellation` line 426 compares the `minY` of two app-wide `staticTexts` matches and got 556.0 for both. On iPad the merge sheet is a *form* sheet, so the library grid stays visible behind it, and 556 pt is exactly where the two grid tile labels sit, side by side — so the query matched the grid, not the sheet. **Unexplained, and worth a VoiceOver check:** `ItemCell` is `.accessibilityElement(children: .ignore)`, so those tile name texts should not be exposed as separate elements at all. If they are, selection-mode tiles may read as fragments to VoiceOver, which would be an app bug. A frame extracted from the test's own screen recording at t = 21.5 s showed the sheet itself was correct: row 1 "Crop target 2", row 2 "Crop target", with the up/down arrows disabled at the ends. The assertions pass on iPhone only because the page sheet covers the library. **Fix applied** (Claude, 06:28–06:40, on the owner's instruction, taking `AppUITests.swift` and `DocumentToolsSheet.swift` from Codex): the test now waits for the new document's navigation bar (`Combined test`, then `Combined test — Pages`) instead of `page-thumbnail-1`, and each merge row's name `Text` carries an `accessibilityIdentifier` `merge-row-<n>` that the test matches instead of the bare name. **Re-verified after the fix:** `./scripts/test.sh` **144 tests passed**, 0 warnings; `./scripts/build-mac-app.sh` and the iOS Simulator build **0 warnings**; `scripts/ui-test-ios.sh 63992C10-…` (iPhone) **TEST SUCCEEDED, 11 passed + Markup skipped**; `scripts/ui-test-ios.sh 62328381-… -only-testing:…` (iPad) **TEST SUCCEEDED, both tests passed** (58.2 s and 86.1 s). That iPad run was the first to exercise **extraction, and the French and Spanish flows, on iPad**; its nine screenshots are `docs/screenshots/f1-tools-ipad-*.png` and show no truncation (the iPad sidebar wraps "Supprimés récemment" and "Eliminados recientemente" onto two lines, which is fine). **Still open:** it is unexplained why the grid's tile name texts were matchable at all, since `ItemCell` is `.accessibilityElement(children: .ignore)`; the fixed test no longer depends on it, but selection mode deserves a VoiceOver check. **Still not verified:** the whole feature on the Mac (never viewed, see the manual checklist); a long document name in the merge and selection UI (every fixture is "Crop target"); a failed save keeping the sheet open (code-inspected only: `DocumentToolsSheet.create()` sets `failed = true` and does not dismiss). **Design nit:** the extract sheet's per-page checkmark is plain black, while every other selection indicator uses `Theme.accent` blue (`DocumentToolsSheet.swift:97`, visible in all three languages). |
| Pass 7: Apple Pencil on iPad, first slice (Claude, 21:45–22:50) | `./scripts/test.sh`: **passed, 128 tests** (new: `InkRenderTests` ×3: pen ink follows rotation and crop and the content-only render omits it; highlighter multiplies over the page; per-point width. `InkExportTests` ×2: PDF keeps selectable text and draws the ink; JPEG of a transparent page keeps black ink. `ObjectChangeTests`: one gesture = one transaction and one revision bump; a bad object aborts the whole change. `InkConversionTests` ×2: PencilKit round trip on a rotated, 1.5× page keeps position, width profile, tool and color. Workflow `inkChangesUndoRedoAndSurviveRelaunch`). `scripts/ui-test-ios.sh 63992C10-…` (iPhone): **passed, 9; the iPad Markup test skipped as designed**. **iPad Air 13-inch (M4), iOS 26.5: `testMarkupWithFingerDrawingSavesAStroke` passed** (finger drag draws nothing while Pencil-only; with Draw with Finger one stroke is saved; still there after leaving Markup and after a relaunch). Screenshot `design-7-ipad-ink-rendered-en.png`: the saved stroke renders at 30–70 % × 50–55 % of the page, exactly where it was dragged, and in the thumbnail. Mac and iOS builds: 0 warnings. **Review fixes (23:00–23:20):** (1) the canvas clears its undo history on *every* reload, not only on page switch, so an undo after a zoom can't save old-scale strokes; (2) a race: SwiftUI refreshed the canvas before a stroke was saved, so it reloaded empty (stroke flickered out, undo wiped); diagnosed with logs, fixed by tracking the states the canvas has sent; (3) objects are filtered to the shown page. **Opening Markup writes nothing** (iPad, `-PaperNestDebugShowMarkup YES`: page revision and the stroke's `modified_at` unchanged in SQLite). Screenshot `design-7-ipad-markup-en.png`: Markup and Draw with Finger in the toolbar, the system tool palette at the bottom. **Undo follow-up (23:20–23:45):** logs showed a stroke's undo step was recorded but nothing ever undid it: SwiftUI's Edit menu takes ⌘Z (not the canvas), and the palette's Undo stayed **disabled** because PencilKit refreshes it from undo-manager notifications. Now each ink change is one step in the **document's** undo history (`DocumentModel.changeInk` inverse), PencilKit's own registration is off, and the canvas's `PaletteUndoManager` forwards undo/redo and relays the document's notifications. The zoom buttons are hidden while marking up (the palette covered them: the test's "Zoom In" tap hit the color picker). **iPad test passed:** palette Undo → 0 strokes, Redo → 1; after a pinch-zoom (canvas size checked) Undo → 0, Redo → 1; persistence as before. **Not verified:** ⌘Z itself (a ⌘Z injected by XCUITest never reached the app's undo in the Simulator, also before these changes); the Edit menu route should apply, check on a device. **Not verified:** Apple Pencil itself (needs a real iPad), the palette's eraser and lasso by hand. |
| Design pass 4 (document view), Claude, 21:10–21:30 | `./scripts/test.sh`: **passed, 119 tests**. `scripts/ui-test-ios.sh 63992C10-…`: **passed, 9 UI tests** (new `testFilterStripAndTitleMenu`: the strip's Grayscale tile applies and becomes selected, Original restores; the title menu adds then removes Favorites). `build-mac-app.sh` and the iOS build: passed, 0 warnings. Tapped through on iPhone: the title menu shows Rename… / Add to Favorites / Export…, and Add to Favorites set `is_favorite = 1` in SQLite. **First iPad check** (iPad Air 13-inch M4, iOS 26.5, screenshots only): library (sidebar counts and folders, 4-column grid, sort and layout controls) and document (title ▾ at the leading edge, rotate/crop/filter centered, Export and ⋯ trailing, page column with `+`). Screenshots `docs/screenshots/design-4-*`. **Not verified:** the Mac document window; iPad interactions (screenshots only); the selected-page border (system highlight remains). |
| Design pass 3 (Export sheet), Claude, 20:50–21:00 | `./scripts/test.sh`: **passed, 119 tests** (LocalizationTests cover the 7 new keys). `scripts/ui-test-ios.sh 63992C10-…`: **passed, 8 UI tests**. New: `testExportTilesSelectOneAtATimeAndCopyConfirms` (JPEG then Range then All each take their own tap inside Form rows; Copy → "Copied to the clipboard.") and `testExportSaveOpensTheSaveDialogAndClosingItKeepsTheExport` (Export → system "Save as" dialog → drag it closed → the ready footer still offers Save… and Share…). `build-mac-app.sh` and the iOS build: passed, 0 warnings. Screenshots `docs/screenshots/design-3-*`: fr (top), es (Export To), dark + largest accessibility text in fr (Pages tiles stack), en with a 5-page JPEG ZIP (Copy dimmed, note shown). **Found and fixed:** the rows' rounded corners clipped the selected tile's border (row edges are now inset); a wrapped French/Spanish label made one tile taller (tiles in a row now share a height). **Not verified:** the Mac sheet (never viewed), Share's system sheet contents, and pasting what Copy put on the clipboard into another app. |
| Design pass 2 (library, sidebar, iPhone home), Claude, 19:00–20:30 | `./scripts/test.sh`: **passed, 119 tests** (+3 `FolderTests`, +1 workflow test for folders/sort/import-into-folder). `scripts/ui-test-ios.sh 63992C10-…`: **passed, 6 UI tests**. New: `testAFolderMadeInTheSidebarHoldsAMovedDocument` (create a folder in the sidebar, move a document in from its ⋯ menu, check "1 item", delete the folder, document kept) and `testHomeRecentOpensADocumentAndSeeAllShowsTheGrid`. Existing tests updated for the iPhone home launch screen. `build-mac-app.sh` and the iOS Simulator build: passed, 0 warnings. Tapped through in the Simulator: Import from the home opens the picker, and the file lands in the library root (checked in SQLite). Screenshots `docs/screenshots/design-2-*` (library and home in en/fr/es/dark, sidebar): no truncation. **Found and fixed:** (1) buttons in a List row lost their styles (Scan looked enabled without a camera), so they moved to a section header; (2) the row's rounded corner clipped the first Recent card's date, so the Recent row is a header too; (3) on iPhone, setting the split-view selection and the library path together dropped the path (diagnosed with logs), so documents from Recent push over the home. **In-document pickers rechecked after moving the library's file importer to the root (an ancestor of every document view):** Replace Page with File… from a document opened via Recent replaced page 1 in place (3 → 5 pages, 1 history row, no new document), and Add Pages… from a document opened via All Documents added 3 pages (1 → 4, no new document), both checked in SQLite. **Not verified:** the Mac and iPad layouts; on the Mac, File > Import… and Page > Replace Page with File… after the importer move (same ancestor setup, never viewed); the camera paths (no device). |
| Combined tree: rescan + Codex's Clean & Native pass 1 (run by Claude, 18:52–19:00) | `./scripts/test.sh`: **passed, 115 tests**. `scripts/ui-test-ios.sh 63992C10-…`: **passed, 4 UI tests** (crop drag, Settings + backup, sidebar navigation, and Codex's new grid/list layout switch). |
| `./scripts/test.sh` (Xcode 27.1), after the atomic-rescan fix | **Passed: 115 tests** (20 + 26 + 17 + 17 + 35), 0 failures, 0 warnings. `scripts/ui-test-ios.sh 63992C10-…`: **3 UI tests passed**. `build-mac-app.sh` and the `PaperNestUI` iOS Simulator build: passed, 0 warnings. |
| Replace Page with File… in the owner's Simulator (iPhone 17 Pro, iOS 26.5), Xcode-built app | **Passed.** Page 2 of 3 replaced by the 3-page `multilingual-letter.pdf`: page 2 kept its place and selection, the 2 extra pages followed it (5 pages). SQLite: 1 `page_content_history` row holding the old content. Cancelling the picker (document menu and library Import) shows no alert and changes nothing. **Found and fixed on the way:** (1) replace silently became *add* (the `fileImporter` binding cleared the picker purpose before `onCompletion` ran); (2) the hand-assembled dev bundle lacked an entitlements section, so every picked file failed with "Could not resolve bookmark… permission" — `build-ios-sim-app.sh` now builds the Xcode project's app; (3) replace and extra-page insert were two commits — now one transaction (`replacePage`, nested savepoints). Undo was not exercised on the device (shake); it is covered by `LibraryWorkflowTests`. |
| `./scripts/test.sh` (Xcode 27.1), after rescan | **Passed: 111 tests** (17 + 17 + 18 + 24 + 35), 0 failures, 0 warnings. UI tests: 3 passed. |
| Rescan / replace in the owner's Simulator (iPhone 17 Pro, iOS 26.5) | The Add/Replace menu shows Scan Pages and Rescan Page **disabled** (no document camera, as intended), plus Add Pages… and Replace Page with File…; the file picker opens. **Picking failed:** "Could not resolve bookmark… you don't have permission" for files Claude copied into the simulator's Files storage from the Mac (the file provider never indexed them), so the app received nothing and the library was unchanged (checked in SQLite). Found and fixed: picker failures were silently ignored; they now show "couldn't be read". |
| `./scripts/test.sh` (Xcode 27.1), after Settings | **Passed: 107 tests** (17 + 17 + 17 + 21 + 35), 0 failures, 0 warnings |
| `scripts/ui-test-ios.sh 63992C10-…` after Settings | **Passed: 3 UI tests** (`AppUITests`: crop drag, Settings + backup, sidebar navigation), 0 warnings |
| Settings on iPhone 17 Pro (iOS 26.5), tapped through by Claude in the owner's attached Simulator | Shows 6 documents / 8 pages / 696 KB. **Export All produced `PaperNest Backup 2026-10-21.zip`; `unzip -t` OK; 6 PDFs. The cropped page is 221 × 311 pt (edit kept) and the rotated page 792 × 612.** French layout fits ("Prêt : 132 ko", Partager… / Enregistrer… / Terminé). Screenshots in `docs/screenshots/iphone-settings-*.png`. The Mac Settings window builds but has not been viewed. |
| `./scripts/test.sh` (Xcode 27.1), after the crop tool and the sidebar change | **Passed: 103 tests** (14 + 17 + 17 + 20 + 35), 0 failures, 0 warnings |
| `scripts/ui-test-ios.sh 63992C10-…` (XCUITest, iPhone 17 Pro, iOS 26.5) | **Passed: 2 UI tests**, 0 warnings: the crop drag test and a sidebar-navigation smoke test. The app also runs on iOS 26.5. |
| `scripts/ui-test-ios.sh` (XCUITest, iOS 27.1 Simulator, headless) | **Passed: `AppUITests`**, 0 warnings. Opens the crop editor, drags the top-left corner (value reads about 70% × 75%), taps Done, reopens, and finds the same crop saved. It also proved a Simulator app can open a library seeded on the Mac (`-PaperNestLibraryPath /tmp/…`). |
| `./scripts/test.sh` (Xcode 27.1) | **Passed: 87 tests** (run as 5 per-target processes: 13 + 16 + 20 + 29 + 9), 0 failures, 0 warnings |
| `./scripts/test.sh --sanitize=thread` (Xcode) | **Passed, 4 runs, 0 ThreadSanitizer reports.** `libclang_rt.tsan_osx_dynamic.dylib` confirmed linked into the test bundles with `otool -L`. |
| `./scripts/test.sh --sanitize=address` (Xcode) | **Passed, 1 run, 0 AddressSanitizer reports.** `libclang_rt.asan_osx_dynamic.dylib` confirmed linked. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build` | **Passed**, 0 errors, 0 warnings. This was the first iOS compile of the shared code, including the VisionKit camera wrapper. |
| `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS' build CODE_SIGNING_ALLOWED=NO` | **Passed**, 0 errors, 0 warnings |
| `xcodegen generate` (XcodeGen 2.46.0) | **Passed**: `PaperNest.xcodeproj` with the `PaperNest-iOS` and `PaperNest-macOS` targets |
| `xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-iOS -destination 'generic/platform=iOS Simulator' build` | **Passed**, 0 compiler warnings. The bundle has ID `com.example.papernest`, MinimumOSVersion 17.0, UIDeviceFamily 1,2, the en/fr/es lproj folders, `PrivacyInfo.xcprivacy` and the UI resource bundle. |
| `xcodebuild -project PaperNest.xcodeproj -scheme PaperNest-macOS -destination 'platform=macOS' build` | **Passed**, 0 compiler warnings. Same bundle ID, LSMinimumSystemVersion 14.0, sandbox and user-selected-file entitlements, `codesign --verify --strict` OK. |
| `./scripts/build-ios-sim-app.sh` | **Passed**: builds the Xcode project's `PaperNest-iOS` app (`com.example.papernest`), installed and launched on the simulator |
| `codesign --verify --strict` on app bundles inside the iCloud-synced checkout | **Failed after the fact**: iCloud added Finder-info attributes after signing. App output moved to `~/Library/Caches/PaperNest/…/dist`, where both bundles still verified 20 s after signing. |
| `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./scripts/build-mac-app.sh` | **Passed**: the dev `PaperNest.app` built and passed `codesign --verify --strict` (ad-hoc) right after signing |
| `open -n PaperNest.app --args -PaperNestLibraryPath <tmp>` | App launched, created the library (SQLite with WAL plus the Assets directory) at the override path, ran for several minutes, quit on SIGTERM. No crash report and no error/fault entries in `log show`. **The UI was not visually inspected.** |
| `swift run papernest-samples Samples` | **Passed**: 6 synthetic samples written |

### What the suites cover

| Area | Suites | Key checks |
|---|---|---|
| Ordering | `SortKeyTests` | Strictly ordered and valid keys, 500 random insertions against a reference array, worst-case same-gap insertion, rejection of bad bounds |
| Coordinates | `PageGeometryTests`, `PaperLayoutTests`, `ImageResolutionPolicyTests` | Each rotation moves the top-left corner to the right place. Crop then rotate. Inverse mapping. OCR boxes follow rotation. PDF `/Rotate` 0/90/180/270/−90/450. Paper fit never crops and keeps aspect ratio. Landscape paper selection. |
| Model | `CodableRoundTripTests`, `NameDeduplicatorTests` | Ink/text/image payloads with accents and € round-trip. Accent- and case-insensitive name deduplication. |
| Persistence | `LibraryStoreTests`, `DurabilityTests`, `DeletionTests`, `NamingAndSearchTests` | Reopen round trip. Moves rewrite only the moved page. Tied keys rebalance. Transform history. Exact undo of page deletion (including objects and OCR). **An undoable page deletion survives permanently deleting another item, shared original or not.** Deleted pages are purged at the next launch. **A v1 library migrates to v2 without losing pages.** **A crash between the asset write and the commit leaves only a sweepable file.** Failed transactions leave nothing. An abandoned uncommitted transaction is discarded. Newer schemas are refused and left untouched. Damaged asset files are detected. Recently Deleted restore and purge at 30 days with shared assets kept. FTS search ignores accents and is safe against injection. |
| Import | `PDFImportTests`, `ImageImportTests` | Vector PDF stored byte-identical. Rotated PDF stored upright. Password prompt, wrong password, unlocked copy with no password stored. Restricted PDFs declined. Truncated PDF/JPEG/PNG rejected. Type sniffed from content. Duplicate names. EXIF 6 rendered upright. DPI-based sizing. Scan sessions keep their order. Pages inserted mid-document. |
| Render | `RenderTests` | Rotation and crop move the marker as expected. Grayscale output is gray. B&W output is strictly two-level. Revert restores the original. Filtered PDF pages are rasterized, unfiltered ones stay vector. A missing original raises an error instead of rendering blank. |
| Export | `PDFExportTests`, `ImageExportTests`, `NamingAndZipTests` | Page order, sizes and selectable en/fr/es text. Rotated and reordered pages export upright in the new order. Letter/A4 fit without cropping. Lossy quality embeds `/DCTDecode`, Best is lossless, Compact is smaller. **Cancellation removes partial output.** ZIP validated by `/usr/bin/unzip -t`. Numbered names. Pixel size and dpi metadata. JPEG flattens transparency onto white so ink survives. Export leaves the library unchanged. CRC-32 check value. Unicode ZIP names extract byte-for-byte. |
| Rescan / replace | `PageReplacementTests`, `LibraryWorkflowTests` | Replacing keeps ID, sort key and position, bumps the revision and returns the previous content; reversing restores it exactly. **A replaced original survives permanently deleting another item and is swept only after the next launch's purge.** Missing pages and missing originals fail without changes. **A rescan with extra pages is one transaction: if an extra page fails to insert, nothing changes; revert/reapply restore it whole.** Model: a password-protected replacement file asks again after a wrong password, then replaces; a locked PDF added after a page lands right there once unlocked. Workflow: rescanning page 2 of 3 with a 2-page capture puts the extra page after it, keeps the grayscale filter and resets the rotation; undo/redo; relaunch; export order. |
| Settings / backup | `StorageUsageTests`, `LibraryBackupTests`, `AppUITests` | Live document/page counts exclude Recently Deleted and deleted pages; space used includes originals. The backup is one valid ZIP with a PDF per document under unique, sanitized names; edits (rotation) are kept; empty documents are skipped; nothing to export is an error; **cancelling leaves no files**. UI test: open Settings from the overflow menu, run the backup, close. |
| Crop | `CropMappingTests`, `CropFrameTests`, `LibraryWorkflowTests`, `RenderTests`, `PDFExportTests`, `AppUITests` | Crop ↔ editor rectangle round-trips for every rotation. Source top-left maps to top-right after a clockwise turn. A rectangle drawn on an upside-down page selects the right source half. Drag math: corners beat edges, edges clamp to the page, edges can't cross or go below the 5% minimum, moving keeps the size. **A crop of a rotated page is undoable/redoable, re-applying the same crop isn't a new edit, and it survives relaunch and exports at the cropped size, landscape, with the marker top-right.** **Found in review and fixed:** a filtered PDF page with a tight (25%) crop failed to render at 3072 px and to export to Letter/A4 (`outputTooLarge`), because the whole page was rasterized at the crop's resolution. Only the crop region is rasterized now; tests cover both paths. |
| Localization | `LocalizationTests` | Every key used exists in en/fr/es. Identical key sets and format arguments. No unused keys. Plurals (French 0/1 singular). French typography. |
| Workflow (view models) | `LibraryWorkflowTests` | **M1 gate on the Mac import path:** import PDF, EXIF photo, locked PDF (wrong password, then right) and an unsupported file. Rotate, move, delete, **undo and redo** (delete and rotate round trips). Drop the session (quit), reopen, then export: order, rotation and text preserved. Recently Deleted flow. Search. Newer-library message. |

### Simulator verified (iPhone, screenshots only)

Device: a dedicated "PaperNest iPhone Duo" simulator (iOS 27.1). It was recreated on 2026-10-21 after all iOS 27.1 simulators disappeared from the machine for reasons outside this session. It's the only device type the installed iOS 27.1 runtime supports, so **no iPad simulator was available** and the iPad layout is not verified. The library was seeded from `Samples/` with `papernest-seed` (the real importer). Screens were opened with debug-only launch arguments (`-PaperNestDebugOpenItem`, `-PaperNestDebugShowExport`) and captured with `xcrun simctl io … screenshot --display=primary`. **No taps or gestures were exercised.** Screenshots are in `docs/screenshots/`.

| Screen | Result |
|---|---|
| Empty library (en) | Correct title, search field, empty-state message, Import button. Scan is disabled because the Simulator has no document camera (intended fallback). |
| Library grid (en, fr) | All six samples render. The EXIF-6 photo is upright, the transparent PNG shows ink on white, and the protected PDF shows its unlocked content. "1 page · Oct 20, 2026" / "1 page · 20 oct. 2026". |
| Document (en, es) | **Found and fixed:** the page strip took half the iPhone width and the actions were hidden in an overflow menu. iPhone now shows the page full width, a thumbnail scroller, and the actions in the bottom toolbar. |
| Export sheet (en, fr, es) | **Found and fixed:** a 440-pt minimum width clipped the sheet on iPhone, and the option values truncated in French and Spanish ("Toutes…pages", "Tamañ…original"). It now uses inline option rows on iOS; the Mac keeps pop-up menus. |
| Crop editor (en, fr) | Opens over the uncropped page with a dimmed outside, frame, thirds guide and corner handles, Reset disabled at full crop. **Found and fixed:** the white frame and handles were invisible over white paper; they now have dark underlays. Checked with a page cropped by `papernest-seed --crop`. The drag is exercised by `AppUITests` (see above). |
| Cropped page in the document view | The app renders the seeded crop correctly: the marker and the rule are at the expected positions. |
| Launch log | **Found and fixed:** ⌘E for Export clashed with the system "Use Selection for Find" shortcut. Export is now ⇧⌘E. |

### Not covered by automated tests yet

- SwiftUI interaction beyond the crop editor. `PaperNest-iOSUITests` covers only crop so far, and the Mac has no UI tests.
- iPad layout (no compatible simulator runtime) and real devices
- Performance at 1/20/100 pages (no measurements taken; no numbers are claimed)
- Storage-full and low-memory behavior

## Open issue: an unexplained navigation glitch on iPhone (2026-10-21)

The first tap on a library thumbnail after launching on the owner's iPhone 17 Pro simulator (iOS 26.5) switched the scope to Favorites instead of opening the document. After that, Back → All Documents left navigation stuck. Root cause not identified. It could not be reproduced in three later attempts with the same sequence, or by the UI test.
- **Change made:** the sidebar selection is now optional (`LibraryModel.sidebarSelection`), as NavigationSplitView expects on iPhone, where it clears the selection when the user goes back. Unit test added.
- **Not proven to fix the glitch:** the UI smoke test passes with both the old and new binding.
- **If it recurs:** capture the exact tap timing (it happened right after a fresh install and launch) and check whether the sidebar list is hit-testable under the pushed library.

Also found by tapping and fixed: the crop sheet's title was black on the dark canvas. The sheet now uses dark appearance on iOS.

## Open issue: one unexplained crash in a test run

During session 1, one full test run ended with **SIGSEGV** (report: `~/Library/Logs/DiagnosticReports/swiftpm-testing-helper-2026-10-20-195924.ips`).
- It happened on an intermediate build with the redo and permanent-delete bugs still present, plus a temporary stub.
- The faulting frame is attributed to `LibraryStore` code, called from `PDFImportTests.typeComesFromContentNotExtension`. At that moment two other test threads were inside `PDFDocument.init` (PDFKit).
- The fault address points to a freed or corrupted pointer (a possible pointer-authentication failure).
- The root cause is **not identified**. It did not recur in 11 consecutive Command Line Tools runs of the final code, 4 Thread Sanitizer runs and 1 Address Sanitizer run under Xcode, none of which reported anything. That's good evidence but not proof.
- Under Xcode, each test target runs in its own process, so the cross-target concurrency of the crashing run (Store and Import tests together) is no longer exercised. If it recurs, serialize PDFKit use first (the importer and the test fixtures).

## Manual checklist

| Check | Platform | Status |
|---|---|---|
| Library window: sidebar scopes, empty states, grid thumbnails, search field | Mac | **Not run**: the owner declined Claude's control of the app |
| File > Import (⌘O) with `Samples/*`; drag files from Finder; paste a screenshot | Mac | Not run |
| Password prompt with `Samples/password-protected.pdf` (password `sample`) | Mac | Not run (covered in automated tests at the model layer) |
| Document view: page strip reorder by drag, rotate (⌘L/⌘R), filters, adjustments popover, undo/redo via Edit menu | Mac | Not run |
| Crop: Page > Crop… (⌘K), drag corners/edges/inside, Reset, Done, then undo/redo, export | Mac | Not run (on iPhone, the corner drag → Done → saved path is covered by `AppUITests`) |
| Export sheet: each format, page ranges, save panel, share menu, file opens in Preview | Mac | Not run |
| French and Spanish UI (`-AppleLanguages "(fr)"`): no truncation in sidebar, toolbar, export sheet | Mac | Not run |
| VoiceOver: grid cells read name + page count; page thumbnails read "Page n of m" | Mac | Not run |
| Sandboxed build (`--sandbox`): import via panel and drop, export via save panel | Mac | Not run |
| Tap through on iPhone: open a document, rotate, filter, Pages sheet reorder, export and save | iPhone (Simulator) | Not run: no taps were exercised |
| iPad split layout, keyboard shortcuts | iPad | **Blocked**: the installed runtime has no iPad simulator; needs an iPad runtime or device |
| Physical camera capture: multi-page scan, cancel, permission denied; Scan Pages and Rescan Page | iPhone | **Blocked**: needs a device and signing (team ID) |
| Replace Page with File… end to end (pick a file, page replaced, undo) | iPhone Simulator, Mac | **iPhone Simulator: passed** (see above; undo covered by tests only). **Mac: not run** (Page > Replace Page with File…) |
| Apple Pencil feel: latency, palm rejection, pressure, hover, Draw with Finger off by default | iPad + Apple Pencil (real device) | **Not run: needs a real iPad and Apple Pencil.** The first slice is built and Simulator-tested with finger drawing (see pass 7 above) |
| Document tools: Select, Duplicate, Merge Documents, Extract Pages, Color Label, Move to Folder, bulk Delete | Mac | **Not run**: the Mac build compiles the selection bar and the tools sheet, but no one has viewed them |
| Document tools: duplicate, select, color label, merge, extract, in en/fr/es | iPad (Simulator) | **Passed** on an iPad Air 13-inch (M4), iOS 26.5, after the test fix: `scripts/ui-test-ios.sh 62328381-… -only-testing:PaperNest-iOSUITests/AppUITests/testDocumentTools…` — both tests, 58.2 s and 86.1 s. Screenshots `docs/screenshots/f1-tools-ipad-*`. |
| Two-device iCloud sync | iPhone + iPad/Mac | Not applicable until M2 |
| Exported PDF/JPEG/PNG/ZIP open in Preview, Acrobat, Files | All | Automated structural checks passed. Not opened in external apps. |

## Performance log

No measurements yet. Record device, OS, document size (1/20/100 pages), elapsed time, peak memory and responsiveness notes here when they're taken.

## Tools screen continuation verification — 2026-10-24

The resumed chat referenced the old DOCS PRO checkout and unfinished Tools toolbar verification. The current checkout is Desktop/PaperNest; the existing 2026-10-23 Tools fixes were preserved. No application source changes were needed in this continuation.

- Full `./scripts/test.sh`: 235 tests passed (47 + 76 + 47 + 26 + 39); no compiler warning/error matches in the log. Log: `/private/tmp/papernest-tools-resume-tests.log`.
- iPhone 17 Pro: `testToolsScreenPicksTwoDocumentsAndMergesThem` and `testAFolderMadeInTheSidebarHoldsAMovedDocument` both passed, 0 failures; `TEST SUCCEEDED`. Log: `/private/tmp/papernest-tools-resume-ui.log`. Result: cache `build-17de0868e51d/xcodeproj/Logs/Test/Test-PaperNest-iOS-2026.10.24_13-10-01--0500.xcresult`.
- This run covers Tools merge and the folder regression on iPhone. It does not newly verify iPad, Mac UI, all Tools actions, or real camera access. Xcode emitted operating-system-build parsing diagnostics after the successful tests.
- Existing work and Qwen reservations remain intact. No commit or push. No test process remains active from this continuation.

## PDF pass-through on export — 2026-10-26 (Claude, backend)

An unedited imported PDF page is now copied from its source file instead of being
redrawn, so its links and annotations survive export. Pages that *have* been
changed keep going down the drawing path.

- Full `./scripts/test.sh`: **371 tests passed** (64 + 123 + 77 + 65 + 42), **0 warnings**.
  Log: `scratchpad/suite.log` (session scratchpad).
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings — built and signed
  `~/Library/Caches/PaperNest/build-17de0868e51d/dist/PaperNest.app`.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.
- 11 tests in `PDFPassThroughTests`, all passed: a link survives with its URL; a
  form widget survives with its `/T` name; title and creator are preserved; text
  and page count unchanged; a cropped page is redrawn and loses its annotations
  (the honest trade, pinned); Letter paper redraws every page; a mixed document
  keeps order and treats each page on its own; a passed-through page does not
  disturb a drawn OCR layer on its neighbour; the export carries the source's
  form dictionary; compressing an unedited page still keeps its link; a page
  getting a recognised-text layer is redrawn.

### What this does **not** establish

- **Interactive form fields are not verified, and ledger row 24 stays Planned.**
  The widget and its name survive, read back through PDFKit. Read back through
  Core Graphics, the exported file has **no** catalog `AcroForm` — and neither
  does the synthetic fixture, because PDFKit writes a widget's `/T` without
  building a form dictionary. So nothing here shows a real form staying
  fillable in another reader. That needs a hand-built fixture with a real
  `/AcroForm`.
- **Behaviour change to note:** compressing an unedited PDF now keeps its links,
  because the page is copied rather than drawn.
- **Pre-existing limitation found while measuring, not introduced here:**
  compression cannot shrink a scanned PDF. An unedited PDF page is never
  re-encoded, so every preset returns it as it was — 8521 bytes copied against
  8531 drawn, identical at `.light` and `.smallest`. It reports no saving rather
  than a fake one.
- No UI was involved; this is export-path logic only. Nothing committed.

## Compressing a scanned PDF — 2026-10-26 (Claude, backend)

Compression can now shrink a PDF whose pages are photographs. A `.pdfPage`
carrying no text of its own is re-encoded as a JPEG at the preset, and the
re-encode is kept **only when it is smaller than the page already is**.

- Full `./scripts/test.sh`: **378 tests passed** (64 + 123 + 77 + 72 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings — built and signed
  `~/Library/Caches/PaperNest/build-17de0868e51d/dist/PaperNest.app`.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured, on a 1600×2000 raster inside a 612×792 page

| source | original | plain export | light | strong | smallest |
|---|---|---|---|---|---|
| scan | 193,043 | 193,103 | 193,103 | 113,235 (−41%) | 56,430 (−71%) |
| digital text PDF | 8,007 | 8,044 | 8,044 | 8,044 | 8,044 |
| blank page | 2,140 | 2,207 | 2,207 | 2,207 | 2,207 |

Seven new tests in `CompressionTests`: a scanned PDF gets smaller at Smallest;
a stronger preset shrinks it further and keeps both pages; the compressed file
differs from a plain export (so the page really is re-encoded, not copied); a
preset that would enlarge the page leaves it alone; a blank page is not
rasterized into something larger (with a precondition asserting the fixture
really is text-free, so the test cannot pass for the wrong reason); a cropped
scanned page is re-encoded **and keeps its crop**; a page too large to
rasterize is left alone rather than failing the export. The two existing guards
still pass — `aVectorPDFKeepsItsTextInsteadOfBeingRasterizedToSaveBytes` and
`anAlreadyCompactOriginalReportsNoSavingRatherThanAFakeOne`.

### A regression caught before it shipped

The first working version rasterized every text-free page at the preset's dpi.
Light is 300 dpi, which **upsamples** a scan of lower resolution: it produced
**416,360 bytes from a 193,043-byte page** — a "compression" that more than
doubled the file, where the old code had simply copied the page. A re-encode is
now measured against the page it would replace, per page, by writing the copied
page alone into a document. Light therefore falls back to copying.
`aPresetThatWouldEnlargeAScannedPageLeavesItAlone` pins it.

### Two more bugs the fixtures found

- **A protected PDF came back as a blank page reported as a 99% saving.** A
  locked document hands back no text, so `carriesText` is false and every page
  looks like a scan; the locked `CGPDFDocument` then draws nothing and the
  white page beats any budget — **845 bytes from 8,110, one grey level**. The
  output also had its encryption stripped. Compression now refuses an
  encrypted or locked PDF outright, which also covers an owner password that
  restricts copying: assembling the output fresh drops that restriction, and
  handing back an unrestricted copy is not ours to do. **Documents are
  unaffected** — the importer stores a decrypted copy and verifies it.
- **A rotated page was distorted.** Sizing the re-encoded page from PDFKit's
  media box ignores `/Rotate`, so a landscape phone scan (portrait media box,
  `/Rotate 90`) had 792×612 of content squeezed into a portrait page: the
  input rendered 396×306 and the output 306×396. The size now comes from
  `PageGeometry.uprightPDFSize` of the crop box.

### What this does **not** do

- **Only image-only scans compress.** A page with text is never rasterized,
  because that destroys every word for a reader, a search and an export. Most
  scanner apps — Notes, Adobe Scan, ScanSnap — embed an invisible OCR layer,
  and that counts as text here, so **those PDFs still will not compress**. This
  bounds how often the feature helps, and it is not a tunable threshold: any
  text at all means the page is left alone.
- **Light rarely helps a scan**, for the upsampling reason above. The savings
  are at Strong and Smallest.
- A page too large to rasterize (over 100M pixels) is left alone rather than
  failing the export — now covered by a test using an 8000pt-square page, about
  1.1 billion pixels at Light's 300 dpi.
- A page that already needs pixel processing (filter, brightness, contrast) is
  excluded from the measurement, because the ordinary path rasterizes it at the
  same quality anyway and measuring would rasterize it twice for identical
  bytes. Its behaviour is unchanged by this slice.
- Only synthetic fixtures were used. **No PDF from a real scanner app has been
  compressed**, so the OCR-layer claim above is reasoned from the rule, not
  measured on a real file.
- No UI: there is still no Compress action in any screen, so none of this is
  user-reachable. Whoever adds one owns showing these real before/after bytes.
- Nothing committed.

## Compressing a PDF kept as a file — 2026-10-27 (Claude, backend)

`compress(fileNamed:data:preset:)` used to refuse a PDF outright. It now
reduces one page by page: pages that carry text are copied untouched, pages
that do not are re-encoded at the preset and kept only when they beat the page
they would replace.

- Full `./scripts/test.sh`: **385 tests passed** (64 + 123 + 77 + 79 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured, on a loose PDF file

| source | original | light | strong | smallest |
|---|---|---|---|---|
| 1600×2000 scan in a 612×792 page | 193,043 | 193,092 | 111,920 (−42%) | 55,115 (−71%) |
| digital text PDF | 8,007 | 8,028 | 8,028 | 8,028 |

Seven new tests in `FileCompressionTests`: a scanned PDF file is reduced rather
than refused (with the output page rendered and checked for content, and a size
floor); a digital PDF keeps its text and reports no saving; pages keep their
order; a preset that would enlarge the file leaves its pages alone; an
encrypted PDF is refused rather than returned blank; a restricted PDF is
refused rather than stripped of its restrictions, leaving no directory behind;
a rotated scanned page keeps its orientation. Both existing refusal guards
still pass — non-image, non-PDF bytes throw `unsupportedFormat` and leave no
directory behind.

### A bug my own test failed to catch

The first version returned **869 bytes from a 193 KB scan** and the test passed,
because it asserted only `isSmaller` — and a blank page is the smallest file of
all. The re-encoded page was built in a one-page `PDFDocument` that was a local
variable, so it was deallocated on return; **a copied `PDFPage` is read lazily
from the document it came from**, and the page serialized empty. The rebuilt
documents are now held until the output has been serialized. This is the same
trap recorded for the pass-through slice, written down there and then walked
into here.

The test now renders the output page and asserts it has more than 8 distinct
grey levels, plus a floor of 10% of the original size. Either assertion fails
at 869 bytes.

### What this does **not** do

- **Only image-only scans benefit.** A page with text is never rasterized. Most
  scanner apps embed an invisible OCR layer, which counts as text, so most real
  PDFs will report no saving. This is the usual answer for PDFs, not the
  exception.
- **Light usually does nothing to a scan** — 300 dpi upsamples most of them, so
  the re-encode is discarded.
- Only synthetic fixtures. **No PDF from a real scanner app has been compressed.**
- **A password-protected or restricted PDF cannot be compressed at all**, by
  choice. Preserving an owner's restrictions through a rebuild is unsolved, so
  it is refused rather than quietly stripped.
- Replacing the stored file with its reduced copy is still a separate decision,
  not taken here. Folder and archive compression remain.
- No UI: there is still no Compress action in any screen.
- Nothing committed.

## Encrypted PDF export — Set Password, row 27 — 2026-10-27 (Claude, backend)

`Exporter.export` takes an optional password and writes a PDF that requires it
to open. Row 27 goes from "no encrypted export" to an engine that has one.

- Full `./scripts/test.sh`: **397 tests passed** (64 + 123 + 77 + 91 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### What the encryption is — measured, not assumed

Read out of the `/Encrypt` dictionary in the written bytes. Both `CGPDFContext`
and `PDFDocument.write(to:withOptions:)` produce the same thing:

```
/Encrypt  /V 4  /R 4  /Length 128  /AESV2  /StmF /StdCF  /EncryptMetadata true
```

- `/AESV2` is **AES-128 in CBC mode**. **Not RC4** — which was the outcome that
  would have made this dishonest to ship at all.
- Revision 4, **not** revision 6 (AES-256, PDF 2.0). Apple's APIs do not expose
  revision 6.
- Revision 4's key derivation is MD5-based and fast, so **the strength is the
  password**, not the cipher. A short password falls to an offline attack.
- A test reads the bytes back and fails if the handler stops being AES, so the
  documented claim cannot quietly become false after an OS update.

**Sayable:** "encrypted with AES-128", "needs this password to open".
**Not sayable:** "secure", "military-grade", or anything implying a weak
password is safe. This wording is in `docs/CODEX_BRIEF.md` for whoever builds
the screen.

### Eleven tests in `EncryptedExportTests`

The file needs the password to open, rejects a wrong one and opens with the
right one with its text intact; an **empty** password does not open it; without
a password nothing is encrypted; an untouched (passed-through) page still
arrives encrypted and still has its link; a **mixed** document keeps every page
and its title; a document with **no** untouched page is encrypted by the
context itself; the handler is AES; a password is refused for JPEG, PNG, TXT
and DOCX; an empty password is refused; a non-ASCII password is refused; and
only the first 32 bytes of a password are honoured.

### Password limits — measured, and they affect the French and Spanish builds

- **ASCII only.** `"été-Ñandú-2026"` failed to write *even though every
  character is Latin-1*, and PDFKit refused `"contraseña-密码-1"` outright. So
  Latin-1 is not the boundary in practice, and non-ASCII is refused up front
  with `ExportError.passwordNotRepresentable` rather than surfacing later as a
  write error. An accented password is a realistic thing for an fr/es user to
  type, so the screen has to say what is allowed before they type it.
- **Only the first 32 bytes count.** A 32-character prefix opens a file written
  with a 44-character password. The full password still works, so this is a
  documentation point rather than a failure — but a longer passphrase is not
  stronger. A test pins it.

### Three traps this had to avoid

- **The owner password matters.** A PDF opens with *either* password. Setting
  only the user password leaves an empty owner password, which opens the file
  regardless — protection that is not protection. Both are set to the same
  value, and a test asserts an empty password fails.
- **Pass-through re-writes the finished file and would have dropped the
  encryption.** `writePDF` encrypts through the context, then pass-through
  assembles the document in PDFKit and writes it to a staged file that replaces
  the encrypted one. The password is re-applied on that write. Same shape as
  compression stripping an owner's restrictions, found yesterday.
- **The reopened file is locked, and a locked document yields blank pages.**
  `replaceWithSourcePages` reopens the encrypted file and copies every page
  that did not pass through out of it. A **mixed** document came back with its
  drawn page blank and **its title gone**, while the passed-through page looked
  perfect — so the single-page test passed and hid it. `drawn` is now unlocked
  before anything is copied. This is the third instance of this same shape in
  two days.

### What this does **not** do

- **No UI.** There is no Set Password action in any screen, so this is not
  user-reachable. It must not appear until the wording above is right.
- **Permissions are not settable** — only whether a password is needed to open.
  No print/copy flags.
- **No non-ASCII password**, which is a real restriction for fr/es users.
- **No password recovery.** A lost password is a lost file. Whoever builds the
  screen owns saying so before the file is written.
- A password-protected PDF still **cannot be compressed** (refused, 2026-10-27),
  so offering both actions needs an explanation rather than a silent failure.
- Not opened in Preview, Acrobat or any other reader — PDFKit and raw-byte
  checks only.
- Nothing committed.

## A digital PDF's text keeps its lines on export — 2026-10-27 (Claude, backend)

TXT and DOCX export read a digital PDF's text from the page's own file instead
of from the search index.

- Full `./scripts/test.sh`: **399 tests passed** (64 + 123 + 77 + 93 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Two faults, one cause

The recorded limitation was that embedded PDF text exported as **one run-on
paragraph**, because `LibraryStore.embeddedText` returns what was indexed for
FTS, normalized for matching. In DOCX that meant a whole page in a single
`<w:p>` — the layout a Word export exists to carry, discarded at the last step.

Writing the test exposed a second fault nobody had recorded: the index is
written by a **background pass**, so a PDF exported soon after import had no
indexed text and the export was refused as `noTextToExport` — for a document
whose every word was sitting in the file. Reading the page's own file fixes
both, and the text is current by construction, since `page.content` names the
asset the page shows now.

The earlier note said this needed `PDFTextExtractor` moved so
`PaperNestExport` could reach it. It did not: `PDFPage.string` gives the lines,
and `PaperNestExport` already opens source PDFs with PDFKit for pass-through.
No module graph change.

### The existing tests were asserting on fiction

Every embedded-text export test seeded the search index with text that was **not
in the PDF** — indexing "Council tax notice for 2026" against a page whose text
was "Council tax notice", or "First page words" against a page reading "One".
They tested the path from index to file, never that a real digital PDF's words
come out. Two of them asserted a document had *no* text while importing a PDF
that plainly had some, and passed only because nothing had been indexed.

They now put the text in the PDF, and the two "no text" tests use a scan, which
genuinely carries none. Same intent, honest fixtures.

### What this does **not** do

- The search index keeps its normalized copy, which is correct for matching.
  Nothing in search changed.
- A cropped page still exports the whole page's text. A crop is a display
  transform, not a redaction — true of the indexed copy too.
- **Still nobody has opened a .docx in a word processor.** Unchanged and still
  owed.
- No UI for either format.
- Nothing committed.

### The shared temporary root bit again

`cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind` failed once during this
work, on residue — one `PaperNestExport-…` directory left by *my own* failing
test earlier in the session. A test that expects a refusal and instead receives
an `ExportOutput` has no `defer` to clean it up, so it leaks. Verified by
listing the directory and matching the UUID before re-running, rather than
assuming. Worth knowing when writing refusal tests.

## Permanent redaction, engine — row 26 — 2026-10-27 (Claude, backend)

Redaction that removes content rather than covering it. Engine only: there is
no screen and no orchestration, because `DocumentModel` is Codex's file.

- Full `./scripts/test.sh`: **406 tests passed** (64 + 126 + 81 + 93 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The design question, answered by the code

The worry was that redaction conflicts with "originals are never modified". It
does not. The library already supports *deleting* an original, which is a
different thing: `replacePageContent` files the old content in
`page_content_history`, and `sweepOrphanAssets` deletes any asset referenced by
no page, history row, file item or placed image. So redaction is render →
replace → forget that page's history → sweep. A redaction-only export path was
the alternative and is the weaker promise; it is not needed.

`replacePageContent` already deletes the page's `ocr` and `pdfText` rows from
`search_index`, so redacted words stop answering searches the moment the
content changes. That part was already right.

### Seven tests, written to fail for a redaction that only looks right

Four on the bytes (`PageRedactionTests`): the redacted words are not in the
output at all; the pixels where they were are black across the whole band while
the rest of the page survives; redacting no rectangles is refused rather than
silently rewriting the page; a scanned page redacts too. Three on the library
(`RedactionStoreTests`): forgetting the history lets the original be swept; a
**shared** original is kept and `isAssetReferenced` says so; the recognised
words are deleted rather than merely unindexed.

### Three limits, each one load-bearing

- **A digital PDF loses selectable text across the whole page**, not only the
  redacted part. Text under a painted rectangle survives any amount of drawing
  on top, so the only honest mechanism is to flatten the page to pixels. The
  page becomes a picture of itself and stops being searchable.
- **A shared original cannot be deleted.** Assets are content-addressed, so two
  pages of identical paper share one; if another page still shows it, the sweep
  correctly keeps it and the content stays reachable through that page.
  `isAssetReferenced` exists so a caller can find this out *before* promising
  anything.
- **Deleting a file does not scrub the disk.** The bytes may persist until
  overwritten, and on a copy-on-write filesystem that is not controllable from
  here. Nothing may say "securely erased" or "unrecoverable".

### What this does **not** do

- **No UI and no orchestration.** Nothing calls `PageRedaction` yet. The
  wording a screen must carry is in `docs/CODEX_BRIEF.md`.
- **Ink, comments and stamps under a rectangle are untouched.** They are
  separate rows; a note containing the redacted thing survives.
- `sweepOrphanAssets` has a one-hour grace period by default, so an original
  survives until the next sweep unless the caller asks for none. Stated rather
  than changed.
- PNG, chosen so a lossy encode cannot leave ringing around a painted edge —
  reasoned, not measured against a recovery tool.
- Nothing committed.

## WebP import — row 32 — 2026-10-27 (Claude, backend)

The row carried a standing instruction: *add WEBP only after codec
verification.* The verification came first and decided the shape of the work.

- Full `./scripts/test.sh`: **411 tests passed** (64 + 126 + 86 + 93 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### What ImageIO actually supports

```
CGImageSourceCopyTypeIdentifiers      → includes org.webmproject.webp
CGImageDestinationCopyTypeIdentifiers → no webp entry
CGImageDestinationCreateWithData(…webp…) → nil
```

**It decodes WebP and cannot encode it.** So:

- Importing a `.webp` is supportable, and now works.
- **Converting *to* WebP is not possible with system frameworks.** That is
  settled, not pending: it needs a third-party encoder (libwebp) and the
  licensing and binary-size decision that comes with one. Row 32 says so now
  rather than leaving a to-do that looks small.
- A WebP fixture cannot be generated at runtime, which is why
  `SyntheticDocuments.webPImage()` is a 50-byte literal rather than drawn. It
  was produced once with Pillow, outside the build.

### Five tests

WebP bytes are recognised; other RIFF files (WAV, AVI) are **not** claimed as
WebP; a `.webp` imports as one image page stored under its own kind with a
`webp` extension; the fixture decodes to the right pixels — its top-left
quadrant red and the rest white, so the test proves a real decode rather than
mere acceptance; and an imported WebP prepares as an image for rendering and
export.

### A wrong assumption, caught by the test

I recorded in the plan that `AssetKind` is a plain string enum needing no
migration. That was wrong: `assets.kind` carries a SQL `CHECK` constraint, and
the import failed with *CHECK constraint failed: kind IN ('pdf','jpeg','png',
'heic','file')*. **Schema v8** widens it, following the v6 migration that added
HEIC exactly. The next migration must be v9.

`PageCommentTests` asserted `schemaVersion() == 7` literally; it now uses
`Schema.latestVersion`, as the three other version assertions already did, so
it stops being a tripwire for every future migration. That file is Codex's
area — the change is one line and mechanical, noted here and in the handoff.

### What this does **not** do

- **No WebP output of any kind**, and no UI change: import simply accepts one
  more type.
- **Animated WebP decodes to its first frame.** That is not animation support
  and must not be described as such.
- Only the 16×16 literal was tried. **No photograph-sized or animated WebP, and
  no file from a real camera or website, has been imported.**
- Nothing committed.

## Native Mac run — 2026-10-27 (Claude, manual)

The first native Mac interaction actually performed in this project. Previous
entries recorded it as unrun and blocked: Codex has no computer-use tools, and
this session's app-access request had been denied twice. It was granted today,
for `com.example.papernest.dev`.

Run against a **throwaway library** at `/tmp/papernest-dev-library`, seeded
fresh from `Samples/` by `scripts/run-mac-app.sh` — 7 documents (oio,
whiteboard-300dpi, transparent-ink, receipt-portrait-exif6, rotated-page,
password-protected and one more). No real library was opened.

### Verified by doing it

- **Home screen** renders with the library: sidebar (Home; Library with All
  Documents 7, Favorites, Recently Deleted; Folders) and a Recent grid whose
  thumbnails draw. **No Scan card on Mac**, which is correct — there is no
  document camera — leaving New Notebook, Import… and New Folder.
- **A document opens and renders** (transparent-ink), with a native toolbar
  exposed as named accessibility elements: Back, Rotate Right, Crop, Filters,
  Export…, More, Zoom Out, Zoom to Fit, Zoom In, Hide Sidebar, and an "Add or
  Replace Pages" control.
- **The menu bar exists and is app-specific:** PaperNest, File, Edit, View,
  **Page**, Window, Help. Page holds Rotate Left, Rotate Right, Replace Page
  with File…, Crop…, Move Page Up, Move Page Down, Revert to Original, Delete
  Page.
- **A menu command works end to end.** Page ▸ Rotate Right applied the quarter
  turn — content moved as expected and **both the canvas and the sidebar
  thumbnail re-rendered** — and Page ▸ Revert to Original restored it. The
  library was left as seeded.
- **The export sheet opens** with PDF / JPEG / PNG, All Pages / Current Page /
  Range, Paper Size and Image Quality, matching iOS.

### The "launched but no window" scare — diagnosed, and the script is fine

Recorded first as a possible fault in `scripts/run-mac-app.sh`: it exited 0 and
reported the app opened, the process was alive, and yet there was **no window**;
`app_list_windows` returned empty twice, including after an explicit relaunch.
Running the binary directly produced a window at once, which made the script
look guilty.

**It is not the script.** Reproduced and tested:

| Launch | Window? |
|---|---|
| `open -n` from a foreground shell, warm bundle | yes, at once |
| `open -n` after a rebuild and re-sign | yes, at once |
| `open -n` from a **backgrounded** task | yes, at once |
| full script, **fresh library**, backgrounded | yes — but `is_off_space: true` |

The last run is the answer. The window **is** created, on a regular desktop
Space; `app_bring_to_current_space` then refused with the reason: *the current
Space is a full-screen app, and a window cannot be moved into a full-screen
Space.* So the app launches correctly and its window lands on a desktop Space
that is not the one being looked at — which from the front looks exactly like
"launched, no window". A screenshot of that window by id shows it healthy, with
the seeded library listed.

Three hypotheses were tested and **disproved** on the way: the `open -n` launch
method, a cold signature after rebuild, and launching from a detached shell with
no GUI session. Each one produced a window immediately.

Not proven: the very first attempts returned an *empty* window list rather than
reporting an off-Space window. That is consistent with the same cause, before
the window could be enumerated, but it was not reproduced and is not claimed.

**If the Mac app seems not to launch:** check a regular desktop Space (Mission
Control, or click the Dock icon) before suspecting the build or the script.

### Not done

- **No export was completed on Mac.** The sheet was opened and closed; the
  file-writing path was exercised on iPhone instead (below).
- **VoiceOver, Dynamic Type, the two-window conflict pass and localized (fr/es)
  Mac runs remain unrun.** This entry does not close those.
- No markup, shapes, stamps or comments were exercised on Mac.
- Only one document of the seven was opened.

### Same build, same day, on iOS

The iOS Simulator build from this tree was also run by hand: on **iPhone 17
Pro**, Home and the document editor render and **an export completed** — all 5
pages as PDF at Original Size, which is the pass-through path, producing a real
file the system save sheet previewed, reported as "Ready: 35 KB"; nothing was
saved. On **iPad Air 13-inch (M4)**, the three-column layout renders and
creating a grid notebook saved and opened with the template drawing correctly.
On both, Scan is correctly disabled and the export sheet offers only PDF/JPEG/
PNG — no TXT, DOCX, Compress, Set Password or Redact — which matches the
"engine exists, no UI" notes rather than contradicting them.

## Redaction as an operation — row 26 — 2026-10-27 (Claude, backend)

The redaction engine landed this morning and **nothing called it**. Composing
the steps is now one operation, so a caller cannot do three of the four and
believe the job is done.

- Full `./scripts/test.sh`: **415 tests passed** (64 + 127 + 89 + 93 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Why it is one call and not four

Rendering alone leaves the original in the library. Replacing the content alone
leaves the recognised words in `page_recognition`. Forgetting the undo history
alone leaves the file on disk. `PageRedactor.redact` does all of it: render,
stage the asset durably, `replacePageContent`, `deleteRecognition`,
`forgetReplacedContent`, then delete the original if nothing else shows it.

### Two decisions about not misleading the caller

- **`originalStillInLibrary` is named so the unsafe answer is `true`.** Assets
  are content-addressed, so two pages of identical paper share one file.
  Redacting one page cannot delete it and the words stay reachable through the
  other page. A caller has to read that flag before claiming anything, and the
  naming puts the dangerous case where it will be noticed.
- **`deleteAssetIfUnreferenced` is targeted, not a sweep.** `sweepOrphanAssets`
  has a one-hour grace period protecting assets staged but not yet referenced;
  calling it with no grace period to collect one file could take another
  operation's freshly staged bytes. The new call touches one asset and refuses
  if anything still points at it. **Row before file**, as the sweep does: a
  crash between leaves an orphan file the sweep collects, while the other order
  would leave a row pointing at nothing.

### Four new tests

The unreferenced asset is deleted — row *and* file — while a referenced one is
refused and kept; after redacting, the page shows the new image, the words do
not answer searches, the recognition row is gone and the original file is off
disk; a **shared** original survives and the outcome says so, with the second
document's paper still present; and the page keeps its id, sort key, crop and
source size.

### What this does **not** do

- **Still no UI.** `DocumentView`/`DocumentModel` are Codex's, and the wording
  any screen must carry is in `docs/CODEX_BRIEF.md`.
- Ink, comments and stamps under a rectangle are untouched — separate rows.
- A digital PDF still loses selectable text across the whole page: flattening
  is the mechanism.
- **It does not scrub the disk.** Deleting a file unlinks it; the bytes may
  persist until overwritten. Nothing may say "securely erased".
- Nothing committed.

### A warning-free build is part of done

The first green run passed every test but raised **4 warnings** — unnecessary
`await`/`try` markers (`store.assets` is not isolated) and an unused
`transaction` result. Fixed before claiming the slice, and the final run is
back to 0 across tests and both builds.

## HEIC export — row 32 — 2026-10-27 (Claude, backend)

Row 32's remaining half. HEIC *import* landed in F2c; writing one has never
been possible, so an exported photo was a JPEG about three times larger than
it needed to be.

- Full `./scripts/test.sh`: **420 tests passed** (64 + 127 + 89 + 98 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured before anything was written

The WebP slice earlier today found ImageIO's support can be **asymmetric** —
it reads WebP and cannot write it — so HEIC was checked the same way instead of
being assumed from the import note:

```
CGImageDestinationCopyTypeIdentifiers → public.heic, public.heics
CGImageSourceCopyTypeIdentifiers      → public.heic, public.heics, public.heif
```

Symmetric. The same 1600×2000 page, same quality setting:

| format | bytes |
|---|---|
| HEIC | 94,742 |
| PNG | 209,699 |
| JPEG | 284,377 |

About a third of the JPEG, round-tripping to the same dimensions, with the
requested 200 dpi coming back as 200.

### The trap, and the test that catches it

`writeImages` chose its type with `options.format == .jpeg ? .jpeg : .png`. A
new case falls into that `else`, so HEIC export would have written **PNG bytes
into a file named `.heic`** — a lie on disk that every filename-based check
would have passed. The switch is now exhaustive, and
`theFileIsReallyHEICAndNotPNGWearingTheExtension` reads the written bytes back
and asserts `CGImageSourceGetType` is `public.heic`. The name is not the
evidence.

### Six tests

The bytes really are HEIC; it decodes back at the requested resolution with its
dpi intact; it is less than half the size of the same page as PNG; PDF, JPEG
and PNG are each unchanged; and several pages still package as a ZIP holding
`.heic` entries.

### What this does **not** do

- **No UI tile**, as with every format added this way. `ExportFormat` is
  `CaseIterable` but **nothing iterates `allCases`** (checked, as when TXT and
  DOCX were added); the sheet's tiles are hand-written and `contentType(for:)`
  derives from the extension, so no screen changed.
- **Compatibility is the real cost and it is not a footnote.** Exporting exists
  to send a file somewhere, and HEIC is the format most likely to reach
  somewhere that cannot open it — older systems, many Windows installs, web
  upload forms. **JPEG stays the default**, and the wording any tile must carry
  is in `docs/CODEX_BRIEF.md`.
- **Nobody has opened one of these files anywhere but this machine.** The
  engine is tested; the format's real-world reception is not.
- Nothing committed.

## Compression output format — row 35 — 2026-10-27 (Claude, backend)

Row 35 named two remainders. This takes the first: `compress(fileNamed:data:
preset:)` hardcoded JPEG, giving up most of the available saving now that HEIC
is in and measured.

- Full `./scripts/test.sh`: **423 tests passed** (64 + 127 + 89 + 101 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### JPEG stays the default, deliberately

Compression exists to make a file easier to **send**. Handing back a HEIC the
recipient cannot open is a worse outcome than a larger JPEG that works, so the
caller opts in rather than being upgraded silently. `CompressionFormat` carries
that reasoning where the choice is made, and the wording any screen needs is in
`docs/CODEX_BRIEF.md` — the warning matters more here than for export, because
compressing is usually the step right before sending.

### Three tests

The default output is still JPEG, checked by reading the bytes back rather than
the filename; asking for HEIC gives a real HEIC — `CGImageSourceGetType` says
`public.heic` — and a materially smaller file than the same photo as JPEG at
the same preset; and bytes that are not a re-encodable image are still refused,
whatever format was asked for, with nothing written.

### What this does **not** do

- **A PDF file item ignores the format entirely**, because HEIC is not a PDF
  image filter. Its behaviour is unchanged: pages carrying text are copied,
  text-free pages re-encoded, none of it HEIC.
- **No UI.** Nothing offers the choice.
- **Folder/archive compression, row 35's other remainder, is deliberately not
  done here.** It needs an honest "before" for each entry, and for a document
  that is the originals it is made of — which live in the store, and `Exporter`
  has no store. Doing it properly means the caller passing those counts in,
  which is a design question worth its own slice rather than a guess bolted on.
  Written down rather than quietly skipped.
- Nothing committed.

## A document's outline — row 36 — 2026-10-27 (Claude, backend)

Row 36's **navigation** half, for one explicitly named format: a PDF's own
table of contents. Not user-created bookmarks, which need storage and a screen.

- Full `./scripts/test.sh`: **428 tests passed** (64 + 127 + 94 + 101 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Verified before designing

An outline written with `PDFOutline`, serialized and reopened, comes back with
its labels and page indices intact, and a PDF with no outline returns
`outlineRoot == nil` — so "this file has no contents page" is distinguishable
from "nobody looked". That is what made a synthetic fixture possible, which is
what decides whether this can be tested honestly at all.

### The part that is not bookkeeping

A PDF's outline points at pages of **that file**. A PaperNest document is a
list of pages that may have been reordered, cropped, deleted, or drawn from
several PDFs at once. So every entry is resolved through the document's current
pages by (asset, source index), never by trusting the index:

- **An entry whose page was deleted is dropped.** An outline leading somewhere
  the document no longer has is worse than no outline.
- **Two merged PDFs each keep their own contents page**, resolving to their own
  pages.
- **Entries keep the order and nesting their author wrote**, because that is
  what a table of contents is. If the pages were reordered the outline will not
  ascend through the document — a true description of the file rather than
  something quietly re-sorted. A child whose parent was dropped keeps its own
  depth for the same reason.

### Five tests

Titles come back in the author's order with the right pages and nesting
(`[0, 1, 0, 0]`, so flattening fails the test); a PDF without an outline yields
none rather than failing; an entry whose page was deleted is dropped, with an
assertion that no returned entry points outside the document's pages; a
document built from two outlined PDFs yields both; and a scan contributes
nothing.

### What this does **not** do

- **PDF only.** Nothing here claims EPUB or any other book format, and row 36
  keeps its condition that formats be named explicitly.
- **User-created bookmarks and reading mode remain Planned.**
- Read-only: no schema change, nothing stored or cached, so the outline cannot
  describe paper a page no longer shows.
- **No UI.** Reading the outline is the engine; presenting it is the screen
  owner's work.
- Only synthetic fixtures — **no real book or scanned PDF with a publisher's
  outline has been read.**

## Compressing an archive — row 35 — 2026-10-27 (Claude, backend)

Row 35's last remainder, which closes the row's engine work. `exportArchive`
packed a selection into one ZIP and could not make any of it smaller; ZIP's own
deflate does nearly nothing to a PDF or a JPEG.

- Full `./scripts/test.sh`: **433 tests passed** (64 + 127 + 94 + 106 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The design question that deferred this, and its answer

The earlier slice left this alone because a `CompressionResult` needs an honest
"before", and for a document that is the originals it is made of — which live
in the store `Exporter` cannot see. Threading those in made the API ugly.

**The answer was not to invent a before at all.** `exportArchive(…preset:)`
returns the ordinary `ExportOutput`. The caller already knows what it had and
can compare; nothing fabricates a baseline, and no store dependency appears.

### Two rules, each with a test

- **Nothing is dropped.** An archive missing a file is data loss that stays
  invisible until someone looks for it, so anything that cannot be compressed
  goes in as it was. The test packs a scanned document, a `.txt`, a `.mov` and
  a `.png`, and counts four entries with the preset and four without.
- **Nothing is grown.** A re-encode that came out bigger is discarded and the
  original kept — so "compress" can legitimately produce an archive the same
  size as the plain one, which the already-compact-PNG test pins.

### Five tests

An archive of scans is smaller with a preset; nothing is dropped from a mixed
selection; a non-image file comes back **byte-identical** after a round trip
through the archive; an already-compact image is not grown; and without a
preset the archive is unchanged, entry list included.

### What this does **not** do

- **A re-encoded image changes extension** — a `.png` can come back as `.jpg`
  inside the archive. That is a real change to what someone gets back, so it is
  stated in `LibraryExportEntry`'s own documentation and in `CODEX_BRIEF.md`
  rather than left to be discovered.
- **Non-image files are never re-encoded**, preserving the promise the entry
  type already made: re-encoding someone's video or spreadsheet would be a lie
  about what they got back.
- **No UI.** Nothing offers an archive preset.
- Synthetic fixtures only; no real multi-gigabyte selection has been archived,
  so nothing is known about time or memory at that scale.

## Word-level text boxes — row 20 — 2026-10-27 (Claude, backend)

Markup worked on whole recognised lines, so highlighting one word highlighted
the sentence around it. Recognition was the reason: a `RecognizedLine` carried
one box and nothing smaller.

- Full `./scripts/test.sh`: **438 tests passed** (64 + 127 + 99 + 106 + 42), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured before building

Vision was asked directly, on a page reading `Invoice total 1234 EUR`:

```
line              x=0.080 w=0.412
  "Invoice"       x=0.080 w=0.129
  "total"         x=0.213 w=0.087
  "1234"          x=0.305 w=0.096
  "EUR"           x=0.405 w=0.087
```

Ordered, non-overlapping, and the last word ends exactly at the line's right
edge (0.405 + 0.087 = 0.492 = 0.080 + 0.412). That is what justified building
it rather than approximating by dividing the line box on character count, which
drifts on any proportional font and would put a highlight over the wrong ink.

### Existing stored results

`page_recognition` holds results written before this field existed.
`RecognizedLine` now has a hand-written `init(from:)` that decodes a missing
`words` as empty, so those results still load and a reader falls back to the
line. **Nothing is recomputed behind the user's back, and no migration was
needed** — recognition is JSON, not columns. A test decodes real old-shape JSON
and asserts no words are invented.

### Five tests

Words come back in reading order and each word's text is part of its line;
every word box sits inside its line's box with positive size; words do not
overlap; old JSON decodes with no words; and words survive an encode/decode
round trip.

### What this does **not** do

- **No UI.** Selecting a word is the screen owner's work; this gives it
  something to select. Row 20's selection interface, moving or resizing marks
  outside PencilKit, and semantic annotation objects all remain planned.
- **A word Vision will not box is dropped, not faked.** The only box available
  to invent from is the line's, and a highlight drawn there would cover text
  the user did not select. So `words` can hold fewer entries than the line has
  words, and a caller must expect that.
- Only synthetic English text was recognised. **No handwriting, no real scan,
  and no French or Spanish line has been checked for word boxes.**

## Saved signatures — row 23 — 2026-10-27 (Claude, backend)

Ink a person drew once, kept, and placeable again on any page. Checkmarks
already existed as symbol stamps, which are *generated shapes*; this is
different in kind.

- Full `./scripts/test.sh`: **448 tests passed** (64 + 131 + 99 + 106 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### What this is, stated before anything else

A saved signature is **a picture of a handwritten signature**. It is not a
cryptographic signature: no certificate, no timestamp, no tamper-evidence, it
proves nothing about who placed it, and anyone holding the file can copy the
image onto another document. **Nothing may say "signed", "verified",
"authenticated" or "secure" — the honest verb is "placed".** That wording is in
the type's own documentation, in `CODEX_BRIEF.md` and in `PRODUCT_SPEC.md`,
because it decides vocabulary rather than being a caveat to add afterwards.

### A design fault the test caught

The first version normalised captured ink into a **unit box** — each axis
scaled to 0...1 independently. That destroys the signature's shape: a 4:1
signature came out square before placement ever saw it, and the aspect-ratio
test failed with *"aspect became 1.0, not 4"*. Both axes are now divided by the
**same** number, the longer side of the ink's bounds, so the shape is part of
what is stored. Had the test only checked that placed ink lands inside its
target, this would have shipped looking subtly wrong on every document.

### Ten tests

**Model (6):** capture normalises by the ink's own bounds and keeps its
proportion; an empty signature is refused; placing puts every point inside the
target; aspect survives placement, so a wide signature in a square target is
letterboxed rather than stretched; the same placement on two page sizes is
proportionally identical; placing does not change the stored signature.

**Store (4):** a signature round-trips with its ink intact; saving the same id
again replaces rather than duplicates; deleting removes only that one;
signatures outlive reopening the library, at the current schema version.

### What this does **not** do

- **Schema is now v9; the next migration must be v10.**
- **No UI.** Drawing a signature and choosing where it goes is the screen
  owner's work. Initials and typed fill-in from row 23 are not built.
- Placed strokes are ordinary ink, so they are editable, erasable, undoable and
  exported like any other ink — and equally removable by anyone with the file.
- Nothing committed to a page by this slice: it produces strokes, and saving
  them onto a page goes through the existing ink APIs.

## Filling a PDF form — row 24 — 2026-10-27 (Claude, backend)

The Tools screen's *Fill Form*. Row 24 had stayed Planned because PaperNest
writes no document-level AcroForm and the synthetic fixture had none either,
so nothing was known about real forms.

- Full `./scripts/test.sh`: **455 tests passed** (64 + 131 + 99 + 113 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Two probes unblocked it

1. **A real AcroForm can be hand-built.** PDFKit cannot create one, so the
   fixture is raw PDF bytes with computed xref offsets: catalog
   `/AcroForm << /Fields [...] >>` and `/FT /Tx` widgets. Core Graphics reads
   it as `[("customer", "")]` — a genuine form, not a loose widget.
2. **PDFKit preserves an AcroForm it did not create.** Setting
   `widgetStringValue` and writing gives, read back through Core Graphics:
   `[("customer", "Jane Appleseed")]`.

The earlier conclusion — *PaperNest writes no AcroForm* — remains true and is a
different statement from *PDFKit cannot keep one*. Both are now recorded so
neither gets mistaken for the other again.

**Every assertion goes through Core Graphics, never PDFKit**, because PDFKit
reports a `fieldName` whether or not the document has a form, which misled this
project once already.

### Seven tests

A real form reports its field names, values and types; a PDF with no form
reports none; a filled value is in the written file's AcroForm as another
reader would see it; filling a field the form does not have is **refused**;
filling a form-less PDF is refused; other fields are left alone; and the field
is still a field afterwards.

### What this does **not** do

- **Only text fields can be filled.** Checkboxes and choice fields are
  *reported* with `isFillable == false` rather than hidden, so a caller can say
  "this form has parts I cannot fill" instead of implying the form is complete.
  Appearance-state handling is not built.
- **Filling does not flatten.** The field stays a field and the next reader can
  change it. The result must not be described as locked or final.
- **PaperNest still writes no AcroForm of its own**, so a form can be filled
  but not created, and a PDF exported from PaperNest has no fields to fill.
- **No UI**, and no real-world form — only the hand-built fixture — has been
  filled. A form from a government or bank website is untested.

## Ticking a box, and the hang that came with it — row 24 — 2026-10-27 (Claude, backend)

Checkboxes join text fields in `PDFForm`. Partway through, the suite stopped
finishing at all — and the cause turned out to predate this change.

- Full `./scripts/test.sh`: **460 tests passed** (64 + 131 + 99 + 118 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Checkboxes, probed before they were designed

Setting `buttonWidgetState = .onState` makes PDFKit write **both** `/V` and
`/AS`, as names, using the widget's **own** on-state name rather than an
assumed `/Yes`. Measured on the fixture: before `V=[""] AS=["—"]`, after
`V=["/Yes"] AS=["/Yes"]`, and reopened `state=1`.

So `FormValue` is typed — `.text(String)` or `.checked(Bool)` — instead of a
bare string. Text offered for a checkbox, or a tick for a text field, is
**refused** (`FormError.wrongKind`) rather than coerced: writing "true" into a
name field, or ticking a box because some string was non-empty, is a guess
about what was meant. Kinds are checked up front, so a refusal leaves the file
untouched instead of half filled. `FormField.isCheckbox` says which is which.

Four new tests: a tick is visible to another reader (`/V` and `/AS` read as
names through Core Graphics); a box can be left unticked; a mismatched kind is
refused; and a refusal writes nothing at all.

### The hang, and what actually caused it

`./scripts/test.sh --filter PDFFormTests` never returned. Build finished, then
no test output at all, killed at the watchdog. `/usr/bin/sample` of the stuck
process put every thread in the same place:

    PDFForm.filled -> PDFPage.lazilyLoadAnnotations
      -> PDFAnnotationTextWidget init -> getFontFromAppearanceString
      -> NSFont fontWithName: -> CoreText -> TAutoActivationManager
      -> XTypeXPCClient XTCopyFontProviders
      -> __NSXPCCONNECTION_IS_WAITING_FOR_A_SYNCHRONOUS_REPLY__ -> mach_msg2_trap

Reading a page's annotations makes PDFKit build each widget, and building one
makes it resolve the font named in the field's `/DA` — `/Helv`, the AcroForm
abbreviation, which is not a real PostScript name, so CoreText goes looking for
it over **synchronous XPC**.

**Three guesses were wrong and are recorded so they are not made again:**

- *A wedged font daemon.* `fontd` and `fontworker` were both alive, and a
  standalone binary resolved the same name promptly: `NSFont(name: "Helv")`
  → nil in 0.009s, `"Helvetica"` → 0.001s.
- *The checkbox change.* `git diff` touched only `fields(in:)`. The hanging
  line is unchanged since commit `10a49b2`, and the three tests that passed at
  that commit hang too.
- *"Several at once."* The first regression test ran 8 concurrent fills on
  plain `Thread`s and **passed with no fix at all**, in 0.066s. That reading
  was wrong, and a test that cannot fail is worth nothing.

The variable is Swift concurrency's **cooperative pool**, and only that:

| 8 concurrent `filled` calls | result |
| --- | --- |
| on plain `Thread`s | all finish, 0.066s |
| in a `withTaskGroup` | hangs; not one task finishes |

The sample says which story it is: 9 threads, 9 lazy annotation loads, 9
threads each waiting on **its own** unanswered reply, and **0** lock-contention
frames. Nine independent stuck calls, not one stuck call with eight waiters.

**The fix is one `NSLock` in `PDFForm`**, held across the whole PDFKit stretch
of both `fields(in:)` and `filled(_:with:)`, so that path is entered one caller
at a time. Verified against the harshest case rather than assumed: with the
lock the task-group probe finishes all 8 in 0.066s, and the command that hung
forever passed **5 runs in a row** (12 tests, ~0.08s each). A dedicated thread
would also have worked — the plain-thread result proves it — but the lock is
smaller, and one-at-a-time is exactly what was measured to be enough. Neither
method calls the other, so a non-recursive lock is safe.

`manyFillsAtOnceAllFinish` now pins this with a task group, which is the only
shape that reproduces it.

### What this does **not** do

- **If that lock is removed, the test hangs rather than fails.** It cannot be
  helped: a thread stuck in `mach_msg` never reaches a cancellation point, so
  no `.timeLimit` fires, and the starved pool cannot run the harness either. A
  hang at `manyFillsAtOnceAllFinish` is the warning; the comment there says so.
- **Corrected — the first version of this entry got the blast radius wrong.**
  It said `PDFPage.copy()` in `Compression.swift` and `Exporter.swift` was the
  same exposed path, and that nothing in the product fans out anyway. Both
  claims were guesses from a grep, and both are wrong. The app fans out
  heavily: **87 `Task {}` / `.task {}` sites across 21 files in
  `PaperNestUI`**, which is exactly why this matters. And the trap is narrower
  than `PDFPage`. Probed at 16 concurrent callers each, on the form fixture:

  | concurrent PDFKit work | result |
  | --- | --- |
  | `page.annotations` | **hangs**, no caller finishes |
  | `page.copy()` | all finish |
  | `page.string` | all finish |
  | `outlineRoot` | all finish |

  So **reading `.annotations` is the trigger** — that is what instantiates the
  widget objects and resolves their `/DA` font. Copying a page, reading its
  text and reading the outline do not. `PDFForm` is the only code in `Sources`
  that reads `.annotations` (`PDFForm.swift:59` and `:88`), so the lock covers
  the product and not merely the test. `PageRenderer`, the hot path, is pure
  Core Graphics — `CGPDFDocument` and `ctx.drawPDFPage`, which draws page
  content without annotations — so the library grid rendering many pages at
  once never enters it.
- **What is still unchecked:** only those four PDFKit calls were measured. If
  some other PDFKit path loads annotations implicitly, it would hang the same
  way and no test would catch it.
- **Why the pool cannot recover is not known.** It is inside CoreText and
  libFontRegistry, and nothing here claims an explanation — only what was
  measured.
- **Choice fields still cannot be filled**, and are reported with
  `isFillable == false`. Picking a value means picking from the options the
  form declares, which this does not read.
- **Still no UI, and still no real-world form.** Only the hand-built fixture
  has been filled or ticked. A form from a government or bank website is
  untested, and PaperNest writes no AcroForm of its own.

## A thumbnail of what a file item holds — row 8 — 2026-10-28 (Claude, backend)

Row 8 has said "generated grid/list thumbnails remain open" since 2026-10-22.
`FileThumbnail.image(at:boundedBy:scale:)` is the engine for them: the system's
Quick Look, asked for a picture of a file's contents.

- Full `./scripts/test.sh`: **466 tests passed** (64 + 131 + 105 + 118 + 48), **0 warnings**.
- The new suite run **5 times in parallel**: 6 tests, ~0.05s each, no hang and
  no orphaned helpers. Worth doing because this goes through a system XPC
  agent, the same family as the PDFKit trap found the day before.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Measured before anything was designed

1. **Ask only for `.thumbnail`, never `.icon`.** Asked for `.all`, Quick Look
   answers a file it cannot read with a generic **512×512 type icon**
   (`type=0`) — measured alike on a `.bin`, a file with no extension and an
   unknown extension. That icon is the symbol the grid already draws from
   `uti`, so returning it would dress a type symbol up as a preview of the
   contents. Asked only for `.thumbnail`, the same three files **error**
   instead, which is the honest answer. `aFileTheSystemCannotReadGivesNothingRatherThanAnIcon`
   is the guard, and the guard was **run rather than claimed**: set the
   representation types to `.all` and it fails with
   `Expectation failed: image == nil`, holding the icon. A guard nobody has
   seen fail is a claim, and the first commit of this slice only claimed it.
   `.lowQualityThumbnail` is also left out, because nothing here measured it —
   the first commit asked for it while every measurement and every line of
   these docs described `.thumbnail` alone.
2. **A missing file is distinguishable from an unpreviewable one.**
   `NSCocoaErrorDomain` 4 against `QLThumbnailErrorDomain` 0
   (`QLThumbnailError.Code.generationFailed`, so no magic number in the code).
   Collapsing them would hide a missing original behind a blank square, so the
   file's existence is checked here and only Quick Look's own code 0 becomes
   `nil`. Everything else — a cancelled or invalid request — is thrown.
3. **The size asked for is a box.** Fresh file per request: asked 120×400 →
   120×120, asked 400×120 → 120×120, asked 200×200 → 200×200, asked 64×64 at
   scale 2 → 128×128. So the picture fits inside and keeps the document's own
   proportions; the parameter is named `boundedBy` because of this, and a
   caller must lay out what comes back rather than what it asked for.

### The `.bin` problem, which is the whole reason this needs care

A stored asset is named `<sha256>.bin`, because `AssetKind.file` covers every
type. Quick Look decides what a file is from its extension and refuses `.bin`,
so pointing it at the asset's own path **always** answers `nil`. The URL has to
carry the real extension: `FilePayload.originalFilename` first, and when that
basename is unusable — `prepareTemporaryCopy` falls back to `<sha>.bin` for an
empty or `/` name — the item's recorded `uti` gives one through
`UTType(uti)?.preferredFilenameExtension` (`public.plain-text` → `txt`,
`org.openxmlformats.wordprocessingml.document` → `docx`).
`theRecordedTypeNamesTheFileWhenTheStoredNameCannot` writes the same bytes both
ways and gets `nil` from one and a picture from the other, so that is a
measurement rather than advice.

### What this does **not** do

- **No UI, so row 8 stays Partial.** Nothing calls this yet; the grid and list
  cells are Codex's. It also deliberately **does not stage files** — a second
  way to do that would compete with `FileKind.prepareTemporaryCopy`, which the
  full preview already uses.
- **Nothing is cached.** Every call asks the system again, so a grid that
  scrolls will re-ask for pictures it has already had. Quick Look has a cache
  of its own, which is why repeats are fast, but nothing here depends on that.
  A thumbnail cache of our own is unbuilt and undecided.
- **iOS behaviour is unmeasured.** It compiles for the Simulator and that is
  all that has been established. Which types Quick Look previews on iOS, and
  whether it previews the same ones as macOS, has not been run.
- **Few types have actually been tried.** `.txt` in the tests, and a `.docx`
  in a probe outside them (`type=2`, 485×792). Spreadsheets, presentations,
  video, audio and archives are untested, and nothing says the system can
  preview any particular one of them.
- **An item whose `uti` is `public.data` gets nothing** when its filename is
  also unusable: that type has no preferred extension, so there is no name to
  stage it under. Measured, and there is no honest way around it.
- **Concurrency is clean as far as it was pushed** — 16 concurrent requests in
  a standalone task group, plus 5 parallel suite runs — but this is a system
  XPC agent, and that is not proof for every type or load.

## How long a media file is, and what it calls itself — row 42 — 2026-10-28 (Claude, backend)

Row 42 (audio and video playback, audiobooks, playlists) was confirmed by the
owner on 2026-10-23. `MediaInspection.inspect(at:)` is the part a player needs
before it can draw anything: the file's own length, whether there is a picture
as well as sound, and what it calls itself. **Playing it is a view and is not
this.**

- Full `./scripts/test.sh`: **473 tests passed** (64 + 131 + 112 + 118 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The fixture is hand-built, and that was measured first

A **RIFF/WAVE file written by hand** is enough: 1.5 seconds of silence reads
back as 1.500, and 2.0 as 2.000. So there is no opaque audio blob in the
repository and no generated file whose length has to be taken on trust — the
same reasoning as the hand-built AcroForm PDF. A `LIST`/`INFO` chunk carries
the tags.

### Three findings that changed the design

1. **`asset.load(.commonMetadata)` is empty for a file whose tags are plainly
   there.** The obvious reader — load the common metadata, look for a title —
   finds *nothing* on this file. The items only come back through
   `AVMetadataItem.metadataItems(from:filteredByIdentifier:)` over
   `.metadata`, which does the per-format mapping and turns `caaf/info-title`
   into `.commonIdentifierTitle`. Measured both ways before a line was written.
2. **`.bin` fails here too, and so does a name with no extension at all.**
   The same playable bytes, measured four ways: `sound.wav` → 1.0s,
   `sound.bin` → `nil`, a name with no extension → `nil`, and — the one that
   refines the rule — **`sound.mp3` → 1.0s**, WAV bytes under an MP3 name.
   So AVFoundation does not demand a *correct* extension; it demands one it
   treats as media at all, and then reads the actual bytes. `.bin` and no
   extension are not media types, so it never looks.
   `theStoredAssetNameIsNotEnoughToReadIt` pins the `.bin` half.

   This is the *same* staging requirement `FileThumbnail` has, reached through
   completely different machinery, so the two engines agree — see "What a
   caller still has to do" below for what that actually requires of the UI.
3. **A missing file is distinguishable from a file that is not media** (−11800
   against −11828), so existence is checked here and only −11828 becomes
   `nil`. Both guards were **run rather than claimed**: breaking the
   classification makes `aFileThatIsNotMediaIsNotAnError` and
   `theStoredAssetNameIsNotEnoughToReadIt` fail with the real −11828 in hand.

### Only what could be measured is shipped

`duration`, `hasAudio`, `hasVideo`, `title`, `artist` — and nothing else.
**`albumName` and `artwork` were left out on purpose.** A WAV `IPRD` chunk for
the album is dropped by AVFoundation entirely — it does not even appear among
the raw items — and nothing hand-buildable here carries artwork, so both would
have been fields no run could demonstrate.

### What this does **not** do

- **Nothing plays.** No seek, speed, background audio, resume, playlists,
  shuffle, system controls or picture-in-picture — row 42 stays Planned, and
  this only clears its groundwork. Nothing calls `inspect` yet.
- **No file with a video track has been inspected.** `hasVideo` is measured
  only as `false`, on audio. A `true` from it is not yet backed by a run, and a
  video fixture needs a real encoder rather than hand-written bytes.
- **Artwork and album are not read at all**, as above. Row 42 asks for
  artwork; it needs a fixture in a format that can carry one.
- **One format has been read: WAV.** MP3, M4A, AAC, MOV and MP4 are untested
  here. The metadata path is format-independent by construction, but that is an
  argument rather than a measurement.
- **A file AVFoundation recognises but cannot parse is thrown, not reported as
  "not media".** Only −11828 was measured, so only −11828 is treated as an
  answer; a corrupt media file's code is unknown and would surface as an error.
- **`duration == nil` is unexercised.** No local file declared an indefinite
  length. It is `nil` rather than `0` so a wrong zero is never shown as a
  length.
- **iOS behaviour is unmeasured.** The Simulator build proves it compiles and
  nothing more. Whether AVFoundation reads the same formats and surfaces tags
  the same way on iOS has not been run.

### What a caller still has to do — and nobody does it yet

Both engines need a URL whose extension the system treats as media or as a
document. **The rule is not "the basename is unusable" — it is "the name's
extension does not name the item's `uti`."** That matters, because
`FileKind.prepareTemporaryCopy` falls back to `<sha>.bin` only for `""`, `.`,
`..` and `/`, and it never reads `uti` at all. So an `originalFilename` with
no extension, or with one that does not match the bytes, is staged under that
name — and a name with no extension was measured to give `nil` from both
engines.

So the `UTType(uti)?.preferredFilenameExtension` fallback that both engines
recommend **is implemented nowhere**: it lives in these notes and in
`theRecordedTypeNamesTheFileWhenTheStoredNameCannot`, not in the staging path
any screen uses. Wiring either engine to a screen means fixing that first.

### Fan-out

16 concurrent `inspect` calls in a task group — the way a playlist or a grid
would ask — returned all 16 titles. Worth running because this is the trap
class from the day before, though `AVAsset.load` suspends rather than blocks,
so a hang was never likely.

## Closing row 42's measurement gaps — row 42 — 2026-10-28 (Claude, backend)

The entry above shipped only what a hand-built WAV could demonstrate, which
left two honest holes: **`hasVideo == true` was never run** — a hard-coded
`false` would have passed every test — and album and artwork were left
unshipped because nothing could prove them. Both are now measured, so the
"does not do" list above is superseded on those three points.

- Full `./scripts/test.sh`: **476 tests passed** (64 + 131 + 115 + 118 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### Two generated fixtures, and one API rejected on the way

- `SyntheticDocuments.videoClip` writes a few frames through `AVAssetWriter`
  with a pixel-buffer adaptor: a **1.3 KB** `.mov` that reads back as 0.600s
  with one video track and no audio. Hand-written bytes cannot make a real
  video track, and without one there is no honest way to test that a file
  reports having a picture. Still synthetic — flat grey frames, nobody's
  recording.
- `SyntheticDocuments.taggedAudio` transcodes `wavAudio` with an
  `AVAssetReader` into an `AVAssetWriter`: a **1.5 KB** `.m4a` whose title,
  artist, album and 174 bytes of artwork all come back. M4A because a RIFF
  file cannot hold these at all — AVFoundation drops a WAV `IPRD` album chunk
  without even listing it, and there is no standard place in one for a picture.
- **`AVAssetExportSession` was rejected**, although it was the first thing that
  worked in a probe. `exportAsynchronously`, `status` and `error` are all
  deprecated in macOS 15 while this package still supports macOS 14, so there
  is no version of it that compiles without warnings. The reader-to-writer
  transcode compiles clean and does the same job.

### What is now measured

- `hasVideo == true` and `hasAudio == false` on a real video track, and
  **the test was proven able to fail**: hard-coding `hasVideo: false` breaks
  `aVideoFileHasAPictureAsWellAsALength`, as hard-coding the error
  classification breaks the two "not media" guards.
- `albumName` and `artwork` round-trip. Artwork is handed back as **the bytes
  the file carries**, not decoded or re-rendered, so nothing is lost or
  invented on the way and the caller picks its own size.
- Tags that are absent from a format that *could* have held them stay `nil`:
  an M4A with only a title reports no album and no artwork rather than empty
  strings.
- A second format, and the first not written by hand: M4A as well as WAVE,
  plus QuickTime for the video.

### What this still does **not** do

- **Nothing plays.** No seek, speed, background audio, resume, playlists,
  shuffle, system controls or picture-in-picture. Nothing calls `inspect`.
  Row 42 stays Planned.
- **MP3 and MOV-with-audio are untested**, and so is anything with more than
  one track of a kind. Three container formats have been read (WAVE, M4A,
  QuickTime) out of the many a library will meet.
- **iOS behaviour is still unmeasured.** The Simulator build proves
  compilation. Whether the same formats read, and whether `AVAssetWriter`
  produces these fixtures there, has not been run.
- **The fixtures depend on the system's H.264 and AAC encoders.** They are
  generated at test time rather than checked in, which keeps binaries out of
  the repository but means these three tests need a machine with those
  encoders.
- **Artwork is not validated as an image.** The test asserts bytes came back,
  not that they decode — the file is asked what it carries, and that is all
  that is claimed.

## Row 43's codec review, answered by measurement — 2026-10-28 (Claude, backend)

Row 43 is "Convert media to MP3 / extract audio", and has said **"codec and
licensing review first"** since it was confirmed on 2026-10-23. This is that
review. **No engine was built and nothing in the app changed** — it is a
finding, recorded so the decision it forces is made with numbers rather than
recollection.

### What this machine can encode

`AudioFormatGetProperty(kAudioFormatProperty_EncodeFormatIDs)` returns **16**
formats:

    aac  aace aacf aacg aach aacl aacp alac apac flac opus lpcm alaw ulaw ilbc ima4

- **MP3 is not among them.** `kAudioFormatMPEGLayer3` is absent from the
  encode list.
- **MP3 *decoding* is available** — it is in the decode list. So a library can
  read an MP3 a user imports and cannot write one.
- AAC, Apple Lossless, FLAC, Opus and plain PCM can all be written.

`AVAssetWriter` agrees from the other side: constructing one with
`AVFileType.mp3` raises `NSInvalidArgumentException`, and the exception names
every type it *will* write — m4a, mp4, mov, caf, wav, aiff, aifc, 3gpp, amr
and the caption formats. No MP3.

### What that means for row 43

- **"Convert to MP3" cannot be built on Apple's frameworks.** It needs a
  third-party encoder bundled into the app, which is the licensing question the
  row anticipated — now a certainty rather than a worry.
- **"Extract audio" can be built today**, to M4A/AAC, or losslessly to Apple
  Lossless, FLAC or WAV. The transcode route is already proven in
  `SyntheticDocuments.taggedAudio`: `AVAssetReader` into `AVAssetWriter`,
  warning-free, and small.

**This is an owner decision and is deliberately left open**, because the two
answers lead to different work: ship "Extract audio" in a format the system
can write, or license an MP3 encoder and carry it in the app. Nothing should
be labelled "MP3" in any screen until that is settled.

### What this does **not** establish

- **One machine, one OS version.** The encoder list is what this Mac reports
  today. It is a strong signal about Apple's platforms but not a guarantee for
  every iOS device, and the same probe has not been run on iOS.
- **Nothing was extracted.** No audio has actually been pulled out of a video
  file; only the available encoders and container types were read.

## A placed image is painted and exported — row 21 — 2026-10-28 (Claude, backend)

**The owner narrowed the queue on 2026-10-28: documents and images only, leave
media alone.** Rows 42 and 43 stop where they are. Row 21 says "placed images
remain planned; models for text/image objects exist", and that was exactly the
state — `PageObject.Payload.image(PlacedImage)` existed, `page_objects` stored
it, and `isAssetReferenced` and `deleteUnreferencedAssetRows` already counted
it, so an asset under a placed image was never swept. **Nothing painted it, and
`PageRenderer.draw` did not even take one.**

- Full `./scripts/test.sh`: **482 tests passed** (64 + 131 + 119 + 120 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The trap it closes, which was a silent one

`PDFPassThrough.isUntouched` asked `hasInk`. An unedited PDF page at its
original paper size with a placed image and **no** ink satisfied every
condition, so export copied it straight from its source file — and the image,
which exists nowhere in that source, **was gone from the export without a
word**. No error, no warning, just a page missing what someone put on it.

The fix is not a `hasPlacedImage` flag beside `hasInk`. The parameter is now
`hasPaintedObjects`, because the condition that matters is "anything is painted
over this page": a text box or a stamp, both named in row 21 as coming, would
have walked into the same hole. `aPageCarryingAPlacedImageIsDrawnRatherThanCopied`
is the test, and it failed before the change.

### Order is the page's, not a rule about kinds

`draw` now takes `[PageLayer]` — `.ink` or `.image` — built from
`LibraryStore.objects(on:)`, which returns a page's objects in `zKey` order.
So an image placed over a stroke covers it and a stroke drawn over an image
covers that, whichever the page says came last. The easy wrong version, images
always painted last, **was tried**: it makes `inkDrawnOverAnImageCoversIt` fail.
That test had passed trivially while nothing drew images at all, which is why it
was worth breaking on purpose.

Only two places called `draw`, both in this lane, so the signature could change
rather than gaining a defaulted parameter that kept the old shape alive.

### Six tests, and what each would catch

The fixture image is white with a **red square across its top-left fifth**, so
every probe reads a point just inside the placed frame's corner — an image drawn
in the wrong place, at the wrong size, or flipped fails. It is painted on the
page; nothing is painted outside its frame; an image over ink covers it; ink
over an image covers that; `includingInk: false` still shows the image, because
the ink editor paints its own strokes and the page must not appear to lose the
image the moment someone draws; and it reaches both an exported PDF and an
exported PNG.

Two more cases were added after the first commit, because every test until
then used an **unrotated, uncropped page**, where several wrong orders of flip
and rotation give the right pixels anyway: one on a page the file itself
rotates a quarter turn, and one whose stamp is stored sideways and upright only
by its EXIF orientation, as a phone photo is. Removing the flip in
`drawPlacedImage` fails **7 of the 8 tests**, these two included, so they are
live guards — though it should be said plainly that they fail for the same
reason the flat case does rather than catching something it cannot.

### Corrected: how a screen would actually place one

The first commit's note here said placing reuses the imported image's asset
"which is what a screen would do". That is **not true**, and the correction
matters more than the claim did. The test gets its `AssetID` by importing the
stamp as a library item; a screen placing a photo from outside the library that
way would leave a stray item behind. And there is **no public API that stages an
asset and writes the object together**: `AssetFileStore.store` stages the file
durably, but inserting the asset row is private, and between staging and the
object being written `sweepOrphanAssets` could take the file away.

`saveObject` is also the *unguarded* write. Every other object kind has a
guarded one — ink has `applyInkChanges`, which checks the objects it expects;
comments have `setPageComment(replacing:)`; markup has `addTextMarkup`. A
guarded `placeImage` that stages the asset and writes the object in one
transaction is the next piece of store work, and it is what turns "the engine
draws a placed image" into "a screen can place one".

### What this does **not** do

- **No UI.** Nothing places an image yet — that is a screen, and screens are
  Codex's. Row 21 stays Partial. A caller would write a `PageObject` with an
  `.image` payload and a `zKey` above the existing ones.
- **No undo, no resize, no rotation.** `PlacedImage` carries an asset and a
  frame, and that is all it carries: no angle, no opacity, no crop. A placed
  image cannot be rotated because the model has nowhere to put the angle.
- **Text boxes and stamps are still not painted.** `.text` payloads are skipped
  in `layers`, as page comments are — deliberately, and the comment there says
  so, but it means row 21's other halves remain open.
- **A placed image whose asset is not on this device throws**, rather than being
  left out of the drawing. That is the honest choice — a page quietly missing
  part of itself is worse than one that says it cannot be drawn — but it means
  one unavailable overlay fails the whole page, and no test covers that path.
- **`PageRenderer.inkStrokes(for:)` still exists and is now used by nothing.**
  It is kept because Codex's editor may want it, with a doc comment saying not
  to draw from it; drawing from it is precisely how a placed image gets lost.
- **The image is stretched to fill its frame.** `drawPlacedImage` draws into
  the rectangle it is given, and every test places a square image in a square
  frame, so nothing here establishes what a mismatched aspect does — it will
  distort. Saved signatures letterbox instead (`SavedSignature.placed(in:on:)`);
  this does not, and which is wanted is a product question.
- **`includingInk: false` has changed meaning, and `ThumbnailCache` passes it.**
  It used to mean "no overlays", because ink was the only one; it now means
  what it says — no ink, placed images kept. Nothing can show one yet, since no
  screen places an image, so there is no live defect. But a caller that wanted
  the bare page needs a different flag, and `Sources/PaperNestUI/ThumbnailCache.swift`
  is the one to look at when images can be placed.
- **Redaction does not touch a placed image's own bytes.** `PageRedaction`
  flattens and repaints the page's *source* through `uprightSourceRaster`, so
  overlays are neither baked in twice nor removed. That is right for ink, and
  it means a placed image covering a redacted region still shows whatever it
  shows — the words are gone from the source, which is what redaction promises,
  but a picture carrying the same words is not redacted. Untested and
  unaddressed.
- **No sibling of the `hasInk` bug was found in this lane.** Everything that
  decides a page's original can be copied instead of drawn goes through
  `isUntouched`; `EmbeddedPageText` and `DocumentOutline` read a source for text
  and an outline rather than to copy it, and compression works on a finished PDF
  where overlays are already drawn in. The `case .ink` filters in
  `PaperNestUI` — `DocumentView`, `MarkupManagerSheet`, `InkCanvas` — are list
  and manager concerns rather than copy decisions, and they are Codex's to
  judge.

## Placing an image, safely — row 21 — 2026-10-28 (Claude, backend)

The entry above drew and exported a placed image, and then had to correct its
own advice: a screen could not safely *write* one. `AssetFileStore.store`
stages the file durably, but inserting the asset row was private, and between
staging and the object being saved `sweepOrphanAssets` was entitled to take the
file. `saveObject` was also the unguarded write, while every other object kind
has a guarded one. `LibraryStore.placeImage(_:on:frame:)` closes that.

- Full `./scripts/test.sh`: **492 tests passed** (64 + 139 + 121 + 120 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### One write

The asset row and the page object go in inside **one transaction**, following
`replacePageContent`: the caller stages the bytes (file written durably first),
and the store inserts the row. `aPlacedImageIsNotSweptAway` is the test that
matters, and it was **proven able to fail** — take `insertAssetRows` out, which
is exactly the naive stage-then-`saveObject` path the earlier note recommended,
and it throws because the sweep took the bytes, while
`placingAnImageWritesTheBytesAndTheRowTogether` fails for want of a row.

The order key is worked out **inside** the write from what the page holds at
that moment, so two placements in a row cannot claim the same place —
`twoImagesInARowBothLandInOrder` pins that. A new image lands on top of what is
already there, as putting something down does.

### Refused rather than stored

- **Bytes the renderer cannot decode as an image.** `AssetKind.isDrawableImage`
  is an exhaustive switch — jpeg, png, heic, webp yes; pdf and file no — so a
  new kind has to decide rather than inherit an answer. Offering a `.pdf`
  asset is `StoreError.invalidPlacement`. Without this the renderer would
  only find out when someone opened the page, by which time the object is
  saved and the page cannot be drawn at all.
- **A frame with no area**, or a non-finite one. `frame.width > 0` alone does
  not catch a NaN origin, so the origin is checked too.
- **A page that is gone, or whose item is deleted** — `pageNotFound`, the same
  guard `addShape` uses.

Each refusal writes **nothing**: the tests check that no object and no asset
row are left behind, so a refusal leaves unreferenced bytes for the sweeper
rather than a half-written placement.

### Three things a screen hits immediately, added after the first pass

The first version of this had twelve fewer tests and two real gaps, both found
by asking what a screen would do on its second call rather than its first.

1. **It returns the page as well as the object now.** Writing an object bumps
   the page's revision, and `addShape(to expected:)` compares the **whole**
   page — so a caller holding the `Page` it started with is refused.
   Confirmed rather than reasoned about: with the page from before the
   placement, `addShape` throws `pageObjectsChanged`; with the page
   `placeImage` returns, it succeeds. Without this, placing an image would
   break the very next edit someone made.
2. **The same image on two pages shares one copy.** The fixture staged unique
   bytes per placement — `"stamp bytes \(UUID())"` — which quietly hid the
   commonest real case: one logo or signature put on several pages. Content
   addressing gives those the same `AssetID`, so the asset row is written
   twice. `insertAssetRows` already handles that (`ON CONFLICT(id) DO UPDATE`),
   and it is now tested end to end: both placements land, removing one keeps
   the bytes because the other page still needs them, and only removing both
   lets them go. Placing a picture that is already a page's **own content** is
   covered too — deleting that placement must not sweep the page's content out
   from under it.
3. **Placing something does not stale what was read off the page.** The
   revision bump could have: `recognizedLines` only answers when
   `sourceRevision == page.revision`, so putting a signature on a scan might
   have dropped its searchable text from export. `bumpRevision` already
   carries a *current completed* result forward with the page, deliberately
   and with a comment saying why; there is now a test saying so from outside,
   because that is a feature-level promise and not an implementation detail.

### What this does **not** do

- **Still no UI.** Row 21 stays Partial. What exists now is the whole engine
  path — stage, place, draw, export — with nothing calling it.
- **No undo.** `placeImage` returns the `PageObject` it wrote, so a caller can
  undo by deleting that id, and `deletingAPlacedImageLetsItsBytesGo` shows the
  bytes then go with it. But there is no undo *entry*: the ink editor's
  `applyInkChanges` records an edit for the undo stack and this does not join
  it, so a placement and an ink stroke do not share one history.
- **No move, resize, rotate or re-layer after the fact.** Changing a placement
  means deleting the object and writing another, which is not the same thing
  and has no test.
- **The bytes in these tests are not images.** Nothing in this path decodes
  them — only the declared kind and the frame matter — so the store tests use
  plain bytes, as `DocumentSplitTests` does. Real images are drawn in
  `PlacedImageRenderTests`. It also keeps AVFoundation, which
  `PaperNestTestSupport` now links for the media fixtures, out of
  `PaperNestStoreTests`, which does not depend on that target.
- **Nothing checks the frame against the page.** A frame may sit entirely off
  the page; drawing clips it away and the object stays. That is deliberate — a
  caller may want an image hanging over an edge — but it means a placement can
  be invisible with no complaint.

## Text typed onto a page — row 21 — 2026-11-01 (Claude, backend)

The last piece of row 21 that had a model and no paint. `TextBox` existed in
Core and `page_objects` stored it; `layers` **skipped** `.text`, so nothing
drew it. It joins `PageLayer` now, which also means `hasPaintedObjects` covers
it without a new flag — the point of generalising that condition when placed
images needed it.

- Full `./scripts/test.sh`: **502 tests passed** (64 + 143 + 125 + 122 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### It is real text, and that is the whole decision

Drawn with CoreText into the export's PDF context, so the words come out as
**text operators rather than glyph outlines**: selectable, copyable and
searchable in the written file. A picture of text would look identical on
screen and be useless to a reader, so the test does not take it on trust —
`textInABoxIsRealTextInTheExportedPDF` reads the words back out with
`PDFDocument.page(at:)?.string`.

The flip is `drawSearchableText`'s and not a second idea of which way is up:
translate to the box's bottom edge in y-down source space, scale y by −1, and
`CTFrameDraw` then lays the first line against the box's **top** and runs down
the page.

### Six tests, and what each would catch

Text is painted inside its box and nowhere outside it; it starts at the **top**
of the box, which is the only one of these that catches an upside-down flip,
since text drawn the wrong way up is still dark pixels in the right box;
`.trailing` puts it at the right edge and not the left; an empty box paints
nothing; the words are real text in the exported PDF; and a page carrying only
a text box is **drawn rather than copied**, which is the trap that was losing
placed images.

The pixel probes scan a **region** rather than a point, because one sample can
land in the gap between two letters and report nothing about text that is
plainly there. The first version of that helper called `PixelProbe.pixel` per
sample, which redraws the whole image each time and took **a minute per test**;
it reads the bitmap once now and the suite is back to milliseconds.

### What this does **not** do

- **No UI.** Nothing lets anyone type on a page — row 21 stays Partial, with
  stickers and stamps still open. A caller writes a `PageObject` with a
  `.text` payload; there is no guarded `placeText` the way `placeImage` exists
  for images, so the asset-free path is the unguarded `saveObject`.
- **One font, Helvetica, hard-coded.** `TextBox` carries a size, a colour and
  an alignment and has nowhere to put a typeface, so nothing here chooses one
  and no other font has been tried.
- **Text longer than its box is clipped**, with nothing to say so. The frame
  path cuts it off; there is no ellipsis, no shrink-to-fit and no indication to
  a caller that some of what was typed is not shown.
- **The words do not reach the search index.** Someone's own typing is exactly
  what they would expect to find by searching, and it will not be found. That
  is a store question — a new `search_index` field and a migration — not a
  render one, and it is not done.
- **No wrapping test.** CoreText wraps inside the frame, but every test here
  uses one short line, so nothing establishes what a paragraph does.
- **iOS is unmeasured**, as for the other engines: the Simulator build proves
  it compiles. Whether Helvetica resolves the same way there has not been run.

## Typed text becomes findable — row 21 — 2026-11-02 (Claude, backend)

Text boxes paint and export as of yesterday, and the words went nowhere near
search — the first thing someone would notice about their own typing. They are
indexed now, on the same page write that saves them.

- Full `./scripts/test.sh`: **509 tests passed** (64 + 150 + 125 + 122 + 48), **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.

### The privacy test was worthless at first, and that is the finding here

A page comment is private. It is typed on the same page, by the same person,
into the same objects table, so `aPrivateCommentIsNeverFindable` is the test
that matters most in this slice. It **passed while the reindex was deliberately
changed to gather comments** — so it was proving nothing.

The reason is worth keeping: writing a comment does not bump the page's
revision, on purpose, so that an undone comment does not invalidate page
history. No bump means no reindex, so the comment was safe **by accident of
timing** rather than by the rule the test claimed to check. The test now saves
an ink stroke after the comment, which does bump the revision and rebuilds the
index while the comment is sitting on the page. Verified both ways round: it
passes as written, and making the reindex gather comments fails it.

So the promise rests on two independent facts, and only one of them was ever
tested before.

### No migration, checked rather than assumed

`search_index` is an FTS5 table whose `field` column is `UNINDEXED` and carries
no `CHECK`, and the index is derived and rebuildable — so a field value needs no
schema change. This was checked rather than assumed because `assets.kind` went
the other way earlier in this project: its `CHECK` constraint did need a
migration, and the plan that said otherwise was wrong.

### Corrected mid-slice: it is the field that already existed

A fifth field, `typed`, was written first. That was wrong.
`LibraryComposition` **already** gathered text boxes into a `text` row — but
only while duplicating, extracting or merging, which is why typing on an
ordinary page indexed nothing. A new name would have left a composed item
carrying the same words twice under two names, and it broke
`DocumentCompositionTests`, which counts the index rows an item owns. That
failure is what surfaced the existing field at all.

So this uses `text`, and composition's hand-rolled copy is **deleted**: the
objects it writes already go through `applyObjectChanges` → `bumpRevision` →
the reindex, which does the same "rebuild from the copy's own objects rather
than carry stale content or source IDs" that comment described, in one place
that also covers simply typing.

### Where it hooks, and what that costs

`bumpRevision` is called from exactly the three object-write paths and nothing
else, so it is the one place that means "this page's objects changed".

It therefore runs on **every** object write, an ink stroke included. The gather
asks for `kind = 'text'` rows only, rather than reading the page's objects
through `objects(on:)`: that would decode every stroke's JSON to discover the
page has no text boxes, costing one decode of everything per stroke through a
drawing session. What remains is one narrow query plus a delete and an insert
per write, which is not free and has not been measured under a real drawing
load.

`LibraryStore.decoder` went from `private` to internal so a second file can use
the configured instance rather than making its own.

### What this does **not** do

- **Seven tests, no UI.** Nothing types on a page yet, so in practice nothing
  is indexed through the app. Row 21 stays Partial.
- **No backfill.** A library whose text boxes predate this change will not find
  them until something writes that page's objects again. In practice no library
  has any, because nothing could create one until yesterday — but there is no
  pass to repair one, unlike `pdfText`, which has a backfill indexer.
- **Search answers with items, not pages.** `search(_:)` returns `[ItemID]`, so
  a hit says the document contains the words and not which page or which box.
- **The words are stored run together.** Several boxes on a page join with a
  space into one row, which is right for matching and is not the page's layout.
- **Nothing is indexed per word or position**, so there is no highlight-the-hit
  behaviour here, only "this document matches".

## A file item shows what it holds — row 8 UI — 2026-11-02 (Claude, UI by owner's direction)

The owner asked Claude to take UI while Codex is out of usage. `FileThumbnail`
shipped on 2026-10-28 with **nothing calling it**; the file details sheet now
shows a real picture of the file's contents where it showed the symbol for its
type.

- Full `./scripts/test.sh`: **511 tests passed** (0 warnings).
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.
- **`./scripts/ui-test-ios.sh` had not reported when this was committed.** It
  was started and was still running; the owner asked for the commit before it
  finished. **So the interaction run for this change is unverified**, and that
  is the one check this project asks for on UI work that the rest cannot stand
  in for. It is recorded here as unrun rather than assumed, and the result will
  be added when it lands.

### What limited the choice of slice at all

Codex has 193 uncommitted files, 14 of them in `PaperNestUI` and
`Apps/iOS/UITests`. For a file with uncommitted changes on both sides,
**whoever commits last silently reverts the other**, so every one of those is
off-limits — including `Localization.swift` and all three `Localizable.strings`.
**That rules out any UI work with new on-screen text**, which is why the Fill
Form, outline and compression screens were not candidates: this slice needed
**no new `L10n` keys**, and that is most of why it was the one available.

The library grid still shows the type symbol. That is one line,
`LibraryView.swift:570`, in a file Codex has open — left for whoever commits it
next rather than changed and lost.

### The fallback is the ordinary case

Most types have no preview, so the symbol stays most of the time. It is a
different claim rather than a worse thumbnail — "this is a spreadsheet" instead
of "this is what the spreadsheet looks like" — and the engine is still asked
only for a real rendering of the contents, never for the generic type icon the
system offers, because that icon *is* the symbol dressed up as a preview.

The header keeps a fixed 44-point box either way, so the row does not change
height when a thumbnail arrives after the copy is staged. The image stays
`accessibilityHidden`, as the symbol was, with the name and size beside it
carrying the meaning — so nothing VoiceOver reads has changed.

### It implements the fallback recorded on 2026-10-28 as "implemented nowhere"

`prepareTemporaryCopy` left a name with no extension exactly as it was, and the
system refuses to look inside such a file — measured then, and `nil` from both
the thumbnail and media engines. The staged copy now borrows the extension from
the item's recorded `uti`.

A name that **already** has an extension is left alone, even one that disagrees
with the recorded type. That copy is what the share sheet hands over, and
renaming someone's file to match its bytes is not that function's business —
`aNameThatAlreadyHasAnExtensionIsNotRewritten` pins that narrowing, and it
passed before the change as well as after, which is worth saying: it guards the
new behaviour from going further than intended rather than proving it.

### What this does **not** do

- **The interaction test is unrun**, as above. Nothing here has been driven in
  a running app.
- **No thumbnail in the library grid or list**, which is where most people
  would look for one.
- **Nothing is cached.** The sheet asks the system each time it opens. The
  staged copy it uses was already being made for sharing, so no file is copied
  twice, but a grid would need a cache this does not have.
- **A thumbnail for a large file still costs a full staged copy**, because the
  system needs a real file with a usable name and the stored asset is
  `<sha>.bin`.
- **No test asserts what is on screen.** The naming fix is covered, and the
  engine was covered in October; the view's own choice between picture and
  symbol is not, because the image is `accessibilityHidden` and so invisible to
  a UI test as well as to VoiceOver.

## iOS UI tests cannot run on this machine — 2026-11-02 (Claude)

**No interaction test has run since 2026-10-29.** This is an environment
failure, not a code one, and it is recorded because it means every UI change
from 2026-11-02 onwards is unverified in the one way this project says counts.

- `./scripts/ui-test-ios.sh` was started for the file-thumbnail change and sat
  for **4 hours 23 minutes with zero output**, no `xcodebuild` process beneath
  it, and was killed.
- The cause is its first real step. `xcrun simctl list devices available -j`
  **hangs**: killed at 60 seconds, 0 bytes written, nothing on stderr. The
  script selects a simulator that way before it echoes anything, which is why
  the log was empty rather than showing a failure.
- So CoreSimulator is wedged on this machine. Codex ran these tests
  successfully on 2026-10-29, so it has gone wrong since.

### What still works, and what does not

- **Unaffected:** `./scripts/test.sh` (511 tests, 0 warnings) and
  `./scripts/build-mac-app.sh`. Neither touches CoreSimulator.
- **Also unaffected:** `xcodebuild -scheme PaperNestUI -destination
  'generic/platform=iOS Simulator' build`, which succeeded today. A *generic*
  destination needs no device enumeration, so iOS **compilation** is still
  verifiable.
- **Blocked:** anything needing a booted simulator — `scripts/ui-test-ios.sh`,
  `scripts/run-mac-app.sh`'s iOS counterpart, screenshots, and every XCUITest.

### Not fixed

The usual remedy is to restart `com.apple.CoreSimulator.CoreSimulatorService`,
which would end any running simulator session. That is the owner's machine and
their call, so it has not been done. Until it is, UI work can be built and
compiled but its interactions cannot be driven, and nothing here should be
described as verified in the app.

## Why the iOS UI tests hang — the actual cause — 2026-11-02 (Claude)

The entry above said CoreSimulator was "wedged" and that the remedy was
restarting `CoreSimulatorService`. **That was a guess, and it was wrong.** The
service was restarted, came back on a new pid, and `simctl list` still hung —
so here is what it really is, found by taking the wrapper apart.

`.../Xcode.app/Contents/Developer/usr/bin/simctl` is a **bash wrapper**. It
reads the installed CoreSimulator version, compares it against the version it
expects, and if the installed one is older it runs:

    "${DEVELOPER_DIR}/usr/bin/xcodebuild" -runFirstLaunch

**synchronously, before exec'ing the real `simctl`.** That command installs
Xcode's system components and asks for an **administrator password**. Nothing
was there to answer it, so it waited — which is why the log stayed at zero
bytes for four and a half hours rather than printing an error.

Measured:

| | |
| --- | --- |
| installed CoreSimulator | **1174.9.2** |
| the `simctl` wrapper expects | **1174.21** |
| `xcodebuild -checkFirstLaunchStatus` | **exit 69** — components still need installing |
| Xcode | 27.2 |

So Xcode was updated and its first-launch component install was never
completed. Codex's last good run was 2026-10-29, which places the update
between then and now.

### The fix needs the owner, and cannot be done from here

    sudo xcodebuild -runFirstLaunch

It needs an administrator password, so no agent can run it. Opening Xcode once
and letting it install components does the same thing. **Until that happens,
every simulator-dependent check stays blocked** — `scripts/ui-test-ios.sh`,
screenshots, every XCUITest — and no UI change can honestly be called verified
in a running app.

### Two things this turned up on the way, worth knowing

- **`sample` on this machine's PATH is not macOS's.** It resolves to a Python
  script in `/Library/Frameworks/Python.framework/Versions/3.11/bin`, which
  fails with `ModuleNotFoundError`. Use `/usr/bin/sample` by full path — the
  PDFKit deadlock in October was only found because that call used the full
  path.
- **`grep` is a shell function wrapping `ugrep`.** It has already emitted
  `ugrep: warning:` in place of a plain grep error. Anything depending on exact
  grep behaviour should call `/usr/bin/grep`.

## Jump to a section by the document's own contents — row 36 — 2026-11-02 (Claude, UI)

`PageRenderer.outline(for:)` shipped on 2026-10-27 and nothing called it. The
editor's More menu now has **Contents**: the document's own table of contents,
with a tap jumping to that page.

- Full `./scripts/test.sh`: **513 tests passed** (0 warnings), `LocalizationTests`
  included — which is the check that the three new-key languages agree, that no
  key is unused, and that French typography is right.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.
- `xcodebuild -scheme PaperNestUI -destination 'generic/platform=iOS Simulator' build`:
  `** BUILD SUCCEEDED **`, 0 warnings.
- **No interaction test.** `scripts/ui-test-ios.sh` cannot run on this machine —
  see the entry above for why — so **nobody has opened this menu, tapped an
  entry or watched the page change.** That is the honest state of it.

### Read from the file, never rearranged

The entries are what the PDF declares, in the author's order and nesting. A
reordered document's contents will therefore not ascend, and that is deliberate:
it is a true description of the file, and sorting it here would invent an
answer the document does not give. The engine already drops entries whose page
was deleted, so an entry points at a page the document still shows.

### The one decision the sheet makes for itself

The sheet holds the outline it read when it opened. A page deleted *while* it is
open would otherwise select an id the document no longer has, leaving the editor
showing nothing — so `pageToSelect` returns nil for an entry whose page has
gone, and the two tests cover both halves: an entry opens the page it points at,
and one whose page has gone opens nothing while its siblings still work.

Nesting is indented but capped at four steps, so a deeply nested heading keeps a
readable text width on a phone.

### What this does **not** do

- **Nothing has been driven.** The menu item, the sheet, the empty state and
  the jump are all unexercised in a running app. The Mac app would still run
  (`scripts/run-mac-app.sh` needs no simulator) and was **not** used to check
  this; that route is open if the owner wants it driven before the simulator is
  fixed.
- **Only PDF outlines.** A notebook, a scan or an image has no outline to read,
  so the sheet correctly says the document carries none — but there is no
  user-made bookmark here, which is the other half of row 36 and still Planned.
- **No current-section highlight**, no jump-to-nearest-heading, and the sheet
  does not follow the page you are on.
- **A file that cannot be read shows "no contents"** rather than an error. For
  a navigation sheet that seemed better than an alert, but it does mean a
  damaged file and a plain one look alike here.
- **Depth beyond four levels is flattened visually** only — the entries are all
  still listed, in order.

## Driving the Mac app: two UI features verified, one bug found — 2026-11-02 (Claude)

The iOS UI tests cannot run here, but **the Mac app needs no simulator**. Both
UI features committed today were driven in it against a throwaway library
seeded with a generated 3-page PDF carrying a real outline and a plain-text
file item. This is the first interaction check since 2026-10-29.

- Full `./scripts/test.sh`: **513 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### Verified by looking at it

- **A file item shows its contents.** The details sheet's header shows a real
  Quick Look preview of the text file — a small page with its words on it — and
  not the blue type symbol. Zoomed in to be sure.
- **Contents lists the document's sections and jumps.** All three entries
  appeared in order, and pressing *Payment Schedule* dismissed the sheet,
  moved the editor to page 3 and selected page 3 in the sidebar.
- Incidentally: **Codex's first-launch welcome screen** appeared on a fresh
  library and dismissed on *Get started*, and stayed dismissed on relaunch.

### The bug this found, which no unit test could

The sheet first reported **"This document doesn't carry contents of its own."**
for a document that plainly had three. Traced rather than guessed:

| checked | result |
| --- | --- |
| the generated fixture on disk | outline root, **3 children**, destinations → pages 0,1,2 |
| the copy the library stored | same, **3 children** — import preserves it |
| `pages` rows in SQLite | three `pdfPage` rows on that asset, indices 0,1,2 |

So the file, the import and the engine's inputs were all correct. The fault was
mine, in the sheet: it took `[Page]` **at construction**. SwiftUI builds a
sheet's content when it is presented, so a sheet opened before the document's
pages had loaded kept an empty snapshot for ever and answered "no contents".
It now takes the `DocumentModel` and reads `model.pages` live, keyed on the
page count so a document still loading is read again when its pages arrive.

**This is exactly the failure the unit tests could not see** — they call the
engine and the one pure helper, neither of which knows when a sheet is built.

### Two things added to make it checkable at all

- **Contents is in the Mac menu bar**, at the top of the Page menu. The
  in-window More menu cannot be opened while the app is in the background, and
  the error said so. A document command belongs in the menu bar on macOS
  anyway. **Deliberately without a keyboard shortcut**: this project has been
  bitten by clashes with system ones, and the simulator that logs them cannot
  run today.
  Worth recording so nobody reads it as a defect: the menu item is **disabled
  while the app is in the background**, and the pre-existing *Crop…* was
  checked and behaves identically — it is how `@FocusedValue` works, not a
  fault in the new item.
- **`-PaperNestDebugShowOutline YES`**, beside the existing
  `-PaperNestDebugShowExport`, `…ShowCrop` and `…ShowMarkup` hooks. It opens
  the sheet at launch, which is both how this was driven in the background and
  how an XCUITest will reach it when the simulator works. **It is also what
  exposed the bug**, by getting to the sheet before the pages loaded.

### What this does **not** establish

- **Still no XCUITest.** Nothing is automated; this was a person-equivalent
  driving the app once. The hook above is in place for when `simctl` works.
- **Mac only.** The iPhone and iPad layouts of the Contents sheet, and its
  behaviour at large text sizes and in French and Spanish, are unchecked.
- **The empty state still cannot be told from a read failure.** A file whose
  outline cannot be read says "no contents", exactly as a file with none does.
  That is unchanged, and it is what made the bug above look like an ordinary
  answer.
- **One document, one outline shape.** Flat, three entries, one asset. Nested
  outlines, multi-source documents and deleted pages are covered by unit tests
  only.

## A Text Box tool, and where the other five asked-for tools stand — row 21 — 2026-11-02 (Claude)

The owner asked for six things: a text box, selecting handwriting and moving
it, an image tool, a highlighter, pencil controls and an eraser. **The survey
first, because most of the answer is not "build it" but "it exists, elsewhere".**

| asked for | where it actually stands |
| --- | --- |
| **Text box** | Engine was done; **the tool is built now**, below. |
| **Select handwriting, move it** | **Works on iOS** — PencilKit's lasso, and `InkConversion` applies `stroke.transform` on save, so a moved stroke persists moved. **Nothing on Mac.** |
| **Image tool** | Engine done (`placeImage`, drawing, export). **No UI on either platform.** |
| **Highlighter** | In the model (`InkStroke.Tool.highlighter`), drawn and exported; reachable on iOS through the PencilKit tool picker. **Not on Mac.** |
| **Pencil controls** | iOS only, PencilKit's own picker (width, colour, pen/pencil/marker). **Not on Mac.** |
| **Eraser** | iOS only, PencilKit's. **Not on Mac.** |

**The finding worth acting on: `InkCanvas` is `#if os(iOS)`, and so is the
Markup toggle. The Mac app has no drawing, no eraser and no lasso at all** —
four of the six requests are a single missing piece, a Mac drawing surface, and
PencilKit does not exist on macOS to supply it.

- Full `./scripts/test.sh`: **520 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### The text box tool

`LibraryStore.placeText` is the guarded way in, as `placeImage` is for
pictures — `saveObject` would take anything, and a box the renderer skips
leaves the page quietly missing what someone typed. Refused rather than
stored: empty or whitespace-only text, a frame with no area or a non-finite
one, a font size of zero, and a missing or deleted page. Each refusal writes
nothing. Seven store tests.

`DocumentModel.addTextBox` wraps it with the refresh and the undo
registration the other mark tools use, so **Undo works on a text box** — seen
working in the app. The same write rebuilds the page's search row, so the
words are findable the moment they are added.

**Verified by driving the Mac app**, not by inference: created a notebook,
opened *Text Box* from the notes tool bar, typed "Agreed at the meeting on
Tuesday", chose Center and red, pressed Add — the text appeared on the page in
red and centred, the sidebar thumbnail updated, and Undo became enabled.

It is in both More menus, the notebook tool row and the Page menu, with eight
new keys in English, French and Spanish. Alignment is a **segmented** control
rather than a pop-up, because French and Spanish truncate in pop-ups.

### What this does **not** do

- **A text box cannot be moved, resized or edited once added.** The frame is
  chosen by `addTextBox` — a band across the upper part of the page, its height
  growing with the font size. This is the biggest gap in the tool and the
  obvious next slice; the owner asked for "move it anywhere" about handwriting,
  and it applies here too.
- **Text longer than the frame is clipped**, silently, as it has been since
  the engine landed.
- **No image tool yet**, though its engine has been ready since 2026-10-28.
- **Nothing was added for the Mac's missing drawing surface**, which is what
  four of the six requests actually need.
- **No XCUITest** — the simulator still cannot run. This was driven by hand on
  Mac, once, in English, in dark mode. iPhone and iPad layouts, large text, and
  French and Spanish are unchecked.

## Correction: undo on a text box did not work — 2026-11-02 (Claude)

The entry above says, of the text box tool, "**Undo works on a text box** —
seen working in the app". **That was wrong, and the way it was wrong is worth
recording.** What I saw was the Undo *button become enabled*. Enabled is not
working, and I wrote down the stronger claim.

Pressing it would have shown "the markup changed" and left the text box on the
page. The editor's whole undo history runs through
`LibraryStore.applyInkChanges`, which guarded `case .ink = object.payload` and
answered `pageObjectsChanged` for anything else. Undoing an *added* text box
applies the inverse change — a delete of that object — so the guard refused it.

Proven before fixing: a store test applying exactly the inverse change the undo
path applies failed with `.pageObjectsChanged`.

### The fix

The guard now accepts the marks a page carries — ink, a text box, a placed
image — rather than ink alone. **A page comment is still refused**, and that is
deliberate: it is private, it has its own guarded path that leaves the page
revision alone, and it must not travel through the markup history.
`PageCommentWorkflowTests` and `InkEditTests` both still pass.

### Verified properly this time

In the running Mac app: made a notebook, added a text box reading "This should
vanish on undo", pressed **Undo** — the text disappeared from the page and from
the sidebar thumbnail, no error appeared, and Redo became enabled. That is the
check the first entry should have had.

- Full `./scripts/test.sh`: **521 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh`: succeeded, 0 warnings.

### What this does not change

A text box still **cannot be moved, resized or edited** once added — the next
slice, and the one the owner asked for. The image tool still has no UI, and the
Mac still has no drawing surface, which is what the highlighter, pencil
controls, eraser and lasso all actually need.

## A placed mark can be picked up and moved — row 21 — 2026-11-02 (Claude)

The gap the text box shipped with: a box could be added and never moved. A
text box or a placed image can now be dragged on the page, with undo.

- Full `./scripts/test.sh`: **526 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### Verified by dragging one

In the running Mac app: added a text box reading "DRAG ME" at the top of a
notebook page, dragged it to the bottom — it moved, the selection outline
followed it and the sidebar thumbnail updated — then pressed **Undo** and it
returned to the top with Redo enabled. Both halves seen, not inferred.

### How it is put together

`MovableMarksOverlay` sits over the rendered page and claims **only** the
rectangles those marks occupy, so scrolling, zooming and the iOS ink canvas
behave exactly as before, and it stands down entirely while the ink canvas is
up. It positions handles with the **same `sourceToView` transform the page was
drawn with** — the one the ink canvas already uses — rather than a second
guess at where a mark is.

The write goes through `applyInkChanges` with `saving: [moved]` and
`replacing: [original]`, so a drag is refused if the object changed underneath
it, and undo comes from the machinery everything else uses. That path only
accepts text and images here because **ink is moved by the drawing canvas's own
lasso** and a page comment has no frame — `moved(_:to:)` returns nil for both
rather than mangling them, and a test says so.

A dragged frame is clamped so its **origin** stays on the page. Hanging over an
edge is allowed, because that is a reasonable thing to want and drawing clips
it; being dragged entirely off and lost is not.

### What this does **not** do

- **No resizing.** There are no handles: a mark keeps the size it was created
  with. For a text box that matters, because text longer than its frame is
  still clipped silently.
- **No editing.** The words in a text box cannot be changed after it is added,
  and there is no delete from the page — only undo.
- **Ink is untouched.** Selecting and moving handwriting remains PencilKit's
  lasso on iOS, and still does not exist on Mac.
- **Mac only, by hand, once.** No XCUITest — the simulator still cannot run —
  so the drag is unexercised on iPhone and iPad, where a drag competes with
  scrolling in a way a mouse does not. That is the most likely place for this
  to behave differently, and it is untested.
- **No multiple selection**, no keyboard nudging, and the selection is not
  cleared by tapping the page.

## Drawing on a Mac — row 21 — 2026-11-02 (Claude)

macOS has no PencilKit, so the Mac had **no drawing, no eraser and no lasso at
all** — the single gap behind four of the six tools the owner asked for. This
is the first half of closing it: a canvas of our own, with a pen and a
highlighter, colour and width, saved as ordinary ink with undo.

- Full `./scripts/test.sh`: **531 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### Verified by drawing

In the running Mac app: made a notebook, turned on **Markup** (the toggle now
exists on Mac), drew a wavy pen stroke, then switched to **Highlighter**,
**Thick** and **yellow** and drew across it. Both appeared, the highlighter
translucent over the pen so the stroke beneath shows through. The pen stroke
survived quitting and relaunching the app, so it is stored as ink like any
other.

### The bug drawing it found

The first stroke **saved but vanished from the page** the moment the pointer
came up — it was in the sidebar thumbnail and nowhere else. The page is
rendered with `includesInk: !isMarkingUp`, which is right for iOS, where
PencilKit draws every stroke itself and the page underneath must not draw them
twice. The Mac canvas previews **only the stroke being drawn**, so the page has
to keep drawing the saved ones. Separated into `pageShowsInk`, with the reason
written down, because the two canvases genuinely need opposite things.

Nothing but driving it would have caught this: the stroke was saved correctly,
so every test passed.

### How it works

One drag, one stroke. Points are captured in view space and converted with the
**inverse of the transform the page was drawn with**, so a stroke lands where
the pointer was at any zoom and is stored in the same upright source space as
everything else. Five tests cover that geometry, including that **the same
place on screen at two different zooms is the same place on the page**, and
that a click without movement is kept as a dot rather than dropped.

Saving goes through `applyInkChanges`, so undo is the same machinery as
everything else.

### What this does **not** do

- **No eraser and no lasso.** Half the gap is still open: nothing on Mac
  selects, moves or rubs out ink. Moving a *text box or image* works (that is
  `MovableMarksOverlay`), but ink is untouched.
- **No pressure, so one width per stroke.** A drag gives position only. On iOS
  Apple Pencil varies the width within a stroke; on Mac it cannot, and that
  difference is real rather than hidden.
- **The widths are the shape tool's** — 1, 2 and 4 source points. "Thick" is
  thin for a highlighter; the sizes have not been tuned for drawing.
- **No smoothing.** Points are joined as straight segments, so a fast stroke
  looks angular where PencilKit would curve it.
- **No XCUITest**, as ever while the simulator is down. Driven by hand on Mac,
  once, with a mouse — not with a trackpad, and not at any zoom but the default.

### A trap worth knowing

`MacInkCanvas.stroke(…)` is a static on a SwiftUI `View`, which makes it
main-actor isolated. Calling it from a test **compiled** and then trapped at
runtime with signal 5. The same thing on `DocumentOutlineSheet.pageToSelect`
was caught at compile time instead. Mark such helpers `nonisolated` — the
failure mode is a crash in the test runner with no assertion message, which
reads like a broken test rather than an isolation problem.

## An Image tool — row 21 — 2026-11-03 (Claude)

The last of the six tools the owner asked for that had no UI at all.
`placeImage` has been ready since 2026-10-28 and nothing called it; **Image**
now sits beside Text Box in the editor and in the Page menu, picks an image
file, and puts it on the page.

- Full `./scripts/test.sh`: **537 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

The bytes are sniffed with the project's own `FileTypeSniffer.kind(of:)`, so
what gets stored is what the bytes **are** rather than what a filename claimed,
and a kind the renderer cannot draw is refused before anything is written. They
are staged durably and the row referencing them is written by `placeImage` in
the same transaction, so the housekeeping sweep cannot take the file in
between.

The frame **keeps the image's own proportions**, so a photo is not squashed into
a box: a 2:1 image comes out 2:1, measured. A sideways photo reports the size it
is *shown* at rather than the size it is stored at, because that is the shape the
frame has to match — the renderer decodes it upright, and
`aSidewaysPhotoReportsTheSizeItIsShownAt` pins the quarter turn. An image whose
size cannot be read still gets a usable frame rather than a zero-sized one the
renderer would skip. Seven tests.

Once placed it can be **dragged**, because `MovableMarksOverlay` already covers
placed images, and undo is registered like every other mark.

### What was verified, and what was not

- **Verified in the running Mac app:** the **Image** button exists in the
  notebook tool row and the editor menus, is disabled with no page selected,
  and is reachable.
- **Not verified:** the picker itself. A macOS open panel is modal and needs
  the app frontmost; background control cannot bring it forward, and no panel
  appeared or could be confirmed. **So the hand-off from "a file was picked" to
  "an image is on the page" has not been driven by anyone.** Everything either
  side of it is covered — the sniffing, the frame, the staging-and-row write,
  the drawing, the dragging and the undo — but that join is code nobody has
  run.

That is the honest state of it, and it is the place to look first if it
misbehaves.

### What this does **not** do

- **No resize.** A placed image keeps the size it was given, as a text box
  does; it can only be dragged.
- **No drag-and-drop onto the page**, and no paste — the picker is the only way
  in.
- **One image per pick.** Multiple selection is off.
- **No XCUITest**, as throughout while the simulator is down.

## An eraser on the Mac — row 21 — 2026-11-03 (Claude)

Drawing arrived on the Mac yesterday with no way to take a mark back except
Undo. **Markup** now reads **Pen | Highlighter | Eraser**, and dragging the
eraser over a stroke removes it.

- Full `./scripts/test.sh`: **543 tests passed**, **0 warnings**, all five
  targets green.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

The eraser is a **mode, not a mark**. `MacMarkupTool` is its own enum rather
than a case added to `InkStroke.Tool`, which is persisted — an eraser case in
the stored enum would invite a saved stroke that claims to be one. The drag
paints nothing: it collects points, converts them to source space, and asks
which ink objects it touched.

**Hit-testing is point-to-segment, in both directions.** A stroke is taken when
any of its points comes within `eraserRadius + width / 2` of a *segment* of the
eraser's path, or any eraser point comes that close to a segment of the stroke.
Measuring only between recorded points was the first implementation and it
was wrong: it missed the middle of a long straight stroke, whose two recorded
points are hundreds apart, and `theEraserTakesTheStrokeItCrosses` caught it. The
reverse direction covers a dot that falls between two samples of a fast flick
(`aFastFlickStillTakesADotBetweenItsSamples`). The reach is 8 source points
plus half the stroke's width, so a thick stroke is caught from further away
(`aThickStrokeIsReachedFromFurtherAway`) and the reach is the same on the page
at any zoom.

Removal goes through `applyInkChanges(on:saving:replacing:deleting:)`, the same
guarded write every other mark uses, as one undoable step named by `L10n`.
Eleven tests cover the geometry and the hit-testing, including
`theEraserNeverTakesATextBoxOrAnImage` — the filter matches `.ink` payloads
only, so a text box or an image sitting under the drag is not collateral.

While the eraser is selected the **width and colour controls are hidden**,
because neither means anything for it, and the preview stroke is a faint grey
instead of the pen's colour.

### Verified by driving the Mac app

Against a throwaway library (`/tmp/pn-erase`, since deleted), in a notebook with
two separate pen strokes one above the other:

- Switching to **Eraser** hid the width and colour rows, leaving the three
  tools.
- One drag down across the **upper** stroke only: **the upper stroke
  disappeared from the page and from the sidebar thumbnail, and the lower one
  stayed.** Both halves of that matter — an eraser that takes everything would
  also pass "the stroke is gone".
- **Undo brought it back**, both lines on the page and in the thumbnail, with
  Redo then enabled. The write is durable, not a view-state trick.

### What this does **not** do

- **Whole strokes only.** A stroke the eraser crosses goes *entirely*, rather
  than being split where it was crossed. Splitting means rewriting a stroke's
  points and deciding what becomes of the halves; a whole-stroke eraser is a
  behaviour people already know, but it is not what PencilKit does on iOS, so
  **the two platforms now erase differently** and nobody should read one as
  evidence about the other.
- **No eraser size.** 8 source points, chosen because aiming a mouse at a thin
  line is harder than aiming a finger. Unmeasured against anyone's hand.
- **No cursor change.** The pointer stays an arrow over the page, so the only
  sign of which tool is armed is the segmented control.
- **Nothing is erased on iOS by this.** PencilKit's own eraser is what iOS has,
  and it is untouched.
- **Still no lasso on Mac**, which is the last of the six tools the owner asked
  for: handwriting cannot be selected and moved there.
- **No XCUITest**, as throughout while the simulator is down — driven by hand
  on Mac, once, in English, in light mode.

## A lasso on the Mac — row 21 — 2026-11-03 (Claude)

The last of the six tools the owner asked for. Handwriting can now be selected
and moved on a Mac: **Markup** reads **Pen | Highlighter | Eraser | Lasso**, a
loop drawn round a stroke selects it, and dragging the selection moves the ink.

- Full `./scripts/test.sh`: **556 tests passed**, **0 warnings**, all five
  targets green.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

**The rule is "wholly enclosed".** Every point of a stroke has to fall inside
the loop, which is what drawing a circle round handwriting means, and it keeps
a loop from dragging off the neighbouring word by its tail. Point-in-polygon is
the even-odd rule, written out rather than handed to `CGPath`, so the loop is
**closed from its last point back to its first** here rather than by whoever
drew it — a drag ends where the pointer stopped, and nobody closes a lasso by
hand.

**The selection is held by `PageObjectID`, never by value.** The strokes are
read back from the model when the move commits. Holding the objects themselves
would have meant that selecting, moving, undoing and then moving again sends
stale points as `replacing:`, `applyInkChanges` refuses the write, and `try?`
swallows it — a drag that silently does nothing. That exact sequence was
driven in the app (below), because the geometry tests cannot reach it.

The move translates every point, keeps the object's **id**, so undo sees one
mark moved rather than one deleted and another added, and keeps each point's
`widthScale` and `time`, so pressure and timing recorded by an Apple Pencil
survive being moved on a Mac. The drag is converted through the page's own
transform — two points through the inverse and subtracted, shared now with
`MovableMarksOverlay` as `DocumentModel.sourceDelta` — so a **rotated** page
moves ink the way it looks. A hand-rolled divide-by-the-scale passes the zoom
test and fails that one, which is why both are pinned.

**A selection is clamped to stay wholly inside the part of the page that is
shown**, which is stricter than `clamped` is for a text box, and for a reason:
the lasso only takes a stroke it can enclose wholly, so handwriting with a tail
outside could never be selected again. The rectangle is `PageGeometry.cropRect`
rather than the whole source, because on a cropped page the canvas covers only
what the crop leaves, and ink dragged under the crop is as unreachable as ink
dragged off the page. Ignoring the crop's origin makes
`aSelectionCannotBeDraggedUnderTheCrop` fail, which is how that was checked. A selection already bigger than the page is left alone rather
than pinned. Fourteen tests. They failed to **build** before the API existed,
which is an error rather than a failure, and **four** were then proven red by
deliberately breaking the guard they cover: the closure, the whole-stroke rule,
the rotated transform and the crop's origin. The other ten were not shown
failing against wrong code, and three of those — `nothingSelectedHasNoBox`,
`translatingIsForInkOnly` and `aSelectionBiggerThanThePageCanStillBeMoved` —
would pass against a good deal of it.

### Verified by driving the Mac app

Against a throwaway library (`/tmp/pn-lasso`, since deleted), in a notebook with
two zigzag pen strokes:

- Switching to **Lasso** hid the width and colour rows, as the eraser does.
- A loop round the **upper** stroke drew a dashed box tight to that stroke and
  left the lower one unselected.
- Dragging from inside the box moved the upper stroke down and left; the lower
  one stayed, the dashed box followed the ink, and the sidebar thumbnail
  redrew. The ink is really moved, not previewed.
- **Undo** put it back, box and all.
- **Dragging the same selection a second time, after that undo, worked** — the
  stale-payload failure above.
- Switching back to **Pen** cleared the dashed box.
- **French and Spanish**, both launched and looked at: *Stylo | Surligneur |
  Gomme | Lasso* and *Lápiz | Marcador | Borrador | Lazo*, all four readable
  in the 420-point row, no truncation.

### Found while checking, and **not** caused by this

**The document toolbar's Redo button reads enabled after undo followed by a
fresh edit.** Reproduced with the pen alone — draw, Undo, draw, and Redo is
still blue — so it is not the lasso's doing. Pressing it changed nothing on the
page, and it then disabled itself.

**Run down and fixed** — see *The Undo button went dead on the stroke you had
just drawn*, below. It was the row's enabled state, not the history, and the
symptom was worse than a lit Redo: the **Undo** button was greyed out on the
mark someone had just drawn.

### What this does **not** do

- **No resize, no rotate, no delete, no copy of a selection.** It can be
  selected and dragged, nothing else.
- **No handles.** The dashed box is drawn but cannot be grabbed by a corner.
- **No lassoing text boxes or images.** Ink only — those move with Markup off,
  through `MovableMarksOverlay`, and the two never coexist.
- **No moving across pages**, and no cut and paste anywhere.
- **The original stays on screen during the drag.** The page renderer keeps
  drawing the ink where it still is until the commit lands, so the dragged
  outline and the original are both visible mid-drag. That is the honest cost
  of previewing in the canvas, and it was chosen over leaving a naked
  rectangle to drag.
- **Partly-enclosed strokes are simply not selected**, with no hint on screen
  saying why. A loop that catches nothing clears the selection.
- **No XCUITest**, as throughout while the simulator is down — driven by hand
  on Mac, once each in English, French and Spanish, in light mode.

## The Undo button went dead on the stroke you had just drawn — 2026-11-03 (Claude)

Found while checking the lasso, then run down on its own. Two earlier drafts of
that entry each got this wrong, which is why the sequence is written out here.

- Full `./scripts/test.sh`: **559 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What was wrong

After drawing a stroke, the editor's **Undo** button stayed greyed and
**Redo** stayed lit — the state from *before* the stroke. You could not undo
the mark you had just made, from the button.

`NotebookHistoryActions` reads `UndoManager.canUndo` and `canRedo`, which are
not observable SwiftUI state, so it re-reads them only when one of its own
inputs changes. It bumps a `revision` on `NSUndoManagerDidCloseUndoGroup`,
`…DidUndoChange` and `…DidRedoChange`. The last two fire; **the first does
not** for these registrations, because every ink edit registers its undo from
inside a `Task` rather than while handling an event, so there is no
event-grouped close for the undo manager to announce. Nothing told the row the
stroke had happened.

`DocumentModel.historyRevision` is the input it was missing: the model advances
it whenever it registers an undo, re-registers one during an undo, or clears
the stack after a failed write, and the row folds it into its `.id`. The model
is the only thing that knows it has touched the stack.

### How it was established, step by step

Everything below is one action per round trip — **a click and a screenshot in
the same batch is useless here**, because the undo runs on a `Task` and the
screenshot is taken before it lands. Two earlier passes were misread exactly
that way, and the first of them is the reason an earlier draft of the lasso
entry called this "a stale label" without evidence.

1. Draw A → Undo → page empty, Undo greyed, Redo lit. **Correct**, and it
   proves the notification path works for an undo.
2. Draw B → B is on the page, and the row **still** reads Undo greyed, Redo
   lit. That is the bug: the display never moved.
3. Press Redo → **A does not come back.** Only B is there, and the row corrects
   itself to Undo lit, Redo greyed. So the redo stack really had been cleared
   by the fresh edit, as `UndoManager` does; the lit Redo was stale, and the
   press changed nothing but the display.
4. **⌘Z undoes the stroke the greyed button refuses.** The keyboard goes
   through the responder chain and never consults the row. So the history was
   sound throughout and nothing was ever lost or misapplied — the fault was
   entirely in which buttons you were allowed to press.

### What was verified after the fix

- Three tests in `HistoryRevisionTests`, each watched failing first (the
  property did not exist): drawing advances the revision, **erasing and moving
  advance it too**, and undoing advances it further rather than going
  backwards. The first asserts `undo.canUndo` alongside, so it cannot pass by
  registering nothing.
- In the running Mac app, on a fresh notebook: drawing a stroke now leaves
  **Undo lit and Redo greyed**, and undo-then-draw-again — the original
  symptom — leaves Undo lit and Redo greyed as well.

### What this does **not** cover

- **The same `Task` registration is used for page transforms**, which bump the
  revision too, but rotate/crop/filter were not re-driven by hand. The tests
  cover ink only.
- **iOS was not driven**, as throughout while the simulator is down; it
  compiles, and the row is shared, so the phone and iPad toolbars should
  benefit identically — *should*, untested.
- **No XCUITest.** `notebook-undo` and `notebook-redo` have accessibility
  identifiers but no `accessibilityValue` saying whether they are enabled, so
  a test would have to assert on `isEnabled`.
- **The root cause is worked around rather than removed.** Registering inside
  an explicit `beginUndoGrouping`/`endUndoGrouping` would make the native
  notification fire by itself, and would be the smaller fix — but it changes
  undo grouping for every edit in the app, including the re-registration that
  runs *during* an undo, and that was not something to change late in a
  session on a hunch. Worth revisiting deliberately.

## The six tools, used together for the first time — 2026-11-03 (Claude)

The six the owner asked for were built one at a time over three days and had
never been exercised side by side. This is that pass, in one notebook on a
Mac, and the two faults it turned up — both fixed here.

- Full `./scripts/test.sh`: **567 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### 1. A text box or an image could never be taken off the page

**Manage Markup said "No marks on this page" with a text box plainly on it** —
and plainly in the sheet's own preview, two inches above those words. Its list
filtered to `.ink`, so the two tools that do not draw ink produced marks the
manager could not see. Nothing else offers a delete: the eraser is ink-only by
design, the lasso selects ink only, and the drag overlay moves without
removing. So once undo had moved on, **a text box or a placed image was on
that page permanently.** That is a worse fault than any of the polish items in
the entries above, and the pass found it in the first two minutes.

The gate was in the store: `editInk` refused anything but `.ink` outright.
Now:

- **Removing** accepts `.ink`, `.text` and `.image` — anything painted on the
  page.
- **A comment is still refused.** It is not painted on the page and has its
  own place to live; sweeping one away from a markup sheet would delete
  something the user cannot see from there.
- **Recolouring stays ink-only** and is **refused**, not skipped, for anything
  else, through a new `StoreError.cannotRecolor`: an image has no colour and a
  text box's colour is not what that picker means. The sheet disables **Apply
  Color** whenever the selection holds anything but ink, so the button never
  promises a refusal.

The sheet lists every painted mark, a text box under its own words rather than
as "Mark 3", and the selection preview outlines text and image frames as it
already did stroke bounds.

### 2. The highlighter drew a hairline

Pen and highlighter shared one row of widths — 1, 2 and 4 points. That is
right for a pen on an A4 page and useless for a highlighter: at **Thick** it
laid a 4-point yellow line *across* the words instead of a band behind them,
which a zoom of the page makes plain. It was not a highlighter in any sense a
user would recognise.

The width row now means different things to different tools: `width(for:)` on
`MacMarkupTool`, with the picker carrying a `MarkupWeight` (thin/medium/thick)
rather than a number. The pen keeps 1/2/4; the highlighter gets 12/20/30, so
its *thinnest* is wider than the pen's thickest and its middle step covers the
18-point line a text box defaults to. Choosing by weight rather than by number
also means switching back to the pen cannot leave a 30-point pen armed.

### What was verified, and how

Thirteen new tests in all, each watched failing first. Three were then proven
red by breaking the guard they cover: the highlighter widths (set back to the
pen's, and two tests fail), removing a text box, and recolouring one.

In the running Mac app, on a throwaway library (`/tmp/pn-six`, since deleted):

- A **new** highlighter stroke lays a proper yellow band behind a line of
  text, in the same frame as the old 4-point stroke still showing as a
  hairline on the line above. Old strokes keep the width they were saved with,
  which is correct and worth knowing.
- Manage Markup lists the text box **under its own words**, with Apply Color
  greyed and Remove Selected lit while it is the selection.
- **Remove Selected takes it off the page**, out of the list, out of the
  preview and out of the sidebar thumbnail — and **Undo puts it back**.

### Also found, and **not** fixed

- **The sheet outgrows the window.** With four marks on a 729-point-tall
  window, Apply Color and Remove Selected fall below the bottom edge; the
  scroll view is there, but synthetic scroll events would not move it, so
  **whether a real trackpad reaches them is unconfirmed**. Verified instead on
  a page with one mark. The sheet asks for `idealHeight: 680` and the Done
  button sits at the very bottom edge. Codex owns that layout.
- **A text box still cannot be edited.** Clicking and double-clicking a placed
  box does nothing but select it: its words, size, colour and alignment are
  fixed at the moment it is added. Now that it can at least be *removed*, this
  is a smaller hole than it was, but a typo still means delete and retype.
- **A text box's frame is taller than its text**, so the dashed selection box
  hangs below the words. The text does wrap rather than clip, which the
  earlier entry for text boxes did not establish.
- **The image picker is still undriven.** A macOS open panel is modal and
  background control cannot bring it forward.
- **Six tools, two homes.** Pen, highlighter, eraser and lasso live behind the
  Markup toggle; Text Box and Image sit in the toolbar and are unavailable
  while Markup is on. That is a coherence question for whoever owns the
  design, not a bug.

## A text box can be changed after it is placed — row 21 — 2026-11-03 (Claude)

The hole the previous entry's pass left open. A text box was **write-once**:
its words, size, colour and alignment were fixed the moment it was added, and
clicking or double-clicking it did nothing but select it. A typo meant
deleting the box and typing it again — and until the previous commit it could
not even be deleted.

- Full `./scripts/test.sh`: **573 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

**Double-click a box and it opens**, pre-filled with what is on the page, with
the sheet titled *Edit Text Box* and its button reading *Save*. The same sheet
adds and edits; `editing` tells it which.

`LibraryStore.updateText` is the way in, with **the same refusals as placing
one** — empty text, a zero or non-finite size, a frame with no area — because
an empty box is just as unusable the second time. It also refuses a payload
that is not a text box, so a stroke handed in here cannot be quietly turned
into text. The write is the **guarded** one, so a box someone else changed
first is refused rather than written over.

The box keeps its **id** and its place in the paint order, so undo sees one
box changed rather than one deleted and another added, and a mark does not
jump above its neighbours when it is edited. The same write rebuilds the
page's `text` index row, so the old words stop being findable as the new ones
start — pinned by a test, since search answering with text the page no longer
carries is the kind of thing nobody notices for months.

**Where it is stays where it is.** The origin and width it was dragged to are
kept, and only the height follows the type size, through
`DocumentModel.textBoxHeight(forFontSize:pageHeight:)` — shared with placing,
so a box does not change shape the first time someone touches it.

The sheet re-reads the box **by id** when Save is pressed rather than trusting
the copy it opened with: an undo in between would otherwise make the guarded
write refuse, and `try?` would hide it. If the box is gone entirely — undone,
or removed from the markup manager — it says so instead of resurrecting it.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-edit`, since deleted), with a box reading
"Pian in full":

- A **double click opens it**, pre-filled: the text, Size 18, Left, black.
- Changing the text, the size (18 → 30), the alignment (Left → Center) and the
  colour (black → red) and pressing **Save** shows all four on the page at
  once, with the frame grown taller and the sidebar thumbnail redrawn.
- **Undo restores every one of them**, frame height included.
- **Editing again straight after that undo works** — the stale-copy trap.
- **Dragging still works.** The double-click is a `highPriorityGesture` in
  front of the drag, which is the thing most likely to have broken moving, so
  it was checked rather than assumed.
- **English, French and Spanish**, all three launched and looked at:
  *Edit Text Box / Save*, *Modifier la zone de texte / Enregistrer*, *Editar el
  cuadro de texto / Guardar*. No truncation in the 460-point sheet.

### What this does **not** do

- **No editing in place.** The words are changed in a sheet, not typed on the
  page, and there is no caret or text selection on the page itself.
- **Still no resize or reflow by hand.** The width is whatever it was placed
  or dragged with; only the height follows the type size, and text longer than
  the box still runs past its bottom edge.
- **No font choice.** One typeface, as before.
- **A placed image cannot be edited**, because there is nothing to edit but
  its frame, and resizing is not built. Double-clicking one does nothing.
- **iOS is untested.** The overlay is shared, so a double *tap* should open
  the same sheet on a phone or iPad, and `accessibilityAction` offers it to
  VoiceOver — *should*: the simulator is still down and neither was driven.
- **No XCUITest**, as throughout.

## A mark can be resized by a corner — row 21 — 2026-11-03 (Claude)

A text box or a placed image kept whatever size it was given: it could be
moved, and since the last two commits removed and edited, but never made
bigger or smaller. Selecting one now puts a handle on each corner.

- Full `./scripts/test.sh`: **585 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

**The corner opposite the one dragged stays exactly where it is.** That is the
whole contract of a corner handle, and getting it wrong makes a box look like
it is running away from the pointer; all four corners are pinned by a test
that checks the anchor survives.

**An image keeps its proportions; a text box does not have any to keep.**
Squashing a photo is what the placing code went to trouble to avoid, so a
resize must not undo it. Which axis drives a locked resize is decided by
**whichever was dragged further**, so the gesture follows the pointer rather
than ignoring one direction, and at the edge of the page a locked image
**shrinks to fit rather than distorting** — the easy mistake there is to clamp
one side and leave the other, which is exactly the squashing the lock exists
to prevent.

Nothing shrinks below 16 source points in either direction — a negative width
draws nothing and leaves something on the page nobody can grab — and nothing
grows past the page, for the same reason a move is clamped. The write is the
same one a move uses, with its own undo name, so the Edit menu says which of
the two it is undoing.

### A regression this turn's checking found in **last** turn's commit

Dragging a corner needs the mark selected first, and **clicking a mark had
stopped selecting it**. `2cd5c8e` added opening-on-double-click as a
`TapGesture(count: 2)` beside the move gesture. A tap-count gesture waits to
see whether a second click is coming and **swallows the single click that
never becomes one** — as `highPriorityGesture` and, tested here, as
`simultaneousGesture` too. It was found by taking the tap gesture out and
watching selection come back, after guessing wrong once.

It is counted by hand now, inside the drag that already handles the first
click: a second click on the same mark within the system's own
`NSEvent.doubleClickInterval` opens it. Three tests cover the pairing. **That
commit's claim that double-clicking worked was true; what it did not say is
that single-clicking had stopped, because that run only checked the double
click and the drag.** A reminder that checking the thing you added is not the
same as checking what it sits next to.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-resize`, since deleted):

- **One click selects** and draws four corner handles.
- **Dragging the bottom-right handle inwards shrinks the box**, with the
  top-left corner staying exactly where it was.
- **Undo restores the old size.**
- **A double click still opens the editor**, and **dragging the middle still
  moves the mark** — the two things the gesture change could have broken.

### What this does **not** do

- **Corners only.** No edge handles, so a box cannot be made wider without
  also being made taller unless the drag happens to be horizontal.
- **No proportional resize for a text box**, and no modifier to lock or
  unlock: SwiftUI's drag gesture does not report modifier keys, so shift-drag
  would have to be read some other way. Images are locked, text is free, and
  that is the whole rule.
- **Text does not reflow to a resized box.** It still runs past the bottom
  edge if there is more of it than the box holds.
- **Pointer only.** The handles are `accessibilityHidden`, because four
  identically labelled stops would be worse for VoiceOver than none — but
  that leaves **no way to resize a mark without a mouse or a finger**, which
  is a gap, not a decision to be proud of.
- **The handles' targets overlap on a small mark.** Each is 22 view points
  across, so on a mark near the 16-point minimum they sit on top of one
  another and whichever is topmost wins.
- **iOS is untested**, as throughout while the simulator is down; the overlay
  is shared, so handles should appear there too.
- **Only the undo name is new text** (`Resize`), and it shows in the Edit
  menu rather than on screen, so the French and Spanish were not looked at
  this time — nothing in the sheet or the page changed.

## Recognition reads in the languages you choose — F4 — 2026-11-03 (Claude)

Taken from "Next for Claude" in the handoff. Recognition always asked Vision
for English, French and Spanish — whatever the document was and whoever was
reading it. Someone scanning German could not say so, and since Vision
**weights the list it is given**, the wrong list does not merely fail to help:
it makes the reading worse.

- Full `./scripts/test.sh`: **598 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

Settings now has a **Text Recognition** section listing every language this
device's Vision can read, named in the reader's own language. Nothing else is
offered: the supported set differs by OS version, and a row that cannot work
is a promise that cannot be kept.

`TextRecognizer.resolve(override:fallback:available:)` decides what to use. A
choice **replaces** the defaults rather than adding to them, for the weighting
reason above. The order chosen is kept, because that is the order Vision
weights. A choice this device cannot honour **at all** falls back to the
defaults rather than leaving recognition with an empty list that reads
nothing — and `unavailable` still carries the whole choice, so the screen says
*"This Mac cannot read Swahili (Kenya)"* instead of quietly reading something
else. Where nothing is readable the list comes back **empty rather than as a
guess**: reading a page in a language nobody asked for produces confident
nonsense, and `recognize` refuses an empty list outright.

Eight tests cover the resolution, with `available` passed in so they do not
depend on what this particular machine supports; two were proven red by
removing the fallback and the de-duplication. Five more cover the stored form,
which is a hand-rolled comma-separated string — a stray space or an empty
entry would reach Vision as an unreadable language and be reported back as the
reader's mistake.

**It also removes a duplication that was waiting to go wrong.**
`DocumentModel.recognizeText` built its recognizer from one constant and
recorded the languages from another, agreeing only because both started from
the same list. Both now come from one resolution. The automatic sweep was
built with the recognizer's own hard-coded default and now takes the same
choice.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-lang`, since deleted):

- The section lists the 28 languages this Mac's Vision reads, each named in
  the reader's language, none ticked to begin with.
- Ticking **German** stores `de-DE`; adding Italian and unticking German
  leaves `it-IT`, so order and removal both work.
- **End to end:** with Italian chosen, the existing recognitions were deleted
  and the app relaunched; the automatic sweep redid all three pages and
  recorded `["it-IT"]` in `page_recognition`. The choice reaches Vision, not
  just the defaults file.
- Storing a language this Mac cannot read shows **"This Mac cannot read
  Swahili (Kenya)."** with Italian still ticked and still used.
- **English, French and Spanish** all launched and looked at; the long footer
  wraps cleanly in each and the language names are localized. The French
  typography test caught a plain space before a colon in the footer, which is
  a narrow no-break space now.

### Fixed on the way: Settings grew to 1834 points tall

A row per language made the macOS Settings window **1834 points tall**, well
past any screen, because that Form sizes itself to its content. The list has a
height of its own and scrolls inside it; the window is 935 now. Seen only
because the window was opened and looked at — the tests would never have
caught it.

### A stale note corrected rather than acted on

The handoff said `DocumentModel.recognizeText(on:)` still called the blocking
`TextRecognizer.recognize(_:)` on the MainActor and should move to
`recognizeOnADedicatedThread(_:)`. **It does not** — both it and the automatic
sweep already use the dedicated thread; the fix landed and the note was never
updated. Checked rather than redone, and the note is removed.

### What this does **not** do

- **No per-document choice.** It is one setting for the whole app; a library
  with French and German documents in it gets both languages on every page or
  switches between them by hand.
- **Nothing is re-recognised when the choice changes.** Pages already read
  keep what they have until something else invalidates them — there is no
  "read these again" anywhere.
- **The accuracy claim in the footer is not measured here.** That more
  languages costs accuracy is Vision's documented behaviour, not something
  this slice benchmarked.
- **iOS is untested**, as throughout while the simulator is down. The section
  is cross-platform and the macOS-only scroll box is `#if os(macOS)`, so the
  iOS Form shows the rows inline — unseen.
- **No XCUITest.** The rows carry `recognition-language-<code>` identifiers
  for one, and the unavailable line carries its own.

## Three working export formats nobody could pick — 2026-11-03 (Claude)

From "Engine work waiting for a screen". `ExportFormat` has six cases and the
export sheet offered **three**: PDF, JPEG and PNG, written out as three tiles
by hand. TXT, HEIC and DOCX all worked in the engine, were unit-tested, and
could not be chosen by anyone.

- Full `./scripts/test.sh`: **604 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

The tile list is **data** now — `ExportSheet.offeredFormats` — and
`ExportFormatOfferTests` fails if it does not cover `ExportFormat.allCases`.
That is the part worth keeping: the next format added to the engine cannot
quietly reach no screen. Six tiles lay out three to a row so they do not
squeeze each other into slivers on a phone.

**A format that holds only the words shows no image options.** `keepsOnlyWords`
lives on `ExportFormat`, so the sheet and the engine cannot disagree about
which is which, and for TXT and DOCX the resolution, quality and packaging
controls are gone — a control that does nothing is worse than no control. In
their place, under the tiles, is what the format costs: *"This format keeps
the words, not the layout: no pictures, no ink, no marks and no page design. A
page with no text of its own is left out, and a document with none cannot be
exported this way."*

**A document with no text gets told so.** `ExportError.noTextToExport` used to
surface as the generic "export failed"; it now reads *"None of these pages
carry any text, so there is nothing to write. Recognize Text first, or export
as PDF or an image instead."* That is the likely case for scanned pages nobody
has recognised yet, and "failed" would send someone looking for a bug.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-exp`, since deleted):

- All six tiles appear: PDF, JPEG, PNG / HEIC, TXT, Word.
- **TXT** on a three-page letter: *Ready: 275 bytes*, which matches the three
  short lines the pages actually carry.
- **Word**: *Ready: 2 KB* — a `.docx` is a zip, so that is the right order.
- **HEIC**: *Ready: 76 KB* for three pages, packaged as a ZIP.
- Choosing TXT hides the image options and shows the caveat; choosing PDF puts
  its own options back.
- A **blank notebook** exported as TXT shows the new message in red rather
  than "export failed".
- **English, French and Spanish** all launched and looked at; both new strings
  wrap cleanly in each.

### Fixed while checking: the caveat did not render at first

It was written as a `Section { EmptyView() } footer: { … }`, and **SwiftUI
drops a Form section whose content is empty — footer and all**. The first run
in the app showed nothing between the tiles and Pages. It sits in the Format
section's own footer now, which is the better place regardless. Worth knowing:
a section that is only a footer does not exist.

### What this does **not** do

- **No password field.** `Exporter.export` takes one and `ExportError` has
  three careful cases for it — including that non-ASCII passwords cannot be
  written, which is a real problem for French and Spanish readers. **Still no
  way to set one**, so that engine remains unreachable.
- **The saved file's contents were not read back.** The sheet reported a
  plausible size for each format and the engines have their own unit tests,
  but the bytes that reached disk were not opened: the save panel is modal and
  background control cannot drive it, and saving into the real Downloads
  folder was not something to do on a check.
- **DOCX keeps one paragraph per line and no formatting**, as its engine
  always has; the caveat says so for both text formats.
- **iOS is untested**, as throughout while the simulator is down. The tile row
  uses `ViewThatFits` on iOS and a plain `HStack` on macOS, so the phone
  layout of six tiles in two rows is unseen.
- **No XCUITest.** Each tile carries `export-format-<format>` and the caveat
  carries `export-words-only-note`.

## A password on an exported PDF — row 27 — 2026-11-03 (Claude)

The engine has taken a password since 2026-10-27, with three carefully
written refusals and eleven tests including *an exported PDF with a password
needs it to open* and *the encryption is AES and not RC4*. **Nothing could
set one.** The last entry named this as the clearest remaining gap; this
closes it.

- Full `./scripts/test.sh`: **613 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### What it does

A **Password** section appears in the export sheet for PDF and for nothing
else — `ExportFormat.canCarryPassword`, on the format so the sheet and the
engine cannot disagree. Switching to TXT takes the section away.

**An empty field means no password**, not an empty one. The engine refuses
`""` outright, because written as both the user and the owner password it
produces a file that opens with nothing while the caller believes it is
protected — and an untouched field is the likeliest source of exactly that.

**A password the writer cannot store is caught where it is typed.** PDFKit
stores nothing outside ASCII — measured, not inferred: `"été-Ñandú-2026"` was
refused as well as `"contraseña-密码-1"`. The engine's own comment asks
whoever builds the screen to say so rather than reject the password with a
generic error, so the reason appears under the field as it is typed and
Export is disabled until it is fixed. That is a real limitation for French
and Spanish readers and it is now named in their own languages.

**A password longer than 32 bytes is flagged, not refused.** Revision 4 reads
the first 32; the whole password still opens the file, so refusing it would
be wrong — but someone typing a long passphrase believes all of it is
protecting them. The note says only the first 32 characters will be needed.

Every `ExportError` now maps to its own sentence rather than "export failed",
which also improves the no-text case from the previous entry.

### Verified by driving the Mac app

On a throwaway library (`/tmp/pn-pw`, since deleted):

- The **Password** section and its footer appear for PDF and **disappear for
  TXT**, replaced by that format's own caveat.
- **English, French and Spanish** all launched and looked at: *Password /
  Password (optional)*, *Mot de passe / Mot de passe (facultatif)*,
  *Contraseña / Contraseña (opcional)*, each with its footer wrapping cleanly.

### What was **not** driven, and what was done instead

**Nothing was typed into the field.** Background control blocks typing into a
secure text field, which is the right restriction, and taking over the screen
needs an approval card that went unanswered through four attempts — so that
route was abandoned rather than retried into the ground.

What that left unexercised was the link between the two tested halves: the
value the sheet decides on reaching the exporter. **`ExportPasswordWorkflowTests`
closes it** by running the same value through the same call the sheet makes,
against a real library and a real exporter, and then opening the written file:

- a typed password leaves a file that is **locked**, refuses a wrong password
  and opens with the typed one;
- an untouched field leaves a file that is **neither locked nor encrypted** —
  the empty-password failure the engine refuses, seen from this side.

Proven red by making `passwordToUse` always return nil, which is exactly the
"sheet silently drops the password" failure worth fearing.

**What is still not covered:** the SwiftUI binding from a keystroke to
`@State password`, and the three messages — accented password, empty
password, 32 characters — which have **never been seen on screen**, only
checked as strings by `LocalizationTests`. An XCUITest is the natural way to
finish it: the field carries `export-password`, the problem line
`export-password-problem` and the length note `export-password-truncated`.

### Also: a red suite that was my own mess

The full run failed once on `cancellingKeepsTheLibraryIdleAndLeavesNoArchiveBehind`,
which asserts no `PaperNestExport-*` directory is left in the temporary root.
The leftover was a **HEIC export from the previous entry's checks**, left at
"Ready" when the app was killed. Not a regression — but worth knowing that
this test reads the shared temporary directory, so driving the real app on
the same machine can turn it red.

### What this does **not** do

- **No password on anything but a PDF**, by design, and no owner/user
  distinction: one password both opens the file and owns it. No permission
  flags — printing, copying and annotating are not restricted separately.
- **The password is not kept anywhere**, which the footer says. There is no
  "remember this" and no keychain.
- **No strength meter and no confirmation field.** A typo in a password that
  is never shown again means a file nobody can open, and nothing warns about
  that.
- **iOS is untested**, as throughout while the simulator is down.

## Row 24 measured: an exported form keeps its boxes and loses its fields — 2026-11-03 (Claude)

Ledger row 24, *interactive PDF form fields preserved*, has read **Planned**
since 2026-10-26 with the note that an unedited page is now copied rather
than redrawn, *"so a field would survive"*. **That inference is wrong**, and
nobody had checked it: the existing pass-through test compares an exported
form against a source that has no form either, and says so in its own
comment.

- Full `./scripts/test.sh`: **616 tests passed**, **0 warnings**. No source
  changed — this slice is a measurement and three tests.

### What actually happens

Exporting a document whose single page carries a real catalog `AcroForm`:

- the **widget annotations survive** — both of them, on the page, where they
  were;
- the **`AcroForm` does not**. `PDFForm.fields(in:)` reads nothing from the
  exported file, and a value that was already filled in is gone with it.

So the export shows the field boxes exactly where they belong and not one of
them is a field any more. That is the worst shape this failure could take,
because it looks right: someone exporting a filled agreement gets a page that
still looks like a form and has lost the answers.

### Why, and what fixing it would take

Structural, not a slip. An `AcroForm` lives in the document **catalog**, not
on a page. Pass-through copies `PDFPage`s into a document that PDFKit then
writes, and **PDFKit exposes no way to carry a catalog dictionary across** —
there is no API for it, so no amount of care in `isUntouched` can help.

The honest fix is a different path: when **every** page of an export is
untouched, comes from one source asset, and is in that source's original
order, copy the source **file** wholesale instead of rebuilding a document.
That would keep the form, the links, the bookmarks and the embedded fonts
together. *(Written here as "and be faster" — **measured 2026-11-04 and that
part is wrong**; see the entry below.)* It needs exact guards — page count, order, asset
identity, no paper change, no text layer, no password — and it changes the
most-used export path, so it is its own slice and is **not** attempted here.

### What is pinned

Three tests, all passing, all written so that **fixing the loss makes them
fail**, with comments saying to rewrite rather than patch them:

- `anExportedFormKeepsItsBoxesAndLosesItsFields` — asserts the fixture really
  has a form first, then that two widgets survive and the form does not.
- `aFilledInValueGoesWithTheForm` — the value is read back from the source
  before the export, so the test cannot pass by the value never existing.
- `aPageThatHadToBeRedrawnLosesItsFormToo` — the other half of the boundary:
  a page redrawn for a different paper size could never keep a form, and
  that is now a measured fact rather than something found on a signature
  page.

Read back through **Core Graphics** throughout, never PDFKit, which reports a
`fieldName` for a widget whether or not the file has a form at all and has
misled this project once already.

### What this does **not** do

- **It does not fix anything.** Row 24 is not closer to working; it is
  closer to being honestly described.
- **One fixture, one page, one field of each kind.** Radio groups, `/Kids`
  hierarchies, signature fields and XFA are untested, and XFA almost
  certainly fares worse.
- **Nothing was checked in another reader.** "The form is gone" means Core
  Graphics finds no `AcroForm`; Acrobat's view of the same file was not
  sought.

## An unedited export is the file that was imported — row 24 fixed — 2026-11-04 (Claude)

Yesterday's entry measured the loss: exporting a page with a real `AcroForm`
kept the widget boxes and lost the form, so the page looked like a form and
was not one. The cause was structural — a form lives in the document
**catalog**, not on a page, and PDFKit cannot carry a catalog across when
pages are copied into a new document. This stops building a new document when
there is nothing to build.

- Full `./scripts/test.sh`: **634 tests passed**, **0 warnings**.
- `./scripts/build-mac-app.sh` and the iOS Simulator build: clean, 0 warnings.

### The rule

`Exporter.wholeSourceAsset` answers one question: is this export simply the
file that was imported? It says yes only when **every** page is an untouched
page of **one** source file, in that file's **own order**, starting at its
first page — and the caller adds that the source has no more pages than the
export does, and that every page really was copied untouched. Then the source
bytes are written out as they are.

Each refusal is a way the copy would hand back something other than what was
asked for: another format, different paper, a password, a crop or rotation,
pages from two files, a subset, a reordering.

### What it buys

- **A form survives**, fields and filled-in values both. So do links,
  bookmarks and embedded fonts, which the same rebuild was losing silently.
- **The export is byte-identical to the import**, asserted as such rather
  than as "it works": anything less means something was rebuilt, and whatever
  was rebuilt can lose things no test thought to check.
- **Compression got honest.** Three compression tests failed the moment this
  landed, on `compressed <= plain` — because `plain` had become the pristine
  source and **the rebuild had been inflating files**. A preset is now allowed
  to hand the source back when no page could be re-encoded, which is both
  smaller and what the compression result already reported: no saving.

### It is not faster, which I had assumed out loud

The handoff and yesterday's entry both said this would "be faster". **It is
not.** Twenty vector pages, three runs each: **copy 0.016s, rebuild 0.013s** —
marginally *slower*, and both negligible.

The reason is plain once measured: the copy path still runs the whole page
loop and writes a placeholder document before throwing it away, because
deciding whether a page is untouched needs the same per-page work either way.
So this does strictly *more* than before for an unedited export. The gain is
correctness — forms, links, bookmarks and fonts surviving — and nothing else.
Said here because it was claimed before it was checked.

### What it costs, deliberately

- **A document handed back whole keeps the source's title and creator**, not
  this app's. Two tests asserted our creator on unedited exports and are
  rewritten: an *assembled* document carries it, one handed back whole does
  not. There is no version that keeps both — setting the metadata means
  writing through PDFKit, and **PDFKit refuses to write the AcroForm fixture
  back at all** (`write(to:)` returns false), which was measured, not assumed.
  Stamping this app as the creator of someone else's unmodified file is not
  obviously right anyway.
- **A password still costs the form**, because a protected file has to be
  written and writing it is the rebuild. Pinned by a test so the trade is
  known rather than discovered: you cannot have both today.

### The guard that nearly shipped untested

Breaking the per-page index check did **not** fail any test at first. The
subset case was caught by the first-page guard, and the deleted-page case by
the page-count guard — so the index check looked load-bearing and was not
proven to be. The case it alone catches is **a shuffle that keeps the first
page and the page count**: three pages exported as 1, 3, 2. Without it the
source comes back in the source's order and the reordering is silently
undone. Two tests now cover it, one on the predicate and one driving a real
export, and both fail when the check is removed.

### What this does **not** do

- **Nothing was driven in the app.** This is engine work with no surface of
  its own; the export sheet is unchanged.
- **One fixture family.** Radio groups, `/Kids` hierarchies, signature fields
  and XFA are still untested, and XFA probably fares worse.
- **No other reader's opinion.** "The form survives" means Core Graphics finds
  it and `PDFForm` reads its value back; Acrobat was not asked.
- **Encrypted sources are untouched by this.** A source that needs a password
  to open was already handled elsewhere and is not part of the copy path.

## Compressing a PDF that cannot shrink no longer costs you the form — 2026-11-04 (Claude)

Found while checking what else the row-24 finding touched. `compressPDF` —
the path for a **stored PDF file**, separate from compressing a document's
pages — rebuilt the document in PDFKit whatever happened, even when **no page
could be re-encoded at all**. That is the common case for a document of real
text, because a preset only re-encodes scans.

- Full `./scripts/test.sh`: **639 tests passed**, **0 warnings**.

### What was wrong

Measured on a one-page PDF carrying a real `AcroForm`, compressed at
*Smallest*:

- the output was **larger than the input**, and
- the **form was gone** — fields and filled-in value both — because a rebuild
  cannot carry a catalog `AcroForm` across.

So "Reduce File Size" on a form could grow the file and kill the form, and
the result would honestly report no saving while the damage was already done.

The comment above that function claimed a copied page brings "a form field's
name" with it. True, and misleading in exactly the way that misled this
project before: **PDFKit reports a `fieldName` for a widget whether or not
the document has a form at all.** The comment now says what actually
survives, and what does not.

### What it does now

If **no page was re-encoded**, the original bytes are handed back. The same
if the rebuild turns out no smaller than the original. So:

- `compressedByteCount <= originalByteCount` is now an invariant for this
  path, where before a "compression" could add bytes;
- a document nothing could shrink keeps its form, its links and everything
  else, because it is not touched at all;
- the result still reports `isSmaller == false` and `savedByteCount == 0`,
  which is what happened.

Both tests were proven red by removing the guard.

### What this does **not** do

- **A page that really was re-encoded still costs the form.** The page content
  genuinely changed, so there is no copy to hand back. Unavoidable, and the
  same shape as the password trade on export.
- **Only the file path changed.** Compressing a *document's pages* goes
  through `writePDF`, which got its own version of this on 2026-11-04.
- **No measurement of how often this bites.** The fixtures say it happens for
  text documents at every preset; how much of a real library is text-only is
  unknown.

### A stale note corrected on the way

The handoff listed "image format choice for output" as remaining backend for
compression. **It is done**: `CompressionFormat` offers JPEG and HEIC with
measured sizes, the image path honours it, and the PDF path documents why it
cannot. Only **folder/archive compression** is left in that area.

## The first-launch recognition sweep, measured at last — 2026-11-04 (Claude)

"The cost of a first-launch sweep over a large library is unmeasured" has
been in this file since 2026-10-26, on every entry that touched recognition.
Measured now.

**8.4 pages per second**, on this Mac: 24 synthetic scans imported in 1.12s,
then `AutomaticTextRecognizer.recognizeMissing()` read all 24 in **2.86s**.

Taken at face value that is roughly **two minutes for a thousand pages** and
**ten for five thousand** — sustained, but batched (ten pages at a time),
resumable, and run on `recognizeOnADedicatedThread`, so it is off the
cooperative pool and does not stall the UI.

### Why that number is an upper bound, not a promise

- **The fixtures are two-line synthetic scans**, clean and sparse. A real
  scanned page of dense text gives Vision far more to do, so the true rate on
  a real library is **lower than 8.4/s, probably by a lot**. This measures the
  machinery, not a photocopied contract.
- **One machine, one OS version**, as every timing in this file.
- **Default batch size (10)**, through the public entry point.
- **Nothing about battery or thermals.** A laptop sweeping five thousand
  pages will be warm and draining; that was not measured and is not claimed
  either way.
- **The measurement was a one-off and is not committed.** A timing assertion
  in the suite would be flaky on a shared machine — and this very suite has
  already been turned red once by the real app leaving a file in the
  temporary directory.

So: the sweep is not a freeze, and it is not free. If a large library ever
needs it to be gentler, the batch size and a pause between batches are the
knobs, and neither exists yet.

## Backup and bulk export inherit the copy rule — 2026-11-04 (Claude)

Having changed what an export produces, the question is which other paths
produce exports. Two do: the **library backup** and the **bulk "export a
selection as one ZIP"**. Both call the same `export`, so both inherit the
rule that an unedited document is handed back as the file that was imported.
Proven rather than assumed, because a fix inherited through a default
argument is exactly what stops being true when someone adds a parameter.

- Full `./scripts/test.sh`: **641 tests passed**, **0 warnings**.
- No source changed — two tests.

### What is pinned

- **A backup keeps a form.** A library containing one form PDF is backed up,
  the archive unzipped, and the file inside is byte-identical to the import
  with its filled-in value still readable. The backup is the path people
  trust most — *keep a copy somewhere safe* — so it is the last place a
  document should come back quietly diminished.
- **An archive asked for with a compression preset keeps what it cannot
  shrink.** This is the combination most likely to go wrong, and did: a
  preset used to force a rebuild unconditionally, so a text document came out
  larger *and* without its form, having compressed nothing. The copy rule
  deliberately still applies under a preset when no page could be
  re-encoded.

### What this does **not** cover

- **A document that really was edited, or a scan a preset really did
  shrink.** Both are rebuilt, and both still lose a form. That is inherent,
  not an oversight.
- **File entries in an archive** were already kept as themselves and are
  untouched by any of this.
- **Nothing about archive size or timing.** Only what comes out the other
  end.



## Notes image tool: Take Photo — Codex, 2026-11-04

- Added iOS native still-photo camera to the image menu beside Photos and Files. Captured JPEG goes through existing durable `DocumentModel.addImage` on the page selected before capture; silent cancel, permission/error feedback, camera availability guard. No scan routing or backend/schema changes. Updated camera purpose strings and UI labels in en/fr/es.
- `./scripts/test.sh`: **651 passed**, exit 0 (153 + 167 + 133 + 150 + 48), including existing NotePhotoPlacementTests and localization parity. Log `/tmp/papernest-note-camera-unit.log`.
- `./scripts/build-mac-app.sh`: **passed**, exit 0. Log `/tmp/papernest-note-camera-mac.log`.
- `./scripts/ui-test-ios.sh 414752ED-CE8A-4298-BB66-9FBCAA962A99 -only-testing:PaperNest-iOSUITests/AppUITests/testNoteImageMenuOffersCameraPhotosAndFiles`: updated iOS Simulator build and **1 interaction test passed**, exit 0. Creates a disposable note, opens image menu, asserts all three sources and unavailable camera disabled. Log `/tmp/papernest-note-camera-green.log`. Apple emits AppIntents metadata-extraction warning (no dependency) and Simulator accessibility/debugger diagnostics; no Swift compiler warnings/errors found.
- Pre-change run: exit 65, named test failed after reaching menu and waiting for absent camera button; runner restarted while collecting failure context. This is not a clean assertion-only red result. Log `/tmp/papernest-note-camera-red.log`.
- Independent focused code review: no actionable issues. `git diff --check` passed.
- **Unrun:** physical camera capture/retake/cancel, permission denial/re-enable, orientation and photo save/reopen on device; iPad interactions and French/Spanish runtime layout/VoiceOver. Simulator cannot verify hardware camera. No device installation or real-library testing performed.

## Duplicate Home heading — verified November 5, recorded November 7, 2026

Removed compact iOS sidebar Home title and Mac dashboard navigation title in RootView; retained destination labels and Profile. Expanded HomeToolsUITests single-title assertion to iPhone. Red iPhone run reproduced 2 Home labels instead of 1 (`/tmp/papernest-home-heading-phone-red.log`). Final iPhone regression passed 1 test, 13.048s (`/tmp/papernest-home-heading-phone-final.log`, TEST SUCCEEDED); iPad passed 1 test, 13.791s (`/tmp/papernest-home-heading-ipad-final.log`, TEST EXECUTE SUCCEEDED). Both verify one brand/Home label and Profile navigation. Mac dev app build passed, 6.79s (`/tmp/papernest-home-heading-mac.log`). Native Mac interaction and physical-device deployment were not performed for this slice. `git diff --check` passed.

Notes/PDF redesign remains a design preview pending owner review; no PDF reliability fix claimed. Preview JavaScript syntax and queried element IDs checked; no browser interaction pass claimed.

## Approved phased redesign — November 7, 2026 (integration in progress)

- Existing checkout and dirty baseline preserved; no schema migration, mock production library, fabricated subscription or sync state. Changes cover Home/libraries, tabbed editor/tool inspector, capture/review and Profile/Pro/Export styling.
- Initial iOS Simulator and Mac builds passed after correcting read-only undoManager environment injection and Core Image corner types. Logs: `/tmp/pn-redesign-ios-build2.log`, `/tmp/pn-redesign-mac-build.log`. These precede final integration fixes.
- First iPad interaction run: 2/5 passed (notebook create/reopen, single Home heading/Profile); 3 failed (sidebar cell hit target, tab accessibility/layout, editor toggle). Log `/tmp/pn-redesign-ipad-ui.log`. Failures are not recorded as passes; fixes under retest.
- `./scripts/test.sh` final-suite run: **734 passed, exit 0** (UI210, Store174, Import139, Export158, Core53), `/tmp/pn-redesign-final-tests.log`. Earlier run had one French typography assertion; changed question-mark spacing to nonbreaking space and reran full suite. Later integration changes will receive their relevant checks.
- Native Mac dark-mode disposable-library check: Home showed one brand; All Documents opened six seeded sample files; Favorites filter correctly showed zero favorites. Native AX row selection did not activate the nested button; actual label click did. Test window closed. No real library edited.
- Physical camera, physical iPad, actual StoreKit purchase and VoiceOver audit remain unrun for this slice.

- Subsequent full unit checks passed: 736 tests after initial window-close guards (`/tmp/pn-redesign-final-tests2.log`), then **739 tests** after global closing locks (`/tmp/pn-redesign-final-tests3.log`, UI215 + Store174 + Import139 + Export158 + Core53).
- iPad retry2 passed Documents/Favorites24.481s, then stalled on opening the created notebook. Retry3/4 reproduced an editor layout loop at launch (main-thread SwiftUI/UIKit layout/trait updates, sampled in `/tmp/pn-editor-hang-sample.txt` and `/tmp/pn-editor-hang-sample3.txt`). Runs explicitly interrupted; not counted as successful. Header/inspector integration under isolated investigation.

- iPad retry6 isolated the startup loop to the computed inspector presentation binding. Restoring the native State binding removes the loop; a single shared header removes the separately observed tab/tool overlap. Retry6 scanner workflow **passed40.073s**: rotate/reset, crop handles, zoom/pan/fit, enhancement, duplicate/reorder/delete, name/save/location and reopen. `/tmp/pn-redesign-ipad-ui6.log` overall failed due separate tab/toggle assertions.
- iPad retry7 Home/Documents20.123s and notebook creation/reopen28.168s passed. Embedded panel root AX identifiers hid Save/Place/Cancel, and empty navigationTitle cleared editor title; fixed by removing inherited IDs and applying titles only to standalone navigation. Toggle video showed actual missed second tap: transparent plain-button labels lacked a full hit shape. Added explicit44-point hit shapes to thumbnail/inspector and tab buttons. `/tmp/pn-redesign-ipad-ui7.log` remains a failed run, not a pass.
- iOS scanner renderer tests: **4 passed**, TEST SUCCEEDED, `/tmp/pn-redesign-scanner-render-tests.log`. Verifies rotation/crop dimensions, filter encoding, enhancement reset/source immutability, invalid input rejection. Expected ImageIO diagnostics from the intentionally invalid3-byte fixture. Added ScannerPageTests to existing iOS canvas test host in project.yml.
- Native Mac final tool-panel build (`/tmp/pn-redesign-final-mac4.log`, build6.91s) passed. Disposable synthetic library: hide/show page strip; Pen anchored settings and width change; signature drawing, naming, save, placement, undo/redo; window-close warning with Keep Open preserving ink/name; two tabs open/select/close with per-tab document/undo state; page duplicate/undo in inspector; Profile→Pro→Continue with Free. Panel titles stay beside the page and document title remains intact. App quit verified. StoreKit products/legal URLs unavailable in this dev configuration, so paywall truthfully showed unavailable/Free rather than fabricated prices. No purchase attempted.

- iPad retry8: form filled-copy save/reopen **42.299s**, signature save/place/undo/redo/reopen **50.537s**, tabs open/switch/close/reopen **26.973s** all passed. The four editor cases reached working Pen popovers but failed locating the offscreen opacity slider. Screenshot proved the iOS Form lazily omits it; corrected tests scroll the bounded form, then assert and change opacity. No production workaround for that test failure. `/tmp/pn-redesign-ipad-ui8.log` overall failed.
- Latest full unit suite remains **739 passed, exit0**, `/tmp/pn-redesign-final-tests4.log`. Latest Mac build **passed0.66s**, `/tmp/pn-redesign-final-mac5.log`. No Swift compiler warnings found in these logs; standard AppIntents metadata and simulator infrastructure diagnostics are distinct from compiler warnings.

- Final iPad editor run: **4/4 passed**, TEST SUCCEEDED,140.081s (`/tmp/pn-redesign-ipad-ui9.log`). Notebook English34.031s; PDF English32.482s, French32.842s, Spanish40.727s. Covers hide/show thumbnails, icon-only Text, pen settings width/opacity and change, inline signature inspector, Pages selection and close. Retained screenshots in `docs/screenshots/approved-2026-11-07/` show real synthetic test documents; translations inspected for wrapping.

- First iPhone run stalled before runner launch; restarted only owned test simulator. Second run (`/tmp/pn-redesign-iphone-ui2.log`, exit65): library2, tabs1, Profile/paywall en/fr/es and welcome2 passed. Inline Spanish accessibilityXXXL failed because page navigation plus hidden palette consumed the keyboard viewport; recorded failure frame confirms tiny page/no toolbar. Four editor tests incorrectly searched iPad sidebar on iPhone; updated tests use native More menu. Scanner Save was under status bar/Dynamic Island because the presentation ignored safe areas; recorded frame confirms overlap. These failures are being corrected and are not counted as passes.

- After compact viewport/safe-area corrections: full unit suite **739 passed**, exit0 (`/tmp/pn-redesign-final-tests5.log`); Mac build **passed0.57s**, exit0 (`/tmp/pn-redesign-final-mac6.log`). No Swift compiler warnings/errors in those logs. Independent scoped review found no source-level regression in tab accessibility, retained thumbnail preference/editor identity, or camera/native-fallback backgrounds. Runtime retests continue.

- iPhone retry3 (`/tmp/pn-redesign-iphone-ui3.log`) restored toolbar visibility but Spanish XXXL Bold remained unreachable; failure screenshot showed the test's narrow scroll gesture opened Color. Compact page fitting now uses available width (vertical scrolling) instead of shrinking page/context controls to remaining height, with held canvas unchanged; explicit text-tool hit shape added. Editor native-menu test's cached AX frame extended beyond the visible menu; its swipe dismissed the menu. Recorded video confirms this was test targeting, not a missing Pages action. Run interrupted after repeated cause identified (exit75); no overall pass claimed.

- Final iPhone interaction run (`/tmp/pn-redesign-iphone-ui4.log`): **6/6 passed**, 296.329s. Inline French/SpanishXXXL keyboard/format/save66.830s; notebook46.988s; PDF English45.915s/French47.929s/Spanish47.526s; scanner41.142s (safe header, exact name, crop/rotate/enhance/zoom/pages/save/reopen). Corrected tests scroll within actual native-menu rows and explicitly set standard text size for editor smoke cases; accessibilityXXXL remains exercised by the dedicated inline test.
- Latest scoped UI suite **215 passed**, exit0 (`/tmp/pn-redesign-final-ui-units.log`); final Mac build **passed0.61s**, exit0 (`/tmp/pn-redesign-final-mac7.log`). No Swift compiler warnings/errors found. Prior full-suite739 results still cover unchanged Core/Store/Import/Export modules.

- StoreKit hosted suite on iOS26.5 **failed**, exit65 (`/tmp/pn-redesign-storekit.log`): SKTestSession could not save/load configuration (`SKInternalErrorDomain code3`), products empty and `.notEntitled`;3 tests/6 issues, no transaction-state pass claimed. This runtime limitation is already recorded in the November4 subscription entry; rerunning on installed iOS27 with debugger enabled. No product entitlement bypass or production signing changes made.

- StoreKit rerun on iOS27 **3/3 tests passed**, including both billing retry/grace arguments,16.982s test time; TEST SUCCEEDED,exit0 (`/tmp/pn-redesign-storekit-ios27.log`). Verified local Apple trial eligibility/purchase, cancellation with access, expiry/refund, injected failure/pending approval/restoration and billing grace state. No app logic/configuration bypass was needed; iOS26.5 local-test service limitation is recorded above.
- Final cleanup: test-owned iPhone26.5/iOS27 and iPad simulators shut down; user's already-open iPhone17ProMax simulator left untouched. Native Mac disposable-library app had already been quit and absence verified. `git diff --check` clean; product brief unchanged. No staging, commits, real-library tests or physical-device deployment.

## Approved Mac/iPad sidebar-header placement — 2026-11-08

- Moved existing page toggle to leading native navigation header beside Back/title, PDF inspector toggle to trailing header beside Export. Both removed from Mac/iPad centered writing toolbar. iPhone placement, panel state/defaults, actions, localized labels/IDs and persistence retained. Files: DocumentView.swift, EditorWorkspaceUITests.swift; approved sample/design docs.
- Red interaction test failed as expected: page toggle bottom196 was below writing toolbar top146 (`/tmp/pn-sidebar-header-red.log`, exit65). Runner subsequently restarted, but failed geometry assertion is retained; no pass inferred from zero-test restart.
- Native Mac disposable library: document and new notebook both show header toggles outside the six-tool writing row; hide both/reopen both passed. Screenshot inspected with panels hidden. Test dev app quit/absence verified; user's Xcode-running app untouched. Mac build passed (`/tmp/pn-sidebar-header-mac.log`).

- iPad26.5 final interaction run **5/5 passed**,213.587s,TEST SUCCEEDED,exit0 (`/tmp/pn-sidebar-header-ipad.log`): notebook plus PDF en/fr/es assert leading/trailing header placement, inspector hide/reopen, page-strip hide/reopen, pen settings, Signature and Pages. Existing French largest-text Signature case also passed. Actual initial notebook screenshot retained at `docs/screenshots/sidebar-header-ipad.png` and visually inspected.
- Full package suite **739 passed**,exit0 (`/tmp/pn-sidebar-header-units.log`); final Mac build **passed11.10s**,exit0 (`/tmp/pn-sidebar-header-mac-final.log`). No Swift compiler warnings/errors found. Final source cleanup preserves the original iPhone page-toggle color as well as placement.

- Final iPhone26.5 notebook editor regression **passed1test**,50.795s,TEST SUCCEEDED,exit0 (`/tmp/pn-sidebar-header-iphone.log`), confirming existing compact page toggle/More workflow, pen settings, Signature and Pages remain usable. This run rebuilt final iOS source. No physical-device or new VoiceOver audit claimed.
- Cleanup: dev Mac test app closed; user's Xcode-launched Mac app untouched. Owned test simulators shut down; no staging/commits or storage/schema changes. `git diff --check` clean.

## Notebook scroll-to-append — 2026-11-08

- Last notebook page now has a localized continuation footer and observes deliberate native downward scrolling. One gesture adds/selects one blank page matching the tail's template, source size and transform. Atomic store tail equality prevents stale/duplicate insertions; existing notebook history handles Undo/Redo. PDF documents do not get this footer. No schema migration or content flattening.
- Full `./scripts/test.sh`: **743 tests passed**, exit0 (`/tmp/pn-scroll-full.log`). New store/model/gate cases verify matching paper, no copied objects, stale-tail rejection, one gesture/one append, no layout-only insertion, undo/redo and reopen. Final focused notebook/localization run **20 tests passed**, exit0 (`/tmp/pn-scroll-final-focused.log`).
- Mac `./scripts/build-mac-app.sh`: **passed**, exit0 (`/tmp/pn-scroll-mac4.log`). Native disposable-library test: last-page wheel scroll changed count3→4, selected new blank page and reset to top; Undo3/Redo4 passed. App closed afterward; user's other Mac app untouched. AppKit clip-view constraints account for SwiftUI safe-area scrolling; a bounded bounds-change observer catches the end of a smooth native scroll.
- iOS build-for-testing **passed** (`/tmp/pn-scroll-append-ios.log`). iPad26.5 UI test **1 passed**,23.428s (`/tmp/pn-scroll-ui3.log`): native swipe, one grid continuation, size retained and saved page still present after relaunch. The test uses navigation mode so its finger swipe is not a lasso gesture.
- Development failures retained: initial tests did not compile until the new API existed; gate assertions needed local result variables, and UI fixture needed item.id. First iPad test left lasso active and failed its count assertion; corrected the test's selected-state label. Initial Mac interaction exposed native inset handling; fixed before final native verification. Initial iPhone single-swipe test did not reach the bottom of its taller-than-viewport page; test now scrolls toward the bottom and stops as soon as one page is appended. No pass inferred from runner restarts.
- Physical-device, new VoiceOver and large-text interactive audits not run for this slice. Footer offers a native labeled Add action as an alternative to scrolling, with en/fr/es strings checked by localization tests. Existing drawing/selection gestures retain their behavior; use navigation mode or scroll outside drawing content.

- Final iPhone26.5 test **1 passed**,21.883s,TEST SUCCEEDED,exit0 (`/tmp/pn-scroll-iphone2.log`); final shared iOS sources rebuilt. Native scroll-to-bottom appends exactly one grid page and relaunch preserves it. Final Mac native verification used the completed bounds observer: a single coordinate-based wheel gesture added page4 from page3, reset viewport to top; Undo/Redo passed. AX Scroll Down alone changes offsets without a wheel event and does not arm append, by design.
- Cleanup: disposable Mac app closed, owned iPad/iPhone simulators shut down. User's already-running iPhone17ProMax and Xcode Mac app left untouched. `git diff --check` clean. No staging, commits or production library tests.

## Continuous notebook scrolling — 2026-11-08

- Scoped changes: DocumentView.swift page stack/active editing surface; EditorWorkspaceUITests.swift adds existing-page down/up regression. No model/schema/persistence changes. Notebook pages share one LazyVStack; selection tracks greatest visible area with stable first-page ties, explicit sidebar/new-page jumps wait for layout, and last row retains the continuation scroll runway. PDFs remain selected-page views.
- Red iPad test reproduced original limitation: after repeated downward swipes active image remained Page1of3 rather than Page2of3 (`/tmp/pn-continuous-red.log`, failed count/label assertion). Development runs exposed initial selection drift, insufficient single-page continuation scroll range, and accessibilityAction changing image roles. Fixed initial positioning gate, last-row minimum viewport height, and inactive-only activation button. Intermediate iPad run canceled after those known regressions; no success inferred from runner restarts (`/tmp/pn-continuous-ipad.log`, `/tmp/pn-continuous-ipad2.log`, `/tmp/pn-continuous-iphone.log`).
- Final Mac build **passed**,15.87s,exit0 (`/tmp/pn-continuous-mac-final.log`). Native disposable notebook: initial page1; downward wheel selected page2; pen drag saved1stroke on page2; upward wheel returned page1 with0strokes; sidebar return to page2 retained1stroke; sidebar jump to finalpage5 and wheel append created page6 fully in view. Actual screenshot inspected. Dev app quit; user's other app untouched.
- Final focused notebook/history/append/localization suite **20 tests passed**,exit0 (`/tmp/pn-continuous-units-final.log`). New strings were unnecessary: page activation reuses en/fr/es page labels. No physical-device, full VoiceOver or 100-page performance audit claimed. Finger drawing/lasso retains its gesture ownership; navigation-mode finger scrolling is tested.

- Final iPhone26.5 UI **2/2 passed**,47.903s,exit0 (`/tmp/pn-continuous-iphone-final.log`): scroll from existing page1 to2 and back without sidebar use, unchanged3-page count, plus matching-paper append/relaunch. Final iOS build completed before test-without-building. iPad final launch stalled before any test started and was interrupted; only the owned iPad simulator was rebooted for retry (`/tmp/pn-continuous-ipad-final.log`).

- Clean iPad retry reached UI tests: PDF workspace **passed46.635s**, append/reopen **passed17.877s**; continuous test exposed padding being counted as visible page area (`/tmp/pn-continuous-ipad-clean.log`, overall exit65). Moved geometry reporting to the actual paper before outer row padding/min-height. Final iPad26.5 **2/2 passed**,33.135s,TEST SUCCEEDED,exit0 (`/tmp/pn-continuous-ipad-paper.log`) verifies page1→2→1 and matching-page append/reopen. iOS rebuilt final source. Final Mac rebuild **passed15.23s**,exit0 (`/tmp/pn-continuous-mac-paper.log`), final focused suite **20 passed**,exit0 (`/tmp/pn-continuous-units-paper.log`). No compiler warnings in Mac/focused logs.

- Final same-build iPhone26.5 recheck **2/2 passed**,35.429s,exit0 (`/tmp/pn-continuous-iphone-paper.log`), covering existing-page down/up and continuation/reopen after the paper-area correction. Final iPad2/2 and iPhone2/2 pass. Disposable Mac app closed; test-owned iPad/iPhone simulators shut down after tests. User's separate app/simulator untouched. `git diff --check` clean; no staging/commits.

## iPad two-finger notebook navigation and scan review — 2026-11-08

- Notebook Pen/Lasso retain their selected tool while the native outer scroll view requires two fingers. A Pencil goes directly to drawing; one-finger drawing/lasso remains available. The iPad lasso uses a native one-contact recognizer that cancels when a second contact joins, preserving PageGeometry selection/move/history. Native scroll settings restore when leaving editing. iPhone and Mac gesture paths remain unchanged.
- iPad custom-camera captures now pause at a full-page Keep Scan/Delete decision. Only Keep appends to the queue; Delete retains earlier queued pages. Pending/processing captures block repeated capture and camera restart, including background/foreground. Auto capture waits for the kept sheet to leave before rearming. Existing VisionKit fallback retains native review. Three new review strings localized en/fr/es; no persistence/schema change.
- Full `./scripts/test.sh`: **748 passed**, exit0 (`/tmp/pn-touch-scan-full.log`). Final touch/scanner/localization subset: **16 passed**, exit0 (`/tmp/pn-touch-scan-unit-final.log`). Initial touch-intent red test failed on missing type before implementation (`/tmp/pn-two-finger-red.log`).
- Final Mac `./scripts/build-mac-app.sh`: **passed**, exit0,6.91s (`/tmp/pn-touch-scan-mac-final.log`). iOS production/UI-test sources rebuilt with `xcodebuild test -scheme PaperNest-iOS` using owned iPad26.5 simulator046CA563; all build products remain in cache. No Swift compiler warnings/errors; Xcode emits its existing optional AppIntents metadata warning.
- Native iOS host suite `xcodebuild test -scheme PaperNest-Canvas`: **11 passed**, exit0,0.420s (`/tmp/pn-touch-canvas-final.log`). Includes actual UIScrollView minimum-touch configure/restore, native recognizer simultaneity, PencilKit persistence/stroke identity/eraser regressions and scanner-page processing.
- Mixed ink/text/image lasso UI regression initially failed because UIPan's recognized location omitted the initial contact before its threshold. Fixed by retaining the first touch location; tight text selection, group selection/move, durable positions/IDs, Undo/Redo, select-all and reopening now **pass**,1test34.741s (`/tmp/pn-touch-lasso-final.log`). Deselect assertion now waits for the UI snapshot to update like the other selection assertions. Temporary trace code removed. Earlier failures retained in `/tmp/pn-ipad-touch-scan-ui.log`, `/tmp/pn-touch-lasso-trace.log`, `/tmp/pn-touch-lasso-origin.log`.
- Initial combined iPad run also passed the new two-finger-contact/no-ink/subsequent-one-finger-writing test22.439s and scanner keep/delete/repeated-capture/background-return test28.974s (`/tmp/pn-ipad-touch-scan-ui.log`); overall that run failed on the lasso issue above, so it is not counted as a green suite.
- Scope limits: public XCTest provides twoFingerTap, not a parallel two-finger drag. Native recognizer setup/contact safety is verified; physical iPad two-finger pan/Pencil/palm interaction and live camera capture have **not** been exercised. Scanner UI tests use synthetic images through a DEBUG-only capture seam into the real processing/review/queue flow. No claim of physical-camera, new VoiceOver, or new French/Spanish visual audit.

- Final iPad interaction rerun **2/2 passed**,52.931s,exit0 (`/tmp/pn-touch-scan-interactions-final.log`): two-finger-contact/no-mark plus subsequent single-finger durable drawing; scanner Keep/Delete/repeated capture/background return. Independent read-only gesture integration review found no actionable correctness issues. `git diff --check` clean. Test apps terminate via test cleanup; owned iPad simulator shut down, user simulator/app untouched. No staging or commits.

## Mac notebook-opening constraint crash investigation — 2026-11-08

- Owner reports notebook opening aborts with NSGenericException: too many Update Constraints in Window passes. Supplied stack includes OutlineListCoordinator/ListTableCellView didUpdateIdealHeight, NSHostingView size-constraint invalidation; exact failing row is not identified by this stack.
- Existing dev Mac binary, disposable `/tmp/papernest-touch-routing-5818DA6F-A8F6-402F-9283-51B2383EF7E3`: existing two-page notebook opens through Notes; new blank A4 notebook creates/opens; narrowing window and reopening A4 succeeds. No matching exception in `/tmp/pn-mac-layout-repro.log`. This does **not** reproduce or fix the owner's crash. No source edits or new build/test-suite claims. Flexible page-thumbnail sizing is a hypothesis only. Awaiting whether failing notebook is new/existing and page count to refine reproduction. Test app closed; user's paused Xcode app left untouched.

## Mac existing-notebook constraint loop fix — 2026-11-08

- Follow-up reproduced the same NSGenericException in an Xcode-built disposable five-page A4 notebook when zooming the window to1919×941, matching the owner's large-window configuration closely. Test process99520 exited133. Evidence: `/tmp/pn-layout-xcode-system.log` at15:04:18; supplied owner stack identifies OutlineListCoordinator/ListTableCellView ideal-height updates. Initial small-window and package-build checks were insufficient.
- Minimal change in DocumentView.PageStrip: macOS thumbnail preview reserves a150-point height instead of a flexible maximum. This removes thumbnail ideal-height negotiation from the AppKit list-row measurement loop; iOS retains the original maximum-height layout. No model/store/schema or document changes. Only aggregate page dimensions/counts were read from the owner's database in read-only mode; all interactive tests used synthetic disposable documents.
- Before/after native regression: original Xcode build crashed during window expansion; changed build survived expansion, reopening the existing five-page notebook from Notes at expanded size, hiding/restoring thumbnails, selecting another page and repeated window zoom/unzoom. Test app terminated normally; user's paused Xcode process untouched. Xcode build for this regression passed (`/tmp/pn-layout-height-build.log`). This verifies the reproduced case, not a direct opening of the owner's private notebook.

- Final verification: Xcode macOS app build **passed**,exit0 (`/tmp/pn-layout-final-mac.log`); generic iOS Simulator PaperNestUI build **passed**,exit0 (`/tmp/pn-layout-final-ios.log`); focused notebook workflow/localization **11 tests passed**,exit0 (`/tmp/pn-layout-regression-tests.log`). No Swift compiler warnings/errors; optional AppIntents metadata warning remains. `git diff --check` clean. Current paused owner app must be stopped/rebuilt to load the fix. No commits or signing/project changes.

## Cross-platform editor zoom — 2026-11-08 (verification in progress)

- Found existing zoom controls were suppressed during markup and absent on iPhone. Added shared Zoom Out/Fit/In controls to the floating palette, retaining Pen/Lasso selection and existing en/fr/es L10n labels. Fit exposes localized percentage to accessibility;44-point icon buttons and Mac shortcuts retained. Shared PageZoom stepping handles arbitrary pinch scales without skipping the next supported step (50–400%).
- Native Mac disposable notebook: zoom buttons100→150→100 and Pen-selected Cmd-plus/Cmd-minus/Cmd-0 passed. Mac build passed (`/tmp/pn-zoom-mac-build.log`). Physical trackpad pinch not exercised.
- PageZoom unit red failed on missing implementation (`/tmp/pn-zoom-unit-red.log`); green2 tests passed (`/tmp/pn-zoom-unit-green.log`). Final focused zoom/touch-intent/localization9 tests passed (`/tmp/pn-zoom-units-final.log`).
- Initial iPad image-target pinch test enlarged but failed the following inward pinch; SwiftUI simultaneous-gesture change did not fix that test (`/tmp/pn-zoom-red.log`, `/tmp/pn-zoom-ipad-green.log`). Native outer-scroll UIPinch recognizer retains baseline through paper relayout; new iOS native one-contact lasso and drawing guard yield to two-contact zoom. Native trace (`/tmp/pn-zoom-trace-diag`) showed the first gesture complete and no second recognized gesture. The enlarged image exceeds viewport, so the test now pinches the visible document scroll area; original image-target failures are retained and not treated as definitive proof of a second-pinch product defect. iPad toolbar-button test passed18.513s in the otherwise failing suite. One concurrent iPhone run was terminated while resolving packages; no result claimed.

## Notes toolbar tests on the 11-inch iPad — Claude, 2026-11-15

- **Cause of the failure:** `NotesToolbarUITests.testEveryToolChangesWhatIsSaved` failed on the iPad Pro 11-inch (M5), iOS 27.0 (DCC189ED-…), at `reveal(finger)` with "Swipe up on tool-panel-scroll: visible frame is empty". The Pen popover was open and correct: `tool-panel-scroll` was at (104, 265, 384, 526) inside the popover at (104, 198, 384, 593). XCUITest still refused to swipe it. A second fault showed up once it scrolled: the Draw with Finger switch stopped at y 779–830, across the popover's bottom edge (791). XCUITest reported it hittable, but the tap landed outside the popover and dismissed it.
- **Fix, test only:** `reveal` now drags slowly by window coordinates from the panel's left margin and holds at the end. It counts a control as reached only when its frame lies wholly inside the panel. No app code changed.
- `./scripts/ui-test-ios.sh DCC189ED-… -only-testing:PaperNest-iOSUITests/NotesToolbarUITests/testEveryToolChangesWhatIsSaved` (iPad Pro 11-inch): **passed**, 166.8 s.
- `-only-testing:PaperNest-iOSUITests/NotesToolbarUITests` on the iPad Pro 13-inch (M5) (046CA563-…): **TEST SUCCEEDED, 3 passed** (167.1 s, 33.4 s, 67.4 s).
- The same suite on the iPhone 17 Pro (63992C10-…): the first attempt never ran, because the simulator failed to launch the test runner ("system shell probably crashed"). After a simulator reboot: **TEST SUCCEEDED, 3 passed** (109.8 s, 11.3 s, 56.1 s).

## Document Tools on the Mac, background-control checks — Claude, 2026-11-15

- Ran `./scripts/run-mac-app.sh /tmp/pn-mac-check -- -PaperNestDebugSkipWelcome YES -PaperNestDebugOpenItem multilingual-letter`: built with **0 warnings**. The seeded throwaway library opened the 3-page `multilingual-letter`, and Document Tools was showing.
- **Resizing the sidebar: passed.** Dragged the inspector's edge with background raw input. At the default width the tool grid is 4 columns. Widened (≈350 pt, as wide as the drag went), it is 5 columns, with Crop, Rotate, Filter, Split and Replace Page on one row. At the narrowest width it is 4 columns again; "Delete Page" and "Replace Page" wrap onto two lines and nothing is cut off.
- **Clicking a thumbnail: passed.** Clicking page 2 opened page 2 and the counter read 2/3. That click went in as an accessibility press, not a raw mouse click.
- **Hover: seen only incidentally.** After the raw drags, page 3's thumbnail stayed lavender, so the hover wash does draw. It did not clear while the pointer was elsewhere, which looks like a leftover of the synthetic events and is not proven to be an app bug. A real-pointer check is still needed.
- **Drag to reorder: NOT verified.** A background raw-input drag from page 1 onto page 3 changed nothing: the `pages` table still holds pdf_page_index 0, 1, 2 at revision 1. A SwiftUI `.draggable` session probably needs a real mouse drag. Full-screen control was requested three times this session and timed out each time.

## Document Tools on the Mac, real-pointer checks — Claude, 2026-11-15 (follows the background checks above)

- The owner approved full-screen control, so the same throwaway library and `multilingual-letter` were driven with the real pointer.
- On arrival an Export sheet was open (not opened by this session) and was cancelled. The page shown had moved to 3/3.
- **Drag to reorder: passed.** The tool's `left_click_drag` from page 1's thumbnail onto page 3's moved page 1 to the end. The `pages` table now orders pdf_page_index 1, 2, 0, and the moved page went to revision 2, so the change is saved. In the editor the first thumbnail now opens "page 2" and the third opens "page 1".
- A held-button drag built from separate `mouse_move` steps did *not* reorder. It most likely never sent real drag events, and it is not evidence against the app.
- **Real clicks on thumbnails: passed.** They select the page; this is the tap-gesture path, not an accessibility press.
- **Hover: passed.** With the real pointer resting on Rotate, the tile drew the light purple wash and border, and it cleared once the pointer moved off. The Annotate header showed the same wash. The tool's bare cursor moves do not trigger hover; a scroll event at the spot did. The page-3 highlight left stuck by the background drags was gone after the first real-pointer event.

## Spacious Home — Codex, 2026-11-15

Implemented the approved spacious Option A on iPhone, iPad and Mac: single greeting, existing brand, top-right Profile, library search, compact existing actions, actual recent previews and folder cards. Home returns clear the previous library search so folder navigation cannot inherit an invisible query. Existing All Documents sorting/selection and editor behavior remain unchanged.

- `GIT_DIR=/dev/null ./scripts/build-mac-app.sh`: **passed**, final build 7.70 s, no compiler warnings (`/tmp/pn-home-mac-verified.log`).
- `GIT_DIR=/dev/null ./scripts/test.sh --filter 'LocalizationTests|LibraryWorkflowTests'`: **17 tests passed** in 2 suites (`/tmp/pn-home-unit.log`).
- Xcode iOS Simulator build/test, `PaperNest-iOS`, iPhone 17 Pro (63992C10-…): **3 tests passed**: `testHomeHasOneSetOfQuickActionsAndFourPhoneTabs` (18.796 s), `testSpaciousHomeProfileAndSearch` (65.744 s), `testStudioHomeLocalizedAndAccessible` (19.588 s). Results: `/tmp/pn-home-phone.xcresult`.
- Same three tests on iPad Pro 13-inch M5 (046CA563-…): **3 tests passed** (16.359 s, 93.107 s, 22.490 s respectively). Includes search → document → Home → See All regression ensuring the old query is cleared. Results: `/tmp/pn-home-ipad.xcresult`.
- Final iPad localized/accessibility test after layout refinement: **passed**, 25.183 s. English/French/Spanish launches, Spanish accessibility XXXL and opening New Note at that size verified. Results: `/tmp/pn-home-ipad-large.xcresult`.
- Native Mac, isolated `com.example.papernest.homecheck` app and synthetic `/tmp/pn-panel-design-mac-library`: **passed** Profile open/close, search result opening, return Home, real empty-folder navigation with query cleared, recent context menu and reopening a 3-page document. Dark Home visually checked. Test app closed afterward.
- Visually inspected normal iPhone/iPad and iPad Spanish XXXL screenshots. Initial iPhone XXXL brand wrapping prompted a dedicated full-width brand line; final phone check is recorded below.
- One final iPhone search rerun stalled before any tests launched; stopped that owned run and restarted only its simulator before retrying. This attempt is **not a pass** (`/tmp/pn-home-phone-final.log`).
- Scoped `git diff --check`: **passed**. No physical-device, live camera, VoiceOver speech or complete app regression claimed for this visual slice. Scan remains unavailable in Simulator as before. Tests used synthetic content only.
- Final fresh iPhone build/test: **2 tests passed, 0 failures** (96.730 s): search/Profile/return-Home regression 75.613 s, localized/XXXL interaction 21.117 s. Result `/tmp/pn-home-phone-retry.xcresult`; visually confirmed full-width PaperNest brand now fits at XXXL. The preceding test-without-building attempt failed during runner preparation with signal TERM, before tests (`/tmp/pn-home-phone-verified.xcresult`); it is not an app assertion failure or a pass.


## Home sample fidelity correction — Codex, 2026-11-15

Owner reported that the initial implementation did not match the approved sample. Compared directly with the A boards; corrected oversized thumbnails, rounded/shadowed action cards, folder presentation, Profile glyph, subtitle and Home background. Home shows three recent items and two folder columns at normal sizes. The actual brand, native sidebar selection, real metadata and existing navigation remain; this is not a claim of pixel-identical native window chrome.

- Mac build: initial 9.08 s and final folder-layout build 14.32 s passed. Final accessibility branch build recorded below.
- LocalizationTests: **5 passed**, 0.055 s (`/tmp/pn-home-match-localization.log`).
- iPad build/test: populated synthetic Home/folder test **passed** (44.415 s) and en/fr/es Profile/search regression **passed** (72.867 s), `/tmp/pn-home-match-ipad.xcresult`. Final folder layout populated test **passed**, 16.719 s (`/tmp/pn-home-match-ipad-final.xcresult`). Rotation was requested, but the screenshots remained portrait; landscape visual verification is not claimed.
- iPhone populated Home/folder test **passed** on both runs (`/tmp/pn-home-match-phone.xcresult`, `/tmp/pn-home-match-phone-verified.xcresult`). The accompanying XXXL creation check failed. An attempted extra-scroll adjustment also failed; reverted it. Restored the prior full-width leading layout for accessibility action buttons, preserving centered compact styling at normal sizes. Final en/fr/es/XXXL interaction run **passed**, 21.884 s (`/tmp/pn-home-match-large.xcresult`). No deeper framework root-cause claim.
- One intermediate UI test compile failed because Thread.sleep was used in an async screenshot test; changed it to Task.sleep and subsequent iOS builds passed.
- Native Mac disposable `com.example.papernest.homematch`, synthetic `/tmp/pn-home-match-mac-library`: visually checked dark Home at 900×570 with all three cards and two folders visible; Profile open/close passed. Test app closed afterward. No user library accessed.
- Actual populated phone/iPad screenshots: `docs/design/mockups/verification-2026-11-15/home-iphone-built.png` and `home-ipad-built.png`. Blank pages are synthetic notebook fixtures, not decorative content in the product.
- Physical devices, VoiceOver speech and a full app regression were not run for this correction.
- Final Mac build after accessibility action-layout correction: **passed**, 6.64 s, no compiler warnings (`/tmp/pn-home-match-mac-verified.log`). Scoped diff whitespace check passed.
## 2026-11-15 21:33 CST — Scan Studio visual preview UI (Codex)

- Added presentation-only Scan UI in `ScannerFeaturePreview.swift`: future Whiteboard and ID/Card mode chips, page preset strip, Cleanup sheet with local sliders, and batch-selection toolbar.
- Wired the visual states into `ScannerWorkspaceView.swift`; no `ScannerPage`, capture engine, export, store, or persistence behavior changed.
- Added en/fr/es localization keys for the new Scan UI.
- `./scripts/build-ios-sim-app.sh` — **passed**, built `/Users/karanpatel/Library/Caches/PaperNest/build-17de0868e51d/dist/ios-simulator/PaperNest.app`.
- UI tests and device interaction checks not run for this presentation-only slice.
