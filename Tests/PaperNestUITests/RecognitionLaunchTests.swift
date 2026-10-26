import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestTestSupport
@testable import PaperNestStore
@testable import PaperNestUI

/// F4: opening a library reads the text off scans nobody has asked about, so
/// an imported receipt is findable by a word on it without the user going
/// through a menu page by page.
@MainActor
@Suite struct RecognitionLaunchTests {
    private func library(_ seed: (LibraryStore, DocumentImporter) async throws -> Void) async throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PaperNestRecognitionLaunch-\(UUID().uuidString)", isDirectory: true)
        let store = try LibraryStore(directory: url)
        try await seed(store, DocumentImporter(store: store))
        return url
    }

    @Test func openingALibraryReadsAScanNobodyHasAskedAbout() async throws {
        var itemID: ItemID?
        let url = try await library { _, importer in
            itemID = try await importer.importItem(
                .data(SyntheticDocuments.textImage(lines: ["Invoice total"]), name: "Receipt")).id
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let id = try #require(itemID)

        let session = LibrarySession(libraryURL: url)
        await session.bootstrap()
        guard case .ready = session.state else {
            Issue.record("library did not open: \(session.state)")
            return
        }
        await session.backgroundTextWork?.value

        let env = try #require(session.environment)
        #expect(try await env.store.search("invoice") == [id])
    }

    @Test func aDigitalPDFIsNotRecognizedBecauseItsOwnTextIsReadFirst() async throws {
        var itemID: ItemID?
        let url = try await library { _, importer in
            itemID = try await importer.importItem(
                .data(SyntheticDocuments.textPDF(pages: ["Council tax notice"]), name: "Notice")).id
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let id = try #require(itemID)

        let session = LibrarySession(libraryURL: url)
        await session.bootstrap()
        await session.backgroundTextWork?.value

        let env = try #require(session.environment)
        let page = try await env.store.pages(of: id)[0]
        // Order matters: the embedded-text pass has to run before recognition,
        // or a digital PDF is read as pixels before anything knows it carries
        // its own words.
        #expect(try await env.store.recognition(for: page.id) == nil)
        #expect(try await env.store.search("council") == [id])
    }
}
