import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// F4: recognized text has to be findable, and — just as important — has to
/// stop being findable the moment it is no longer current.
@Suite struct RecognitionSearchTests {
    /// `TempDirectory` is noncopyable, so each test owns its own and this
    /// only seeds the library inside it.
    private func seed(_ store: LibraryStore) async throws -> (LibraryItem, Page) {
        let asset = try store.assets.store(Data("scan".utf8), kind: .png, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Untitled scan", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(asset.id)),
        ], assets: [asset])
        return (item, try await store.pages(of: item.id)[0])
    }

    private func completed(_ page: Page, _ text: String) -> PageRecognition {
        PageRecognition(pageID: page.id, sourceRevision: page.revision, engineVersion: "test", status: .completed,
                        languages: ["en-US"], lines: text.split(separator: "\n").map {
                            RecognizedLine(text: String($0), box: .exact(x: 0.1, y: 0.1, width: 0.5, height: 0.02), confidence: 0.9)
                        })
    }

    @Test func wordsInsideThePageAreFoundEvenWhenTheTitleDoesNotMatch() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seed(store)
        #expect(try await store.search("invoice").isEmpty)

        try await store.saveRecognition(completed(page, "Quarterly invoice\nAmount due 42 EUR"))

        #expect(try await store.search("invoice") == [item.id])
        #expect(try await store.search("quarterly") == [item.id])
        #expect(try await store.search("mortgage").isEmpty)
        // The title still matches too; one hit per item, not one per field.
        #expect(try await store.search("Untitled") == [item.id])
    }

    @Test func rerunningRecognitionReplacesTheOldWordsInsteadOfAddingToThem() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seed(store)
        try await store.saveRecognition(completed(page, "Draft version"))
        #expect(try await store.search("draft") == [item.id])

        try await store.saveRecognition(completed(page, "Final version"))
        #expect(try await store.search("final") == [item.id])
        #expect(try await store.search("draft").isEmpty, "the superseded text must not stay findable")
        #expect(try await store.search("version") == [item.id])
    }

    @Test(arguments: [PageRecognition.Status.pending, .failed])
    func anUnfinishedResultLeavesNothingFindable(_ status: PageRecognition.Status) async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seed(store)
        try await store.saveRecognition(completed(page, "Readable words"))
        #expect(try await store.search("readable") == [item.id])

        var restarted = completed(page, "Readable words")
        restarted.status = status
        try await store.saveRecognition(restarted)
        #expect(try await store.search("readable").isEmpty)
        #expect(try await store.recognition(for: page.id)?.status == status)
    }

    @Test func textSurvivesAReopenAndGoesAwayWithTheDocument() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let asset = try store.assets.store(Data("scan".utf8), kind: .png, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Receipt", pages: [
            .init(sourceSize: CGSize(width: 600, height: 800), content: .image(asset.id)),
        ], assets: [asset])
        let page = try await store.pages(of: item.id)[0]
        try await store.saveRecognition(completed(page, "Café Müller 12,50"))

        let reopened = try LibraryStore(directory: dir.url)
        // FTS folds accents, as the existing search tests require.
        #expect(try await reopened.search("cafe") == [item.id])
        #expect(try await reopened.search("muller") == [item.id])

        try await reopened.moveToRecentlyDeleted([item.id])
        #expect(try await reopened.search("cafe").isEmpty, "deleted documents must not surface in search")
        try await reopened.deletePermanently([item.id])
        #expect(try await reopened.search("cafe").isEmpty)
        #expect(try await reopened.integrityCheck().isEmpty)
    }

    @Test func aResultFromAnOlderRevisionIsKeptButNotFindable() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (item, page) = try await seed(store)
        try await store.saveRecognition(completed(page, "Current words"))
        #expect(try await store.search("current") == [item.id])

        // The page changes, so the stored text no longer describes it.
        var stale = completed(page, "Current words")
        stale.sourceRevision = page.revision - 1
        try await store.saveRecognition(stale)
        #expect(try await store.search("current").isEmpty)
        #expect(try await store.recognition(for: page.id)?.sourceRevision == page.revision - 1,
                "the stale result is kept so it can be shown as out of date")
    }

    @Test func recognitionForAMissingPageIsRejected() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let (_, page) = try await seed(store)
        var orphan = completed(page, "Nowhere")
        orphan.pageID = PageID.make()
        await #expect(throws: StoreError.pageNotFound) { try await store.saveRecognition(orphan) }
        #expect(try await store.search("nowhere").isEmpty)
    }
}
