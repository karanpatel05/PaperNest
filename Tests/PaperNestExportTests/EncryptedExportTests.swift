import CoreGraphics
import Foundation
import PDFKit
import Testing
import PaperNestCore
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestExport

/// Row 27: writing a PDF that needs a password to open.
///
/// What this encryption is, measured rather than assumed: both `CGPDFContext`
/// and `PDFDocument.write(to:withOptions:)` emit `/V 4 /R 4 /Length 128` with
/// `/AESV2` — AES-128 in CBC mode. Not RC4, and not the AES-256 of revision 6,
/// which Apple's APIs do not expose. Revision 4's key derivation is fast, so
/// the strength of the result is the strength of the password.
@Suite struct EncryptedExportTests {
    private let password = "correct horse battery staple"

    private func exportPDF(_ fixture: ExportFixture, _ name: String, _ pages: [Page],
                           password: String?,
                           options: ExportOptions = ExportOptions(format: .pdf, paperSize: .original))
        async throws -> (Data, ExportOutput) {
        let output = try await fixture.exporter.export(itemName: name, pages: pages,
                                                       options: options, password: password)
        return (try Data(contentsOf: output.files[0]), output)
    }

    @Test func anExportedPDFWithAPasswordNeedsItToOpen() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])

        let (data, output) = try await exportPDF(fixture, item.name, pages, password: password)
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(data: data))
        #expect(document.isEncrypted)
        #expect(document.isLocked)
        #expect(document.unlock(withPassword: "not it") == false)
        #expect(document.unlock(withPassword: password))
        #expect(document.page(at: 0)?.string?.contains("Confidential") == true)
    }

    /// A document opens with *either* the user or the owner password. Leave the
    /// owner password empty and it opens with an empty one, which would defeat
    /// the user password entirely — protection that is not protection.
    @Test func anEmptyPasswordDoesNotOpenAnEncryptedExport() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])

        let (data, output) = try await exportPDF(fixture, item.name, pages, password: password)
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(data: data))
        #expect(document.unlock(withPassword: "") == false)
        #expect(document.isLocked, "an empty password opened it")
    }

    @Test func withoutAPasswordNothingIsEncrypted() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Ordinary notice"])

        let (data, output) = try await exportPDF(fixture, item.name, pages, password: nil)
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(data: data))
        #expect(document.isEncrypted == false)
        #expect(document.isLocked == false)
        #expect(document.page(at: 0)?.string?.contains("Ordinary") == true)
    }

    /// Pins the claim itself, read out of the raw bytes. The documentation
    /// says AES-128; if an OS release quietly moved this to RC4 the wording
    /// would become a false security claim, and nothing else here would
    /// notice. `/AESV3` (AES-256) would also pass, because that is an
    /// improvement rather than a regression.
    @Test func theEncryptionIsAESAndNotRC4() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])

        let (data, output) = try await exportPDF(fixture, item.name, pages, password: password)
        defer { output.removeTemporaryFiles() }

        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("/Encrypt"))
        #expect(text.contains("/AESV2") || text.contains("/AESV3"),
                "the standard security handler is no longer AES — the documented claim is now wrong")
    }

    /// Pass-through re-writes the finished file through PDFKit after the
    /// context closes. Without the password on that write, the export arrives
    /// unprotected while the caller believes it is protected — the same
    /// "assembling fresh strips protection" failure compression hit.
    @Test func anUntouchedPageStillArrivesEncrypted() async throws {
        let fixture = try ExportFixture()
        let item = try await fixture.importer.importItem(
            .data(SyntheticDocuments.annotatedPDF(), name: "Agreement"))
        let pages = try await fixture.store.pages(of: item.id)

        let (data, output) = try await exportPDF(fixture, item.name, pages, password: password)
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(data: data))
        #expect(document.isEncrypted, "the pass-through re-write dropped the encryption")
        #expect(document.isLocked)
        #expect(document.unlock(withPassword: password))
        // And the page really did pass through: its link is still there.
        let page = try #require(document.page(at: 0))
        #expect(page.annotations.contains { $0.type == "Link" })
    }

    /// The gap every other password test here leaves: these all use an
    /// untouched page, so PDFKit writes the final file. A document with *no*
    /// untouched page keeps the `CGContext`'s own encryption as the finished
    /// file, and nothing was reading that.
    @Test func aDocumentWithNoUntouchedPageIsStillEncryptedByTheContext() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])
        var cropped = pages[0].transform
        cropped.crop = .exact(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        let edited = try await fixture.store.updateTransform(pages[0].id, to: cropped)

        let (data, output) = try await exportPDF(fixture, item.name, [edited], password: password)
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(data: data))
        #expect(document.isLocked)
        #expect(document.unlock(withPassword: password))
        #expect(document.page(at: 0)?.string?.contains("Confidential") == true)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("/AESV2") || text.contains("/AESV3"))
    }

    /// `replaceWithSourcePages` reopens the file the context just wrote — which
    /// is now **encrypted and locked** — and copies every page that did not
    /// pass through out of it. A locked document yields nothing, so the drawn
    /// pages of a mixed document come back blank. Same chain as the 845-byte
    /// blank page in compression, reached a different way.
    @Test func aMixedDocumentExportedWithAPasswordKeepsEveryPage() async throws {
        let fixture = try ExportFixture()
        let untouched = try await fixture.importer.importItem(
            .data(SyntheticDocuments.annotatedPDF(), name: "Agreement"))
        let untouchedPages = try await fixture.store.pages(of: untouched.id)
        let second = try await fixture.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Second page here"]), name: "Notice"))
        var secondPages = try await fixture.store.pages(of: second.id)
        var cropped = secondPages[0].transform
        cropped.crop = .exact(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        secondPages[0] = try await fixture.store.updateTransform(secondPages[0].id, to: cropped)

        let (data, output) = try await exportPDF(fixture, "Mixed",
                                                 [untouchedPages[0], secondPages[0]], password: password)
        defer { output.removeTemporaryFiles() }

        let document = try #require(PDFDocument(data: data))
        #expect(document.unlock(withPassword: password))
        #expect(document.pageCount == 2)
        // Page 0 passed through: its link is intact.
        #expect(try #require(document.page(at: 0)).annotations.contains { $0.type == "Link" })
        // Page 1 was drawn into the encrypted file and copied back out of it.
        #expect(document.page(at: 1)?.string?.contains("Second page here") == true,
                "the drawn page came back blank — it was copied from a locked document")
        #expect(document.documentAttributes?[PDFDocumentAttribute.titleAttribute] as? String == "Mixed")
    }

    /// Measured: PDFKit's `write(to:withOptions:)` returns false for
    /// `"contraseña-密码-1"`, so an accented or non-Latin password cannot be
    /// written at all. Refused where it can be explained rather than surfacing
    /// as a write error after the fact — this is a realistic password for a
    /// French or Spanish user.
    @Test func aPasswordWithCharactersTheFormatCannotEncodeIsRefused() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])

        await #expect(throws: ExportError.passwordNotRepresentable) {
            try await fixture.exporter.export(itemName: item.name, pages: pages,
                                              options: ExportOptions(format: .pdf),
                                              password: "contraseña-密码-1")
        }
    }

    /// Latin-1 is *not* the boundary, which is why this is a test and not an
    /// assumption: an export with `"été-Ñandú-2026"` failed to write, even
    /// though every character of it is Latin-1. The rule is ASCII, and this is
    /// a real limitation for French and Spanish users rather than a detail.
    @Test func anAccentedPasswordIsRefusedBecauseTheWriterCannotStoreIt() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])

        await #expect(throws: ExportError.passwordNotRepresentable) {
            try await fixture.exporter.export(itemName: item.name, pages: pages,
                                              options: ExportOptions(format: .pdf),
                                              password: "été-Ñandú-2026")
        }
    }

    /// A long password still opens the file, but revision 4 honours only its
    /// first 32 bytes — a 32-character prefix unlocks a file written with 44
    /// characters. Pinned so the brief's statement of the limit stays true.
    @Test func onlyTheFirstThirtyTwoBytesOfAPasswordAreHonoured() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])
        let long = String(repeating: "a", count: 40) + "ZZZZ"

        let (data, output) = try await exportPDF(fixture, item.name, pages, password: long)
        defer { output.removeTemporaryFiles() }

        #expect(try #require(PDFDocument(data: data)).unlock(withPassword: long))
        #expect(try #require(PDFDocument(data: data)).unlock(withPassword: String(long.prefix(32))),
                "the 32-byte limit no longer holds; the brief says it does")
    }

    @Test func anEmptyPasswordIsRefusedRatherThanWritten() async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])

        await #expect(throws: ExportError.emptyPassword) {
            try await fixture.exporter.export(itemName: item.name, pages: pages,
                                              options: ExportOptions(format: .pdf), password: "")
        }
    }

    /// Writing an unprotected file when the caller asked for protection is the
    /// kind of silent false promise this project forbids, so a password on a
    /// format that cannot carry one is refused rather than ignored.
    @Test(arguments: [ExportFormat.jpeg, .png, .txt, .docx])
    func aPasswordOnAFormatThatCannotCarryOneIsRefused(_ format: ExportFormat) async throws {
        let fixture = try ExportFixture()
        let (item, pages) = try await fixture.importPDF(["Confidential memo"])

        await #expect(throws: ExportError.passwordNotSupported) {
            try await fixture.exporter.export(itemName: item.name, pages: pages,
                                              options: ExportOptions(format: format),
                                              password: self.password)
        }
    }
}
