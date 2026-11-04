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

    /// The finished document is assembled fresh, so its title and creator have
    /// to be carried over deliberately; a fresh `PDFDocument` has neither.
    @Test func theDocumentKeepsItsTitleAndCreator() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await importAnnotated(fixture)

        let (document, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        let attributes = try #require(document.documentAttributes)
        #expect(attributes[PDFDocumentAttribute.titleAttribute] as? String == "Agreement")
        #expect(attributes[PDFDocumentAttribute.creatorAttribute] as? String == Brand.pdfCreator)
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

    /// **Ledger row 24 was Planned on an inference, and the inference is
    /// wrong.** It read: an unedited page is copied rather than redrawn, "so
    /// a field would survive". Nobody had exported a document that really has
    /// a form — the test above compares two *empty* ones and says so.
    ///
    /// Measured here with `SyntheticDocuments.acroFormPDF`, which builds a
    /// real catalog `AcroForm`: the widget annotations come through on the
    /// page, **and the form dictionary does not**. So an exported copy shows
    /// the field boxes where they were and none of them is a field any more:
    /// the worst shape of failure, because it looks right.
    ///
    /// The cause is structural rather than a slip. An `AcroForm` lives in the
    /// document **catalog**, not on a page; pass-through copies `PDFPage`s
    /// into a document PDFKit then writes, and PDFKit exposes no way to carry
    /// a catalog dictionary across. Keeping it would mean copying the source
    /// **file** wholesale when every page of it is untouched and in its
    /// original order — a worthwhile slice, and a different one.
    ///
    /// Read back through Core Graphics, never PDFKit, which reports a
    /// `fieldName` for a widget whether or not the file has a form at all.
    ///
    /// **If this test fails, the loss has been fixed — rewrite it rather than
    /// patching the numbers.**
    @Test func anExportedFormKeepsItsBoxesAndLosesItsFields() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [
            .init(name: "customer", value: "Jane Appleseed"),
            .init(type: "Btn", name: "agreed"),
        ])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let (_, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        // The fixture really does have a form, or this measures nothing.
        let sourceURL = fixture.url.appendingPathComponent("real-acroform.pdf")
        try source.write(to: sourceURL)
        #expect(Self.acroFormFieldNames(in: sourceURL) == ["customer", "agreed"])

        // What survives: the boxes. What does not: the form they belonged to.
        let exported = try #require(PDFDocument(url: output.files[0]))
        #expect(exported.page(at: 0)?.annotations.count == 2, "even the widgets were lost")
        #expect(Self.acroFormFieldNames(in: output.files[0]).isEmpty,
                "the form survived — good news, and this test now needs rewriting")
    }

    /// And so a value someone had already filled in goes with it. This is
    /// what row 24 costs in practice: export a filled form and the answers
    /// are gone, while the page still looks like a form.
    @Test func aFilledInValueGoesWithTheForm() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer", value: "Jane Appleseed")])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)
        // The value is really there before the export.
        #expect(try PDFForm.fields(in: source).first?.value == "Jane Appleseed")

        let (_, output) = try await exportPDF(fixture, item.name, pages)
        defer { output.removeTemporaryFiles() }

        #expect(try PDFForm.fields(in: Data(contentsOf: output.files[0])).isEmpty,
                "the filled value came through — rewrite this test")
    }

    /// The other half of the boundary: a page that had to be **redrawn**
    /// could never keep a form, because the form lives in the file and a
    /// drawing knows nothing about it. Pinned so the limit is a measured
    /// fact rather than something a user discovers on a signature page.
    @Test func aPageThatHadToBeRedrawnLosesItsFormToo() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        // A different paper size forces the page to be redrawn.
        let (_, output) = try await exportPDF(fixture, item.name, pages,
                                              options: ExportOptions(format: .pdf, paperSize: .a4))
        defer { output.removeTemporaryFiles() }

        #expect(Self.acroFormFieldNames(in: output.files[0]).isEmpty)
    }
}
