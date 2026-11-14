import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
import PaperNestCore
@testable import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestRender

/// PDFs whose author limited what may be done with them — a government form
/// with copying switched off is the everyday case. They used to be declined;
/// now they are imported exactly as they are, and what the author switched
/// off is read back from the stored original whenever it matters.
@Suite struct RestrictedPDFImportTests {
    @Test func aPDFWithCopyingSwitchedOffIsImportedExactlyAsItIs() async throws {
        let lib = try TestLibrary()
        let original = SyntheticDocuments.restrictedPDF(pages: ["Application", "Signature"])

        let item = try await lib.importer.importItem(.data(original, name: "Form.pdf"))

        let pages = try await lib.store.pages(of: item.id)
        #expect(pages.count == 2)
        #expect(pages.map(\.sourceSize) == [CGSize(width: 612, height: 792), CGSize(width: 612, height: 792)])
        // The stored original is the file, byte for byte: its protection is
        // in those bytes, and a rewritten copy would not have it.
        let stored = try #require(try await lib.renderer.sourcePDFData(for: pages[0]))
        #expect(stored == original)
        let document = try #require(CGDataProvider(data: stored as CFData).flatMap(CGPDFDocument.init))
        #expect(document.isEncrypted && document.isUnlocked && !document.allowsCopying)
    }

    @Test func aPDFWithPrintingSwitchedOffIsImportedToo() async throws {
        let lib = try TestLibrary()
        let original = SyntheticDocuments.restrictedPDF(pages: ["Draft"], allowsCopying: true, allowsPrinting: false)

        let item = try await lib.importer.importItem(.data(original, name: "Draft.pdf"))

        #expect(try await lib.store.pages(of: item.id).count == 1)
    }

    /// The pages can be drawn: a restricted file that opens without a password
    /// is readable by anyone, which is the whole point of accepting it.
    @Test func itsPagesRenderLikeAnyOther() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(
            .data(SyntheticDocuments.restrictedPDF(pages: ["Application"]), name: "Form.pdf"))
        let page = try #require(try await lib.store.pages(of: item.id).first)

        let image = try await lib.renderer.renderThumbnail(page, maxPixelSize: 792)

        // The fixture's black marker, top left, and white paper beside it.
        #expect(PixelProbe.pixel(image, x: 50.0 / 612, y: 50.0 / 792).isDark)
        #expect(PixelProbe.pixel(image, x: 300.0 / 612, y: 500.0 / 792).isWhite)
    }

    /// A file that needs a password *and* is restricted is still declined.
    /// The library keeps a copy that opens without the password, and making
    /// that copy would write the author's limits out of it.
    @Test func aPDFThatNeedsAPasswordAndIsRestrictedIsStillDeclined() async throws {
        let lib = try TestLibrary()
        let locked = SyntheticDocuments.restrictedPDF(pages: ["Secret"], userPassword: "open-sesame")

        await #expect(throws: ImportError.restrictedPDF(filename: "Locked.pdf")) {
            try await lib.importer.importItem(.data(locked, name: "Locked.pdf"), password: "open-sesame")
        }
        #expect(try await lib.store.items(in: .all).isEmpty)
    }

    // MARK: - Reading the limits back

    @Test func theLimitsAreReadFromTheStoredOriginal() async throws {
        let lib = try TestLibrary()
        let noCopy = try await lib.importer.importItem(.data(SyntheticDocuments.restrictedPDF(pages: ["A"]), name: "A.pdf"))
        let noPrint = try await lib.importer.importItem(
            .data(SyntheticDocuments.restrictedPDF(pages: ["B"], allowsCopying: true, allowsPrinting: false), name: "B.pdf"))
        let open = try await lib.importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["C"]), name: "C.pdf"))

        let a = try await lib.renderer.permissions(for: try await lib.store.pages(of: noCopy.id))
        let b = try await lib.renderer.permissions(for: try await lib.store.pages(of: noPrint.id))
        let c = try await lib.renderer.permissions(for: try await lib.store.pages(of: open.id))

        #expect(a == DocumentPermissions(allowsCopying: false, allowsPrinting: true))
        #expect(b == DocumentPermissions(allowsCopying: true, allowsPrinting: false))
        #expect(c == .unrestricted)
        #expect(a.isRestricted && b.isRestricted && !c.isRestricted)
    }

    /// Pages from several files are bound by all of their authors at once,
    /// which is what makes a merged document safe without anything being
    /// recorded when the merge is made.
    @Test func pagesFromSeveralFilesCarryEveryAuthorsLimits() async throws {
        let lib = try TestLibrary()
        let noCopy = try await lib.importer.importItem(.data(SyntheticDocuments.restrictedPDF(pages: ["A"]), name: "A.pdf"))
        let noPrint = try await lib.importer.importItem(
            .data(SyntheticDocuments.restrictedPDF(pages: ["B"], allowsCopying: true, allowsPrinting: false), name: "B.pdf"))
        let open = try await lib.importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["C"]), name: "C.pdf"))
        let together = try await lib.store.pages(of: open.id) + lib.store.pages(of: noCopy.id) + lib.store.pages(of: noPrint.id)

        #expect(try await lib.renderer.permissions(for: together)
                == DocumentPermissions(allowsCopying: false, allowsPrinting: false))
        #expect(try await lib.renderer.permissions(for: []) == .unrestricted)
    }

    /// A picture or a notebook page has no author's limits to read.
    @Test func pagesThatAreNotFromAPDFAreUnrestricted() async throws {
        let lib = try TestLibrary()
        let picture = try await lib.importer.importItem(
            .data(SyntheticDocuments.image(width: 400, height: 300, type: .png), name: "Photo.png"))

        #expect(try await lib.renderer.permissions(for: try await lib.store.pages(of: picture.id)) == .unrestricted)
    }
}
