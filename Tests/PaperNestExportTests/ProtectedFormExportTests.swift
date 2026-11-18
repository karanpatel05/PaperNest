import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// A password on an exported PDF, read back from the written file on every
/// path the writer can take: the unchanged original written again under the
/// password (which keeps a form's fields), the rebuild with untouched pages
/// put back, and the drawing context's own encryption. Each must be AES,
/// open with the password, and not open without it or with a wrong one.
@Suite struct ProtectedFormExportTests {
    private let password = "correct-horse"

    private func export(_ fixture: ExportFixture, _ name: String, _ pages: [Page], password: String?,
                        options: ExportOptions = ExportOptions(format: .pdf, paperSize: .original))
        async throws -> (Data, ExportOutput) {
        let output = try await fixture.exporter.export(itemName: name, pages: pages, options: options, password: password)
        return (try Data(contentsOf: output.files[0]), output)
    }

    /// The names of the form's fields, read from the file's catalog after
    /// unlocking it with `password` — what another reader sees as fillable.
    private func fieldNames(in data: Data, password: String?) -> [String] {
        guard let provider = CGDataProvider(data: data as CFData), let document = CGPDFDocument(provider) else { return [] }
        if let password, !document.isUnlocked { _ = document.unlockWithPassword(password) }
        guard let catalog = document.catalog else { return [] }
        var form: CGPDFDictionaryRef?
        guard CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form), let form else { return [] }
        var fields: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(form, "Fields", &fields), let fields else { return [] }
        return (0..<CGPDFArrayGetCount(fields)).compactMap { index -> String? in
            var field: CGPDFDictionaryRef?
            var title: CGPDFStringRef?
            guard CGPDFArrayGetDictionary(fields, index, &field), let field,
                  CGPDFDictionaryGetString(field, "T", &title), let title else { return nil }
            return CGPDFStringCopyTextString(title) as String?
        }
    }

    /// Encrypted with AES, locked, opened by the password and by nothing else.
    private func expectProtected(_ data: Data, _ label: String) throws {
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("/Encrypt"), "\(label): not encrypted")
        #expect(text.contains("/AESV2") || text.contains("/AESV3"), "\(label): not AES")
        for wrong in ["", "Correct-horse", "wrong"] {
            let document = try #require(PDFDocument(data: data))
            #expect(document.isLocked, "\(label): opens without a password")
            #expect(!document.unlock(withPassword: wrong), "\(label): opened with \"\(wrong)\"")
        }
        let document = try #require(PDFDocument(data: data))
        #expect(document.unlock(withPassword: password), "\(label): the password does not open it")
    }

    // MARK: - The unchanged original, written again under the password

    /// **A password no longer costs the form.** The unchanged original is
    /// written again under the password rather than rebuilt from its pages,
    /// so its fields stay fields.
    @Test func anUnchangedFormExportedWithAPasswordKeepsItsFields() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer"), .init(name: "city")])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let (data, output) = try await export(fixture, item.name, pages, password: password)
        defer { output.removeTemporaryFiles() }

        try expectProtected(data, "unchanged form")
        #expect(data != source, "the password was not applied")
        #expect(fieldNames(in: data, password: password) == ["customer", "city"], "the form's fields were lost")
        let document = try #require(PDFDocument(data: data))
        _ = document.unlock(withPassword: password)
        #expect(document.pageCount == 1)
        #expect(document.page(at: 0)?.annotations.filter { $0.type == "Widget" }.count == 2)
    }

    /// Answers filled in before exporting are still there, and still editable.
    @Test func aFilledFormExportedWithAPasswordKeepsItsAnswers() async throws {
        let fixture = try ExportFixture()
        let blank = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")])
        let filled = try PDFForm.filled(blank, with: ["customer": .text("Ana Ruiz")])
        let item = try await fixture.importer.importItem(.data(filled, name: "Agreement filled"))
        let pages = try await fixture.store.pages(of: item.id)

        let (data, output) = try await export(fixture, item.name, pages, password: password)
        defer { output.removeTemporaryFiles() }

        try expectProtected(data, "filled form")
        let document = try #require(PDFDocument(data: data))
        _ = document.unlock(withPassword: password)
        let field = try #require(document.page(at: 0)?.annotations.first { $0.fieldName == "customer" })
        #expect(field.widgetStringValue == "Ana Ruiz")
        #expect(fieldNames(in: data, password: password) == ["customer"])
    }

    /// The links of an unchanged PDF survive the password too.
    @Test func anUnchangedPDFWithLinksKeepsThemUnderAPassword() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(.data(SyntheticDocuments.annotatedPDF(), name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let (data, output) = try await export(fixture, item.name, pages, password: password)
        defer { output.removeTemporaryFiles() }

        try expectProtected(data, "links")
        let document = try #require(PDFDocument(data: data))
        _ = document.unlock(withPassword: password)
        #expect(document.pageCount == pages.count)
        #expect(document.page(at: 0)?.annotations.contains { $0.type == "Link" } == true)
    }

    /// An owner-password PDF that allows everything has no author limits to
    /// keep, but it is already encrypted: what PDFKit would write from it is
    /// not something to rely on, so it is rebuilt as before — and the
    /// password asked for is still the one that opens it.
    @Test func anAlreadyEncryptedSourceIsRebuiltUnderThePassword() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.restrictedPDF(pages: ["Memo"], allowsCopying: true, allowsPrinting: true)
        let item = try await fixture.importer.importItem(.data(source, name: "Memo"))
        let pages = try await fixture.store.pages(of: item.id)

        let (data, output) = try await export(fixture, item.name, pages, password: password)
        defer { output.removeTemporaryFiles() }

        try expectProtected(data, "owner-password source")
        let document = try #require(PDFDocument(data: data))
        _ = document.unlock(withPassword: password)
        #expect(document.string?.contains("Memo") == true, "the page did not survive")
    }

    // MARK: - The other two paths keep their checks

    /// Some pages of a PDF: not the original, so rebuilt, with the untouched
    /// pages put back — AES, the password, and those pages' links.
    @Test func someUntouchedPagesWithAPasswordAreRebuiltAndProtected() async throws {
        let fixture = try ExportFixture()
        // Three pages, the first carrying a link to the web.
        let item = try await fixture.importer.importItem(.data(SyntheticDocuments.handBuiltLinkedPDF(), name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)
        try #require(pages.count == 3)
        let chosen = [pages[0], pages[2]]

        let (data, output) = try await export(fixture, item.name, chosen, password: password)
        defer { output.removeTemporaryFiles() }

        try expectProtected(data, "some pages")
        let document = try #require(PDFDocument(data: data))
        _ = document.unlock(withPassword: password)
        #expect(document.pageCount == 2)
        #expect(document.page(at: 0)?.annotations.contains { $0.type == "Link" } == true, "the untouched page was not put back")
    }

    /// Every page redrawn: the drawing context's own encryption is the file.
    @Test func aRedrawnDocumentIsProtectedByTheContextAlone() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])

        let (data, output) = try await export(fixture, item.name, pages, password: password,
                                              options: ExportOptions(format: .pdf, paperSize: .a4))
        defer { output.removeTemporaryFiles() }

        try expectProtected(data, "redrawn")
    }

    /// Without a password the unchanged original is still handed back byte for byte.
    @Test func withoutAPasswordTheUnchangedFormIsTheSameFile() async throws {
        let fixture = try ExportFixture()
        let source = SyntheticDocuments.acroFormPDF(fields: [.init(name: "customer")])
        let item = try await fixture.importer.importItem(.data(source, name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let (data, output) = try await export(fixture, item.name, pages, password: nil)
        defer { output.removeTemporaryFiles() }

        #expect(data == source)
    }
}
