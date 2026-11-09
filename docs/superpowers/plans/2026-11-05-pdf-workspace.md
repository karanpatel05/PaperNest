# PDF forms, signatures and page tools

Owner selected this group after the inline-text work, using Goodnotes and Adobe Acrobat as capability references. Preserve PaperNest styling and existing product brief; this slice does not claim complete product parity.

## Implementation

- Harden existing PDFForm field-kind/read-only/repeated-widget handling and SavedSignature stroke normalization before exposing UI.
- Fill PDF Form reads the current document's actual export, presents real fields by page, retains drafts on failure, and saves a new immutable filled copy into Documents in the original folder. Text fields and checkboxes only; unsupported/read-only fields are shown honestly. A flat or transformed PDF offers the existing on-page Text Box route. No silent reversion to an untouched original.
- Signature captures local handwriting, permits naming/reuse/deletion, previews placement using PageGeometry and commits all strokes as one guarded undo step. This is a visual signature, without certificate verification or signing-service claims.
- Pages provides shared iPhone/iPad/Mac organization with selection, rotate, reorder, duplicate, extract and delete. Duplication preserves editable objects, assets and recognition with new identities; mutations are durable and undoable where supported.
- New advanced operations use the existing Pro entitlement boundary. Existing content remains viewable/exportable after expiration.
- Place the tools in the existing More dropdown beside Text Box. No replacement app, new persistence authority or changes to CLAUDE_CODE_PROMPT.md.

## Verification

Synthetic form tests must read real AcroForm values after saving/reopening/exporting and preserve original bytes. Signature tests cover stroke width, rotated/cropped placement, atomic history and failed saves. Page tests cover copied content, identity independence, history and transaction rollback. Run native Mac and iPhone/iPad interactions, localization checks and both builds; record actual outcomes in TEST_MATRIX.

## Known scope boundaries

The existing exporter preserves interactive forms only for complete untouched source PDFs. Painting signatures or rearranging pages produces a visual PDF; the form UI explains that distinction. Dropdown/radio fields, XFA, certificate signatures, existing-PDF text replacement, collaboration, audio and handwriting recognition are separate capabilities and must not be advertised as implemented by this slice.

Reference feature descriptions: [Goodnotes content selection](https://support.goodnotes.com/hc/en-us/articles/7353695644175-Select-Move-and-Edit-Content-With-the-Lasso-Tool), [Adobe Acrobat desktop tools](https://helpx.adobe.com/acrobat/desktop/get-started/learn-the-basics/overview.html). These inform scope, not copied branding or interfaces.


## Files in this slice

- UI: `Sources/PaperNestUI/PDFFormSheet.swift`, `SignatureSheet.swift`, `DocumentPagesSheet.swift`, editor integration in `DocumentView.swift` and `DocumentModel.swift`; `Localization.swift` and en/fr/es resources.
- Existing engines: `Sources/PaperNestExport/PDFForm.swift`, `Sources/PaperNestCore/SavedSignature.swift`, `Sources/PaperNestStore/LibraryComposition.swift`; new `Sources/PaperNestStore/SignaturePlacement.swift`. No schema migration.
- Tests: `PDFFormTests.swift`, `SavedSignatureTests.swift`, `PageDuplicationTests.swift`, `SignaturePlacementTests.swift`, `PDFFormWorkflowTests.swift`, `SignatureWorkflowTests.swift`, `PageToolsWorkflowTests.swift`, `Tests/Support/SyntheticDocuments.swift`, `Apps/iOS/UITests/AppUITests.swift`; synthetic `Tests/Fixtures/Interactive Form.pdf` and `scripts/seed-pdf-workspace-ui.sh`.
- Documentation: this plan, inline-text plan, CLEAN_NATIVE_DESIGN, UNIFIED_STUDIO_REDESIGN, TEST_MATRIX, SESSION_HANDOFF and verification screenshots. Other dirty files in the shared checkout are preserved and are not attributed to this slice.

## Runtime corrections

Mac form save initially committed the correct bytes but hung in SwiftUI's accessibility focus graph when the Form was replaced with a success view. Explicitly clearing focus alone and keeping the Save toolbar item alone did not resolve it. Keeping the Form hierarchy alive, marking fields read-only after success and showing the completion section in place did resolve the native interaction. Mac page toolbar history needs an HStack boundary so both Undo and Redo appear. Screenshot and accessibility checks also caught inherited identifiers and excessive icon scaling; explicit accessibility containment and bounded icon artwork preserve control access at XXXL.

## Compatibility limits

Repeated AcroForm field names are conservatively unsupported because PDFKit did not reliably preserve every widget's value/appearance. Malformed form hierarchies are bounded before PDFKit construction. Existing saved signatures with the old incorrect width normalization cannot be automatically repaired because their capture dimensions were not stored; new captures normalize coordinates and width together. These are capability boundaries, not destructive migrations.
