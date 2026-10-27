import CoreGraphics
import Foundation
import Testing
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestStore

/// Row 33: a text file becomes a document you can work with, rather than an
/// opaque file. The conversion is a choice — importing a `.txt` normally still
/// keeps it as itself.
@Suite struct TextConversionTests {
    @Test func aConvertedTextFileIsADocumentWithPages() async throws {
        let lib = try TestLibrary()

        let item = try await lib.importer.importTextAsDocument("Meeting notes\nAction items follow",
                                                               named: "Notes")

        #expect(item.kind == .document, "not a file item: it has pages now")
        let pages = try await lib.store.pages(of: item.id)
        #expect(pages.count == 1)
        // Real PDF pages, so crop, rotate, filters and ink all apply.
        if case .pdfPage = pages[0].content {} else {
            Issue.record("expected a PDF page, got \(pages[0].content)")
        }
        #expect(try await lib.store.filePayload(item.id) == nil)
    }

    @Test func aLongTextFileBecomesSeveralPages() async throws {
        let lib = try TestLibrary()
        let lines = (1...200).map { "Line \($0)" }.joined(separator: "\n")

        let item = try await lib.importer.importTextAsDocument(lines, named: "Long")

        #expect(try await lib.store.pages(of: item.id).count > 1)
    }

    @Test func theConvertedDocumentIsSearchableByItsOwnWords() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importTextAsDocument("Electricity usage summary", named: "Bill")

        // The pages carry real text, so the embedded-text pass indexes them
        // without any recognition being involved.
        try await EmbeddedTextIndexer(store: lib.store).indexMissing()

        #expect(try await lib.store.search("electricity") == [item.id])
        #expect(try await lib.store.recognition(for: lib.store.pages(of: item.id)[0].id) == nil)
    }

    @Test func atextFileWithNothingInItIsRefused() async throws {
        let lib = try TestLibrary()

        await #expect(throws: ImportError.empty(filename: "Blank")) {
            try await lib.importer.importTextAsDocument("   \n\t ", named: "Blank")
        }
        #expect(try await lib.store.items(in: .all).isEmpty, "a refusal leaves nothing behind")
    }

    @Test func importingATextFileNormallyStillKeepsItAsAFile() async throws {
        let lib = try TestLibrary()
        let url = lib.url.appendingPathComponent("Budget.txt")
        try Data("spending notes".utf8).write(to: url)

        let item = try await FileItemImporter(store: lib.store).importFile(at: url)

        // Converting is a choice; the default is still to keep the bytes as
        // they arrived, which existing behaviour and tests depend on.
        #expect(item.kind == .file)
        #expect(try await lib.store.filePayload(item.id)?.originalFilename == "Budget.txt")
    }
}
