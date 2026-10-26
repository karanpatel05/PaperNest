# Basic DOCX Export Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement inline; final fresh-context review.

**Goal:** F4's last export deliverable, named in FEATURE_EXPANSION as "TXT and basic DOCX", and half of ledger row 34. TXT landed; a Word file has not.
**Architecture:** A `.docx` is a ZIP of XML parts, and `ZipWriter` already exists for ZIP export, so this writes the three parts a word processor needs — `[Content_Types].xml`, `_rels/.rels` and `word/document.xml` — rather than taking on a dependency. Text comes from the same source precedence as TXT: current completed recognition first, then the text a digital PDF carries. One paragraph per recognized line, an explicit page break between pages.
**Tech Stack:** Swift 6, the existing `ZipWriter`, `XMLParser` in tests; no dependencies.
**Spec:** Backend only, which is my lane under the owner's 2026-10-26 division. **Basic** means the words in a real Word file, not layout reconstruction — tables, columns and positioned images are F5 and are not attempted here.

## Constraints and review focus
- **Escaping is the whole correctness story.** Text is written into XML, so an unescaped `&`, `<` or `>` produces a file no word processor can open. Recognized text comes from whatever was on the paper, so an ampersand is ordinary, not exotic. Every run of text is escaped, and a test feeds it `Tom & Jerry <b>` and then parses the result.
- **XML 1.0 forbids most control characters**, and OCR of a noisy scan can return them. They are dropped rather than written, because one stray byte would make the whole file unreadable. A test feeds a NUL through.
- **A Word file that Word cannot open is worse than no exporter.** Structure is verified independently — `/usr/bin/unzip` lists the parts, and `XMLParser` parses `word/document.xml` — but **whether Pages, Word or Google Docs actually opens it is a manual check I cannot perform.** It goes in TEST_MATRIX as not run, and in the brief as something whole-app testing must confirm before this is offered in any screen.
- Same refusal as TXT: a document with no text on any page throws `ExportError.noTextToExport` rather than producing a Word file containing nothing.
- `ExportFormat` gains a case. Checked already for TXT and still true: nothing iterates `allCases`, the export sheet's format tiles are written one per format, and `contentType(for:)` derives from the file extension. So the case appears in no UI until someone adds a tile, which is the honest state for backend work.

## Task 1 — the writer
- [ ] Add failing tests: the output is a ZIP holding the three required parts; `word/document.xml` parses as well-formed XML; recognized lines appear as separate paragraphs; `&`, `<` and `>` are escaped and the file still parses; a control character is dropped rather than written; pages are separated by a page break; accents survive as UTF-8; a document with no text is refused.
- [ ] Add `ExportFormat.docx` and its extension, and a new `DocxExport.swift` behind the existing `export` switch.
- [ ] Run focused tests, record red/green.

## Task 2 — verify and record
- [ ] Full `./scripts/test.sh` **under a timeout**, `./scripts/build-mac-app.sh`, and the `PaperNestUI` iOS Simulator build.
- [ ] Record in TEST_MATRIX, **re-reading it immediately before writing** because Codex is editing it right now for its verification backlog.
- [ ] Add the "opens in a real word processor" check to `docs/CODEX_BRIEF.md` as owed whole-app verification, and release the claim.

## Execution ledger
- Baseline: `0917be6`, **336 tests passing**, 0 warnings. Codex is concurrently active on the verification backlog in `DocumentModel.swift`, `Apps/iOS/UITests`, `docs/TEST_MATRIX.md` and `docs/SESSION_HANDOFF.md` — none of which this slice touches.
- `ZipWriter` is `init(url:date:)` / `addFile(named:data:)` / `finish()`, already used by ZIP export and archive creation.
