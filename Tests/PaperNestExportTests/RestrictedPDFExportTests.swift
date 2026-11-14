import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestRender
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// What leaves the app from a PDF whose author switched copying or printing
/// off. Every way out goes through `Exporter.export`, so this is where the
/// author's limits are kept: nothing may be written that is freer than the
/// file it was made from.
@Suite struct RestrictedPDFExportTests {
    private func imported(_ fixture: ExportFixture, pages: [String] = ["Application", "Signature"],
                          allowsCopying: Bool = false, allowsPrinting: Bool = true)
        async throws -> (original: Data, item: PaperNestCore.LibraryItem, pages: [Page]) {
        let original = SyntheticDocuments.restrictedPDF(pages: pages, allowsCopying: allowsCopying,
                                                        allowsPrinting: allowsPrinting)
        let item = try await fixture.importer.importItem(.data(original, name: "Form.pdf"))
        return (original, item, try await fixture.store.pages(of: item.id))
    }

    private func drawOn(_ page: Page, _ fixture: ExportFixture) async throws {
        try await fixture.store.saveObject(PageObject(
            pageID: page.id, zKey: "m",
            payload: .ink(InkStroke(tool: .pen, color: .black, width: 20,
                                    points: [InkPoint(x: 300, y: 600), InkPoint(x: 500, y: 600)])),
            modifiedAt: Date()))
    }

    /// The limits of a written PDF, as anyone opening it without the owner's
    /// password gets them.
    private func limits(of url: URL, userPassword: String? = nil) throws
        -> (encrypted: Bool, opensFreely: Bool, copying: Bool, printing: Bool, pages: Int) {
        let data = try Data(contentsOf: url)
        let document = try #require(CGDataProvider(data: data as CFData).flatMap(CGPDFDocument.init))
        let opensFreely = document.isUnlocked
        if !opensFreely, let userPassword { _ = document.unlockWithPassword(userPassword) }
        return (document.isEncrypted, opensFreely, document.allowsCopying, document.allowsPrinting, document.numberOfPages)
    }

    /// Nothing has been done to it: what is exported is the file that came in.
    @Test func anUntouchedFormIsExportedAsTheFileItCameInAs() async throws {
        let f = try ExportFixture()
        let (original, item, pages) = try await imported(f)

        let output = try await f.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }

        #expect(try Data(contentsOf: output.files[0]) == original)
    }

    /// Words and pictures are exactly what "copying" is. Each of these would
    /// hand out the contents with no protection at all.
    @Test(arguments: [ExportFormat.txt, .docx, .jpeg, .png, .heic])
    func itsWordsAndPicturesCannotBeExported(_ format: ExportFormat) async throws {
        let f = try ExportFixture()
        let (_, item, pages) = try await imported(f)
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRestricted-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let exporter = Exporter(renderer: f.exporter.renderer, temporaryRoot: scratch)

        await #expect(throws: ExportError.copyingNotAllowed) {
            try await exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: format))
        }
        // Refused before anything was written.
        #expect(try FileManager.default.contentsOfDirectory(atPath: scratch.path).isEmpty)
    }

    /// With something drawn on a page the PDF has to be rebuilt. The rebuilt
    /// file must be as closed as the original: this is the path that used to
    /// write the author's limits away.
    @Test func aFormThatWasDrawnOnIsExportedWithItsLimitsIntact() async throws {
        let f = try ExportFixture()
        let (original, item, pages) = try await imported(f)
        try await drawOn(pages[0], f)

        let output = try await f.exporter.export(itemName: item.name, pages: try await f.store.pages(of: item.id),
                                                 options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }

        let written = try Data(contentsOf: output.files[0])
        #expect(written != original)
        let after = try limits(of: output.files[0])
        #expect(after.encrypted && after.opensFreely, "it must still open without a password, as the original does")
        #expect(!after.copying, "the rebuilt PDF lets its contents be copied; the original did not")
        #expect(after.printing)
        #expect(after.pages == 2)
        // The stroke is on it, and page 2, which nobody touched, kept its words.
        let image = try #require(PixelProbe.renderPDFPage(written, index: 0, scale: 0.5))
        #expect(PixelProbe.pixel(image, x: 400.0 / 612, y: 600.0 / 792).isDark)
        #expect(PDFDocument(data: written)?.page(at: 1)?.string?.contains("Signature") == true)
        // The owner password is not one anybody can guess from the file.
        let document = try #require(PDFDocument(data: written))
        for guess in ["", "owner-only", item.name, "Form"] {
            _ = document.unlock(withPassword: guess)
            #expect(!document.allowsCopying, "\"\(guess)\" opened it as its owner")
        }
    }

    @Test func somePagesOfAFormAreExportedWithItsLimitsIntact() async throws {
        let f = try ExportFixture()
        let (_, item, pages) = try await imported(f, pages: ["One", "Two", "Three"])

        let output = try await f.exporter.export(itemName: item.name, pages: [pages[2], pages[0]],
                                                 options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }

        let after = try limits(of: output.files[0])
        #expect(after.pages == 2 && after.encrypted && after.opensFreely && !after.copying && after.printing)
        let text = PDFDocument(url: output.files[0])?.page(at: 0)?.string ?? ""
        #expect(text.contains("Three"), "the pages are not the ones asked for, in the order asked")
    }

    @Test func aFormLaidOnOtherPaperIsExportedWithItsLimitsIntact() async throws {
        let f = try ExportFixture()
        let (_, item, pages) = try await imported(f)

        let output = try await f.exporter.export(itemName: item.name, pages: pages,
                                                 options: ExportOptions(format: .pdf, paperSize: .a4))
        defer { output.removeTemporaryFiles() }

        let after = try limits(of: output.files[0])
        #expect(after.pages == 2 && after.encrypted && after.opensFreely && !after.copying)
    }

    /// A password the exporter chose opens the file. It must open it as a
    /// reader, not as its owner — or anyone could lift the author's limits by
    /// exporting with a password of their own.
    @Test func aPasswordOnTheExportOpensItWithoutLiftingItsLimits() async throws {
        let f = try ExportFixture()
        let (_, item, pages) = try await imported(f)

        let output = try await f.exporter.export(itemName: item.name, pages: pages,
                                                 options: ExportOptions(format: .pdf), password: "let-me-in")
        defer { output.removeTemporaryFiles() }

        let closed = try limits(of: output.files[0])
        #expect(closed.encrypted && !closed.opensFreely, "the export was meant to need a password")
        let opened = try limits(of: output.files[0], userPassword: "let-me-in")
        #expect(opened.pages == 2)
        #expect(!opened.copying, "the exporter's own password opened it as owner")
        #expect(opened.printing)
    }

    /// A file that may be copied but not printed keeps "not printed" through
    /// an export, in whatever shape the export takes.
    @Test func printingSwitchedOffStaysOffInARebuiltExport() async throws {
        let f = try ExportFixture()
        let (_, item, pages) = try await imported(f, allowsCopying: true, allowsPrinting: false)
        try await drawOn(pages[0], f)

        let output = try await f.exporter.export(itemName: item.name, pages: try await f.store.pages(of: item.id),
                                                 options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }

        let after = try limits(of: output.files[0])
        #expect(after.encrypted && after.opensFreely && after.copying && !after.printing)
    }

    /// Copying is allowed there, so its words may leave as words.
    @Test func aFileThatOnlyForbidsPrintingCanStillBeExportedAsText() async throws {
        let f = try ExportFixture()
        let (_, item, pages) = try await imported(f, allowsCopying: true, allowsPrinting: false)

        let output = try await f.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .txt))
        defer { output.removeTemporaryFiles() }

        #expect(try String(contentsOf: output.files[0], encoding: .utf8).contains("Application"))
    }

    // MARK: - Printing

    @Test func aFileThatForbidsPrintingIsNotMadeReadyForThePrinter() async throws {
        let f = try ExportFixture()
        let (_, item, pages) = try await imported(f, allowsCopying: true, allowsPrinting: false)

        await #expect(throws: ExportError.printingNotAllowed) {
            try await f.exporter.export(itemName: item.name, pages: pages, options: ExportOptions(format: .pdf),
                                        purpose: .printing)
        }
    }

    /// The everyday case: a government form may be printed, and what goes to
    /// the print panel is still closed to copying.
    @Test func aFormThatAllowsPrintingIsMadeReadyStillClosedToCopying() async throws {
        let f = try ExportFixture()
        let (_, item, pages) = try await imported(f)
        try await drawOn(pages[1], f)

        let output = try await f.exporter.export(itemName: item.name, pages: try await f.store.pages(of: item.id),
                                                 options: ExportOptions(format: .pdf, includesRecognizedText: false),
                                                 purpose: .printing)
        defer { output.removeTemporaryFiles() }

        let after = try limits(of: output.files[0])
        #expect(after.pages == 2 && after.opensFreely && !after.copying && after.printing)
    }

    // MARK: - Together with other documents

    /// One restricted page closes the whole export it is part of.
    @Test func pagesFromAnOpenFileAndARestrictedOneAreExportedClosed() async throws {
        let f = try ExportFixture()
        let (_, _, restricted) = try await imported(f, pages: ["Form"])
        let (item, open) = try await f.importPDF(["Cover letter"])

        let output = try await f.exporter.export(itemName: item.name, pages: open + restricted,
                                                 options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }

        let after = try limits(of: output.files[0])
        #expect(after.pages == 2 && after.encrypted && after.opensFreely && !after.copying)
        await #expect(throws: ExportError.copyingNotAllowed) {
            try await f.exporter.export(itemName: item.name, pages: open + restricted, options: ExportOptions(format: .txt))
        }
    }

    /// A backup archive holds each document as a PDF. A restricted one goes in
    /// closed, and the rest are exactly what they were.
    @Test func aBackupArchiveKeepsARestrictedDocumentClosed() async throws {
        let f = try ExportFixture()
        let (original, form, formPages) = try await imported(f)
        let (letter, letterPages) = try await f.importPDF(["Cover letter"])

        let output = try await f.exporter.exportLibrary(
            [LibraryExportItem(name: form.name, pages: formPages), LibraryExportItem(name: letter.name, pages: letterPages)],
            archiveName: "Backup")
        defer { output.removeTemporaryFiles() }

        let extracted = output.directory.appendingPathComponent("extracted", isDirectory: true)
        #expect(try unzip(["-q", output.files[0].path, "-d", extracted.path]).status == 0)
        #expect(try Data(contentsOf: extracted.appendingPathComponent("\(ExportNaming.baseName(form.name)).pdf")) == original)
        let plain = try limits(of: extracted.appendingPathComponent("\(ExportNaming.baseName(letter.name)).pdf"))
        #expect(!plain.encrypted && plain.copying)
    }

    // MARK: - Forms

    /// The reason any of this exists: a government form has to be fillable.
    /// The copy with the answers in it is a new file, and it must come out as
    /// closed as the blank form went in.
    @Test func aFilledCopyOfARestrictedFormIsAsClosedAsTheForm() throws {
        let form = SyntheticDocuments.restrictedAcroFormPDF()
        let closed = DocumentPermissions(allowsCopying: false, allowsPrinting: true)
        #expect(PageRenderer.permissions(ofPDF: form) == closed, "the fixture is not a restricted form")
        #expect(try PDFForm.fields(in: form).map(\.name) == ["customer"])

        let filled = try PDFForm.filled(form, with: ["customer": .text("Ada Lovelace")])

        #expect(PageRenderer.permissions(ofPDF: filled) == closed)
        #expect(try PDFForm.fields(in: filled).first?.value == "Ada Lovelace")
    }

    /// The whole road a form travels in the app: imported, handed to the form
    /// workspace, filled, and the filled copy imported as a document of its own.
    @Test func aRestrictedFormCanBeImportedFilledAndKeptAsADocument() async throws {
        let f = try ExportFixture()
        let form = SyntheticDocuments.restrictedAcroFormPDF()
        let item = try await f.importer.importItem(.data(form, name: "Form.pdf"))
        let pages = try await f.store.pages(of: item.id)

        // What the form workspace reads its fields from.
        let output = try await f.exporter.export(itemName: item.name, pages: pages,
                                                 options: ExportOptions(includesRecognizedText: false))
        defer { output.removeTemporaryFiles() }
        let handed = try Data(contentsOf: output.files[0])
        #expect(handed == form)
        let filled = try PDFForm.filled(handed, with: ["customer": .text("Ada Lovelace")])

        let copy = try await f.importer.importItem(.data(filled, name: "Form (filled).pdf"))

        let copyPages = try await f.store.pages(of: copy.id)
        #expect(try await f.exporter.renderer.permissions(for: copyPages)
                == DocumentPermissions(allowsCopying: false, allowsPrinting: true))
        await #expect(throws: ExportError.copyingNotAllowed) {
            try await f.exporter.export(itemName: copy.name, pages: copyPages, options: ExportOptions(format: .txt))
        }
    }

    /// Nothing changes for a file whose author restricted nothing.
    @Test func anOrdinaryPDFIsStillExportedOpen() async throws {
        let f = try ExportFixture()
        let (item, pages) = try await f.importPDF(["Ordinary"])
        try await drawOn(pages[0], f)

        let output = try await f.exporter.export(itemName: item.name, pages: try await f.store.pages(of: item.id),
                                                 options: ExportOptions(format: .pdf))
        defer { output.removeTemporaryFiles() }

        let after = try limits(of: output.files[0])
        #expect(!after.encrypted && after.opensFreely && after.copying && after.printing)
    }
}
