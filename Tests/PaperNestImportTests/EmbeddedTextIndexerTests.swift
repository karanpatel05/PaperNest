import Foundation
import Testing
import PaperNestCore
import PaperNestTestSupport
@testable import PaperNestImport
@testable import PaperNestStore

/// F4: the backfill that reads text out of PDF pages nobody has looked at
/// yet, so a library imported before this existed becomes searchable too.
@Suite struct EmbeddedTextIndexerTests {
    @Test func makesAnImportedTextPDFFindableByItsContents() async throws {
        let lib = try TestLibrary()
        let item = try await lib.importer.importItem(
            .data(SyntheticDocuments.textPDF(pages: ["Electricity usage summary", "Direct debit mandate"]), name: "Bill"))
        #expect(try await lib.store.search("electricity").isEmpty, "nothing has read the PDF yet")

        let indexed = try await EmbeddedTextIndexer(store: lib.store).indexMissing()

        #expect(indexed == 2)
        #expect(try await lib.store.search("electricity") == [item.id])
        #expect(try await lib.store.search("mandate") == [item.id], "later pages are read too")
        #expect(try await lib.store.search("gas").isEmpty)
    }

    @Test func aSecondPassOverAScannedPDFHasNothingLeftToDo() async throws {
        let lib = try TestLibrary()
        _ = try await lib.importer.importItem(.data(SyntheticDocuments.scannedPDF(pages: 2), name: "Scan"))
        let indexer = EmbeddedTextIndexer(store: lib.store)

        #expect(try await indexer.indexMissing() == 2, "both pages are looked at once")
        // A scanner library is mostly image-only pages. Looking at them again
        // on every launch would be wasted work on every launch.
        #expect(try await indexer.indexMissing() == 0)
        #expect(try await lib.store.pagesMissingEmbeddedText().isEmpty)
    }

    @Test func leavesImageAndNotebookPagesAlone() async throws {
        let lib = try TestLibrary()
        _ = try await lib.importer.importItem(.data(SyntheticDocuments.image(width: 400, height: 560, type: .png), name: "Photo"))

        // Only PDF pages carry a text layer; a photo needs recognition, which
        // is a different feature and must not be faked here.
        #expect(try await EmbeddedTextIndexer(store: lib.store).indexMissing() == 0)
    }
}
