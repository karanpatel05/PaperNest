import CoreGraphics
import Foundation
import Testing
import PaperNestCore
@testable import PaperNestStore

/// What has to be true of the *library* after a redaction, as opposed to the
/// bytes of the new page. The words have to be gone from here too, or the
/// redaction is theatre.
@Suite struct RedactionStoreTests {
    private func imagePage(_ asset: AssetFileStore.StagedAsset) -> LibraryStore.NewPage {
        .init(sourceSize: CGSize(width: 500, height: 700), content: .image(asset.id))
    }

    private func recognition(_ page: Page, _ text: String) -> PageRecognition {
        PageRecognition(pageID: page.id, sourceRevision: page.revision, engineVersion: "test",
                        status: .completed, languages: ["en-US"],
                        lines: [RecognizedLine(text: text, box: .exact(x: 0.1, y: 0.1, width: 0.5, height: 0.02),
                                               confidence: 0.9)])
    }

    /// While the undo history holds the old content, the original is still
    /// referenced and still in the library — so a redaction is not finished
    /// until that history is forgotten.
    @Test func forgettingTheHistoryLetsTheOriginalBeSweptAway() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let original = try store.assets.store(Data("the secret page".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Statement",
                                              pages: [imagePage(original)], assets: [original])
        let page = try await store.pages(of: item.id)[0]
        let redacted = try store.assets.store(Data("redacted page".utf8), kind: .png, originalFilename: nil)
        _ = try await store.replacePageContent(
            page.id,
            with: LibraryStore.PageContentSnapshot(sourceSize: CGSize(width: 500, height: 700),
                                                   content: .image(redacted.id), transform: PageTransform()),
            assets: [redacted])

        // Still there: the replacement is undoable, so the original is kept.
        #expect(try await store.isAssetReferenced(original.id))
        #expect(try await store.sweepOrphanAssets(gracePeriod: 0) == 0)

        #expect(try await store.forgetReplacedContent(for: page.id) == 1)
        #expect(try await store.isAssetReferenced(original.id) == false)
        #expect(try await store.sweepOrphanAssets(gracePeriod: 0) == 1)
    }

    /// Content addressing means two pages of identical paper share one asset.
    /// The sweep is right to keep it, and the honest thing is to say so rather
    /// than report a removal that did not happen.
    @Test func aSharedOriginalIsKeptAndSaysSo() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let original = try store.assets.store(Data("the secret page".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Statement",
                                              pages: [imagePage(original), imagePage(original)], assets: [original])
        let pages = try await store.pages(of: item.id)
        let redacted = try store.assets.store(Data("redacted page".utf8), kind: .png, originalFilename: nil)
        _ = try await store.replacePageContent(
            pages[0].id,
            with: LibraryStore.PageContentSnapshot(sourceSize: CGSize(width: 500, height: 700),
                                                   content: .image(redacted.id), transform: PageTransform()),
            assets: [redacted])
        _ = try await store.forgetReplacedContent(for: pages[0].id)

        // The second page still shows that paper, so the bytes stay — and the
        // caller can find that out before promising the content is gone.
        #expect(try await store.isAssetReferenced(original.id))
        #expect(try await store.sweepOrphanAssets(gracePeriod: 0) == 0)
    }

    /// `replacePageContent` clears the page's rows from `search_index`, so the
    /// words stop answering searches at once. The recognition row still
    /// physically holds them, which is not redaction.
    @Test func theRecognisedWordsAreDeletedNotJustUnindexed() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let original = try store.assets.store(Data("the secret page".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Statement",
                                              pages: [imagePage(original)], assets: [original])
        let page = try await store.pages(of: item.id)[0]
        try await store.saveRecognition(recognition(page, "ACCOUNT 55512345 SECRET"))

        #expect(try await store.recognition(for: page.id) != nil)
        try await store.deleteRecognition(for: page.id)

        #expect(try await store.recognition(for: page.id) == nil, "the words are still stored")
        #expect(try await store.search("55512345").isEmpty)
    }

    /// Redaction needs to remove one file, now. `sweepOrphanAssets` will not
    /// do: its grace period protects assets staged but not yet referenced, so
    /// sweeping with none to collect a single file could take another
    /// operation's freshly staged bytes with it.
    @Test func anUnreferencedAssetIsDeletedRowAndFile() async throws {
        let dir = TempDirectory()
        let store = try LibraryStore(directory: dir.url)
        let original = try store.assets.store(Data("the secret page".utf8), kind: .jpeg, originalFilename: nil)
        let item = try await store.createItem(kind: .document, name: "Statement",
                                              pages: [imagePage(original)], assets: [original])
        let page = try await store.pages(of: item.id)[0]
        let url = store.assets.url(for: original.id, kind: .jpeg)
        #expect(FileManager.default.fileExists(atPath: url.path))

        // While the page shows it, it must survive.
        #expect(try await store.deleteAssetIfUnreferenced(original.id) == false)
        #expect(FileManager.default.fileExists(atPath: url.path))

        let redacted = try store.assets.store(Data("redacted page".utf8), kind: .png, originalFilename: nil)
        _ = try await store.replacePageContent(
            page.id,
            with: LibraryStore.PageContentSnapshot(sourceSize: CGSize(width: 500, height: 700),
                                                   content: .image(redacted.id), transform: PageTransform()),
            assets: [redacted])
        _ = try await store.forgetReplacedContent(for: page.id)

        #expect(try await store.deleteAssetIfUnreferenced(original.id))
        #expect(try await store.assetRecord(original.id) == nil, "the row is still there")
        #expect(!FileManager.default.fileExists(atPath: url.path), "the file is still on disk")
    }
}
