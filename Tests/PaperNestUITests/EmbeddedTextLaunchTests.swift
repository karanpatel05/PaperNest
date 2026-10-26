import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestTestSupport
@testable import PaperNestStore
@testable import PaperNestUI

/// F4: opening a library has to make its digital PDFs findable by their own
/// words, including the ones imported before text indexing existed — and it
/// must not hold up launch to do it.
@MainActor
@Suite struct EmbeddedTextLaunchTests {
    private func seededLibrary(_ pages: [String], named name: String) async throws -> (URL, ItemID) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestEmbeddedTextLaunch-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: url)
        let item = try await DocumentImporter(store: store)
            .importItem(.data(SyntheticDocuments.textPDF(pages: pages), name: name))
        // Nothing has read the PDF: this is the state an existing library is in.
        #expect(try await store.search("council").isEmpty)
        return (url, item.id)
    }

    @Test func openingALibraryMakesItsDigitalPDFsFindableByTheirContents() async throws {
        let (url, itemID) = try await seededLibrary(["Council tax notice"], named: "Notice")
        defer { try? FileManager.default.removeItem(at: url) }

        let session = LibrarySession(libraryURL: url)
        await session.bootstrap()

        // Launch finished without waiting for the pass...
        guard case .ready = session.state else {
            Issue.record("library did not open: \(session.state)")
            return
        }
        // ...and the pass then makes the contents findable.
        await session.embeddedTextIndexing?.value
        let env = try #require(session.environment)
        #expect(try await env.store.search("council") == [itemID])
        #expect(try await env.store.search("plumbing").isEmpty)
    }
}
