import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// Export draws every page through a CGContext, which reproduces the marks and
/// drops everything else — links, form fields, annotations. For a page nobody
/// has changed, redrawing is the wrong operation; copying it is the right one.
@Suite struct PDFPassThroughTests {
    private func importAnnotated(_ fixture: ExportFixture, name: String = "Agreement")
        async throws -> (PaperNestCore.LibraryItem, [Page]) {
        let item = try await fixture.importer.importItem(.data(SyntheticDocuments.annotatedPDF(), name: name))
        return (item, try await fixture.store.pages(of: item.id))
    }

    private func exportPDF(_ fixture: ExportFixture, _ name: String, _ pages: [Page],
                           options: ExportOptions = ExportOptions(format: .pdf, paperSize: .original))
        async throws -> (PDFDocument, ExportOutput) {
        let output = try await fixture.exporter.export(itemName: name, pages: pages, options: options)
        let document = try #require(PDFDocument(url: output.files[0]))
        return (document, output)
    }

    @Test func aLinkInAnImportedPDFSurvivesExport() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)

        let (document, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let page = try #require(document.page(at: 0))
        let link = page.annotations.first { $0.type == "Link" }
        let found = try #require(link, "the link was dropped; the page was redrawn instead of copied")
        #expect(found.url?.absoluteString == "https://example.com/invoice")
    }

    /// At the PDFKit annotation level only: the widget and its `/T`. Whether
    /// the field is *fillable* in another reader is a document-level AcroForm
    /// question, and `theExportCarriesTheSourcesFormDictionary` covers that.
    @Test func aFormFieldSurvivesExportWithItsName() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)

        let (document, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let page = try #require(document.page(at: 0))
        let widget = page.annotations.first { $0.type == "Widget" }
        let field = try #require(widget, "the form field was dropped")
        #expect(field.widgetFieldType == .text)
        // Not decoration: a field whose name PDFKit regenerated comes back as
        // `text5`/`text10`, which no form consumer can match to its data.
        #expect(field.fieldName == "customer")
    }

    /// A document this app **assembled** carries its title and creator; a
    /// fresh `PDFDocument` has neither, so they are set deliberately.
    @Test func anAssembledDocumentKeepsItsTitleAndCreator() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)

        // Different paper, so the document really is assembled rather than
        // handed back whole.
        let (document, output) = try await exportPDF(fixture, item.name, pages,
                                                     options: ExportOptions(format: .pdf, paperSize: .a4))
        defer { output.removeTemporaryFiles() }

        let attributes = try #require(document.documentAttributes)
        #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Agreement")
        #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String == Brand.pdfCreator)
    }

    /// A document handed back **whole** keeps the source's own metadata,
    /// because it *is* the source: the same bytes, not a rebuild of them.
    ///
    /// That is a deliberate trade and the price of keeping the form. Setting
    /// our title and creator means writing the document through PDFKit, and
    /// PDFKit will not write this fixture back at all — `write(to:)` returns
    /// false for it — so there is no version of this that keeps both. Nor is
    /// stamping this app as the creator of somebody else's unmodified file
    /// obviously right.
    @Test func aDocumentHandedBackWholeKeepsTheSourcesMetadata() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)

        let (document, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let attributes = document.documentAttributes ?? [:]
        #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String != Brand.pdfCreator,
                "the file was rebuilt after all, or the source grew our creator")
    }

    @Test func theTextAndPageCountAreUnchanged() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)

        let (document, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(document.pageCount == pages.count)
        let page = try #require(document.page(at: 0))
        #expect(page.string?.contains("Signed agreement") == true)
    }

    /// The honest trade, pinned: once a page is edited it has to be redrawn,
    /// and a redraw cannot carry annotations. The crop is what the user asked
    /// for; losing the link is the cost, and it must not be papered over.
    @Test func aCroppedPageIsRedrawnAndLosesItsAnnotations() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)
        var cropped = pages[0].transform
        cropped.crop = .exact(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let edited = try await fixture.store.updateTransform(pages[0].id, to: cropped)

        let (document, output) = try await exportPDF(fixture, item.name, [edited])
        defer { output.removeTemporaryFiles() }

        let page = try #require(document.page(at: 0))
        #expect(page.annotations.isEmpty, "an edited page cannot be copied, so its annotations go")
        // The edit really was applied: the cropped page is smaller than the source.
        #expect(page.bounds(for: .mediaBox).width < 612)
    }

    @Test func exportingOntoLetterPaperRedrawsEveryPage() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)

        let (document, output) = try await exportPDF(fixture, item.name, pages,
                                                     options: ExportOptions(format: .pdf, paperSize: .usLetter))
        defer { output.removeTemporaryFiles() }

        // The page is being re-laid onto chosen paper, so it is not the source page.
        let page = try #require(document.page(at: 0))
        #expect(page.annotations.isEmpty)
    }

    @Test func aMixedDocumentKeepsOrderAndTreatsEachPageOnItsOwn() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["First page", "Second page"]), name: "Mixed"))
        var pages = try await fixture.store.pages(of: item.id)
        var cropped = pages[1].transform
        cropped.crop = .exact(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        pages[1] = try await fixture.store.updateTransform(pages[1].id, to: cropped)

        let (document, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(document.pageCount == 2)
        #expect(try #require(document.page(at: 0)).string?.contains("First page") == true)
        #expect(try #require(document.page(at: 1)).string?.contains("Second page") == true)
        // Page one was copied at its own size; page two was redrawn cropped.
        #expect(try #require(document.page(at: 0)).bounds(for: .mediaBox).width == 612)
        #expect(try #require(document.page(at: 1)).bounds(for: .mediaBox).width < 612)
    }

    /// Every drawn page in a document that has a passed-through page now goes
    /// through copy, a fresh document and `PDFDocument.write` on its way out.
    /// The invisible recognised-text layer is drawn, so this is where it would
    /// be lost — and no existing searchable-PDF test exports an untouched PDF
    /// page alongside one.
    @Test func aPassedThroughPageDoesNotDisturbADrawnTextLayer() async throws {
        let fixture = try ExportFixture()
        let (_, pdfPages) = try await importAnnotated(fixture)
        let scan = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textImage(lines: ["Invoice total 1234 EUR"]), name: "Scan"))
        let scanPages = try await fixture.store.pages(of: scan.id)
        try await fixture.store.saveRecognition(PageRecognition(
            pageID: scanPages[0].id, sourceRevision: scanPages[0].revision, engineVersion: "test",
            status: .completed, languages: ["en-US"],
            lines: [RecognizedLine(text: "Invoice total 1234 EUR",
                                   box: .exact(x: 0.1, y: 0.1, width: 0.6, height: 0.03), confidence: 0.9)]))

        let (document, output) = try await exportPDF(
            fixture, "Mixed", [pdfPages[0], scanPages[0]],
            options: ExportOptions(format: .pdf, paperSize: .original, includesRecognizedText: true))
        defer { output.removeTemporaryFiles() }

        #expect(document.pageCount == 2)
        // The PDF page passed through: it has no recognition of its own, so no
        // text layer is drawn for it, and its link is still there.
        let first = try #require(document.page(at: 0))
        #expect(first.annotations.contains { $0.type == "Link" })
        #expect(first.bounds(for: .mediaBox).width == 612)
        // The image page was drawn, and the text asked for came with it.
        let second = try #require(document.page(at: 1))
        #expect(second.string?.contains("Invoice total 1234 EUR") == true)
    }

    /// PDFKit reports a `fieldName` for a widget whether or not the file has a
    /// document-level form, which is what misread this once. Read back through
    /// Core Graphics instead.
    ///
    /// The answer: the fixture has no catalog `AcroForm` either — PDFKit writes
    /// the widget with its `/T` but builds no form dictionary — so it is not a
    /// real interactive form, and this slice claims nothing about one.
    @Test func theExportCarriesTheSourcesFormDictionary() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)

        let (_, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let exported = Self.acroFormFieldNames(in: output.files[0])
        let sourceURL = fixture.url.appendingPathComponent("acroform-source.pdf")
        try SyntheticDocuments.annotatedPDF().write(to: sourceURL)
        let source = Self.acroFormFieldNames(in: sourceURL)

        // Both are empty today: PDFKit writes the widget with its `/T` but
        // builds no catalog AcroForm, so the fixture is not a real interactive
        // form and this slice claims nothing about one. What is pinned is that
        // the export carries over whatever form dictionary the source had — the
        // moment a fixture with a real AcroForm exists, this fails if it is lost.
        #expect(exported == source, "source form \(source), exported form \(exported)")
    }

    /// Every `/T` in the catalog's `AcroForm` `/Fields`, descending into `/Kids`.
    private static func acroFormFieldNames(in url: URL) -> [String] {
        guard let document = CGPDFDocument(url as CFURL),
              let catalog = document.catalog else { return [] }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return [] }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return [] }
        var names: [String] = []
        collectFieldNames(fields, into: &names)
        return names
    }

    private static func collectFieldNames(_ fields: CGPDFArrayRef, into names: inout [String]) {
        for index in 0..<CGPDFArrayGetCount(fields) {
            var field: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field else { continue }
            var title: CGPDFStringRef?
            if CGPDFDictionaryGetString(field, "T", &title), let title,
               let text = CGPDFStringCopyTextString(title) {
                names.append(text as String)
            }
            var kids: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(field, "Kids", &kids), let kids {
                collectFieldNames(kids, into: &names)
            }
        }
    }

    /// Compression copies an unedited page that **carries text**, and that is
    /// the decision this pins. Such a page is drawn as vector whatever preset
    /// is asked for, so every preset returns the same bytes and drawing it
    /// would lose the link for nothing. A text-free page is a different case:
    /// it is re-encoded instead of copied, which `CompressionTests` covers.
    @Test func compressingAnUneditedPageStillKeepsItsLink() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)
        let original = try await fixture.store.originalByteCount(of: item.id)

        let result = try await fixture.exporter.compress(
            itemName: item.name, pages: pages, originalByteCount: original, preset: .smallest)
        defer { result.output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(url: result.output.files[0]))
        let page = try #require(document.page(at: 0))
        let link = page.annotations.first { $0.type == "Link" }
        #expect(try #require(link).url?.absoluteString == "https://example.com/invoice")
    }

    @Test func aPageWithARecognisedTextLayerIsRedrawn() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)
        try await fixture.store.saveRecognition(PageRecognition(
            pageID: pages[0].id, sourceRevision: pages[0].revision, engineVersion: "test",
            status: .completed, languages: ["en-US"],
            lines: [RecognizedLine(text: "Signed agreement",
                                   box: .exact(x: 0.1, y: 0.1, width: 0.5, height: 0.02), confidence: 0.9)]))

        let (document, output) = try await exportPDF(
            fixture, item.name, pages,
            options: ExportOptions(format: .pdf, paperSize: .original, includesRecognizedText: true))
        defer { output.removeTemporaryFiles() }

        // Copying the source page would drop the invisible text layer that was
        // asked for, so this page is drawn instead.
        #expect(try #require(document.page(at: 0)).annotations.isEmpty)
    }

    // MARK: - A real interactive form, row 24

    /// **Row 24, measured on 2026-11-03 and fixed on 2026-11-04.**
    ///
    /// The ledger used to infer that because an unedited page is copied
    /// rather than redrawn, "a field would survive". It did not: the widget
    /// annotations came through and the catalog `AcroForm` did not, so an
    /// exported page showed the field boxes and not one of them was a field
    /// — and a value already filled in went with them.
    ///
    /// The cause was structural. An `AcroForm` lives in the document
    /// **catalog**, not on a page, and PDFKit offers no way to carry one
    /// across when pages are copied into a new document. So the fix is not to
    /// build a new document when the export *is* the file that was imported:
    /// see `Exporter.wholeSourceAsset`.
    ///
    /// Read back through Core Graphics, never PDFKit, which reports a
    /// `fieldName` for a widget whether or not the file has a form at all.
    @Test func aRealFormSurvivesBeingExportedUntouched() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer", value: "Jane Appleseed"),
            .init(type: "Btn", name: "agreed"),
        ])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let (_, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(Self.acroFormFieldNames(in: output.files[0]) == ["customer", "agreed"])
        #expect(try PDFForm.fields(in: Data(contentsOf: output.files[0])).first?.value == "Jane Appleseed",
                "the fields came back but the answers did not")
    }

    /// The export of an unedited file is that file, byte for byte. Stated as
    /// a hash rather than "it works": anything less than identical means
    /// something was rebuilt, and whatever was rebuilt can lose things this
    /// test does not know to look for.
    @Test func anUneditedDocumentIsHandedBackByteForByte() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let (_, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(try Data(contentsOf: output.files[0]) == source)
    }

    /// The boundary, and the reason the predicate is strict: a page that had
    /// to be **redrawn** cannot keep a form, because the form lives in the
    /// file and a drawing knows nothing about it. A redrawn export is also
    /// not the source file, so it must not be handed back as one.
    @Test func aPageThatHadToBeRedrawnLosesItsFormToo() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let (_, output) = try await exportPDF(fixture, item.name, pages,
                                              options: ExportOptions(format: .pdf, paperSize: .a4))
        defer { output.removeTemporaryFiles() }

        #expect(Self.acroFormFieldNames(in: output.files[0]).isEmpty)
        #expect(try Data(contentsOf: output.files[0]) != source)
    }

    /// A password still costs the form, because a protected file has to be
    /// written and writing it is the rebuild. Pinned so the cost is known
    /// rather than discovered: **you cannot have both today.**
    @Test func askingForAPasswordStillCostsTheForm() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let output = try await fixture.exporter.export(
            itemName: item.name, pages: pages,
            options: ExportOptions(format: .pdf, paperSize: .original), password: "correct-horse")
        defer { output.removeTemporaryFiles() }

        #expect(try Data(contentsOf: output.files[0]) != source, "the password was not applied")
        #expect(Self.acroFormFieldNames(in: output.files[0]).isEmpty)
    }

    /// **The worst thing a whole-file copy could do**: hand back a file that
    /// still contains a page somebody deleted. Driven as a real export
    /// rather than left to the predicate's unit test, because this is the
    /// one failure that would be silent, permanent and impossible to spot
    /// from the page count alone if the guard were off by one.
    @Test func aDeletedPageDoesNotComeBackInTheExport() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Keep me alpha", "DELETE ME beta", "Keep me gamma"])
        let kept = [pages[0], pages[2]]

        let (document, output) = try await exportPDF(fixture, item.name, kept)
        defer { output.removeTemporaryFiles() }

        #expect(document.pageCount == 2)
        let text = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }.joined()
        #expect(!text.contains("DELETE ME"), "a deleted page came back in the export")
    }

    /// A shuffle that keeps the first page and the page count is the one
    /// reordering nothing else catches: the first-page guard sees index 0 and
    /// the page-count guard sees three of three. Without the per-page index
    /// check the source would come back in the source's order and the
    /// reordering would be silently undone.
    @Test func aShuffleKeepingTheFirstPageIsStillExportedAsAsked() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Page alpha", "Page beta", "Page gamma"])

        let (document, output) = try await exportPDF(fixture, item.name, [pages[0], pages[2], pages[1]])
        defer { output.removeTemporaryFiles() }

        #expect(document.page(at: 1)?.string?.contains("Page gamma") == true,
                "the shuffle was undone and the source came back in its own order")
        #expect(document.page(at: 2)?.string?.contains("Page beta") == true)
    }

    /// The same for reordering: the export must be the order that was asked
    /// for, not the source's.
    @Test func reorderedPagesAreNotHandedBackInSourceOrder() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Page alpha", "Page beta"])

        let (document, output) = try await exportPDF(fixture, item.name, [pages[1], pages[0]])
        defer { output.removeTemporaryFiles() }

        #expect(document.page(at: 0)?.string?.contains("Page beta") == true,
                "the pages came back in the source's order")
    }

    /// A protected source must not come back out protected.
    ///
    /// Worth pinning because the whole-file copy hands back stored bytes
    /// verbatim, and "the stored bytes" for a password-protected import are
    /// **the unlocked copy**, not the file the user picked — `PDFInspector`
    /// unlocks it once, at import, and stores that. If it ever stored the
    /// original instead, this path would hand someone an export they cannot
    /// open, with a password they never set for it.
    @Test func aProtectedSourceIsExportedOpenable() async throws {
        let fixture = try ExportFixture()
        let locked = SyntheticDocuments.encryptedPDF(text: "Confidential alpha", password: "correct-horse")
        let item = try await fixture.importer.importItem(.data(locked, name: "Sealed"), password: "correct-horse")
        let pages = try await fixture.store.pages(of: item.id)

        let (document, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(!document.isLocked, "the export needs a password the user never set for it")
        #expect(!document.isEncrypted)
        #expect(document.page(at: 0)?.string?.contains("Confidential alpha") == true)
        // And it is not the bytes the user handed in, which were encrypted.
        #expect(try Data(contentsOf: output.files[0]) != locked)
    }

}
