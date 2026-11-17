import Foundation
import Testing
import PaperNestCore
import PaperNestImport
import PaperNestStore
import PaperNestTestSupport
@testable import PaperNestUI

/// The Compare screen's model: what can be chosen, running the comparison,
/// moving through its pages, and swapping the two documents.
@MainActor @Suite(.serialized) struct CompareModelTests {
    private func library() async throws -> (URL, LibrarySession, LibraryStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PaperNestCompare-\(UUID())")
        let session = LibrarySession(libraryURL: root)
        await session.bootstrap()
        return (root, session, try #require(session.environment?.store))
    }

    private func finished(_ model: CompareModel) async throws {
        for _ in 0..<200 where model.phase != .done && model.phase != .failed {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.phase == .done)
    }

    @Test func choosingAnotherDocumentComparesItAndShowsTheFirstChange() async throws {
        let (root, session, store) = try await library()
        defer { try? FileManager.default.removeItem(at: root) }
        let importer = DocumentImporter(store: store)
        let old = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: [
            "Chapter one begins with the harbour at dawn", "Invoice total 42 paid in March"]), name: "Statement"))
        let new = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: [
            "Chapter one begins with the harbour at dawn", "Invoice total 42 paid in April"]), name: "Statement v2"))
        let model = CompareModel(originalID: old.id, session: session)

        await model.loadCandidates()
        #expect(model.candidates.map(\.id) == [new.id], "the original is not offered against itself")

        model.choose(new.id)
        try await finished(model)

        let comparison = try #require(model.comparison)
        #expect(comparison.textChangeCount == 1)
        #expect(model.position == 1, "the screen opens on the first page that differs")
        #expect(model.current?.textChanges.first?.removed.map(\.text) == ["March"])
        #expect(model.oldPage?.id == model.oldPages[1].id && model.newPage?.id == model.newPages[1].id)

        model.step(-1)
        #expect(model.position == 0 && model.current?.kind == .same)
        model.step(-1)
        #expect(model.position == 0, "stepping stops at the first page")

        await model.loadImages()
        #expect(model.oldImage != nil && model.newImage != nil && model.overlayImage != nil)
    }

    @Test func swappingComparesTheOtherWayRound() async throws {
        let (root, session, store) = try await library()
        defer { try? FileManager.default.removeItem(at: root) }
        let importer = DocumentImporter(store: store)
        let old = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["Invoice total 42 paid in March"]),
                                                       name: "Old"))
        let new = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["Invoice total 42 paid in April"]),
                                                       name: "New"))
        let model = CompareModel(originalID: old.id, session: session)
        await model.loadCandidates()
        model.choose(new.id)
        try await finished(model)

        model.swap()
        try await finished(model)

        #expect(model.originalID == new.id && model.newID == old.id)
        #expect(model.current?.textChanges.first?.removed.map(\.text) == ["April"])
        #expect(model.current?.textChanges.first?.added.map(\.text) == ["March"])
    }

    /// A page only one document has is shown with nothing beside it.
    @Test func anAddedPageHasNoOriginalPage() async throws {
        let (root, session, store) = try await library()
        defer { try? FileManager.default.removeItem(at: root) }
        let importer = DocumentImporter(store: store)
        let old = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: ["Chapter one begins at dawn here"]),
                                                       name: "Short"))
        let new = try await importer.importItem(.data(SyntheticDocuments.textPDF(pages: [
            "Chapter one begins at dawn here", "An appendix about the lighthouse keeper"]), name: "Long"))
        let model = CompareModel(originalID: old.id, session: session)
        model.choose(new.id)
        try await finished(model)

        #expect(model.current?.kind == .added)
        #expect(model.oldPage == nil && model.newPage != nil)
        await model.loadImages()
        #expect(model.overlayImage == nil && model.newImage != nil)
    }
}
